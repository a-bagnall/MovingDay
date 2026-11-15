extends WalkableArea
class_name MainMenu
## Main scene. Input sources (keyboard scheme or gamepad) join by holding interact;
## each joined player appears in the room. Standing on a run-slot pad and pressing
## interact starts a new run (empty slot) or continues the saved one.

const HOLD_TIME := 0.8
const SLOT_SPACING := 5.0
const SLOT_Z := -2.0
const PAD_SIZE := Vector3(3.0, 0.1, 3.0)
const SLOT_COLOR := Color(0.95, 0.75, 0.3)
const PLACEHOLDER_COLOR := Color(0.6, 0.6, 0.65)

var _held: Dictionary[int, float] = {}
var _status: Label


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


func _spawn_point(player_id: int) -> Vector3:
	return Vector3((player_id - 1.5) * 1.5, 0.1, 3.0)


func _process(delta: float) -> void:
	_poll_joins(delta)
	_update_text()


func _slot_text(slot: int) -> String:
	var state := SaveManager.peek_run(slot)
	if state == null:
		return "Slot %d\nNew run" % slot
	return "Slot %d\nDay %d  %s" % [slot, state.day, UIKit.money(state.wallet)]


func _on_slot_interacted(_player_id: int, slot: int) -> void:
	if SaveManager.has_run(slot):
		GameFlow.continue_run(slot)
	else:
		GameFlow.new_run(slot)
	set_process(false)
	set_physics_process(false)   # a second press must not start the run twice


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
				spawn_player(InputSetup.assigned_count())
		else:
			_held.erase(source)


func _update_text() -> void:
	var lines := PackedStringArray()
	if InputSetup.assigned_count() < InputSetup.MAX_PLAYERS:
		lines.append("Hold E, Enter or gamepad A to join")
	if InputSetup.assigned_count() > 0:
		lines.append("Stand on a slot and press interact to play")
	lines.append("")
	for player_id in range(1, InputSetup.MAX_PLAYERS + 1):
		if player_id <= InputSetup.assigned_count():
			lines.append("Player %d: %s" % [player_id, InputSetup.describe(InputSetup.source_of(player_id))])
		else:
			lines.append("Player %d: waiting..." % player_id)
	for source in _held:
		lines.append("Joining: %s %d%%" % [InputSetup.describe(source), roundi(_held[source] / HOLD_TIME * 100.0)])
	_status.text = "\n".join(lines)
