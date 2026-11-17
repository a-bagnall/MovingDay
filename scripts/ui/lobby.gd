extends CanvasLayer
class_name Lobby
## Pre-job lobby. Input sources (keyboard scheme or gamepad) join by holding
## interact and the level spawns that player; each joined player then presses
## interact to toggle ready. Once everyone is ready a countdown runs, and at
## zero `started` fires. Un-readying cancels the countdown.

signal player_joined(player_id: int)
signal started

const HOLD_TIME := 0.8
const COUNTDOWN_TIME := 5.0

var _held: Dictionary[int, float] = {}
var _was_pressed: Dictionary[int, bool] = {}
var _ready_flags: Array[bool] = []
var _countdown := -1.0
var _hint: Label
var _cards: Array[Dictionary] = []   # per slot: {panel, name, device, state}


func _ready() -> void:
	_ready_flags.resize(InputSetup.MAX_PLAYERS)
	for player_id in range(1, InputSetup.assigned_count() + 1):
		var source := InputSetup.source_of(player_id)
		_was_pressed[source] = InputSetup.is_interact_pressed(source)

	var root := UIKit.setup(self)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIKit.SPACE_L)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	column.add_child(UIKit.banner("MOVING DAY!", 1300.0))

	# One card per player slot, so who is in and who is ready reads at a glance.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIKit.SPACE_M)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(row)
	for player_id in range(1, InputSetup.MAX_PLAYERS + 1):
		row.add_child(_build_card(player_id))

	var note := PanelContainer.new()
	note.theme_type_variation = &"NotePanel"
	note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint = UIKit.label("", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER, &"DarkLabel")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 1700   # fixed width so the countdown does not resize the card
	note.add_child(_hint)
	column.add_child(note)


func _build_card(player_id: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 360)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIKit.SPACE_S)
	panel.add_child(box)
	var name_label := UIKit.label("P%d" % player_id, UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(name_label)
	var device_icon := TextureRect.new()
	device_icon.custom_minimum_size = Vector2(220, 120)
	device_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	device_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	device_icon.visible = false
	box.add_child(device_icon)
	var device := UIKit.label("", UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel")
	device.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	device.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(device)
	var state := UIKit.label("", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(state)
	_cards.append({"panel": panel, "device": device, "device_icon": device_icon, "state": state})
	return panel


func _process(delta: float) -> void:
	_poll_joins(delta)
	_poll_ready()
	_update_countdown(delta)
	_update_text()


func _poll_joins(delta: float) -> void:
	for source in InputSetup.available_sources():
		if InputSetup.assigned_count() >= InputSetup.MAX_PLAYERS:
			return
		if InputSetup.is_assigned(source):
			continue
		if InputSetup.is_interact_pressed(source):
			var held: float = _held.get(source, 0.0) + delta
			_held[source] = held
			if held >= HOLD_TIME:
				_held.erase(source)
				InputSetup.assign(source)
				# The join hold must not count as the first ready press.
				_was_pressed[source] = true
				player_joined.emit(InputSetup.assigned_count())
		else:
			_held.erase(source)


func _poll_ready() -> void:
	for player_id in range(1, InputSetup.assigned_count() + 1):
		var source := InputSetup.source_of(player_id)
		var pressed := InputSetup.is_interact_pressed(source)
		if pressed and not _was_pressed.get(source, false):
			_ready_flags[player_id - 1] = not _ready_flags[player_id - 1]
		_was_pressed[source] = pressed


func _update_countdown(delta: float) -> void:
	if _ready_flags.has(false):
		_countdown = -1.0
		return
	if _countdown < 0.0:
		_countdown = COUNTDOWN_TIME
	_countdown -= delta
	if _countdown <= 0.0:
		started.emit()
		queue_free()


func _update_text() -> void:
	var joined := InputSetup.assigned_count()
	for i in _cards.size():
		var card: Dictionary = _cards[i]
		var device: Label = card["device"]
		var state: Label = card["state"]
		var panel: Control = card["panel"]
		var device_icon: TextureRect = card["device_icon"]
		var player_id := i + 1
		var joining := _joining_text()
		if player_id <= joined:
			var source := InputSetup.source_of(player_id)
			device_icon.texture = UIKit.device_texture(source)
			device_icon.visible = true
			var player_ready: bool = _ready_flags[i]
			device.text = _device_name(source)
			state.text = "READY" if player_ready else "NOT READY"
			state.add_theme_color_override("font_color", UIKit.SUCCESS if player_ready else UIKit.PINK)
			panel.modulate.a = 1.0
		elif player_id == joined + 1 and not joining.is_empty():
			device_icon.texture = UIKit.device_texture(_joining_source())
			device_icon.visible = true
			device.text = joining
			state.text = "JOINING"
			state.add_theme_color_override("font_color", UIKit.GOLD)
			panel.modulate.a = 1.0
		else:
			device_icon.visible = false
			device.text = ""
			state.text = "WAITING"
			state.add_theme_color_override("font_color", UIKit.MUTED)
			panel.modulate.a = 0.55   # an empty slot recedes

	var lines := PackedStringArray()
	if _countdown >= 0.0:
		lines.append("Starting in %d. Press %s to cancel." % [ceili(_countdown), UIKit.INTERACT_KEYS])
	else:
		if joined < InputSetup.MAX_PLAYERS:
			lines.append("Hold %s to join" % UIKit.INTERACT_KEYS)
		lines.append("Press %s to ready up. The job starts when everyone is ready." % UIKit.INTERACT_KEYS)
	_hint.text = "\n".join(lines)


## Source currently holding to join, or -99 when nobody is joining.
func _joining_source() -> int:
	for source in _held:
		return source
	return -99


## "Keyboard 1  45%" for whichever source is currently holding to join, or "".
func _joining_text() -> String:
	var source := _joining_source()
	if source == -99:
		return ""
	return "%s\n%d%%" % [_device_name(source), roundi(_held[source] / HOLD_TIME * 100.0)]


## A short name that fits a card; the full control list is in the README.
func _device_name(source: int) -> String:
	if source == InputSetup.KB_WASD:
		return "Keyboard\nWASD + E"
	if source == InputSetup.KB_ARROWS:
		return "Keyboard\nArrows + Enter"
	var name := Input.get_joy_name(source)
	return "Controller\n%s" % (name if not name.is_empty() else "Gamepad")
