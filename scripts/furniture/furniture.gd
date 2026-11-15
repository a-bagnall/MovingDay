extends RigidBody3D
class_name Furniture
## A physics-driven removable object. Carrying never teleports the body: each
## holder pulls a grip point toward a spot in front of them with a damped
## spring force, so speed/direction mismatches between players swing and
## twist the object.

signal damaged(amount: float, total: float)

@export var data: FurnitureData
## Optional model. Collision, grips and hold height are sized from its mesh bounds.
@export var model_scene: PackedScene
@export var model_scale: float = 1.0

const GRIP_REACH := 0.65      ## Distance from the furniture end to where a player stands.
const MAX_CARRY_ACCEL := 45.0
const MAX_STRAIN := 2.2       ## Grip further than this from the holder = auto-drop (e.g. a player pinned by a wall). Must exceed Player.reach (1.8) or far grabs drop instantly.
## Players are locked to the grip point they grabbed: each frame they are pulled
## back toward it, so the item's rotation swings them around and corners are hard.
const LOCK_SLACK := 0.1       ## Distance from the grip a player can drift before being pulled back.
const LOCK_STIFFNESS := 0.6   ## Fraction of the excess distance corrected per physics frame.
const CARRY_SPEED_CAP := 0.7       ## Top speed multiplier while carrying alone.
const COOP_SPEED_CAP := 0.95       ## Top speed multiplier when enough players share the load.
## Solo grip: a lone player holding something that needs two loses grip over time,
## much faster when running or when the item swings. At zero the item falls.
const SLIP_BASE := 0.12            ## Grip lost per second just standing there.
const SLIP_PER_SPEED := 0.09       ## Extra per m/s the holder moves.
const SLIP_PER_SWING := 0.25       ## Extra per rad/s the item spins.
const SLIP_RECOVER := 0.6          ## Grip regained per second once properly staffed.
## Teams can lose grip too, but only through wild handling:
const TEAM_SWING_FREE := 1.2       ## Spin (rad/s) a team can absorb without slipping.
const TEAM_SLIP_PER_SWING := 0.35  ## Grip lost per second per rad/s above that.
const TEAM_STRAIN_FREE := 0.7      ## Grip-to-holder stretch (m) a team can absorb.
const TEAM_SLIP_PER_STRAIN := 0.5  ## Grip lost per second per metre above that.
const DAMAGE_SCALE := 0.5          ## Overall damage harshness (was 0.25).
const FURNITURE_HIT_THRESHOLD := 0.6  ## Furniture-vs-furniture knocks count at this fraction of the threshold.
const HOLD_GRAVITY_SCALE := 0.6   ## Gravity while fully lifted (1.0 = full weight, lower = floatier).
const HELD_ANGULAR_DAMP := 4.0     ## Rotational drag while held; higher = less wobble and swing.
const DISSOLVE_TIME := 0.8

var total_damage: float = 0.0
var in_truck: bool = false
var is_delivered: bool = false
## False in the lobby so settling and nudges cost nothing.
var damage_enabled: bool = true

var _visual: Node3D
var _grips := PackedVector3Array()
var _size: Vector3
var _holders: Dictionary = {}   # grip index (int) -> Player
var _grip_strength := 1.0       ## 1 = secure, 0 = slips free. Only drains when under-staffed.
var _damage_cooldown := 0.0
var _flash := 0.0
var _material: StandardMaterial3D
var _base_color := Color(0.7, 0.55, 0.4)


func _ready() -> void:
	if data == null:
		data = FurnitureData.new()
	add_to_group("furniture")
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2)
	mass = data.mass
	linear_damp = 0.4
	angular_damp = 1.5
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = true

	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.05
	physics_material_override = pm

	_size = data.size
	_build_visual()
	_build_collision()
	_build_grips()


# --- construction ---------------------------------------------------------

func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = _size
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	if model_scene:
		var model := model_scene.instantiate() as Node3D
		model.scale = Vector3.ONE * model_scale
		_visual.add_child(model)
		var bounds := _model_bounds(model)
		model.position = -bounds.get_center()
		_size = bounds.size
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = _size
		mesh.mesh = box
		_material = StandardMaterial3D.new()
		_base_color = _color_for_handling()
		_material.albedo_color = _base_color
		mesh.material_override = _material
		_visual.add_child(mesh)

	var label := Label3D.new()
	label.text = "%s\n%s" % [data.display_name, _tier_text()]
	label.modulate = _tier_color()
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.01
	label.font_size = 28
	label.position.y = _size.y * 0.5 + 0.5
	_visual.add_child(label)


func _tier_text() -> String:
	match data.tier():
		FurnitureData.Tier.FRAGILE: return "FRAGILE"
		FurnitureData.Tier.HEAVY: return "HEAVY - hits hard"
		_: return "sturdy"


func _tier_color() -> Color:
	match data.tier():
		FurnitureData.Tier.FRAGILE: return Color(1.0, 0.35, 0.35)
		FurnitureData.Tier.HEAVY: return Color(1.0, 0.7, 0.2)
		_: return Color(0.6, 0.95, 0.6)


func _model_bounds(model: Node3D) -> AABB:
	var inverse := global_transform.affine_inverse()
	var bounds := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b := inverse * mi.global_transform * mi.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	assert(not first, "Furniture model has no meshes")
	return bounds


func _color_for_handling() -> Color:
	match data.handling:
		FurnitureData.Handling.HEAVY: return Color(0.45, 0.45, 0.55)
		FurnitureData.Handling.FRAGILE: return Color(0.6, 0.85, 0.9)
		FurnitureData.Handling.AWKWARD: return Color(0.8, 0.6, 0.3)
		FurnitureData.Handling.OVERSIZED: return Color(0.6, 0.4, 0.7)
		_: return Color(0.72, 0.58, 0.42)


func _build_grips() -> void:
	if data.grip_points.size() >= 2:
		_grips = data.grip_points
		return
	var half := _size * 0.5
	if _size.x >= _size.z:
		var x := half.x + GRIP_REACH
		_grips = PackedVector3Array([Vector3(-x, 0, 0), Vector3(x, 0, 0)])
	else:
		var z := half.z + GRIP_REACH
		_grips = PackedVector3Array([Vector3(0, 0, -z), Vector3(0, 0, z)])


# --- grabbing -------------------------------------------------------------

func is_held() -> bool:
	return not _holders.is_empty()


func can_be_grabbed_by(player: Player) -> bool:
	return player.held_furniture == null and _free_grip_indices().size() > 0


func _free_grip_indices() -> Array[int]:
	var out: Array[int] = []
	for i in _grips.size():
		if not _holders.has(i):
			out.append(i)
	return out


func distance_to_nearest_free_grip(from: Vector3) -> float:
	var best := INF
	for i in _free_grip_indices():
		var g := to_global(_grips[i])
		best = minf(best, Vector2(g.x - from.x, g.z - from.z).length())
	return best


func request_grab(player: Player) -> bool:
	var best_i := -1
	var best_d := INF
	for i in _free_grip_indices():
		var g := to_global(_grips[i])
		var d := Vector2(g.x - player.global_position.x, g.z - player.global_position.z).length()
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return false

	if _holders.is_empty():
		_grip_strength = 1.0
	_holders[best_i] = player
	player.held_furniture = self
	add_collision_exception_with(player)
	player.add_collision_exception_with(self)
	sleeping = false
	angular_damp = HELD_ANGULAR_DAMP
	return true


func release(player: Player) -> void:
	for i in _holders.keys():
		if _holders[i] == player:
			_holders.erase(i)
	player.held_furniture = null
	player.speed_multiplier = 1.0
	remove_collision_exception_with(player)
	player.remove_collision_exception_with(self)
	if _holders.is_empty():
		gravity_scale = 1.0
		angular_damp = 1.5


# --- carrying physics -----------------------------------------------------

func _physics_process(delta: float) -> void:
	_damage_cooldown = maxf(_damage_cooldown - delta, 0.0)
	_update_flash(delta)

	if _holders.is_empty():
		return

	var holder_count := _holders.size()
	var lift := clampf(float(holder_count) / float(data.players_required), 0.0, 1.0)
	gravity_scale = lerpf(1.0, HOLD_GRAVITY_SCALE, lift)

	var drop_list: Array[Player] = []
	var worst_strain := 0.0

	for i in _holders.keys():
		var player: Player = _holders[i]
		var grip_world := to_global(_grips[i])
		var r := grip_world - global_position
		var target := _target_for(player, lift)
		var point_velocity := linear_velocity + angular_velocity.cross(r)

		var accel := data.carry_stiffness * (target - grip_world) - data.carry_damping * point_velocity
		accel = accel.limit_length(MAX_CARRY_ACCEL)
		apply_force(accel * mass / float(holder_count), r)

		var strain := grip_world.distance_to(target)
		worst_strain = maxf(worst_strain, strain)
		if strain > MAX_STRAIN:
			drop_list.append(player)

	_update_player_speed(lift, worst_strain)

	if _update_grip(delta, worst_strain):
		for p in _holders.values():
			if not drop_list.has(p):
				drop_list.append(p)

	for p in drop_list:
		if p.held_furniture == self:
			if _grip_strength <= 0.0:
				p.stumble()   # slipped, not just strained
			release(p)


## The grip point is pulled to the holder's own position (at hold height), so the
## item follows where the player actually is.
func _target_for(player: Player, lift: float) -> Vector3:
	var hold_height := maxf(_size.y * 0.5 + 0.15, 0.7)
	var target := player.global_position
	target.y = player.global_position.y + lerpf(0.1, hold_height, lift)
	return target


## Called by the player every physics frame after it has moved: drags the player
## back toward the grip point it grabbed, so it cannot walk away from the item
## or sidestep around it. Walls still block, which strains the grip.
func pull_holder(player: Player) -> void:
	for i in _holders.keys():
		if _holders[i] != player:
			continue
		var stand := to_global(_grips[i])
		stand.y = player.global_position.y
		var err := stand - player.global_position
		var dist := err.length()
		if dist > LOCK_SLACK:
			player.move_and_collide(err / dist * (dist - LOCK_SLACK) * LOCK_STIFFNESS)
		return


## Returns true when the grip has given out and everyone should let go.
func _update_grip(delta: float, strain: float) -> bool:
	if _holders.size() >= data.players_required:
		# A full team is steady, but wild swinging or players pulling apart
		# still shakes the grip loose.
		var shake := maxf(angular_velocity.length() - TEAM_SWING_FREE, 0.0) * TEAM_SLIP_PER_SWING \
			+ maxf(strain - TEAM_STRAIN_FREE, 0.0) * TEAM_SLIP_PER_STRAIN
		if shake > 0.0:
			_grip_strength = maxf(_grip_strength - shake * delta, 0.0)
		else:
			_grip_strength = minf(_grip_strength + SLIP_RECOVER * delta, 1.0)
		return _grip_strength <= 0.0
	var speed := 0.0
	for p: Player in _holders.values():
		speed = maxf(speed, Vector2(p.velocity.x, p.velocity.z).length())
	var drain := SLIP_BASE + SLIP_PER_SPEED * speed + SLIP_PER_SWING * angular_velocity.length()
	_grip_strength = maxf(_grip_strength - drain * delta, 0.0)
	return _grip_strength <= 0.0


func _update_player_speed(lift: float, strain: float) -> void:
	# Carrying anything slows you; weight slows you further. A full team is much
	# faster than a lone player, because the weight is shared.
	var teamed := _holders.size() >= 2
	var cap := COOP_SPEED_CAP if teamed else CARRY_SPEED_CAP
	var weight_factor := mass / (float(_holders.size()) * (70.0 if teamed else 45.0))
	var mult := clampf(cap - weight_factor * 0.4, 0.3, cap)
	if lift < 1.0:
		mult = minf(mult, 0.3)   # not enough people: drag, don't lift
	mult *= clampf(1.0 - maxf(strain - 0.8, 0.0) / 2.5, 0.25, 1.0)
	for player in _holders.values():
		(player as Player).speed_multiplier = mult


# --- delivery -------------------------------------------------------------

## Permanent: the item stops being physical and shrinks away, but the node stays
## so its damage still counts toward the contract. Scale only: fading via
## transparency stuttered the game.
func deliver() -> void:
	is_delivered = true
	in_truck = true
	remove_from_group("furniture")
	freeze = true
	collision_layer = 0
	collision_mask = 0

	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.01, DISSOLVE_TIME)
	tween.tween_property(_visual, "position:y", 0.5, DISSOLVE_TIME)
	tween.finished.connect(_on_dissolved)


func _on_dissolved() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


# --- damage ---------------------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not damage_enabled or in_truck or _damage_cooldown > 0.0 or data == null:
		return
	# dv = impulse / own mass, so a light item hit by a heavy one takes a big dv
	# (the TV suffers, the sofa barely notices) without extra rules.
	var threshold := data.effective_threshold()
	var worst := 0.0
	for i in state.get_contact_count():
		var dv := state.get_contact_impulse(i).length() / maxf(mass, 0.01)
		var limit := threshold
		if state.get_contact_collider_object(i) is Furniture:
			limit *= FURNITURE_HIT_THRESHOLD   # knocking items together always hurts
		worst = maxf(worst, dv - limit)
	if worst > 0.0:
		_apply_damage(worst)


## `excess` is how far the impact went past the damage threshold (m/s).
func _apply_damage(excess: float) -> void:
	# Sturdy things still take a little; fragile things take a lot.
	var raw := excess * maxf(data.fragility, 0.1) * data.value * DAMAGE_SCALE
	var amount := minf(raw, data.value - total_damage)
	if amount <= 0.01:
		return
	total_damage += amount
	_damage_cooldown = 0.25
	_flash = 1.0
	damaged.emit(amount, total_damage)


func _update_flash(delta: float) -> void:
	_flash = maxf(_flash - delta * 3.0, 0.0)
	if _material == null:
		return
	var ratio := clampf(total_damage / maxf(data.value, 0.01), 0.0, 1.0)
	var worn := _base_color.lerp(Color(0.35, 0.1, 0.1), ratio * 0.6)
	_material.albedo_color = worn.lerp(Color.RED, _flash)
