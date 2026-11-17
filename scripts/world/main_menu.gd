extends WalkableArea
class_name MainMenu
## Main scene. Input sources (keyboard scheme or gamepad) join by holding interact;
## each joined player appears in the room, and so do players on other machines when
## playing online (any mix of local and online players, up to InputSetup.MAX_PLAYERS).
## Standing on a run-slot pad and pressing interact starts a new run (empty slot) or
## continues the saved one. The Online pad opens a small host/join panel over the
## room; closing it leaves the connection (and everyone in the room) as it is.
##
## Online, only the host picks the run. GameFlow then takes every machine to the
## briefing together; no one else can join until the run is over (see GameFlow._go).

const HOLD_TIME := 0.8
const SLOT_SPACING := 5.0
const SLOT_Z := -2.0
const PAD_SIZE := Vector3(3.0, 0.1, 3.0)
const SLOT_COLOR := Color(0.95, 0.75, 0.3)
const WARDROBE_COLOR := Color(0.85, 0.55, 0.75)
const ONLINE_COLOR := Color(0.4, 0.7, 0.9)
const NOTICE_TIME := 4.0

var _held: Dictionary[int, float] = {}
var _status: Label
var _online_menu: OnlineMenu
var _run_panel: RunPanel
var _wardrobe_layer: CanvasLayer
var _wardrobe_row: HBoxContainer
var _slot_zones: Dictionary[int, InteractZone] = {}
var _choosers: Dictionary[int, Chooser] = {}   # players currently picking a character
var _notice := ""
var _notice_time := 0.0


func _init() -> void:
	room_size = Vector2(20.0, 10.0)


func _ready() -> void:
	super()
	_status = _build_hud("MOVING DAY!")

	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var x := (slot - (SaveManager.SLOT_COUNT + 1) * 0.5) * SLOT_SPACING
		var zone := add_zone(Vector3(x, 0.0, SLOT_Z), PAD_SIZE, SLOT_COLOR, _slot_text(slot))
		zone.interacted.connect(_on_slot_interacted.bind(slot))
		_slot_zones[slot] = zone
	var wardrobe := add_zone(Vector3(7.0, 0.0, 2.5), PAD_SIZE, WARDROBE_COLOR, "Wardrobe\nPick a character", true)
	wardrobe.interacted.connect(_start_choosing)
	var online := add_zone(Vector3(-7.0, 0.0, 2.5), PAD_SIZE, ONLINE_COLOR, "Online\nHost or join", true)
	online.interacted.connect(_on_online_interacted)

	_online_menu = OnlineMenu.new()
	add_child(_online_menu)

	_wardrobe_layer = CanvasLayer.new()
	_wardrobe_layer.layer = 25
	add_child(_wardrobe_layer)
	var wardrobe_root := UIKit.setup(_wardrobe_layer)
	var wardrobe_dock := CenterContainer.new()
	wardrobe_dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wardrobe_dock.offset_top = -500.0
	wardrobe_dock.offset_bottom = -UIKit.SAFE_Y
	wardrobe_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wardrobe_root.add_child(wardrobe_dock)
	_wardrobe_row = HBoxContainer.new()
	_wardrobe_row.add_theme_constant_override("separation", UIKit.SPACE_M)
	_wardrobe_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wardrobe_dock.add_child(_wardrobe_row)
	_wardrobe_layer.visible = false

	_run_panel = RunPanel.new()
	_run_panel.continue_requested.connect(_start_run)
	_run_panel.deleted.connect(func(slot: int) -> void: _slot_zones[slot].set_text(_slot_text(slot)))
	add_child(_run_panel)


func _spawn_point(player_id: int) -> Vector3:
	return Vector3((player_id - 1.5) * 1.5, 0.1, 3.0)


## One player's character-picking state: they stand still while left/right cycles
## through the catalogue and interact confirms.
class Chooser:
	var player_id := 0
	var panel: PanelContainer
	var character_label: Label
	var color_label: Label
	var color_swatch: ColorRect
	var original_character := 0
	var original_color := 0
	var stick_was_neutral := true
	var stick_y_neutral := true
	var interact_was_down := true   # the press that opened the picker must not confirm it
	var back_was_down := false


func _physics_process(delta: float) -> void:
	super(delta)
	# A player who has just arrived (and has not chosen before) picks right away.
	var ids: Array[int] = InputSetup.local_player_ids()   # typed: `:=` fails to infer on a fresh import
	for ordinal in ids.size():
		var id: int = ids[ordinal]
		if CharacterCatalog.choices.has(id) or _choosers.has(id):
			continue
		var remembered := SaveManager.remembered_character(ordinal)
		if remembered >= 0:   # picked on an earlier launch: no need to ask again
			CharacterCatalog.choose(id, remembered)
			var remembered_color := SaveManager.remembered_color(ordinal)
			if remembered_color >= 0:
				CharacterCatalog.choose_color(id, remembered_color)
			var player := _find_player(id)
			if player:
				player.set_character(remembered)
				if remembered_color >= 0:
					player.set_color_index(remembered_color)
		else:
			_start_choosing(id)
	_update_choosers()


func _start_choosing(player_id: int) -> void:
	var player := _find_player(player_id)
	if player == null or not player.is_local or _choosers.has(player_id):
		return
	var chooser := Chooser.new()
	chooser.player_id = player_id
	chooser.original_character = player.character
	chooser.original_color = player.color_index
	chooser.panel = PanelContainer.new()
	chooser.panel.custom_minimum_size = Vector2(760, 380)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIKit.SPACE_S)
	chooser.panel.add_child(column)
	column.add_child(UIKit.label("PLAYER %d  ·  WARDROBE" % player_id,
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))
	chooser.character_label = UIKit.label("", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(chooser.character_label)
	var color_row := HBoxContainer.new()
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	color_row.add_theme_constant_override("separation", UIKit.SPACE_S)
	chooser.color_swatch = ColorRect.new()
	chooser.color_swatch.custom_minimum_size = Vector2(72, 72)
	color_row.add_child(chooser.color_swatch)
	chooser.color_label = UIKit.label("", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	color_row.add_child(chooser.color_label)
	column.add_child(color_row)
	column.add_child(UIKit.label("← / →  Character     ↑ / ↓  Colour",
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel"))
	column.add_child(UIKit.label("A / Interact  Confirm     B / Esc  Cancel",
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel"))
	_wardrobe_row.add_child(chooser.panel)
	_wardrobe_layer.visible = true

	player.movement_locked = true
	player.set_character(CharacterCatalog.choice_for(player_id))
	player.set_color_index(CharacterCatalog.color_index_for(player_id))
	_choosers[player_id] = chooser
	_refresh_chooser_label(chooser, player)


func _update_choosers() -> void:
	for id in _choosers.keys():
		var chooser: Chooser = _choosers[id]
		var player := _find_player(id)
		if player == null:   # left the room while choosing
			_choosers.erase(id)
			continue
		var source := InputSetup.source_of(id)
		var back_down := Input.is_joy_button_pressed(source, JOY_BUTTON_B) if source >= 0 else Input.is_key_pressed(KEY_ESCAPE)
		if back_down and not chooser.back_was_down:
			_cancel_choosing(chooser, player)
			continue
		chooser.back_was_down = back_down

		var x := player.input.move.x
		if absf(x) < 0.3:
			chooser.stick_was_neutral = true
		elif chooser.stick_was_neutral and absf(x) > 0.6:
			chooser.stick_was_neutral = false
			var step := 1 if x > 0.0 else -1
			var next := posmod(player.character + step, CharacterCatalog.count())
			CharacterCatalog.choose(id, next)
			player.set_character(next)
			player.pop()
			_refresh_chooser_label(chooser, player)
		var y := player.input.move.y
		if absf(y) < 0.3:
			chooser.stick_y_neutral = true
		elif chooser.stick_y_neutral and absf(y) > 0.6:
			chooser.stick_y_neutral = false
			var next_color := posmod(player.color_index + (1 if y > 0.0 else -1), CharacterCatalog.color_count())
			CharacterCatalog.choose_color(id, next_color)
			player.set_color_index(next_color)
			player.pop()
			_refresh_chooser_label(chooser, player)
		var down := player.input.interact
		if down and not chooser.interact_was_down:
			_finish_choosing(chooser, player)
		chooser.interact_was_down = down


func _finish_choosing(chooser: Chooser, player: Player) -> void:
	CharacterCatalog.choose(chooser.player_id, player.character)   # records the pick even if untouched
	var ordinal: int = InputSetup.local_player_ids().find(chooser.player_id)
	SaveManager.remember_character(ordinal, player.character)
	CharacterCatalog.choose_color(chooser.player_id, player.color_index)
	SaveManager.remember_color(ordinal, player.color_index)
	player.movement_locked = false
	player.pop()
	chooser.panel.queue_free()
	_choosers.erase(chooser.player_id)
	if _choosers.is_empty():
		_wardrobe_layer.visible = false


func _cancel_choosing(chooser: Chooser, player: Player) -> void:
	# Back discards the unconfirmed preview and restores the previous selection.
	CharacterCatalog.choose(chooser.player_id, chooser.original_character)
	CharacterCatalog.choose_color(chooser.player_id, chooser.original_color)
	player.set_character(chooser.original_character)
	player.set_color_index(chooser.original_color)
	player.movement_locked = false
	player.pop()
	chooser.panel.queue_free()
	_choosers.erase(chooser.player_id)
	if _choosers.is_empty():
		_wardrobe_layer.visible = false


func _refresh_chooser_label(chooser: Chooser, player: Player) -> void:
	chooser.character_label.text = CharacterCatalog.character_name(player.character)
	chooser.color_label.text = CharacterCatalog.COLOR_NAMES[player.color_index]
	chooser.color_swatch.color = CharacterCatalog.COLORS[player.color_index]


func _process(delta: float) -> void:
	_notice_time = maxf(_notice_time - delta, 0.0)
	if not _online_menu.visible and not _run_panel.is_open() and _choosers.is_empty():
		_poll_joins(delta)
	_update_text()


func _slot_text(slot: int) -> String:
	var state := SaveManager.peek_run(slot)
	if state == null:
		return "Slot %d\nNew run" % slot
	var text := "Slot %d\nDay %d  %s" % [slot, state.day, UIKit.money(state.wallet)]
	if not state.modifiers.is_empty():
		text += "\n%d modifier%s" % [state.modifiers.size(), "" if state.modifiers.size() == 1 else "s"]
	return text


## An empty slot starts a new run. A saved one opens its details card (continue or
## delete). Only a player on this machine can do either, so someone is here to answer;
## online the host's machine chooses the run.
func _on_slot_interacted(player_id: int, slot: int) -> void:
	if _run_panel.is_open() or not InputSetup.local_player_ids().has(player_id):
		return
	if SaveManager.has_run(slot):
		_run_panel.open(slot)
	else:
		_start_run(slot)


func _start_run(slot: int) -> void:
	if SaveManager.has_run(slot):
		GameFlow.continue_run(slot)
	else:
		GameFlow.new_run(slot)
	set_process(false)
	set_physics_process(false)   # a second press must not start the run twice


func _on_online_interacted(_player_id: int) -> void:
	if not _online_menu.visible:
		_online_menu.open()


func _say(text: String) -> void:
	_notice = text
	_notice_time = NOTICE_TIME


func _poll_joins(delta: float) -> void:
	for source in InputSetup.available_sources():
		if not NetworkManager.can_add_local_player():
			return
		if InputSetup.is_assigned(source):
			continue
		if InputSetup.is_interact_pressed(source):
			var held: float = _held.get(source, 0.0) + delta
			_held[source] = held
			if held >= HOLD_TIME:
				_held.erase(source)
				# Online, the host picks the new player's id; the room updates when it answers.
				InputSetup.assign(source, NetworkManager.is_online())
				NetworkManager.set_local_player_count(InputSetup.assigned_count())
				reconcile_players()
		else:
			_held.erase(source)


func _update_text() -> void:
	# Keep the panel focused on the party roster; the join glyphs are shown
	# separately in the HUD. No duplicate join, network, or back instructions.
	var lines := PackedStringArray()
	var occupied := {}
	for player_id in InputSetup.local_player_ids():
		occupied[player_id] = true
	for player_id in NetworkManager.remote_player_ids():
		occupied[player_id] = true

	for player_id in range(1, InputSetup.MAX_PLAYERS + 1):
		if occupied.has(player_id):
			var character := CharacterCatalog.character_name(CharacterCatalog.choice_for(player_id))
			lines.append("P%d  %s" % [player_id, character])
		else:
			lines.append("P%d  Open" % player_id)
	_status.text = "\n".join(lines)

## One line about the online session, or "" offline.
func _online_line() -> String:
	match NetworkManager.mode:
		NetworkManager.Mode.HOST:
			# A PC can have many addresses (VPNs, virtual adapters); two is plenty for a hint.
			var addresses := NetworkManager.local_addresses().slice(0, 2)
			return "Online: hosting, %d/%d players. Friends on your network join with %s" % [
				NetworkManager.player_count(), InputSetup.MAX_PLAYERS,
				", ".join(addresses) if not addresses.is_empty() else "(no address found)"]
		NetworkManager.Mode.CLIENT:
			return "Online: connected, %d/%d players" % [NetworkManager.player_count(), InputSetup.MAX_PLAYERS]
	return ""
