extends CanvasLayer
class_name Briefing
## Between-contract briefing. Shows the previous property's receipt alongside
## the next client's letter, or the day summary when the day clock has expired.

const TYPEWRITER_CHARS_PER_SECOND := 48.0

var _letter: Label
var _typewriter_text := ""
var _revealed_chars := 0.0
var _typing := false
var _was_pressed: Dictionary[int, bool] = {}
var _continue_label: Label


func _ready() -> void:
	# Briefings are non-play time: never consume the day clock while reading
	# the debrief, the next contract, or the end-of-day summary.
	GameFlow.day_clock_running = false
	for player_id in InputSetup.local_player_ids():
		var source := InputSetup.source_of(player_id)
		_was_pressed[source] = InputSetup.is_interact_pressed(source)
	_build_ui()


func _process(delta: float) -> void:
	if _typing:
		_revealed_chars = minf(float(_typewriter_text.length()),
			_revealed_chars + TYPEWRITER_CHARS_PER_SECOND * delta)
		_letter.visible_characters = floori(_revealed_chars)
		if _revealed_chars >= _typewriter_text.length():
			_typing = false
			_continue_label.text = _continue_prompt()

	_poll_interact()


func _build_ui() -> void:
	var root := UIKit.setup(self)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIKit.SPACE_M)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(column)

	column.add_child(UIKit.banner("DISPATCH OFFICE", 2700.0))

	# Day status as three chips: scannable at a glance, not one long run-on line.
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", UIKit.SPACE_M)
	status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status.add_child(UIKit.chip("DAY %d" % SaveManager.run.day, UIKit.GOLD))
	status.add_child(UIKit.chip("%s LEFT" % UIKit.format_time(GameFlow.day_time_remaining), UIKit.CREAM))
	status.add_child(UIKit.chip("%d DONE" % GameFlow.day_contract_count, UIKit.CREAM))
	column.add_child(status)

	var panels := HBoxContainer.new()
	panels.add_theme_constant_override("separation", UIKit.SPACE_M)
	column.add_child(panels)
	panels.add_child(_build_previous_panel())
	panels.add_child(_build_next_panel())

	_continue_label = UIKit.key_prompt(column, "Press %s to skip the letter" % UIKit.interact_keys_text())


func _contract_label(text: String, size: int = UIKit.FONT_BODY,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := UIKit.label(text, size, align)
	label.add_theme_font_override("font", UIKit.paper_font())
	return label


## A receipt table in the paper font: muted labels, values on the right.
func _receipt() -> GridContainer:
	var grid := UIKit.stat_grid()
	grid.add_theme_constant_override("v_separation", 8)
	return grid


func _receipt_row(grid: GridContainer, left: String, right: String,
		color: Color = UIKit.CREAM) -> void:
	UIKit.add_stat(grid, left, right, color, UIKit.paper_font())


func _build_previous_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1340, 1000)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIKit.SPACE_S)
	panel.add_child(column)

	column.add_child(_contract_label("PREVIOUS PROPERTY", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	if GameFlow.previous_contract_result.is_empty():
		column.add_child(_contract_label("FIRST JOB OF THE DAY", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
		var empty := _contract_label("No previous property completed yet.\n\nYour team's results will appear here after each move.", UIKit.FONT_BODY)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(empty)
		return panel

	var result := GameFlow.previous_contract_result
	var outcome := "COMPLETED" if bool(result.get("success", true)) else "CONTRACT FAILED"
	column.add_child(_contract_label("%s  ·  PROPERTY %02d  |  %s" % [
		outcome, int(result.get("contract_number", GameFlow.day_contract_count)),
		str(result.get("client_name", "Previous client"))],
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(HSeparator.new())

	var rows := _receipt()
	column.add_child(rows)
	_receipt_row(rows, "Items delivered", "%d / %d" % [
		int(result.get("items_delivered", 0)), int(result.get("items_required", result.get("items_delivered", 0)))])
	_receipt_row(rows, "Completion", "%d%%" % roundi(float(result.get("completion", 0.0)) * 100.0))
	if float(result.get("failure_penalty", 0.0)) > 0.0:
		_receipt_row(rows, "Failure penalty", "-" + UIKit.money(float(result.get("failure_penalty", 0.0))), UIKit.PINK)
	_receipt_row(rows, "Time", UIKit.format_time(float(result.get("time", 0.0))))
	_receipt_row(rows, "Base pay", UIKit.money(float(result.get("base_pay", 0.0))))
	_receipt_row(rows, "Time bonus", "+" + UIKit.money(float(result.get("time_bonus", 0.0))), UIKit.SUCCESS)
	_receipt_row(rows, "Style bonus", "+" + UIKit.money(float(result.get("style_bonus", 0.0))), UIKit.SUCCESS)
	var damage := float(result.get("damage", 0.0))
	_receipt_row(rows, "Damage", "-" + UIKit.money(damage), UIKit.PINK if damage > 0.5 else UIKit.CREAM)

	column.add_child(HSeparator.new())
	var total := _receipt()
	column.add_child(total)
	_receipt_row(total, "PAYMENT", UIKit.money(float(result.get("payment", 0.0))), UIKit.GOLD)
	return panel


func _build_next_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1340, 1000)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIKit.SPACE_S)
	panel.add_child(column)

	if GameFlow.current_contract == null:
		column.add_child(_contract_label("END OF DAY", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
		var done := _contract_label("No more contracts today. Your team has finished the shift.", UIKit.FONT_BODY)
		done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(done)
		column.add_child(HSeparator.new())
		column.add_child(_contract_label("DAY TOTAL", UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))
		var rows := _receipt()
		column.add_child(rows)
		_receipt_row(rows, "Contracts completed", str(int(GameFlow.day_total.get("contracts_completed", 0))))
		_receipt_row(rows, "Contracts failed", str(int(GameFlow.day_total.get("contracts_failed", 0))), UIKit.PINK)
		_receipt_row(rows, "Failure penalties", "-" + UIKit.money(float(GameFlow.day_total.get("failure_penalty", 0.0))), UIKit.PINK)
		_receipt_row(rows, "Total base pay", UIKit.money(float(GameFlow.day_total.get("base_pay", 0.0))))
		_receipt_row(rows, "Time bonuses", "+" + UIKit.money(float(GameFlow.day_total.get("time_bonus", 0.0))), UIKit.SUCCESS)
		_receipt_row(rows, "Style bonuses", "+" + UIKit.money(float(GameFlow.day_total.get("style_bonus", 0.0))), UIKit.SUCCESS)
		var damage := float(GameFlow.day_total.get("damage", 0.0))
		_receipt_row(rows, "Damage costs", "-" + UIKit.money(damage), UIKit.PINK if damage > 0.5 else UIKit.CREAM)
		column.add_child(HSeparator.new())
		var total := _receipt()
		column.add_child(total)
		_receipt_row(total, "TAKE-HOME", UIKit.money(float(GameFlow.day_total.get("payment", 0.0))), UIKit.GOLD)
		return panel

	var contract := GameFlow.current_contract
	column.add_child(_contract_label("NEXT JOB", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_contract_label("CONTRACT %02d  |  TARGET: %d ITEMS  |  OFFER: %s" % [
		contract.contract_number, Balance.contract_item_target(contract.contract_number), UIKit.money(contract.payout)],
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_contract_label("To: Moving team\nFrom: %s" % contract.client_name, UIKit.FONT_BODY))
	column.add_child(HSeparator.new())
	_letter = _contract_label("")
	_letter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_letter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_letter)
	_typewriter_text = contract.letter_text
	_typing = true
	_letter.text = _typewriter_text
	_letter.visible_characters = 0
	return panel


func _poll_interact() -> void:
	for player_id in InputSetup.local_player_ids():
		var source := InputSetup.source_of(player_id)
		var pressed := InputSetup.is_interact_pressed(source)
		var was_pressed: bool = _was_pressed.get(source, true)
		_was_pressed[source] = pressed
		if pressed and not was_pressed:
			if _typing:
				_revealed_chars = float(_typewriter_text.length())
				_letter.visible_characters = -1
				_typing = false
				_continue_label.text = _continue_prompt()
			else:
				_continue()
			return


func _continue_prompt() -> String:
	var what := "start the next job" if GameFlow.current_contract != null else "finish the day"
	return "Press %s to %s" % [UIKit.interact_keys_text(), what]


func _continue() -> void:
	# A client keeps running: the host may not have answered yet, so it can press again.
	if GameFlow.is_authority():
		set_process(false)
	GameFlow.continue_from_briefing()
