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
const LOCK_SLACK := 0.3       ## Distance from the grip a player can drift before being pulled back.
const LOCK_STIFFNESS := 0.3   ## Fraction of the excess distance corrected per physics frame.
const LOCK_MAX_SPEED := 2.5   ## Cap (m/s) on how hard the lock can drag a player.
const GRIP_GRACE := 1.0       ## Seconds after grabbing before grip can start to slip.
const CARRY_SPEED_CAP := 0.7       ## Top speed multiplier while carrying alone.
const COOP_SPEED_CAP := 0.95       ## Top speed multiplier when enough players share the load.
## Solo grip: a lone player holding something that needs two loses grip over time,
## much faster when running or when the item swings. At zero the item falls.
const SLIP_BASE := 0.12            ## Grip lost per second just standing there.
const SLIP_PER_SPEED := 0.09       ## Extra per m/s the holder moves.
const SLIP_PER_SWING := 0.25       ## Extra per rad/s the item spins.
const SLIP_RECOVER := 0.6          ## Grip regained per second once properly staffed.
## Teams can lose grip too, but only through wild handling:
const TEAM_SWING_FREE := 1.8       ## Spin (rad/s) a team can absorb without slipping.
const TEAM_SLIP_PER_SWING := 0.3   ## Grip lost per second per rad/s above that.
const TEAM_STRAIN_FREE := 0.9      ## Grip-to-holder stretch (m) a team can absorb.
const TEAM_SLIP_PER_STRAIN := 0.4  ## Grip lost per second per metre above that.
const DAMAGE_SCALE := 0.5          ## Overall damage harshness (was 0.25).
const FURNITURE_HIT_THRESHOLD := 0.6  ## Furniture-vs-furniture knocks count at this fraction of the threshold.
const HOLD_GRAVITY_SCALE := 0.6   ## Gravity while fully lifted (1.0 = full weight, lower = floatier).
const HELD_ANGULAR_DAMP := 4.0     ## Rotational drag while held; higher = less wobble and swing.
const DISSOLVE_TIME := 0.8
## Feedback ("pizzazz")
const WOBBLE_START := 0.65         ## Below this grip strength the item starts to wobble.
const WOBBLE_ANGLE := 0.24         ## Max wobble tilt in radians at zero grip.
const LAND_SPEED := 1.5            ## Downward speed (m/s) that counts as a landing thud.
const DUST_FULL_SPEED := 6.0       ## Landing speed that produces the biggest puff.

static var _dust_mesh: SphereMesh
static var _dust_curve: Curve

var total_damage: float = 0.0
var in_truck: bool = false
var is_delivered: bool = false
## False until the job's settle period ends, so spawn settling and nudges cost nothing.
var damage_enabled: bool = true

## Last notable impact (m/s of velocity change) and seconds since, for the debug overlay.
var debug_peak_dv := 0.0
var debug_peak_age := 99.0

var _visual: Node3D
var _grips := PackedVector3Array()
var _size: Vector3
var _holders: Dictionary = {}   # grip index (int) -> Player
var _grip_strength := 1.0       ## 1 = secure, 0 = slips free. Only drains when under-staffed.
var _grip_grace := 0.0
var _damage_cooldown := 0.0
var _flash := 0.0
var _time := 0.0
var _shake := 0.0               ## Damage jitter, 1 -> 0.
var _prev_vy := 0.0
var _pop_tween: Tween
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
	# Say who can carry it, so it "makes sense" before anyone tries.
	var who := "2 players" if data.players_required >= 2 else "1 player"
	label.text = "%s\n%s - %s" % [data.display_name, _tier_text(), who]
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


func holder_count() -> int:
	return _holders.size()


## 0-100, how secure the current grip is.
func grip_percent() -> int:
	return roundi(_grip_strength * 100.0)


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
	_grip_grace = GRIP_GRACE
	_holders[best_i] = player
	player.held_furniture = self
	add_collision_exception_with(player)
	player.add_collision_exception_with(self)
	sleeping = false
	angular_damp = HELD_ANGULAR_DAMP
	_pop(0.8)
	player.pop()
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


# --- feedback -------------------------------------------------------------

func _process(delta: float) -> void:
	if is_delivered or _visual == null:
		return
	_time += delta
	# Wobble grows as grip fails, warning the players before the item drops.
	var wobble := 0.0
	if is_held():
		wobble = clampf((WOBBLE_START - _grip_strength) / WOBBLE_START, 0.0, 1.0)
	var tilt := wobble * WOBBLE_ANGLE
	_visual.rotation = Vector3(sin(_time * 23.0) * tilt, 0.0, sin(_time * 19.0 + 1.0) * tilt)
	_shake = maxf(_shake - delta * 4.0, 0.0)
	_visual.position = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * _shake * 0.08


## Squash-and-stretch bounce on the visual. Strength 1 is a full pop.
func _pop(strength: float = 1.0) -> void:
	if _visual == null or is_delivered:
		return
	if _pop_tween:
		_pop_tween.kill()
	_visual.scale = Vector3(1.0 + 0.18 * strength, 1.0 - 0.15 * strength, 1.0 + 0.18 * strength)
	_pop_tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(_visual, "scale", Vector3.ONE, 0.45)


## Detects the moment a falling item stops and answers with a thud: dust and a squash.
func _check_landing() -> void:
	var vy := linear_velocity.y
	if not in_truck and not is_delivered and _prev_vy < -LAND_SPEED and vy > -0.5:
		var strength := clampf(-_prev_vy / DUST_FULL_SPEED, 0.3, 1.5)
		_spawn_dust(strength)
		_pop(strength)
	_prev_vy = vy


func _spawn_dust(strength: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	if _dust_mesh == null:
		_dust_mesh = SphereMesh.new()
		_dust_mesh.radius = 0.12
		_dust_mesh.height = 0.24
		_dust_mesh.radial_segments = 6
		_dust_mesh.rings = 3
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.93, 0.9, 0.82)
		_dust_mesh.material = mat
		_dust_curve = Curve.new()
		_dust_curve.add_point(Vector2(0.0, 1.0))
		_dust_curve.add_point(Vector2(1.0, 0.0))

	var p := CPUParticles3D.new()
	p.mesh = _dust_mesh
	p.amount = int(8 + 10 * strength)
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 85.0
	p.gravity = Vector3(0.0, -1.5, 0.0)
	p.initial_velocity_min = 0.8 * strength
	p.initial_velocity_max = 2.2 * strength
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _dust_curve
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(_size.x, _size.z) * 0.35
	parent.add_child(p)
	p.global_position = global_position + Vector3(0.0, -_size.y * 0.5, 0.0)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


func _show_damage_popup(amount: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var label := Label3D.new()
	label.text = "-$%d" % maxi(roundi(amount), 1)
	label.modulate = Color(1.0, 0.3, 0.3)
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.012
	label.font_size = 44
	parent.add_child(label)
	label.global_position = global_position + Vector3(0.0, _size.y * 0.5 + 0.9, 0.0)
	var tween := label.create_tween()
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.1, 0.9)
	tween.parallel().tween_property(label, "scale", Vector3.ONE * 0.3, 0.5).set_delay(0.4)
	tween.tween_callback(label.queue_free)


# --- carrying physics -----------------------------------------------------

func _physics_process(delta: float) -> void:
	_damage_cooldown = maxf(_damage_cooldown - delta, 0.0)
	debug_peak_age += delta
	_update_flash(delta)
	_check_landing()

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

		# Damp toward the holder's velocity, not toward standing still: otherwise the
		# item trails a metre behind at running speed, which fought the grip lock
		# and drained the grip while simply walking.
		var accel := data.carry_stiffness * (target - grip_world) \
			+ data.carry_damping * (player.velocity - point_velocity)
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
func pull_holder(player: Player, delta: float) -> void:
	for i in _holders.keys():
		if _holders[i] != player:
			continue
		var stand := to_global(_grips[i])
		stand.y = player.global_position.y
		var err := stand - player.global_position
		var dist := err.length()
		if dist > LOCK_SLACK:
			# A rope, not a vice: gentle, and capped so it can never out-pull walking.
			var step := minf((dist - LOCK_SLACK) * LOCK_STIFFNESS, LOCK_MAX_SPEED * delta)
			player.move_and_collide(err / dist * step)
		return


## Returns true when the grip has given out and everyone should let go.
func _update_grip(delta: float, strain: float) -> bool:
	if _grip_grace > 0.0:
		_grip_grace -= delta   # settling in after the grab: no slipping yet
		return false
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
	if _pop_tween:
		_pop_tween.kill()
	_visual.rotation = Vector3.ZERO
	_visual.position = Vector3.ZERO
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
	if in_truck or data == null:
		return
	# dv = impulse / own mass, so a light item hit by a heavy one takes a big dv
	# (the TV suffers, the sofa barely notices) without extra rules.
	var threshold := data.effective_threshold()
	var worst := 0.0
	var peak := 0.0
	for i in state.get_contact_count():
		var dv := state.get_contact_impulse(i).length() / maxf(mass, 0.01)
		peak = maxf(peak, dv)
		var limit := threshold
		if state.get_contact_collider_object(i) is Furniture:
			limit *= FURNITURE_HIT_THRESHOLD   # knocking items together always hurts
		worst = maxf(worst, dv - limit)
	if peak > 0.3:
		debug_peak_dv = peak       # for the F3 overlay: confirms impulses are reported
		debug_peak_age = 0.0
	if not damage_enabled or _damage_cooldown > 0.0:
		return
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
	_shake = 1.0
	_show_damage_popup(amount)
	damaged.emit(amount, total_damage)


func _update_flash(delta: float) -> void:
	_flash = maxf(_flash - delta * 3.0, 0.0)
	if _material == null:
		return
	var ratio := clampf(total_damage / maxf(data.value, 0.01), 0.0, 1.0)
	var worn := _base_color.lerp(Color(0.35, 0.1, 0.1), ratio * 0.6)
	_material.albedo_color = worn.lerp(Color.RED, _flash)
