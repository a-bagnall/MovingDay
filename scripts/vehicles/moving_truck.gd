extends Node3D
class_name MovingTruck
## Box truck with a walk-up ramp. Cab, chassis and wheels come from a flat-deck
## model; the cargo bay is built from boxes, and its roof and walls are cut away
## on screen around any player standing inside.
## Local origin is the foot of the ramp on the ground; the truck extends along +x.

const MODEL := "res://assets/vehicles/delivery-flat.fbx"
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

var zone: DeliveryZone

var _cutaway: CutawayReveal
var _metal := StandardMaterial3D.new()


func _ready() -> void:
	var bed := AABB(Vector3(RAMP_LENGTH, FLOOR_Y - 0.1, -BED_WIDTH * 0.5),
		Vector3(BED_LENGTH, BED_HEIGHT + 0.1, BED_WIDTH))
	_cutaway = CutawayReveal.create(self, bed, Color(0.92, 0.93, 0.97))
	add_child(_cutaway)
	_metal.albedo_color = Color(0.55, 0.55, 0.6)
	_build_model()
	_build_ramp()
	_build_bed()
	_build_chassis_collision()
	_build_zone()


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
		if material == _cutaway.material:
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
			Vector3(BED_LENGTH, BED_HEIGHT, WALL), _cutaway.material, true)
	_add_box(Vector3(RAMP_LENGTH + BED_LENGTH + WALL * 0.5, wall_y, 0.0),
		Vector3(WALL, BED_HEIGHT, BED_WIDTH + 2.0 * WALL), _cutaway.material, true)
	_add_box(Vector3(RAMP_LENGTH + (BED_LENGTH + WALL) * 0.5, FLOOR_Y + BED_HEIGHT + WALL * 0.5, 0.0),
		Vector3(BED_LENGTH + WALL, WALL, BED_WIDTH + 2.0 * WALL), _cutaway.material, true)


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
