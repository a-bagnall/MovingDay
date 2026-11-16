extends CanvasLayer
class_name RunOver
## Shown when a run ends (today: bankruptcy). Reads GameFlow.run_summary, which has
## everything because the run itself is already gone, and returns to the main menu when a
## player presses interact. Online, only the host can continue; it takes everyone with it.

## Ignore presses for this long, so the press that dismissed the last briefing cannot
## skip this screen.
const INPUT_LOCKOUT := 1.0

## Keyed by the cause string GameFlow.fail_run is given (GameFlow.CAUSE_BANKRUPT is
## "bankrupt"). Literal here because an autoload is not usable in a constant.
const CAUSES := {
	"bankrupt": {
		"title": "BANKRUPT",
		"line": "The company could not cover its running costs.",
	},
}

var _was_pressed: Dictionary[int, bool] = {}
var _lockout := INPUT_LOCKOUT
var _prompt: Label


func _ready() -> void:
	GameFlow.day_clock_running = false
	for player_id in InputSetup.local_player_ids():
		var source := InputSetup.source_of(player_id)
		_was_pressed[source] = InputSetup.is_interact_pressed(source)
	_build_ui()


func _process(delta: float) -> void:
	_lockout = maxf(0.0, _lockout - delta)
	for player_id in InputSetup.local_player_ids():
		var source := InputSetup.source_of(player_id)
		var pressed := InputSetup.is_interact_pressed(source)
		var was_pressed: bool = _was_pressed.get(source, true)
		_was_pressed[source] = pressed
		if pressed and not was_pressed and _lockout <= 0.0 and GameFlow.is_authority():
			set_process(false)
			GameFlow.open_main_menu()
			return


func _build_ui() -> void:
	var summary := GameFlow.run_summary
	var cause: Dictionary = CAUSES.get(str(summary.get("cause", "")), {"title": "RUN OVER", "line": ""})

	var root := UIKit.setup(self)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)

	var banner := PanelContainer.new()
	banner.theme_type_variation = &"BannerPanel"
	banner.custom_minimum_size = Vector2(1700, 0)
	banner.add_child(UIKit.label(str(cause["title"]), UIKit.FONT_TITLE, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(banner)

	var line := UIKit.label(str(cause["line"]), UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	line.add_theme_color_override("font_color", UIKit.PINK)
	column.add_child(line)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1700, 0)
	column.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)

	var modifiers: Array = summary.get("modifiers", [])
	var modifier_ids: Array[String] = []
	for id in modifiers:
		modifier_ids.append(str(id))
	_add_row(grid, "Days completed", str(int(summary.get("days_completed", 0))))
	_add_row(grid, "Last day's take-home", UIKit.money(float(summary.get("last_take_home", 0.0))))
	_add_row(grid, "Last day's running costs", "-" + UIKit.money(float(summary.get("last_overhead", 0.0))))
	_add_row(grid, "Final wallet", UIKit.money(float(summary.get("wallet", 0.0))))
	_add_row(grid, "Contracts completed", str(int(summary.get("contracts_completed", 0))))
	_add_row(grid, "Total earned", UIKit.money(float(summary.get("total_earned", 0.0))))
	_add_row(grid, "Damage costs", UIKit.money(float(summary.get("total_damage", 0.0))))
	_add_row(grid, "Running costs paid", UIKit.money(float(summary.get("total_overhead", 0.0))))
	_add_row(grid, "Best day", UIKit.money(float(summary.get("best_day", 0.0))))
	_add_row(grid, "Modifiers", RunModifiers.names(modifier_ids) if not modifier_ids.is_empty() else "None")

	var record := UIKit.label("", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	if bool(summary.get("new_best", false)):
		record.text = "NEW PERSONAL BEST: %d days" % int(summary.get("best_run_day", 0))
		record.add_theme_color_override("font_color", UIKit.GOLD)
	else:
		record.text = "Personal best: %d days" % int(summary.get("best_run_day", 0))
	column.add_child(record)

	var prompt := PanelContainer.new()
	prompt.theme_type_variation = &"ButtonPanel"
	prompt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var text := "Press %s to return to the main menu" % UIKit.INTERACT_KEYS if GameFlow.is_authority() \
		else "Waiting for the host to continue"
	_prompt = UIKit.label(text, UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	prompt.add_child(_prompt)
	column.add_child(prompt)


func _add_row(grid: GridContainer, left: String, right: String) -> void:
	var l := UIKit.label(left, UIKit.FONT_BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l)
	grid.add_child(UIKit.label(right, UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_RIGHT))
