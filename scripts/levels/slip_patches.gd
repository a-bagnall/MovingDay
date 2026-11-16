class_name SlipPatches
extends Node
## The Wet Floors modifier: a few slick puddles on the ground floor, set along the routes
## from the furniture to the truck. A player standing in one has very little control (see
## Player), so carrying through them is a gamble.
##
## Every machine places the same puddles, because the choice depends only on the run's
## slot and day and on the order of the items. Players read the puddles through the
## "slip_patches" group and each puddle's "radius" meta, so nothing else needs to know
## this class.

const GROUP := "slip_patches"
const PUDDLE_COLOR := Color(0.45, 0.75, 1.0, 0.55)
## Items above this height are on an upper floor, and skipped (the route to the truck there
## goes down the stairs, not in a straight line).
const GROUND_FLOOR_MAX_Y := 1.2


func setup(items: Array[Furniture], toward: Vector3, day: int, slot: int) -> void:
	if not RunModifiers.has("wet_floors"):
		return
	var ground: Array[Furniture] = []
	for item in items:
		if item.position.y < GROUND_FLOOR_MAX_Y:
			ground.append(item)
	if ground.is_empty():
		return
	ground.sort_custom(func(a: Furniture, b: Furniture) -> bool: return a.net_id < b.net_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("puddles_%d_%d" % [slot, day])
	for i in Balance.WET_FLOORS_PUDDLES:
		var item := ground[i % ground.size()]
		var along := rng.randf_range(0.3, 0.7)
		var spot := Vector3(lerpf(item.position.x, toward.x, along), 0.0, lerpf(item.position.z, toward.z, along))
		spot += Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))   # off the exact line
		_add_puddle(spot)


func _add_puddle(spot: Vector3) -> void:
	var puddle := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = Balance.WET_FLOORS_RADIUS
	mesh.bottom_radius = Balance.WET_FLOORS_RADIUS
	mesh.height = 0.02
	puddle.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = PUDDLE_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.05
	material.metallic = 0.3
	puddle.material_override = material
	puddle.set_meta("radius", Balance.WET_FLOORS_RADIUS)
	puddle.add_to_group(GROUP)
	add_child(puddle)
	puddle.global_position = spot + Vector3(0.0, 0.03, 0.0)
