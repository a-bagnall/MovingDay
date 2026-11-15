extends CharacterBody3D
class_name Player
## Shared gameplay controller for every animal. Species differences are purely
## visual: assign a different `model_scene` and nothing here changes.
##
## Movement is deliberately weighty: acceleration, gradual braking, sluggish
## direction reversals, and an occasional stumble on abrupt reversals at speed.

@export var player_id: int = 1
## Optional GLB/PackedScene for the character model. Should face -Z.
@export var model_scene: PackedScene
@export var model_scale: float = 1.0

@export_group("Movement")
@export var max_speed: float = 5.0
@export var acceleration: float = 14.0
@export var braking: float = 9.0
@export var reversal_penalty: float = 0.6  ## <1 makes direction reversals sluggish
@export var turn_speed: float = 9.0
@export var gravity: float = 24.0
@export var stumble_time: float = 0.55

@export_group("Interaction")
@export var reach: float = 1.8
@export var push_strength: float = 0.05

## Camera yaw the input is rotated by, so "up" on the stick is "up" on screen.
const CAMERA_YAW := PI / 4.0

## Set each frame by the furniture being carried (1.0 = unencumbered).
var speed_multiplier: float = 1.0
var held_furniture: Furniture = null
## False while in the lobby: players can move but not grab.
var can_interact := true

var _visual: Node3D
var _source: int
var _interact_prev := false
var _prev_input_dir := Vector3.ZERO
var _stumble_left := 0.0


func _ready() -> void:
	_source = InputSetup.source_of(player_id)
	_interact_prev = InputSetup.is_interact_pressed(_source)
	add_to_group("players")
	collision_layer = 1 << 1          # layer 2: players
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2)  # world, players, furniture
	_build_collision()
	_build_visual()


func _build_collision() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.3
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.65
	add_child(col)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	if model_scene:
		var model := model_scene.instantiate()
		if model is Node3D:
			(model as Node3D).scale = Vector3.ONE * model_scale
		_visual.add_child(model)
		return

	# Placeholder: coloured capsule with a "nose" so facing is readable.
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.3
	mesh.mesh = capsule
	mesh.position.y = 0.65
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.45, 0.2) if player_id == 1 else Color(0.25, 0.55, 0.9)
	mesh.material_override = mat
	_visual.add_child(mesh)

	var nose := MeshInstance3D.new()
	nose.mesh = BoxMesh.new()
	nose.scale = Vector3(0.2, 0.2, 0.3)
	nose.position = Vector3(0, 0.9, -0.45)
	_visual.add_child(nose)


func _physics_process(delta: float) -> void:
	var input := InputSetup.get_move(_source)
	var input_dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, CAMERA_YAW)

	_stumble_left = maxf(_stumble_left - delta, 0.0)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	_check_stumble(input_dir, horizontal)

	var control := 0.25 if _stumble_left > 0.0 else 1.0
	var target := input_dir * max_speed * speed_multiplier * control
	var rate := acceleration if input_dir.length() > 0.01 else braking
	rate *= lerpf(0.5, 1.0, speed_multiplier)
	if horizontal.dot(target) < 0.0:
		rate *= reversal_penalty
	horizontal = horizontal.move_toward(target, rate * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	if held_furniture:
		_face_point(held_furniture.global_position, delta)
	else:
		_update_facing(horizontal, delta)
	move_and_slide()
	if held_furniture:
		held_furniture.pull_holder(self)
	_push_rigid_bodies()

	if input_dir.length() > 0.5:
		_prev_input_dir = input_dir.normalized()

	var interact_held := InputSetup.is_interact_pressed(_source)
	if interact_held and not _interact_prev and can_interact:
		_interact()
	_interact_prev = interact_held


func _check_stumble(input_dir: Vector3, horizontal: Vector3) -> void:
	if _stumble_left > 0.0 or held_furniture != null:
		return
	if input_dir.length() < 0.5 or _prev_input_dir == Vector3.ZERO:
		return
	var fast := horizontal.length() > max_speed * 0.8
	var reversed := _prev_input_dir.dot(input_dir.normalized()) < -0.8
	if fast and reversed:
		_stumble_left = stumble_time


func _update_facing(horizontal: Vector3, delta: float) -> void:
	if horizontal.length() < 0.3:
		return
	var target_angle := atan2(-horizontal.x, -horizontal.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_angle, clampf(turn_speed * delta, 0.0, 1.0))


## While carrying, always face the item so the player looks like they are gripping it.
func _face_point(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	var target_angle := atan2(-to.x, -to.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_angle, clampf(turn_speed * 1.5 * delta, 0.0, 1.0))


func get_facing() -> Vector3:
	var a := _visual.rotation.y if _visual else 0.0
	return Vector3(-sin(a), 0.0, -cos(a))


func _push_rigid_bodies() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider()
		if body is RigidBody3D and not (body is Furniture and (body as Furniture).is_held()):
			var rb := body as RigidBody3D
			var push := -c.get_normal()
			push.y = 0.0
			# Mass-proportional per-frame impulse: players shove light things
			# easily and barely nudge heavy ones.
			rb.apply_central_impulse(push * Vector3(velocity.x, 0.0, velocity.z).length() * rb.mass * push_strength)


func _interact() -> void:
	if held_furniture:
		held_furniture.release(self)
		return

	var best: Furniture = null
	var best_dist := reach
	for node in get_tree().get_nodes_in_group("furniture"):
		var f := node as Furniture
		if f == null or not f.can_be_grabbed_by(self):
			continue
		var d := f.distance_to_nearest_free_grip(global_position)
		if d < best_dist:
			best_dist = d
			best = f
	if best:
		best.request_grab(self)
