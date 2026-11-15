extends Camera3D
class_name IsoCamera
## Fixed-orientation orthographic camera. Only position and zoom change: it
## follows the midpoint of all players and widens to keep both in frame.

@export var distance: float = 30.0
@export var min_size: float = 12.0
@export var max_size: float = 22.0
@export var spread_zoom: float = 1.1
@export var follow_speed: float = 4.0
@export var zoom_speed: float = 3.0

var _focus := Vector3.ZERO


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = min_size
	near = 0.1
	far = 120.0
	# True isometric: 45 degree yaw, ~35.264 degree pitch.
	rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	current = true
	_snap_to_focus()


func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	var center := Vector3.ZERO
	for p in players:
		center += (p as Node3D).global_position
	center /= players.size()

	var spread := 0.0
	for p in players:
		spread = maxf(spread, (p as Node3D).global_position.distance_to(center))

	_focus = _focus.lerp(center, clampf(follow_speed * delta, 0.0, 1.0))
	var target_size := clampf(min_size + spread * spread_zoom, min_size, max_size)
	size = lerpf(size, target_size, clampf(zoom_speed * delta, 0.0, 1.0))
	_place()


func _snap_to_focus() -> void:
	_place()


func _place() -> void:
	global_position = _focus + global_basis.z * distance
