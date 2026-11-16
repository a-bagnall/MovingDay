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
	column.add_theme_constant_override("separation", 18)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(column)

	var banner := PanelContainer.new()
	banner.theme_type_variation = &"BannerPanel"
	banner.custom_minimum_size = Vector2(2700, 0)
	banner.add_child(UIKit.label("DISPATCH OFFICE", UIKit.FONT_TITLE, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(banner)

	var subtitle := "DAY %d  |  %s REMAINING  |  %d CONTRACTS COMPLETED" % [
		SaveManager.run.day,
		UIKit.format_time(GameFlow.day_time_remaining),
		GameFlow.day_contract_count,
	]
	column.add_child(UIKit.label(subtitle, UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))
	var run_notes := PackedStringArray()
	if not SaveManager.run.modifiers.is_empty():
		run_notes.append("MODIFIERS: %s" % RunModifiers.names(SaveManager.run.modifiers).to_upper())
	if GameFlow.current_contract != null and StickyLinks.pair_count(SaveManager.run.day) > 0:
		run_notes.append("HEADS UP: SOME ITEMS ARE STUCK TOGETHER")
	if not run_notes.is_empty():
		column.add_child(UIKit.label("  |  ".join(run_notes), UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))

	var panels := HBoxContainer.new()
	panels.add_theme_constant_override("separation", 20)
	column.add_child(panels)
	panels.add_child(_build_previous_panel())
	panels.add_child(_build_next_panel())

	var prompt := PanelContainer.new()
	prompt.theme_type_variation = &"ButtonPanel"
	prompt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_label = UIKit.label("Press %s to skip the letter" % UIKit.INTERACT_KEYS, UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	prompt.add_child(_continue_label)
	column.add_child(prompt)


func _contract_label(text: String, size: int = UIKit.FONT_BODY,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := UIKit.label(text, size, align)
	label.add_theme_font_override("font", UIKit.paper_font())
	return label


func _build_previous_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1340, 1000)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	column.add_child(_contract_label("PREVIOUS PROPERTY", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	if GameFlow.previous_contract_result.is_empty():
		column.add_child(_contract_label("FIRST JOB OF THE DAY", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
		column.add_child(_contract_label("No previous property completed yet.\n\nYour team's results will appear here after each move.", UIKit.FONT_BODY))
		return panel

	var result := GameFlow.previous_contract_result
	var receipt := _contract_label("PROPERTY %02d\n%s\n--------------------------------\nItems delivered: %s\nCompletion: %d%%\nTime: %s\nBase pay: %s\nTime bonus: +%s\nStyle bonus: +%s\nDamage: -%s\n--------------------------------\nPAYMENT: %s" % [
		GameFlow.day_contract_count,
		str(result.get("client_name", "Previous client")),
		str(result.get("items_delivered", "-")),
		roundi(float(result.get("completion", 0.0)) * 100.0),
		UIKit.format_time(float(result.get("time", 0.0))),
		UIKit.money(float(result.get("base_pay", 0.0))),
		UIKit.money(float(result.get("time_bonus", 0.0))),
		UIKit.money(float(result.get("style_bonus", 0.0))),
		UIKit.money(float(result.get("damage", 0.0))),
		UIKit.money(float(result.get("payment", 0.0))),
	])
	receipt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(receipt)
	return panel


func _build_next_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1340, 1000)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	if GameFlow.current_contract == null:
		column.add_child(_contract_label("END OF DAY", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
		column.add_child(_contract_label("No more contracts today. Your team has finished the shift.", UIKit.FONT_BODY))
		column.add_child(_contract_label("DAY TOTAL", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
		column.add_child(_contract_label("Contracts completed: %d\nTotal base pay: %s\nTime bonuses: %s\nStyle bonuses: %s\nDamage costs: -%s\n\nTAKE-HOME: %s" % [
			int(GameFlow.day_total.get("contracts_completed", 0)),
			UIKit.money(float(GameFlow.day_total.get("base_pay", 0.0))),
			UIKit.money(float(GameFlow.day_total.get("time_bonus", 0.0))),
			UIKit.money(float(GameFlow.day_total.get("style_bonus", 0.0))),
			UIKit.money(float(GameFlow.day_total.get("damage", 0.0))),
			UIKit.money(float(GameFlow.day_total.get("payment", 0.0))),
		], UIKit.FONT_BODY))
		return panel

	var contract := GameFlow.current_contract
	column.add_child(_contract_label("NEXT JOB", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_contract_label("CONTRACT %02d  |  OFFER: %s" % [contract.contract_number, UIKit.money(contract.payout)], UIKit.FONT_SMALL))
	column.add_child(_contract_label("To: Moving team\nFrom: %s" % contract.client_name, UIKit.FONT_BODY))
	var divider := HSeparator.new()
	column.add_child(divider)
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
	return "Press %s to %s" % [UIKit.INTERACT_KEYS, what]


func _continue() -> void:
	# A client keeps running: the host may not have answered yet, so it can press again.
	if GameFlow.is_authority():
		set_process(false)
	GameFlow.continue_from_briefing()
