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
var _label: Label


func _ready() -> void:
	_ready_flags.resize(InputSetup.MAX_PLAYERS)
	for player_id in range(1, InputSetup.assigned_count() + 1):
		var source := InputSetup.source_of(player_id)
		_was_pressed[source] = InputSetup.is_interact_pressed(source)

	_label = Label.new()
	_label.position = Vector2(300, 160)
	_label.add_theme_font_size_override("font_size", 28)
	add_child(_label)


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
	var lines := PackedStringArray(["MOVING DAY!", ""])
	if InputSetup.assigned_count() < InputSetup.MAX_PLAYERS:
		lines.append("Hold E, Enter or gamepad A to join")
	lines.append("Press your interact button to ready up")
	lines.append("")
	for player_id in range(1, InputSetup.MAX_PLAYERS + 1):
		if player_id <= InputSetup.assigned_count():
			var state := "READY" if _ready_flags[player_id - 1] else "not ready"
			lines.append("Player %d: %s - %s" % [player_id, InputSetup.describe(InputSetup.source_of(player_id)), state])
		else:
			lines.append("Player %d: waiting..." % player_id)
	for source in _held:
		lines.append("Joining: %s %d%%" % [InputSetup.describe(source), roundi(_held[source] / HOLD_TIME * 100.0)])
	if _countdown >= 0.0:
		lines.append("")
		lines.append("Starting in %d" % ceili(_countdown))
	_label.text = "\n".join(lines)
