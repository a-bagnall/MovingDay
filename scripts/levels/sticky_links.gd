class_name StickyLinks
extends Node
## From day 3 some of the job's furniture is stuck together in pairs, so it has to be
## carried (and fitted through doors and up stairs) as one awkward lump.
##
## Every machine picks the same pairs, because the choice only depends on the run's slot
## and day and on the order of the items. Each machine moves the partner next to its
## mate and draws the gum blob; only the host (or an offline game) makes the actual
## physics joint, because the host simulates the furniture and streams the result.

const FIRST_STICKY_DAY := Balance.STICKY_FIRST_DAY
const PAIR_EVERY_DAYS := Balance.STICKY_PAIR_EVERY_DAYS   # one more stuck pair this many days after the last
const MAX_PAIRS := Balance.STICKY_MAX_PAIRS
## Pairs heavier than this are skipped, so a stuck pair can always be moved by its team.
const MAX_COMBINED_MASS := 85.0
## Pairs further apart than this vertically are on different floors, and skipped.
const MAX_HEIGHT_GAP := 1.0
## Seconds to let the moved partner settle against its mate before gluing.
const GLUE_DELAY := 1.3
const GUM_COLOR := Color(1.0, 0.45, 0.7)

## Pairs picked for this job (0 until setup runs), for the HUD.
var pairs_made := 0


## How many stuck pairs a job on `day` has: 1 from the first sticky day, one more every
## few days, and extra ones with the Gum Everywhere modifier (all numbers in Balance).
static func pair_count(day: int) -> int:
	var base := 0
	if day >= FIRST_STICKY_DAY:
		base = 1 + (day - FIRST_STICKY_DAY) / PAIR_EVERY_DAYS
	return mini(base + RunModifiers.extra_sticky_pairs(), MAX_PAIRS)


func _ready() -> void:
	add_to_group("sticky_links")


func setup(items: Array[Furniture], day: int, slot: int) -> void:
	var wanted := pair_count(day)
	if wanted == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sticky_%d_%d" % [slot, day])

	var pool: Array[Furniture] = items.duplicate()
	pool.sort_custom(func(a: Furniture, b: Furniture) -> bool: return a.net_id < b.net_id)
	var pairs: Array = []   # of [Furniture, Furniture]
	while pairs.size() < wanted and pool.size() >= 2:
		var first: Furniture = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var mate := _best_mate(first, pool)
		if mate == null:
			continue
		pool.erase(mate)
		pairs.append([first, mate])
	for pair: Array in pairs:
		_bring_together(pair[0], pair[1])
	pairs_made = pairs.size()
	if pairs.is_empty():
		return

	await get_tree().create_timer(GLUE_DELAY).timeout
	for pair: Array in pairs:
		if is_instance_valid(pair[0]) and is_instance_valid(pair[1]):
			_glue(pair[0], pair[1])


## The closest item that `a` may be stuck to, or null.
func _best_mate(a: Furniture, pool: Array[Furniture]) -> Furniture:
	var best: Furniture = null
	var best_distance := INF
	for b in pool:
		if absf(a.position.y - b.position.y) > MAX_HEIGHT_GAP:
			continue
		if a.data.mass + b.data.mass > MAX_COMBINED_MASS:
			continue
		if a.data.players_required > 1 and b.data.players_required > 1:
			continue
		var distance := a.position.distance_to(b.position)
		if distance < best_distance:
			best_distance = distance
			best = b
	return best


## Moves `b` along the line towards `a` until the two just touch.
func _bring_together(a: Furniture, b: Furniture) -> void:
	var direction := Vector3(b.position.x - a.position.x, 0.0, b.position.z - a.position.z)
	if direction.length() < 0.01:
		direction = Vector3.RIGHT
	direction = direction.normalized()
	var gap := _reach(a) + _reach(b) + 0.05
	b.position = Vector3(a.position.x + direction.x * gap, b.position.y, a.position.z + direction.z * gap)


## Half the footprint's longest side: a safe distance to keep two items touching, not overlapping.
func _reach(item: Furniture) -> float:
	return maxf(item.data.size.x, item.data.size.z) * 0.5


func _glue(a: Furniture, b: Furniture) -> void:
	var middle := (a.global_position + b.global_position) * 0.5
	if not a.is_puppet:
		var joint := Generic6DOFJoint3D.new()
		joint.exclude_nodes_from_collision = true
		add_child(joint)
		joint.global_position = middle
		joint.node_a = a.get_path()
		joint.node_b = b.get_path()
		for axis in ["x", "y", "z"]:
			joint.call("set_flag_%s" % axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.call("set_param_%s" % axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.call("set_param_%s" % axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.call("set_flag_%s" % axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.call("set_param_%s" % axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
			joint.call("set_param_%s" % axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)

	# A blob of pink gum where they meet, riding on the first item.
	var blob := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.26
	blob.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = GUM_COLOR
	material.roughness = 0.35
	blob.material_override = material
	a.add_child(blob)
	blob.global_position = middle
