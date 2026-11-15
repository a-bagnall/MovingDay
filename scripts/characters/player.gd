extends CharacterBody3D
class_name Player
## Shared gameplay controller for every animal. Species differences are purely
## visual: assign a different `model_scene` and nothing here changes.
##
## Movement is deliberately weighty: acceleration, gradual braking, sluggish
## direction reversals, and an occasional stumble on abrupt reversals at speed.

@export var player_id: int = 1
## True if this machine's InputSetup drives the player; false when something else
## (the network layer) fills `input` each frame.
@export var is_local := true
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

## Body colour per player id (id 1 is the first entry).
const PLAYER_COLORS := [
	Color(0.9, 0.45, 0.2),
	Color(0.25, 0.55, 0.9),
	Color(0.35, 0.75, 0.4),
	Color(0.9, 0.8, 0.25),
]

## This frame's input. Filled from InputSetup for local players.
var input := PlayerInput.new()

## Set each frame by the furniture being carried (1.0 = unencumbered).
var speed_multiplier: float = 1.0
var shop_speed_multiplier: float = 1.0
var shop_acceleration_multiplier: float = 1.0
var held_furniture: Furniture = null
## False in the main menu and hub: players can move but not grab.
var can_interact := true

var _visual: Node3D
var _source: int
var _interact_prev := false
var _prev_input_dir := Vector3.ZERO
var _stumble_left := 0.0
var _pop_tween: Tween
## Online client: until this tick (msec), ignore the host saying this player holds
## something. Set when the player lets go, so the host's not-yet-updated state does
## not make it grab again.
var net_ignore_holds_until := 0

var _net_position := Vector3.ZERO   # latest state from the owning machine (remote players)
var _net_yaw := 0.0
var _has_net_state := false


func _ready() -> void:
	if is_local:
		_source = InputSetup.source_of(player_id)
	if SaveManager.run != null:
		if SaveManager.run.speed_boost_day == SaveManager.run.day:
			shop_speed_multiplier = SaveManager.run.speed_boost
		if SaveManager.run.acceleration_boost_day == SaveManager.run.day:
			shop_acceleration_multiplier = SaveManager.run.acceleration_boost
	_poll_input()
	_interact_prev = input.interact
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
	mat.albedo_color = PLAYER_COLORS[(player_id - 1) % PLAYER_COLORS.size()]
	mesh.material_override = mat
	_visual.add_child(mesh)

	var nose := MeshInstance3D.new()
	nose.mesh = BoxMesh.new()
	nose.scale = Vector3(0.2, 0.2, 0.3)
	nose.position = Vector3(0, 0.9, -0.45)
	_visual.add_child(nose)


## Reads this machine's input source into `input`. Remote players are skipped:
## their input is set from outside.
func _poll_input() -> void:
	if not is_local:
		return
	input.move = InputSetup.get_move(_source)
	input.interact = InputSetup.is_interact_pressed(_source)


func _physics_process(delta: float) -> void:
	_poll_input()
	if not is_local:
		_follow_remote(delta)
		return
	var input_dir := Vector3(input.move.x, 0.0, input.move.y).rotated(Vector3.UP, CAMERA_YAW)

	_stumble_left = maxf(_stumble_left - delta, 0.0)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	_check_stumble(input_dir, horizontal)

	var control := 0.25 if _stumble_left > 0.0 else 1.0
	var target := input_dir * max_speed * shop_speed_multiplier * speed_multiplier * control
	var rate := acceleration * shop_acceleration_multiplier if input_dir.length() > 0.01 else braking
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
		held_furniture.pull_holder(self, delta)
	_push_rigid_bodies()

	if input_dir.length() > 0.5:
		_prev_input_dir = input_dir.normalized()

	if input.interact and not _interact_prev and can_interact:
		_interact()
	_interact_prev = input.interact


## State to stream to other machines: [id, position, velocity, facing, move, interact].
func net_state() -> Array:
	return [player_id, global_position, velocity, _visual.rotation.y if _visual else 0.0,
		input.move, input.interact]


## Remote players: remember where the owning machine says this player is, and feed
## its input so interact presses reach the area's zones. `velocity_` is kept so the
## furniture this player carries (simulated on the host) can match its speed.
func apply_net_state(position_: Vector3, yaw: float, move: Vector2, interact: bool,
		velocity_ := Vector3.ZERO) -> void:
	_net_position = position_
	_net_yaw = yaw
	input.move = move
	input.interact = interact
	velocity = velocity_
	_has_net_state = true


## Remote players are not simulated here; they glide to the last reported state.
func _follow_remote(delta: float) -> void:
	if not _has_net_state:
		return
	if global_position.distance_to(_net_position) > 4.0:
		global_position = _net_position   # far behind (just spawned): snap
	else:
		global_position = global_position.lerp(_net_position, 1.0 - exp(-16.0 * delta))
	if _visual:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _net_yaw, 1.0 - exp(-14.0 * delta))


## Quick squash-and-stretch, used when snapping onto a grip.
func pop() -> void:
	if _visual == null:
		return
	if _pop_tween:
		_pop_tween.kill()
	_visual.scale = Vector3(1.2, 0.8, 1.2)
	_pop_tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(_visual, "scale", Vector3.ONE, 0.45)


## Called when the player loses their grip on something heavy.
func stumble() -> void:
	if not is_local:
		# The host simulates the carrying, so it learns of a slip first; the machine
		# that owns this player has to be told.
		if NetworkManager.is_host():
			var sync := get_tree().get_first_node_in_group("job_sync") as JobSync
			if sync:
				sync.notify_stumble(player_id)
		return
	_stumble_left = stumble_time


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
			var impulse := push * Vector3(velocity.x, 0.0, velocity.z).length() * rb.mass * push_strength
			var item := body as Furniture
			if item != null and item.is_puppet:
				# On a client the furniture is a copy; the host does the shoving.
				var sync := get_tree().get_first_node_in_group("job_sync") as JobSync
				if sync:
					sync.queue_push(item.net_id, impulse)
			else:
				rb.apply_central_impulse(impulse)


func _interact() -> void:
	if not GameFlow.is_authority():
		_request_interact()
		return
	if held_furniture:
		held_furniture.release(self)
		return
	var best := _nearest_grabbable()
	if best:
		best.request_grab(self)


## Online client: the host owns the furniture, so grabbing and dropping are requests.
func _request_interact() -> void:
	if held_furniture:
		NetworkManager.send_interact_request(player_id, -1)
		held_furniture.release(self)   # let go at once; the host's state catches up
		net_ignore_holds_until = Time.get_ticks_msec() + 400
		return
	var best := _nearest_grabbable()
	if best:
		NetworkManager.send_interact_request(player_id, best.net_id)


func _nearest_grabbable() -> Furniture:
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
	return best
