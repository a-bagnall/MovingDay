extends CanvasLayer
class_name ContractTracker
## Tracks the job: items required, delivered, damage cost and elapsed time.
## Shows a live HUD, then a results panel once every item is in the truck and
## all items are delivered.

signal contract_finished(result: Dictionary)

var zone: DeliveryZone
var required: Array[Furniture] = []
var elapsed := 0.0
var finished := false

var _hud: Label
var _results: Label


func setup(delivery_zone: DeliveryZone, items: Array[Furniture]) -> void:
	zone = delivery_zone
	required = items
	_build_ui()


func _build_ui() -> void:
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 22)
	add_child(_hud)

	_results = Label.new()
	_results.position = Vector2(380, 180)
	_results.add_theme_font_size_override("font_size", 28)
	_results.visible = false
	add_child(_results)


func _process(delta: float) -> void:
	if finished or zone == null:
		return
	elapsed += delta

	var delivered := zone.delivered_items.size()
	var damage := total_damage()
	_hud.text = "Delivered: %d / %d    Damage: $%d    Time: %s\nInteract button: grab / drop" % [
		delivered, required.size(), roundi(damage), _format_time(elapsed)
	]

	if delivered >= required.size() and required.size() > 0:
		_finish()


func total_damage() -> float:
	var total := 0.0
	for f in required:
		if is_instance_valid(f):
			total += f.total_damage
	return total


func _finish() -> void:
	finished = true
	var delivered := zone.delivered_items.size()
	var damage := total_damage()
	var completion := float(delivered) / float(maxi(required.size(), 1))
	var base_pay := 500.0
	var time_bonus := maxf(0.0, 120.0 - elapsed) * 2.0
	var payment := maxf(0.0, base_pay * completion + time_bonus - damage)

	var result := {
		"completion": completion,
		"damage": damage,
		"time": elapsed,
		"payment": payment,
	}
	_results.text = "JOB COMPLETE\n\nItems delivered: %d / %d\nDamage: $%d\nTime: %s\nPayment: $%d\n\nPress R to restart" % [
		delivered, required.size(), roundi(damage), _format_time(elapsed), roundi(payment)
	]
	_results.visible = true
	contract_finished.emit(result)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if finished and key and key.pressed and key.keycode == KEY_R:
		get_tree().reload_current_scene()


func _format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]
