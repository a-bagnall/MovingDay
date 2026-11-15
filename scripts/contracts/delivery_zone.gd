extends Area3D
class_name DeliveryZone
## The truck's cargo bay. Furniture counts as delivered while it is inside the
## zone and not being held. Items knocked back out stop counting.

signal delivery_changed(count: int)

@export var size: Vector3 = Vector3(3.0, 2.2, 4.5)

var delivered_items: Array[Furniture] = []


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


func _physics_process(_delta: float) -> void:
	var current: Array[Furniture] = []
	for body in get_overlapping_bodies():
		var f := body as Furniture
		if f and not f.is_held():
			current.append(f)
			f.in_truck = true

	for old in delivered_items:
		if is_instance_valid(old) and not current.has(old):
			old.in_truck = false

	if current.size() != delivered_items.size():
		delivered_items = current
		delivery_changed.emit(current.size())
	else:
		delivered_items = current
