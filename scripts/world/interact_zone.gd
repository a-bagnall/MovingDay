extends Area3D
class_name InteractZone
## A floor pad with a floating label, used in the main menu and the hub. It only
## reports which players stand on it and when one of them presses interact;
## WalkableArea does the input polling and the owning area decides what it means.

signal interacted(player_id: int)

const ZONE_HEIGHT := 2.0
const PAD_ALPHA := 0.55

var _label: Label3D


func _init(p_size := Vector3(3.0, 0.1, 3.0), p_color := Color.WHITE, p_text := "") -> void:
	collision_layer = 0
	collision_mask = 1 << 1   # players
	monitoring = true
	monitorable = false

	var shape := BoxShape3D.new()
	shape.size = Vector3(p_size.x, ZONE_HEIGHT, p_size.z)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = ZONE_HEIGHT * 0.5
	add_child(col)

	var pad := BoxMesh.new()
	pad.size = Vector3(p_size.x, 0.05, p_size.z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(p_color, PAD_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := MeshInstance3D.new()
	mesh.mesh = pad
	mesh.material_override = material
	mesh.position.y = 0.03
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	_label = Label3D.new()
	_label.text = p_text
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.pixel_size = 0.01
	_label.outline_size = 16
	_label.position.y = 2.2
	add_child(_label)


func set_text(text: String) -> void:
	_label.text = text


func players_inside() -> Array[Player]:
	var out: Array[Player] = []
	for body in get_overlapping_bodies():
		var player := body as Player
		if player:
			out.append(player)
	return out
