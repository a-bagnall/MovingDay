extends CanvasLayer
class_name ContractTracker
## Tracks one property: required deliveries, damage cost and elapsed time.
## Completing a property hands its result to GameFlow, which opens the briefing.

signal contract_finished(result: Dictionary)

const PAR_TIME := 120.0        ## Seconds under which a time bonus is earned.
const TIME_BONUS_RATE := 2.0   ## Dollars per second under par.

var zone: DeliveryZone
var required: Array[Furniture] = []
var contract: Contract
var elapsed := 0.0
var finished := false

var _root: Control
var _delivered_value: Label
var _damage_value: Label
var _time_value: Label
var _day_value: Label


func setup(delivery_zone: DeliveryZone, items: Array[Furniture], job_contract: Contract = null) -> void:
	zone = delivery_zone
	required = items
	contract = job_contract if job_contract != null else GameFlow.current_contract
	_build_ui()


func _build_ui() -> void:
	_root = UIKit.setup(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bar)
	_delivered_value = _add_chip(bar, "DELIVERED")
	_damage_value = _add_chip(bar, "DAMAGE")
	_time_value = _add_chip(bar, "JOB TIME")
	_day_value = _add_chip(bar, "DAY LEFT")

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var hint := PanelContainer.new()
	hint.theme_type_variation = &"NotePanel"
	hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hint.add_child(UIKit.label("Interact: grab / drop", UIKit.FONT_SMALL,
		HORIZONTAL_ALIGNMENT_LEFT, &"DarkLabel"))
	column.add_child(hint)


func _add_chip(bar: HBoxContainer, caption: String) -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -6)
	panel.add_child(box)
	box.add_child(UIKit.label(caption, UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))
	var value := UIKit.label("", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(value)
	bar.add_child(panel)
	return value


func _process(delta: float) -> void:
	if finished or zone == null:
		return
	elapsed += delta

	var delivered := zone.delivered_items.size()
	var damage := total_damage()
	_delivered_value.text = "%d / %d" % [delivered, required.size()]
	_damage_value.text = UIKit.money(damage)
	_time_value.text = UIKit.format_time(elapsed)
	_day_value.text = UIKit.format_time(GameFlow.day_time_remaining)
	_damage_value.add_theme_color_override("font_color",
		Color("ffb3a3") if damage > 0.5 else UIKit.CREAM)

	if delivered >= required.size() and required.size() > 0:
		_finish()


func total_damage() -> float:
	var total := 0.0
	for item in required:
		if is_instance_valid(item):
			total += item.total_damage
	return total


func _finish() -> void:
	finished = true
	var delivered := zone.delivered_items.size()
	var damage := total_damage()
	var completion := float(delivered) / float(maxi(required.size(), 1))
	var base := contract.payout * completion if contract else 500.0 * completion
	var time_bonus := maxf(0.0, PAR_TIME - elapsed) * TIME_BONUS_RATE
	var payment := maxf(0.0, base + time_bonus - damage)
	var result := {
		"client_name": contract.client_name if contract else "Client",
		"contract_number": contract.contract_number if contract else 1,
		"items_delivered": delivered,
		"completion": completion,
		"damage": damage,
		"time": elapsed,
		"base_pay": base,
		"time_bonus": time_bonus,
		"payment": payment,
	}
	contract_finished.emit(result)
	GameFlow.finish_contract(result)
