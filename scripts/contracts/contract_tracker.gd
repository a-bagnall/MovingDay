extends CanvasLayer
class_name ContractTracker
## Tracks one property: required deliveries, damage cost and elapsed time.
## Completing a property hands its result to GameFlow, which opens the briefing.

signal contract_finished(result: Dictionary)

## PAR_TIME and TIME_BONUS_RATE are live Balance settings.

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

	# Contracts ask for a small, progressively larger subset of the house.
	# The deterministic priority keeps early jobs approachable and stays in sync online.
	var candidates: Array[Furniture] = []
	candidates.append_array(items)
	candidates.sort_custom(func(a: Furniture, b: Furniture) -> bool:
		return _item_rank(a) < _item_rank(b)
	)
	var contract_number := contract.contract_number if contract != null else 1
	var target := mini(Balance.contract_item_target(contract_number), candidates.size())
	required.clear()
	for i in candidates.size():
		if i < target:
			required.append(candidates[i])
		else:
			candidates[i].queue_free()
	items.clear()
	items.append_array(required)
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
	if not GameFlow.is_authority():
		return
	if delivered >= required.size() and required.size() > 0:
		_finish(true)
	elif GameFlow.day_time_remaining <= 0.0:
		_finish(false)


func _item_rank(item: Furniture) -> int:
	if item.data == null:
		return Balance.CONTRACT_ITEM_ORDER.size()
	var rank := Balance.CONTRACT_ITEM_ORDER.find(item.data.display_name)
	return rank if rank >= 0 else Balance.CONTRACT_ITEM_ORDER.size()


func total_damage() -> float:
	var total := 0.0
	for item in required:
		if is_instance_valid(item):
			total += item.total_damage
	return total


func _finish(success: bool) -> void:
	finished = true
	var delivered := zone.delivered_items.size()
	var missing := maxi(required.size() - delivered, 0)
	var damage := total_damage()
	var completion := float(delivered) / float(maxi(required.size(), 1))
	var base := contract.payout * completion if contract else 500.0 * completion
	var failure_penalty := 0.0 if success else Balance.FAILED_CONTRACT_BASE_PENALTY \
		+ float(missing) * Balance.FAILED_CONTRACT_PER_MISSING_ITEM_PENALTY
	var time_bonus := maxf(0.0, Balance.PAR_TIME - elapsed) * Balance.TIME_BONUS_RATE if success else 0.0
	var style_rate := 0.0
	if SaveManager.profile != null:
		match SaveManager.profile.equipped_outfit:
			"workwear":
				style_rate = 0.10
			"enchanted_workwear":
				style_rate = 0.15
	var style_bonus := (base + time_bonus) * style_rate
	var payment := base + time_bonus + style_bonus - damage - failure_penalty
	var result := {
		"client_name": contract.client_name if contract else "Client",
		"contract_number": contract.contract_number if contract else 1,
		"success": success,
		"items_delivered": delivered,
		"items_required": required.size(),
		"items_missing": missing,
		"completion": completion,
		"damage": damage,
		"failure_penalty": failure_penalty,
		"time": elapsed,
		"base_pay": base,
		"time_bonus": time_bonus,
		"style_bonus": style_bonus,
		"payment": payment,
	}
	contract_finished.emit(result)
	GameFlow.finish_contract(result)
