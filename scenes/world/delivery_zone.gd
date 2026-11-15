extends Area3D
class_name DeliveryZone
## The truck's cargo bay. Furniture released inside for DELIVER_DELAY seconds
## is delivered for good and dissolves; items leaving first reset their timer.

signal delivery_changed(count: int)

const DELIVER_DELAY := 1.0

@export var size: Vector3 = Vector3(3.0, 2.2, 4.5)

var delivered_items: Array[Furniture] = []
## False in the hub: nothing counts as delivered.
var active := true

var _dwell: Dictionary[Furniture, float] = {}


func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = 1 << 2   # furniture only
	monitoring = true
	monitorable = false

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = size.y * 0.5
	add_child(col)


func _physics_process(delta: float) -> void:
	if not active:
		return
	var dwell: Dictionary[Furniture, float] = {}
	for body in get_overlapping_bodies():
		var f := body as Furniture
		if f == null or f.is_delivered or f.is_held():
			continue
		var time: float = _dwell.get(f, 0.0) + delta
		if time >= DELIVER_DELAY:
			f.deliver()
			delivered_items.append(f)
			delivery_changed.emit(delivered_items.size())
		else:
			dwell[f] = time
			f.in_truck = true

	for old in _dwell:
		if not dwell.has(old) and not old.is_delivered:
			old.in_truck = false
	_dwell = dwell
