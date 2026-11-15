extends Node
class_name CutawayReveal
## Drives cutaway.gdshader: cuts a soft screen-space hole in every surface using
## `material` around each player standing inside `region`, so players stay
## visible through roofs and floors. Add it to the tree for it to update.

const SHADER := "res://assets/materials/cutaway.gdshader"
## Must match the reveals array size in cutaway.gdshader.
const SLOTS := 2
const FADE_SPEED := 4.0
## Chest height the hole is centred on.
const REVEAL_HEIGHT := 0.9

var material := ShaderMaterial.new()
## Volume (in `space`'s local coordinates) that counts as "hidden".
var region: AABB
var space: Node3D

var _fade: Array[float] = []


static func create(in_space: Node3D, in_region: AABB, albedo: Color) -> CutawayReveal:
	var reveal := CutawayReveal.new()
	reveal.space = in_space
	reveal.region = in_region
	reveal.material.shader = load(SHADER)
	reveal.material.set_shader_parameter("albedo", albedo)
	return reveal


func _init() -> void:
	_fade.resize(SLOTS)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var players := get_tree().get_nodes_in_group("players")
	var reveals := PackedVector3Array()
	reveals.resize(SLOTS)
	for i in mini(players.size(), SLOTS):
		var player := players[i] as Node3D
		var inside := region.has_point(space.to_local(player.global_position))
		_fade[i] = move_toward(_fade[i], 1.0 if inside else 0.0, delta * FADE_SPEED)
		var screen := camera.unproject_position(player.global_position + Vector3.UP * REVEAL_HEIGHT) / viewport_size
		reveals[i] = Vector3(screen.x, screen.y, _fade[i])
	material.set_shader_parameter("reveals", reveals)
