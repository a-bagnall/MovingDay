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
	(_prompt.get_parent().get_parent() as Control).modulate.a = 0.5 if _lockout > 0.0 else 1.0   # dim until presses count
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
	column.add_theme_constant_override("separation", UIKit.SPACE_M)
	center.add_child(column)

	column.add_child(UIKit.banner(str(cause["title"]), 1700.0))

	var line := UIKit.label(str(cause["line"]), UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	line.add_theme_color_override("font_color", UIKit.PINK)
	column.add_child(line)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1700, 0)
	column.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UIKit.SPACE_M)
	panel.add_child(body)

	var modifiers: Array = summary.get("modifiers", [])
	var modifier_ids: Array[String] = []
	for id in modifiers:
		modifier_ids.append(str(id))

	# The headline numbers first, then the full breakdown under a rule.
	var headline := UIKit.stat_grid()
	body.add_child(headline)
	UIKit.add_stat(headline, "Days completed", str(int(summary.get("days_completed", 0))), UIKit.GOLD)
	var wallet := float(summary.get("wallet", 0.0))
	UIKit.add_stat(headline, "Final wallet", UIKit.money(wallet),
		UIKit.PINK if wallet < 0.0 else UIKit.GOLD)
	body.add_child(HSeparator.new())

	var grid := UIKit.stat_grid()
	body.add_child(grid)
	UIKit.add_stat(grid, "Last day's take-home", UIKit.money(float(summary.get("last_take_home", 0.0))))
	UIKit.add_stat(grid, "Last day's running costs", "-" + UIKit.money(float(summary.get("last_overhead", 0.0))), UIKit.PINK)
	UIKit.add_stat(grid, "Contracts completed", str(int(summary.get("contracts_completed", 0))))
	UIKit.add_stat(grid, "Contracts failed", str(int(summary.get("contracts_failed", 0))), UIKit.PINK)
	UIKit.add_stat(grid, "Total earned", UIKit.money(float(summary.get("total_earned", 0.0))))
	UIKit.add_stat(grid, "Damage costs", UIKit.money(float(summary.get("total_damage", 0.0))))
	UIKit.add_stat(grid, "Running costs paid", UIKit.money(float(summary.get("total_overhead", 0.0))))
	UIKit.add_stat(grid, "Best day", UIKit.money(float(summary.get("best_day", 0.0))))
	UIKit.add_stat(grid, "Modifiers", RunModifiers.names(modifier_ids) if not modifier_ids.is_empty() else "None")

	var record := UIKit.label("", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER)
	if bool(summary.get("new_best", false)):
		record.text = "NEW PERSONAL BEST: %d days" % int(summary.get("best_run_day", 0))
		record.add_theme_color_override("font_color", UIKit.GOLD)
	else:
		record.text = "Personal best: %d days" % int(summary.get("best_run_day", 0))
		record.add_theme_color_override("font_color", UIKit.MUTED)
	column.add_child(record)

	var text := "Press %s to return to the main menu" % UIKit.INTERACT_KEYS if GameFlow.is_authority() \
		else "Waiting for the host to continue"
	_prompt = UIKit.key_prompt(column, text, GameFlow.is_authority())
