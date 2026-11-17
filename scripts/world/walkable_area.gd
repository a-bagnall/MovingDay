extends Node3D
class_name WalkableArea
## Base for the main menu and the hub: a small walkable room with the iso camera,
## spawned players, interact zones and a themed HUD. Subclasses set `room_size`
## in _init(), override _spawn_point(), and add zones in _ready() after super().
##
## Players here cannot grab anything (can_interact is false). Pressing interact
## on a zone emits that zone's `interacted` signal.
##
## Online, every machine shows every player: local players are driven by this
## machine's input, remote ones by state streamed from theirs. Pads that
## change the whole session (run slots, the truck) are decided by the host alone;
## pads marked `local_only` (such as opening a menu) react on the machine that
## pressed them.

const WALL_HEIGHT := 1.2   # same low walls as the test house, to keep the iso view readable
const WALL_THICKNESS := 0.3
const FLOOR_COLOR := Color(0.78, 0.65, 0.5)
const WALL_COLOR := Color(0.9, 0.88, 0.8)

## x and z extent of the room, centred on the origin. Set it in the subclass _init().
var room_size := Vector2(20.0, 12.0)

## How often this machine tells the others where its players are.
const NET_SEND_INTERVAL := 1.0 / 30.0

var _zones: Array[InteractZone] = []
var _interact_prev: Dictionary[int, bool] = {}
var _net_timer := 0.0


func _ready() -> void:
	_build_environment()
	_build_room()
	add_child(IsoCamera.new())
	NetworkManager.roster_changed.connect(reconcile_players)
	NetworkManager.player_states_received.connect(_on_player_states_received)
	reconcile_players()


func _physics_process(delta: float) -> void:
	_poll_zone_presses()
	_stream_local_players(delta)


func _poll_zone_presses() -> void:
	for player: Player in get_tree().get_nodes_in_group("players"):
		var pressed := player.input.interact
		if pressed and not _interact_prev.get(player.player_id, true):
			for zone in _zones:
				if _may_trigger(zone, player) and zone.players_inside().has(player):
					zone.interacted.emit(player.player_id)
		_interact_prev[player.player_id] = pressed


## Local-only pads answer to this machine's players; shared pads answer to everyone,
## but only on the host (clients see the result when the host acts).
func _may_trigger(zone: InteractZone, player: Player) -> bool:
	if zone.local_only:
		return player.is_local
	return not NetworkManager.is_online() or NetworkManager.is_host()


func _stream_local_players(delta: float) -> void:
	_net_timer += delta
	if _net_timer < NET_SEND_INTERVAL:
		return
	_net_timer = 0.0
	var states: Array = []
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_local:
			states.append(player.net_state())
	if not states.is_empty():
		NetworkManager.send_player_states(states)


func _on_player_states_received(peer_id: int, states: Array) -> void:
	var allowed: Array = NetworkManager.roster().get(peer_id, [])
	for state in states:
		if not (state is Array) or (state as Array).size() < 6:
			continue
		var player := _find_player(state[0])
		# Only accept states for players that peer actually owns.
		if player == null or player.is_local or not allowed.has(player.player_id):
			continue
		player.apply_net_state(state[1], state[3], state[4], state[5], state[2])


func _find_player(player_id: int) -> Player:
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.player_id == player_id:
			return player
	return null


## Makes the players in the room match the session: one for each local player that
## has an id, plus one for each player on another machine. Safe to call any time.
func reconcile_players() -> void:
	var wanted := {}   # player id -> is local
	for id in InputSetup.local_player_ids():
		wanted[id] = true
	for id in NetworkManager.remote_player_ids():
		wanted[id] = false

	for player: Player in get_tree().get_nodes_in_group("players"):
		if not wanted.has(player.player_id) or wanted[player.player_id] != player.is_local:
			player.remove_from_group("players")   # queue_free is deferred; leave the roster now
			player.queue_free()
			_interact_prev.erase(player.player_id)
	for id: int in wanted:
		if _find_player(id) == null:
			spawn_player(id, wanted[id])


## Where `player_id` appears. Override in the subclass.
func _spawn_point(_player_id: int) -> Vector3:
	return Vector3(0.0, 0.1, 0.0)


func spawn_player(player_id: int, local := true) -> void:
	var player := Player.new()
	player.player_id = player_id
	player.is_local = local
	player.can_interact = false
	player.position = _spawn_point(player_id)
	add_child(player)
	# A button still held from the join (or the previous screen) must be released
	# before it counts as a zone press.
	_interact_prev[player_id] = local and InputSetup.is_interact_pressed(InputSetup.source_of(player_id))


func add_zone(center: Vector3, size: Vector3, color: Color, text: String,
		local_only := false) -> InteractZone:
	var zone := InteractZone.new(size, color, text)
	zone.local_only = local_only
	zone.position = center
	add_child(zone)
	_zones.append(zone)
	return zone


## Builds the screen layout (title banner on top, status note at the bottom) and
## returns the status label for the subclass to update.
func _build_hud(title: String) -> Label:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := UIKit.setup(layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	column.add_child(UIKit.banner(title, 1300.0))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var note := PanelContainer.new()
	note.theme_type_variation = &"NotePanel"
	note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var status := UIKit.label("", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, &"DarkLabel")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 1800   # fixed width so long lines wrap instead of overflowing
	note.add_child(status)
	column.add_child(note)
	return status


# --- world ----------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.95)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_room() -> void:
	# Floor top sits at y = 0, matching the house floor.
	_add_box(Vector3(0.0, -0.15, 0.0), Vector3(room_size.x, 0.3, room_size.y), FLOOR_COLOR)
	var half := room_size * 0.5
	var wall_y := WALL_HEIGHT * 0.5
	_add_box(Vector3(0.0, wall_y, -half.y), Vector3(room_size.x, WALL_HEIGHT, WALL_THICKNESS), WALL_COLOR)
	_add_box(Vector3(0.0, wall_y, half.y), Vector3(room_size.x, WALL_HEIGHT, WALL_THICKNESS), WALL_COLOR)
	_add_box(Vector3(-half.x, wall_y, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, room_size.y), WALL_COLOR)
	_add_box(Vector3(half.x, wall_y, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, room_size.y), WALL_COLOR)


func _add_box(center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
