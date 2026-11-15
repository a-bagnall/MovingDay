extends WalkableArea
class_name MainMenu
## Main scene. Input sources (keyboard scheme or gamepad) join by holding interact;
## each joined player appears in the room, and so do players on other machines when
## playing online (any mix of local and online players, up to InputSetup.MAX_PLAYERS).
## Standing on a run-slot pad and pressing interact starts a new run (empty slot) or
## continues the saved one. The Online pad opens a small host/join panel over the
## room; closing it leaves the connection (and everyone in the room) as it is.
##
## Jobs are not synchronised between machines yet, so a run cannot start while other
## machines are connected. Flip ONLINE_JOBS_READY once they are.

const HOLD_TIME := 0.8
const SLOT_SPACING := 5.0
const SLOT_Z := -2.0
const PAD_SIZE := Vector3(3.0, 0.1, 3.0)
const SLOT_COLOR := Color(0.95, 0.75, 0.3)
const PLACEHOLDER_COLOR := Color(0.6, 0.6, 0.65)
const ONLINE_COLOR := Color(0.4, 0.7, 0.9)
const ONLINE_JOBS_READY := false
const NOTICE_TIME := 4.0

var _held: Dictionary[int, float] = {}
var _status: Label
var _online_menu: OnlineMenu
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
	add_zone(Vector3(7.0, 0.0, 2.5), PAD_SIZE, PLACEHOLDER_COLOR, "Wardrobe\nComing soon")
	var online := add_zone(Vector3(-7.0, 0.0, 2.5), PAD_SIZE, ONLINE_COLOR, "Online\nHost or join", true)
	online.interacted.connect(_on_online_interacted)

	_online_menu = OnlineMenu.new()
	add_child(_online_menu)


func _spawn_point(player_id: int) -> Vector3:
	return Vector3((player_id - 1.5) * 1.5, 0.1, 3.0)


func _process(delta: float) -> void:
	_notice_time = maxf(_notice_time - delta, 0.0)
	if not _online_menu.visible:   # typing an address must not also join players
		_poll_joins(delta)
	_update_text()


func _slot_text(slot: int) -> String:
	var state := SaveManager.peek_run(slot)
	if state == null:
		return "Slot %d\nNew run" % slot
	return "Slot %d\nDay %d  %s" % [slot, state.day, UIKit.money(state.wallet)]


func _on_slot_interacted(_player_id: int, slot: int) -> void:
	if not ONLINE_JOBS_READY and NetworkManager.peer_count() > 1:
		_say("Online jobs aren't ready yet - disconnect to play together on this computer")
		return
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
	var lines := PackedStringArray()
	if _notice_time > 0.0:
		lines.append(_notice)
		lines.append("")
	if NetworkManager.can_add_local_player():
		lines.append("Hold E, Enter or gamepad A to join")
	if InputSetup.assigned_count() > 0:
		if NetworkManager.mode == NetworkManager.Mode.CLIENT:
			lines.append("The host chooses the run")
		else:
			lines.append("Stand on a slot and press interact to play")
	var online := _online_line()
	if not online.is_empty():
		lines.append(online)
	lines.append("")

	var remote := NetworkManager.remote_player_ids()
	for player_id in range(1, InputSetup.MAX_PLAYERS + 1):
		if InputSetup.local_player_ids().has(player_id):
			lines.append("Player %d: %s" % [player_id, InputSetup.describe(InputSetup.source_of(player_id))])
		elif remote.has(player_id):
			lines.append("Player %d: online" % player_id)
		else:
			lines.append("Player %d: waiting..." % player_id)
	for source in _held:
		lines.append("Joining: %s %d%%" % [InputSetup.describe(source), roundi(_held[source] / HOLD_TIME * 100.0)])
	_status.text = "\n".join(lines)


## One line about the online session, or "" offline.
func _online_line() -> String:
	match NetworkManager.mode:
		NetworkManager.Mode.HOST:
			var addresses := NetworkManager.local_addresses()
			return "Online: hosting, %d/%d players. Friends on your network join with %s" % [
				NetworkManager.player_count(), InputSetup.MAX_PLAYERS,
				", ".join(addresses) if not addresses.is_empty() else "(no address found)"]
		NetworkManager.Mode.CLIENT:
			return "Online: connected, %d/%d players" % [NetworkManager.player_count(), InputSetup.MAX_PLAYERS]
	return ""
