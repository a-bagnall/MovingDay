class_name PingMarker
extends Node3D
## A coloured "look here" marker: a pulsing ring on the floor with a bobbing arrow
## above it, in the colour of the player who pinged. It fades out on its own.

const LIFETIME := 4.0
const FADE_TIME := 0.8

var _age := 0.0
var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _materials: Array[StandardMaterial3D] = []


## Puts a marker at `position` in `parent`. `radius` is the ring's size (an item's reach).
static func spawn(parent: Node, position: Vector3, color: Color, radius := 0.6) -> PingMarker:
	var marker := PingMarker.new()
	parent.add_child(marker)
	marker.global_position = position + Vector3(0.0, 0.05, 0.0)
	marker._build(color, radius)
	return marker


func _build(color: Color, radius: float) -> void:
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius
	torus.outer_radius = radius + 0.12
	_ring.mesh = torus
	_ring.material_override = _material(color)
	add_child(_ring)

	_arrow = MeshInstance3D.new()
	var cone := CylinderMesh.new()   # an upside-down cone points at the spot
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.45
	_arrow.mesh = cone
	_arrow.material_override = _material(color)
	_arrow.position = Vector3(0.0, 1.5, 0.0)
	add_child(_arrow)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.no_depth_test = true   # visible through furniture
	_materials.append(m)
	return m


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var pulse := 1.0 + sin(_age * 7.0) * 0.08
	_ring.scale = Vector3(pulse, 1.0, pulse)
	_arrow.position.y = 1.5 + sin(_age * 5.0) * 0.15
	var fade := clampf((LIFETIME - _age) / FADE_TIME, 0.0, 1.0)
	for m in _materials:
		m.albedo_color.a = fade
