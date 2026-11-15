extends Node3D
class_name WalkableArea
## Base for the main menu and the hub: a small walkable room with the iso camera,
## spawned players, interact zones and a themed HUD. Subclasses set `room_size`
## in _init(), override _spawn_point(), and add zones in _ready() after super().
##
## Players here cannot grab anything (can_interact is false). Pressing interact
## on a zone emits that zone's `interacted` signal.

const WALL_HEIGHT := 1.2   # same low walls as the test house, to keep the iso view readable
const WALL_THICKNESS := 0.3
const FLOOR_COLOR := Color(0.78, 0.65, 0.5)
const WALL_COLOR := Color(0.9, 0.88, 0.8)

## x and z extent of the room, centred on the origin. Set it in the subclass _init().
var room_size := Vector2(20.0, 12.0)

var _zones: Array[InteractZone] = []
var _interact_prev: Dictionary[int, bool] = {}


func _ready() -> void:
	_build_environment()
	_build_room()
	add_child(IsoCamera.new())
	for player_id in range(1, InputSetup.assigned_count() + 1):
		spawn_player(player_id)


func _physics_process(_delta: float) -> void:
	for player: Player in get_tree().get_nodes_in_group("players"):
		var pressed := InputSetup.is_interact_pressed(InputSetup.source_of(player.player_id))
		if pressed and not _interact_prev.get(player.player_id, true):
			for zone in _zones:
				if zone.players_inside().has(player):
					zone.interacted.emit(player.player_id)
		_interact_prev[player.player_id] = pressed


## Where `player_id` appears. Override in the subclass.
func _spawn_point(_player_id: int) -> Vector3:
	return Vector3(0.0, 0.1, 0.0)


func spawn_player(player_id: int) -> void:
	var player := Player.new()
	player.player_id = player_id
	player.can_interact = false
	player.position = _spawn_point(player_id)
	add_child(player)
	# A button still held from the join (or the previous screen) must be released
	# before it counts as a zone press.
	_interact_prev[player_id] = InputSetup.is_interact_pressed(InputSetup.source_of(player_id))


func add_zone(center: Vector3, size: Vector3, color: Color, text: String) -> InteractZone:
	var zone := InteractZone.new(size, color, text)
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

	var banner := PanelContainer.new()
	banner.theme_type_variation = &"BannerPanel"
	banner.custom_minimum_size = Vector2(1300, 0)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner.add_child(UIKit.label(title, UIKit.FONT_TITLE, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(banner)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var note := PanelContainer.new()
	note.theme_type_variation = &"NotePanel"
	note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var status := UIKit.label("", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, &"DarkLabel")
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
