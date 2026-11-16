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
## Optional override model (should face -Z). Normally leave this empty: the model comes
## from CharacterCatalog, by the player's choice.
@export var model_scene: PackedScene
@export var model_scale: float = 1.0
## Index into CharacterCatalog.ENTRIES. -1 = whatever this player id picked.
var character := -1
## True while the player is picking a character: they stand still.
var movement_locked := false
var _char_root: Node3D
var _char_yaw := 0.0
var _anim: AnimationPlayer
var _anim_idle: StringName = &""
var _anim_walk: StringName = &""
var _anim_current: StringName = &""
var _anim_time := 0.0
var _anim_lean := 0.0
var _skeleton: Skeleton3D
var _rig := {}
var _walk_blend := 0.0
var _carry_blend := 0.0
var _idle_time := 0.0

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
	if character < 0:
		character = CharacterCatalog.choice_for(player_id)
	if _attach_character(character):
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


## Switches to catalogue character `index`, keeping the facing and squash state.
func set_character(index: int) -> void:
	index = CharacterCatalog.clamp_index(index)
	if index == character or _visual == null or model_scene != null:
		return
	var old := _visual.get_node_or_null("Character")
	if old:
		_visual.remove_child(old)
		old.queue_free()
	character = index
	_attach_character(index)


## Builds the character model under _visual, scaled to its catalogue height with its
## feet on the ground and centred on the player. False if the model could not load.
func _attach_character(index: int) -> bool:
	var entry: Dictionary = CharacterCatalog.ENTRIES[CharacterCatalog.clamp_index(index)]
	var scene := load(entry["path"]) as PackedScene
	if scene == null:
		return false
	var root := Node3D.new()
	root.name = "Character"
	var model := scene.instantiate() as Node3D
	if model == null:
		return false
	root.add_child(model)
	_visual.add_child(root)

	var box := _mesh_bounds(model)
	if box.size.y > 0.0001:
		var fit: float = float(entry["height"]) / box.size.y
		model.scale *= fit
		# Feet on the floor, centred under the player (bounds were in unscaled model space).
		model.position = Vector3(-(box.position.x + box.size.x * 0.5) * fit, -box.position.y * fit,
			-(box.position.z + box.size.z * 0.5) * fit)
	print("[Character] %s: measured size %s -> fitted to %.2f m" % [entry["name"], box.size, entry["height"]])
	_char_root = root
	_char_yaw = float(entry["yaw"])
	root.rotation.y = _char_yaw
	_setup_animations(model)
	return true


## Models that ship with animations (the robot) use them; the rest are animated
## procedurally in _animate_character.
func _setup_animations(model: Node3D) -> void:
	_rig.clear()
	_skeleton = null
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_build_rig(skeletons[0] as Skeleton3D)
	_anim = null
	_anim_idle = &""
	_anim_walk = &""
	_anim_current = &""
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	var player := found[0] as AnimationPlayer
	for anim_name in player.get_animation_list():
		var lower := String(anim_name).to_lower()
		if _anim_idle == &"" and "idle" in lower:
			_anim_idle = anim_name
		elif _anim_walk == &"" and "walk" in lower:
			_anim_walk = anim_name
	if _anim_idle == &"" or _anim_walk == &"":
		return
	for anim_name in [_anim_idle, _anim_walk]:
		player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim = player
	player.play(_anim_idle)
	_anim_current = _anim_idle


## Finds the limbs of a plushie skeleton by name ("BearLLeg1", "CatHead", ...). Missing
## bones are simply skipped, so any rig works as far as it is named this way.
func _build_rig(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	for i in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(i)
		for key in ["LLeg1", "RLeg1", "LArm1", "RArm1", "Head", "Chest", "Hips"]:
			if bone_name.ends_with(key):
				var parent := skeleton.get_bone_parent(i)
				var rest := skeleton.get_bone_global_rest(i)
				var parent_basis := Basis.IDENTITY if parent < 0 else skeleton.get_bone_global_rest(parent).basis.orthonormalized()
				_rig[key] = {
					"bone": i,
					"rest_rot": skeleton.get_bone_rest(i).basis.get_rotation_quaternion(),
					"parent_basis": parent_basis,
					"global_basis": rest.basis.orthonormalized(),
					"side": signf(rest.origin.x) if signf(rest.origin.x) != 0.0 else 1.0,
				}


## Rotates a bone by `delta` (a rotation in the model's own axes: X is side to side,
## Y up, Z front to back) from its rest pose. Axes of the bone itself don't matter.
func _pose_bone(key: String, delta: Basis) -> void:
	if not _rig.has(key):
		return
	var info: Dictionary = _rig[key]
	var local: Basis = (info["parent_basis"] as Basis).inverse() * delta * (info["global_basis"] as Basis)
	_skeleton.set_bone_pose_rotation(info["bone"], local.get_rotation_quaternion())


func _process(delta: float) -> void:
	_animate_character(delta)


## Cute, bouncy motion: a hop on every step (stretch going up, squash on landing), arms
## and legs swinging, a waddle and a lean; breathing, head tilts and arm sways when idle;
## arms out in front when carrying. Plushies are posed bone by bone; the robot plays
## its own clips.
func _animate_character(delta: float) -> void:
	if _char_root == null or not is_instance_valid(_char_root):
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := speed > 0.4
	if _anim:
		var want := _anim_walk if moving else _anim_idle
		if want != _anim_current:
			_anim.play(want, 0.2)
			_anim_current = want
		_anim.speed_scale = clampf(speed / max_speed, 0.6, 1.3) if moving else 1.0
		return

	var amount := clampf(speed / max_speed, 0.0, 1.0) if moving else 0.0
	_walk_blend = lerpf(_walk_blend, amount, 1.0 - exp(-10.0 * delta))
	var carry_target := 1.0 if held_furniture != null else 0.0
	_carry_blend = lerpf(_carry_blend, carry_target, 1.0 - exp(-9.0 * delta))
	var step_rate := lerpf(7.0, 13.0, _walk_blend)
	_anim_time += delta * (step_rate if _walk_blend > 0.05 else 2.0)   # one cycle = two steps
	_idle_time += delta

	var w := _walk_blend
	var hop := absf(sin(_anim_time))                       # 0 at footfall, 1 at the top
	var bob := hop * 0.11 * w
	# Stretch tall on the way up, squash flat as the foot lands.
	var squash := 1.0 + (hop - 0.45) * 0.16 * w
	squash += sin(_idle_time * 2.2) * 0.02 * (1.0 - w)     # breathing
	var roll := sin(_anim_time) * 0.16 * w                 # waddle
	var lean := lerpf(_anim_lean, 0.14 if moving else 0.0, 1.0 - exp(-8.0 * delta))
	_anim_lean = lean
	_char_root.position.y = bob
	_char_root.rotation = Vector3(-lean, _char_yaw, roll)
	var wide := 1.0 / sqrt(squash)
	_char_root.scale = Vector3(wide, squash, wide)

	if _skeleton == null:
		return
	var swing := sin(_anim_time)
	# Legs: quick little steps, opposite each other.
	_pose_bone("LLeg1", Basis(Vector3.RIGHT, swing * 0.9 * w))
	_pose_bone("RLeg1", Basis(Vector3.RIGHT, -swing * 0.9 * w))
	# Arms: hang down from the plushie T-pose, swing against the legs, and rise to
	# hold the furniture when carrying.
	for key in ["LArm1", "RArm1"]:
		if not _rig.has(key):
			continue
		var side: float = _rig[key]["side"]
		var phase := -swing if key == "LArm1" else swing
		var idle_sway := sin(_idle_time * 1.7 + (0.0 if key == "LArm1" else 1.4)) * 0.07 * (1.0 - w)
		var drop := Basis(Vector3.BACK, -side * lerpf(1.15, 0.45, _carry_blend))
		var raise := Basis(Vector3.RIGHT, phase * 0.8 * w + idle_sway - 1.35 * _carry_blend)
		_pose_bone(key, raise * drop)
	# Head: keeps level against the waddle, with a curious idle tilt and glance.
	var look := sin(_idle_time * 0.9) * 0.22 * (1.0 - w)
	var tilt := sin(_idle_time * 1.3 + 1.0) * 0.12 * (1.0 - w) - roll * 0.6
	_pose_bone("Head", Basis(Vector3.UP, look) * Basis(Vector3.BACK, tilt) * Basis(Vector3.RIGHT, -bob * 1.5 + 0.04 * sin(_anim_time * 2.0) * w))
	# Chest: a little counter-twist as the shoulders swing, and a breath.
	_pose_bone("Chest", Basis(Vector3.UP, -swing * 0.12 * w) * Basis(Vector3.RIGHT, sin(_idle_time * 2.2) * 0.02 * (1.0 - w)))


## Combined bounds of every mesh under `model`, in the model's own (unscaled) space.
## A skinned mesh is drawn in its skeleton's space and ignores the mesh node's own
## transform, so it is measured through the skeleton's transform instead.
func _mesh_bounds(model: Node3D) -> AABB:
	var to_model := {model: Transform3D.IDENTITY}   # node -> transform relative to the model root
	var queue: Array[Node3D] = [model]
	while not queue.is_empty():
		var n: Node3D = queue.pop_front()
		for child in n.get_children():
			if child is Node3D:
				to_model[child] = to_model[n] * (child as Node3D).transform
				queue.append(child)
	var result := AABB()
	var have := false
	for node: Node3D in to_model:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var space: Transform3D = to_model[mi]
		if mi.skin != null:
			var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			if skeleton != null and to_model.has(skeleton):
				space = to_model[skeleton]
		var b: AABB = space * mi.mesh.get_aabb()
		result = b if not have else result.merge(b)
		have = true
	return result


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
	var move := Vector2.ZERO if movement_locked else input.move
	var input_dir := Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, CAMERA_YAW)

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


## State to stream to other machines:
## [id, position, velocity, facing, move, interact, character].
func net_state() -> Array:
	return [player_id, global_position, velocity, _visual.rotation.y if _visual else 0.0,
		input.move, input.interact, character]


## Remote players: remember where the owning machine says this player is, and feed
## its input so interact presses reach the area's zones. `velocity_` is kept so the
## furniture this player carries (simulated on the host) can match its speed.
func apply_net_state(position_: Vector3, yaw: float, move: Vector2, interact: bool,
		velocity_ := Vector3.ZERO, character_ := -1) -> void:
	if character_ >= 0:
		CharacterCatalog.choose(player_id, character_)
		set_character(character_)
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
