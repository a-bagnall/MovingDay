extends Node3D
class_name MovingTruck
## Box truck with a walk-up ramp. Cab, chassis and wheels come from a flat-deck
## model; the cargo bay is built from boxes, and its roof and walls are cut away
## on screen around any player standing inside.
## Local origin is the foot of the ramp on the ground; the truck extends along +x.

const MODEL := "res://assets/vehicles/delivery-flat.fbx"
const SHELL_SHADER := "res://assets/materials/truck_cutaway.gdshader"
const MODEL_SCALE := 2.0
## Model units: length, and distance from the model origin to its rear (-Z) end.
const MODEL_LENGTH := 3.25
const MODEL_REAR := 1.65

const RAMP_LENGTH := 3.5
const RAMP_WIDTH := 2.0
const RAMP_THICKNESS := 0.2

## Cargo floor top; clears the model's wheel arches.
const FLOOR_Y := 1.4
const BED_LENGTH := 4.2
const BED_WIDTH := 2.6
const BED_HEIGHT := 1.9
const WALL := 0.1
const CAB_HEIGHT := 2.7

## Must match the reveals array size in truck_cutaway.gdshader.
const REVEAL_SLOTS := 2
const REVEAL_FADE_SPEED := 4.0
## Chest height the reveal is centred on.
const REVEAL_HEIGHT := 0.9

var zone: DeliveryZone

var _shell := ShaderMaterial.new()
var _metal := StandardMaterial3D.new()
var _fade: Array[float] = [0.0, 0.0]


func _ready() -> void:
	_shell.shader = load(SHELL_SHADER)
	_metal.albedo_color = Color(0.55, 0.55, 0.6)
	_build_model()
	_build_ramp()
	_build_bed()
	_build_chassis_collision()
	_build_zone()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var players := get_tree().get_nodes_in_group("players")
	var reveals := PackedVector3Array()
	reveals.resize(REVEAL_SLOTS)
	for i in mini(players.size(), REVEAL_SLOTS):
		var player := players[i] as Node3D
		var target := 1.0 if _is_inside_bed(player.global_position) else 0.0
		_fade[i] = move_toward(_fade[i], target, delta * REVEAL_FADE_SPEED)
		var screen := camera.unproject_position(player.global_position + Vector3.UP * REVEAL_HEIGHT) / viewport_size
		reveals[i] = Vector3(screen.x, screen.y, _fade[i])
	_shell.set_shader_parameter("reveals", reveals)


func _is_inside_bed(world_pos: Vector3) -> bool:
	var p := to_local(world_pos)
	return (p.x > RAMP_LENGTH and p.x < RAMP_LENGTH + BED_LENGTH
		and absf(p.z) < BED_WIDTH * 0.5
		and p.y > FLOOR_Y - 0.1 and p.y < FLOOR_Y + BED_HEIGHT)


func _add_box(center: Vector3, size: Vector3, material: Material, collide: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
	if material:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = material
		if material == _shell:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mesh)
	add_child(body)
	return body


func _build_model() -> void:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * MODEL_SCALE
	model.rotation_degrees.y = 90.0
	model.position = Vector3(RAMP_LENGTH + MODEL_REAR * MODEL_SCALE, 0.0, 0.0)
	add_child(model)


func _build_ramp() -> void:
	var angle := atan2(FLOOR_Y, RAMP_LENGTH)
	var length := Vector2(RAMP_LENGTH, FLOOR_Y).length()
	var normal := Vector3(-sin(angle), cos(angle), 0.0)
	var mid := Vector3(RAMP_LENGTH, FLOOR_Y, 0.0) * 0.5
	var ramp := _add_box(mid - normal * RAMP_THICKNESS * 0.5,
		Vector3(length, RAMP_THICKNESS, RAMP_WIDTH), _metal, true)
	ramp.rotation.z = angle


func _build_bed() -> void:
	var bed_center_x := RAMP_LENGTH + BED_LENGTH * 0.5
	_add_box(Vector3(bed_center_x, FLOOR_Y - 0.2, 0.0),
		Vector3(BED_LENGTH, 0.4, BED_WIDTH), _metal, false)

	var wall_y := FLOOR_Y + BED_HEIGHT * 0.5
	var side_z := (BED_WIDTH + WALL) * 0.5
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(bed_center_x, wall_y, side * side_z),
			Vector3(BED_LENGTH, BED_HEIGHT, WALL), _shell, true)
	_add_box(Vector3(RAMP_LENGTH + BED_LENGTH + WALL * 0.5, wall_y, 0.0),
		Vector3(WALL, BED_HEIGHT, BED_WIDTH + 2.0 * WALL), _shell, true)
	_add_box(Vector3(RAMP_LENGTH + (BED_LENGTH + WALL) * 0.5, FLOOR_Y + BED_HEIGHT + WALL * 0.5, 0.0),
		Vector3(BED_LENGTH + WALL, WALL, BED_WIDTH + 2.0 * WALL), _shell, true)


func _build_chassis_collision() -> void:
	var total := MODEL_LENGTH * MODEL_SCALE
	_add_box(Vector3(RAMP_LENGTH + total * 0.5, FLOOR_Y * 0.5, 0.0),
		Vector3(total, FLOOR_Y, BED_WIDTH), null, true)
	var cab_length := total - BED_LENGTH
	_add_box(Vector3(RAMP_LENGTH + BED_LENGTH + cab_length * 0.5, CAB_HEIGHT * 0.5, 0.0),
		Vector3(cab_length, CAB_HEIGHT, BED_WIDTH), null, true)


func _build_zone() -> void:
	zone = DeliveryZone.new()
	zone.size = Vector3(BED_LENGTH, BED_HEIGHT, BED_WIDTH)
	zone.position = Vector3(RAMP_LENGTH + BED_LENGTH * 0.5, FLOOR_Y, 0.0)
	add_child(zone)
