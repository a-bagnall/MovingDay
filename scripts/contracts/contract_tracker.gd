extends CanvasLayer
class_name ContractTracker
## Tracks the job: items required, delivered, damage cost and elapsed time.
## Shows a live HUD, then a results screen once every item is in the truck.

signal contract_finished(result: Dictionary)

const BASE_PAY := 500.0
const PAR_TIME := 120.0        ## Seconds under which a time bonus is earned.
const TIME_BONUS_RATE := 2.0   ## Dollars per second under par.
## Seconds before the results can be dismissed, so a button held at the finish does not skip them.
const CONTINUE_DELAY := 1.5

var zone: DeliveryZone
var required: Array[Furniture] = []
var elapsed := 0.0
var finished := false

var _root: Control
var _delivered_value: Label
var _damage_value: Label
var _time_value: Label
var _results: Control
var _result := {}
var _results_age := 0.0
var _interact_prev: Dictionary[int, bool] = {}   # keyed by player id


func setup(delivery_zone: DeliveryZone, items: Array[Furniture]) -> void:
	zone = delivery_zone
	required = items
	_build_ui()


# --- HUD ------------------------------------------------------------------

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

	# Top: three stat chips, centred.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 36)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bar)
	_delivered_value = _add_chip(bar, "DELIVERED")
	_damage_value = _add_chip(bar, "DAMAGE")
	_time_value = _add_chip(bar, "TIME")

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	# Bottom-left: controls hint on a note.
	var hint := PanelContainer.new()
	hint.theme_type_variation = &"NotePanel"
	hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hint.add_child(UIKit.label("Interact: grab / drop", UIKit.FONT_SMALL,
		HORIZONTAL_ALIGNMENT_LEFT, &"DarkLabel"))
	column.add_child(hint)


## Adds a captioned stat chip to `bar` and returns its value label.
func _add_chip(bar: HBoxContainer, caption: String) -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -6)
	panel.add_child(box)
	box.add_child(UIKit.label(caption, UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))
	var value := UIKit.label("", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(value)
	bar.add_child(panel)
	return value


func _process(delta: float) -> void:
	if finished:
		_poll_continue(delta)
		return
	if zone == null:
		return
	elapsed += delta

	var delivered := zone.delivered_items.size()
	var damage := total_damage()
	_delivered_value.text = "%d / %d" % [delivered, required.size()]
	_damage_value.text = UIKit.money(damage)
	_time_value.text = UIKit.format_time(elapsed)
	# Damage text turns pink once it starts costing money.
	_damage_value.add_theme_color_override("font_color",
		Color("ffb3a3") if damage > 0.5 else UIKit.CREAM)

	if delivered >= required.size() and required.size() > 0:
		_finish()


func total_damage() -> float:
	var total := 0.0
	for f in required:
		if is_instance_valid(f):
			total += f.total_damage
	return total


# --- results --------------------------------------------------------------

func _finish() -> void:
	finished = true
	var delivered := zone.delivered_items.size()
	var damage := total_damage()
	var completion := float(delivered) / float(maxi(required.size(), 1))
	var base := BASE_PAY * completion
	var time_bonus := maxf(0.0, PAR_TIME - elapsed) * TIME_BONUS_RATE
	var payment := maxf(0.0, base + time_bonus - damage)

	var result := {
		"completion": completion,
		"damage": damage,
		"time": elapsed,
		"base_pay": base,
		"time_bonus": time_bonus,
		"payment": payment,
	}
	_result = result
	_show_results(result, delivered)
	contract_finished.emit(result)


func _show_results(result: Dictionary, delivered: int) -> void:
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_results)

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.05, 0.03, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	var banner := PanelContainer.new()
	banner.theme_type_variation = &"BannerPanel"
	banner.custom_minimum_size = Vector2(1300, 0)
	banner.add_child(UIKit.label("JOB COMPLETE", UIKit.FONT_TITLE, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(banner)

	var details := PanelContainer.new()
	details.custom_minimum_size = Vector2(1300, 0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 14)
	details.add_child(grid)
	column.add_child(details)

	_add_row(grid, "Items delivered", "%d / %d" % [delivered, required.size()])
	_add_row(grid, "Time", UIKit.format_time(result.time))
	_add_row(grid, "Base pay", UIKit.money(result.base_pay))
	_add_row(grid, "Time bonus", "+" + UIKit.money(result.time_bonus))
	_add_row(grid, "Damage", "-" + UIKit.money(result.damage))
	_add_row(grid, "PAYMENT", UIKit.money(result.payment), UIKit.FONT_BIG, UIKit.GOLD)

	var prompt := PanelContainer.new()
	prompt.theme_type_variation = &"ButtonPanel"
	prompt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prompt.add_child(UIKit.label("Press interact to continue", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(prompt)

	_animate_in(column, dim)


func _add_row(grid: GridContainer, left: String, right: String,
		size: int = UIKit.FONT_BODY, right_color: Color = UIKit.CREAM) -> void:
	var l := UIKit.label(left, size)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l)
	var r := UIKit.label(right, size, HORIZONTAL_ALIGNMENT_RIGHT)
	r.add_theme_color_override("font_color", right_color)
	grid.add_child(r)


## Pop the results in with a bounce; waits a frame so the container has a size.
func _animate_in(column: Control, dim: Control) -> void:
	dim.modulate.a = 0.0
	column.modulate.a = 0.0
	await get_tree().process_frame
	column.pivot_offset = column.size * 0.5
	column.scale = Vector2(0.75, 0.75)
	column.modulate.a = 1.0
	var tween := create_tween().set_parallel()
	tween.tween_property(dim, "modulate:a", 1.0, 0.25)
	tween.tween_property(column, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Any player pressing interact (a fresh press, after CONTINUE_DELAY) ends the day.
func _poll_continue(delta: float) -> void:
	_results_age += delta
	for player_id in range(1, InputSetup.assigned_count() + 1):
		var pressed := InputSetup.is_interact_pressed(InputSetup.source_of(player_id))
		var was_pressed: bool = _interact_prev.get(player_id, true)
		_interact_prev[player_id] = pressed
		if pressed and not was_pressed and _results_age >= CONTINUE_DELAY:
			set_process(false)   # one call only; the scene changes next frame
			GameFlow.finish_day(_result)
			return
