extends Node
## Input sources and player assignment. A source is a keyboard scheme (negative
## id) or a gamepad (its device id, >= 0). Sources claim a player number on the
## join screen. Keyboard actions are registered here; gamepads are read per
## device because InputMap actions cannot be limited to one device.

const KB_WASD := -1
const KB_ARROWS := -2
const MAX_PLAYERS := 4
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

var _players: Array[int] = []   # source of each local player, in join order
## Player id of each local player (same order as _players). Offline that is 1, 2, 3...
## Online the host hands the ids out (see NetworkManager), so a machine's players can
## be, say, 1 and 4. 0 means "joined, but the host has not given an id yet".
var _ids: Array[int] = []
## True while a typing UI is open: keyboard sources then read as idle, so typing
## an address does not walk anyone around. Gamepads are unaffected.
var ui_captured := false


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
	if source < 0:
		if ui_captured:
			return Vector2.ZERO
		return Input.get_vector(
			_action(source, "left"), _action(source, "right"),
			_action(source, "up"), _action(source, "down"))
	var stick := Vector2(
		Input.get_joy_axis(source, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(source, JOY_AXIS_LEFT_Y))
	return stick.limit_length(1.0) if stick.length() > JOY_DEADZONE else Vector2.ZERO


func is_interact_pressed(source: int) -> bool:
	if source < 0:
		if ui_captured:
			return false
		return Input.is_action_pressed(_action(source, "interact"))
	return Input.is_joy_button_pressed(source, JOY_BUTTON_A)


func _action(source: int, action: String) -> String:
	return "kb%d_%s" % [-source, action]
