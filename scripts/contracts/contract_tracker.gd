extends CanvasLayer
class_name ContractTracker
## Tracks one property: required deliveries, damage cost and elapsed time.
## Completing a property hands its result to GameFlow, which opens the briefing.

signal contract_finished(result: Dictionary)

const PAR_TIME := 120.0        ## Seconds under which a time bonus is earned.
const TIME_BONUS_RATE := 2.0   ## Dollars per second under par.
const FIRST_DAY_DEBUG_ITEM := "Box"

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
var _delivered_bar: ProgressBar


func setup(delivery_zone: DeliveryZone, items: Array[Furniture], job_contract: Contract = null) -> void:
	zone = delivery_zone
	contract = job_contract if job_contract != null else GameFlow.current_contract

	# Keep day one deliberately simple while the progression loop is being tested.
	# Retain the lightweight, single-player Box and remove the other spawned items.
	if SaveManager.run != null and SaveManager.run.day == 1:
		var debug_item: Furniture
		for item in items:
			if item.data != null and item.data.display_name == FIRST_DAY_DEBUG_ITEM:
				debug_item = item
				break
		if debug_item == null and not items.is_empty():
			debug_item = items[0]

		for item in items:
			if item != debug_item:
				item.queue_free()
		items.clear()
		if debug_item != null:
			items.append(debug_item)

	required = items
	_build_ui()


func _build_ui() -> void:
	_root = UIKit.setup(self)

	var margin := UIKit.safe_area(_root)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bar)
	_delivered_value = _add_chip(bar, "DELIVERED", true)
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
	hint.add_child(UIKit.label("Grab / drop: %s\nLift: %s\nAction: %s\nHeave-ho: %s" % [
		UIKit.INTERACT_KEYS, UIKit.LIFT_KEYS, UIKit.ACTION_KEYS, UIKit.HEAVE_KEYS],
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_LEFT, &"DarkLabel"))
	column.add_child(hint)


func _add_chip(bar: HBoxContainer, caption: String, with_progress: bool = false) -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -6)
	panel.add_child(box)
	box.add_child(UIKit.label(caption, UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))
	var value := UIKit.label("", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(value)
	if with_progress:
		_delivered_bar = UIKit.progress_bar(UIKit.SUCCESS)
		box.add_child(_delivered_bar)
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
		UIKit.PINK if damage > 0.5 else UIKit.CREAM)
	_delivered_bar.max_value = maxf(float(required.size()), 1.0)
	_delivered_bar.value = float(delivered)
	# The day clock turns gold, then pink, as it runs down.
	var day_left := GameFlow.day_time_remaining
	_day_value.add_theme_color_override("font_color",
		UIKit.PINK if day_left < 60.0 else (UIKit.GOLD if day_left < 120.0 else UIKit.CREAM))

	# The host decides when the job is over; clients follow it to the briefing.
	if delivered >= required.size() and required.size() > 0 and GameFlow.is_authority():
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
	var style_rate := 0.0
	if SaveManager.profile != null:
		match SaveManager.profile.equipped_outfit:
			"workwear":
				style_rate = 0.10
			"enchanted_workwear":
				style_rate = 0.15
	var style_bonus := (base + time_bonus) * style_rate
	var payment := maxf(0.0, base + time_bonus + style_bonus - damage)
	var result := {
		"client_name": contract.client_name if contract else "Client",
		"contract_number": contract.contract_number if contract else 1,
		"items_delivered": delivered,
		"completion": completion,
		"damage": damage,
		"time": elapsed,
		"base_pay": base,
		"time_bonus": time_bonus,
		"style_bonus": style_bonus,
		"payment": payment,
	}
	contract_finished.emit(result)
	GameFlow.finish_contract(result)
