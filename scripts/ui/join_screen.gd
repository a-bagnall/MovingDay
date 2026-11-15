extends CanvasLayer
class_name JoinScreen
## Lets each input source (keyboard scheme or gamepad) claim a player number by
## holding its interact button. Emits all_joined once every slot is taken.

signal all_joined

const HOLD_TIME := 0.8

var _held: Dictionary[int, float] = {}
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(300, 160)
	_label.add_theme_font_size_override("font_size", 28)
	add_child(_label)


func _process(delta: float) -> void:
	for source in InputSetup.available_sources():
		if InputSetup.assigned_count() >= InputSetup.MAX_PLAYERS:
			break
		if InputSetup.is_assigned(source):
			continue
		if InputSetup.is_interact_pressed(source):
			var held: float = _held.get(source, 0.0) + delta
			_held[source] = held
			if held >= HOLD_TIME:
				InputSetup.assign(source)
				_held.erase(source)
		else:
			_held.erase(source)

	_update_text()
	if InputSetup.assigned_count() >= InputSetup.MAX_PLAYERS:
		all_joined.emit()
		queue_free()


func _update_text() -> void:
	var lines := PackedStringArray(["MOVING DAY!", "Hold E, Enter or gamepad A to join", ""])
	for player_id in range(1, InputSetup.MAX_PLAYERS + 1):
		if player_id <= InputSetup.assigned_count():
			lines.append("Player %d: %s" % [player_id, InputSetup.describe(InputSetup.source_of(player_id))])
		else:
			lines.append("Player %d: waiting..." % player_id)
	for source in _held:
		lines.append("Joining: %s %d%%" % [InputSetup.describe(source), roundi(_held[source] / HOLD_TIME * 100.0)])
	_label.text = "\n".join(lines)
