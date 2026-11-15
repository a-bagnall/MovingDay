extends Node
## Input sources and player assignment. A source is a keyboard scheme (negative
## id) or a gamepad (its device id, >= 0). Sources claim a player number on the
## join screen. Keyboard actions are registered here; gamepads are read per
## device because InputMap actions cannot be limited to one device.

const KB_WASD := -1
const KB_ARROWS := -2
const MAX_PLAYERS := 2
const JOY_DEADZONE := 0.2

const ACTIONS := ["up", "down", "left", "right", "interact"]

const KEYS := {
	KB_WASD: {
		"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D,
		"interact": KEY_E,
	},
	KB_ARROWS: {
		"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"interact": KEY_ENTER,
	},
}

var _players: Array[int] = []   # index = player_id - 1, value = source


func _ready() -> void:
	for source: int in KEYS.keys():
		for action: String in ACTIONS:
			var action_name := _action(source, action)
			InputMap.add_action(action_name, JOY_DEADZONE)
			var key_event := InputEventKey.new()
			key_event.physical_keycode = KEYS[source][action]
			InputMap.action_add_event(action_name, key_event)


func available_sources() -> Array[int]:
	var out: Array[int] = [KB_WASD, KB_ARROWS]
	out.append_array(Input.get_connected_joypads())
	return out


func describe(source: int) -> String:
	match source:
		KB_WASD:
			return "Keyboard (WASD + E)"
		KB_ARROWS:
			return "Keyboard (Arrows + Enter)"
		_:
			return "%s (A)" % Input.get_joy_name(source)


func assign(source: int) -> void:
	_players.append(source)


func is_assigned(source: int) -> bool:
	return _players.has(source)


func assigned_count() -> int:
	return _players.size()


func source_of(player_id: int) -> int:
	return _players[player_id - 1]


func get_move(source: int) -> Vector2:
	if source < 0:
		return Input.get_vector(
			_action(source, "left"), _action(source, "right"),
			_action(source, "up"), _action(source, "down"))
	var stick := Vector2(
		Input.get_joy_axis(source, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(source, JOY_AXIS_LEFT_Y))
	return stick.limit_length(1.0) if stick.length() > JOY_DEADZONE else Vector2.ZERO


func is_interact_pressed(source: int) -> bool:
	if source < 0:
		return Input.is_action_pressed(_action(source, "interact"))
	return Input.is_joy_button_pressed(source, JOY_BUTTON_A)


func _action(source: int, action: String) -> String:
	return "kb%d_%s" % [-source, action]
