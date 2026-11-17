extends Node
## Input sources and player assignment. A source is a keyboard scheme (negative
## id) or a gamepad (its device id, >= 0). Sources claim a player number on the
## join screen. Keyboard actions are registered here; gamepads are read per
## device because InputMap actions cannot be limited to one device.

const KB_WASD := -1
const KB_ARROWS := -2
const MAX_PLAYERS := 4
const JOY_DEADZONE := 0.2

## Buttons beyond movement and interact. Lift is held; Action and Ping are pressed.
const BUTTONS := ["lift", "action", "ping", "heave"]
## How far a gamepad trigger must be pulled to count as pressed.
const TRIGGER_PRESSED := 0.5

const ACTIONS := ["up", "down", "left", "right", "interact", "lift", "action", "ping", "heave"]

const KEYS := {
	KB_WASD: {
		"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D,
		"interact": KEY_E, "lift": KEY_Q, "action": KEY_R, "ping": KEY_F, "heave": KEY_SPACE,
	},
	KB_ARROWS: {
		"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"interact": KEY_ENTER, "lift": KEY_SHIFT, "action": KEY_CTRL, "ping": KEY_SLASH, "heave": KEY_PERIOD,
	},
}

## Keys that exist on both sides of the keyboard: the arrow scheme only wants the right one.
const RIGHT_SIDE_ONLY := [KEY_SHIFT, KEY_CTRL]

var _players: Array[int] = []   # source of each local player, in join order
## Player id of each local player (same order as _players). Offline that is 1, 2, 3...
## Online the host hands the ids out (see NetworkManager), so a machine's players can
## be, say, 1 and 4. 0 means "joined, but the host has not given an id yet".
var _ids: Array[int] = []
## True while a menu card is open: every source (keyboard and gamepad) then reads as
## idle, so navigating the card does not walk anyone around or press interact pads.
## The card itself is driven by Godot's UI focus (d-pad, stick, A, B).
var ui_captured := false


func _ready() -> void:
	_ensure_gamepad_ui_events()
	for source: int in KEYS.keys():
		for action: String in ACTIONS:
			var action_name := _action(source, action)
			InputMap.add_action(action_name, JOY_DEADZONE)
			var key_event := InputEventKey.new()
			key_event.physical_keycode = KEYS[source][action]
			if source == KB_ARROWS and RIGHT_SIDE_ONLY.has(KEYS[source][action]):
				key_event.location = KEY_LOCATION_RIGHT
			InputMap.action_add_event(action_name, key_event)


## Menus run on Godot's ui_* actions. Make sure each has its gamepad button even if the
## engine defaults leave one out: A accepts, B goes back, d-pad moves the focus.
func _ensure_gamepad_ui_events() -> void:
	var wanted := {
		"ui_accept": JOY_BUTTON_A,
		"ui_cancel": JOY_BUTTON_B,
		"ui_up": JOY_BUTTON_DPAD_UP,
		"ui_down": JOY_BUTTON_DPAD_DOWN,
		"ui_left": JOY_BUTTON_DPAD_LEFT,
		"ui_right": JOY_BUTTON_DPAD_RIGHT,
	}
	for action: String in wanted:
		if not InputMap.has_action(action):
			continue
		var has_button := false
		for event in InputMap.action_get_events(action):
			var pad := event as InputEventJoypadButton
			if pad and pad.button_index == wanted[action]:
				has_button = true
		if not has_button:
			var button := InputEventJoypadButton.new()
			button.button_index = wanted[action]
			InputMap.action_add_event(action, button)


func available_sources() -> Array[int]:
	var out: Array[int] = [KB_WASD, KB_ARROWS]
	out.append_array(Input.get_connected_joypads())
	return out


## Short label for rosters: the full bindings live on the pause menu's Controls page.
func short_name(source: int) -> String:
	match source:
		KB_WASD:
			return "Keyboard (WASD)"
		KB_ARROWS:
			return "Keyboard (arrows)"
		_:
			return Input.get_joy_name(source)


func describe(source: int) -> String:
	match source:
		KB_WASD:
			return "Keyboard (WASD + E, Q lift, R action, F ping, Space heave-ho)"
		KB_ARROWS:
			return "Keyboard (Arrows + Enter, R-Shift lift, R-Ctrl action, / ping, . heave-ho)"
		_:
			return "%s (A)" % Input.get_joy_name(source)


## Claims a player for `source`. Offline the id is its position in join order; when
## `awaiting_id` is true (online) it stays 0 until the host assigns one.
func assign(source: int, awaiting_id := false) -> void:
	_players.append(source)
	_ids.append(0 if awaiting_id else _players.size())


func is_assigned(source: int) -> bool:
	return _players.has(source)


## Number of local players, including any still waiting for an id.
func assigned_count() -> int:
	return _players.size()


## Ids of the local players that have one. Use this, not 1..assigned_count(), to
## spawn or poll local players, because online ids are not consecutive.
func local_player_ids() -> Array[int]:
	var out: Array[int] = []
	for id in _ids:
		if id > 0:
			out.append(id)
	return out


## The input source driving player `player_id` (one of this machine's players).
func source_of(player_id: int) -> int:
	var index := _ids.find(player_id)
	assert(index >= 0, "Player %d is not a local player" % player_id)
	return _players[index]


## Online: takes the ids the host granted this machine, in order. Local players
## beyond the list keep waiting.
func apply_ids(ids: Array[int]) -> void:
	for i in _players.size():
		_ids[i] = ids[i] if i < ids.size() else 0


## Drops the newest local players until only `count` remain (the host had no room).
func truncate(count: int) -> void:
	while _players.size() > maxi(count, 0):
		_players.pop_back()
		_ids.pop_back()


## Back to offline numbering (1, 2, 3...), e.g. after leaving an online session.
func reset_ids() -> void:
	for i in _ids.size():
		_ids[i] = i + 1


func get_move(source: int) -> Vector2:
	if ui_captured:
		return Vector2.ZERO
	if source < 0:
		return Input.get_vector(
			_action(source, "left"), _action(source, "right"),
			_action(source, "up"), _action(source, "down"))
	var stick := Vector2(
		Input.get_joy_axis(source, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(source, JOY_AXIS_LEFT_Y))
	return stick.limit_length(1.0) if stick.length() > JOY_DEADZONE else Vector2.ZERO


func is_interact_pressed(source: int) -> bool:
	if ui_captured:
		return false
	if source < 0:
		return Input.is_action_pressed(_action(source, "interact"))
	return Input.is_joy_button_pressed(source, JOY_BUTTON_A)


## Whether `button` ("lift", "action", "ping" or "heave") is held for `source`. Gamepad: left
## trigger is lift, X is action, Y is ping, B is heave-ho.
func is_button_pressed(source: int, button: String) -> bool:
	if ui_captured:
		return false
	if source < 0:
		return Input.is_action_pressed(_action(source, button))
	match button:
		"lift":
			return Input.get_joy_axis(source, JOY_AXIS_TRIGGER_LEFT) > TRIGGER_PRESSED
		"action":
			return Input.is_joy_button_pressed(source, JOY_BUTTON_X)
		"ping":
			return Input.is_joy_button_pressed(source, JOY_BUTTON_Y)
		"heave":
			return Input.is_joy_button_pressed(source, JOY_BUTTON_B)
	return false


func _action(source: int, action: String) -> String:
	return "kb%d_%s" % [-source, action]
