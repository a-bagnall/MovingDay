extends CanvasLayer
class_name DebugOverlay
## F3 toggles a live readout of every furniture item and player, for tuning
## carrying and damage: grip, damage so far, and the last impact against the
## item's damage limit. If "last hit" never changes when you bump things, the
## physics engine is not reporting contact impulses and damage will not work.

var _panel: PanelContainer
var _label: Label
var _balance_panel: PanelContainer


func _ready() -> void:
	layer = 100
	# A translucent backing panel keeps the text readable over any room.
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 90)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	back.set_corner_radius_all(8)
	back.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", back)
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_panel.add_child(_label)
	_panel.visible = false
	_build_balance_panel()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F3:
		_panel.visible = not _panel.visible
	elif key.keycode == KEY_F4:
		_balance_panel.visible = not _balance_panel.visible


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	var lines: PackedStringArray = ["F3 DEBUG  ·  F4 BALANCE LAB", ""]
	if SaveManager.run != null:
		lines.append("Run: day %d  wallet $%d  modifiers: %s" % [
			SaveManager.run.day, roundi(SaveManager.run.wallet),
			RunModifiers.names(SaveManager.run.modifiers) if not SaveManager.run.modifiers.is_empty() else "none"])
		lines.append("Contracts: %d attempted / %d completed / %d failed" % [
			SaveManager.run.contracts_attempted, SaveManager.run.contracts_completed, SaveManager.run.contracts_failed])
		lines.append("Next target: %d items" % Balance.contract_item_target(SaveManager.run.contracts_attempted + 1))
		lines.append("Day clock: %.1fs / %.1fs" % [GameFlow.day_time_remaining, Balance.DAY_LENGTH])
		lines.append("")

	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p:
			lines.append("P%d  speed x%.2f  holding: %s" % [
				p.player_id, p.speed_multiplier,
				p.held_furniture.data.display_name if p.held_furniture else "-"])
	lines.append("")

	for node in get_tree().get_nodes_in_group("furniture"):
		var f := node as Furniture
		if f == null:
			continue
		var limit := f.data.effective_threshold()
		var hit := "none"
		if f.debug_peak_age < 5.0:
			hit = "%.1f m/s (%.1fs ago)" % [f.debug_peak_dv, f.debug_peak_age]
		lines.append("%-8s hold %d/%d  grip %3d%%  damage $%d/$%d  hit limit %.1f  last hit %s" % [
			f.data.display_name, f.holder_count(), f.data.players_required,
			f.grip_percent(), roundi(f.total_damage), roundi(f.data.value), limit, hit])

	_label.text = "\n".join(lines)



func _build_balance_panel() -> void:
	_balance_panel = PanelContainer.new()
	_balance_panel.position = Vector2(620, 90)
	_balance_panel.custom_minimum_size = Vector2(560, 900)
	_balance_panel.size = Vector2(560, 900)
	_balance_panel.visible = false
	add_child(_balance_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_balance_panel.add_child(outer)
	var heading := Label.new()
	heading.text = "BALANCE LAB  ·  F4"
	heading.add_theme_font_size_override("font_size", 22)
	outer.add_child(heading)
	var note := Label.new()
	note.text = "Live session values. Day length applies next day; contract targets apply next contract."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	outer.add_child(note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 5)
	scroll.add_child(controls)

	for setting: Dictionary in Balance.debug_controls():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		controls.add_child(row)
		var caption := Label.new()
		caption.text = str(setting["label"])
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_theme_font_size_override("font_size", 14)
		row.add_child(caption)
		var spin := SpinBox.new()
		spin.min_value = float(setting["min"])
		spin.max_value = float(setting["max"])
		spin.step = float(setting["step"])
		spin.value = float(setting["value"])
		spin.custom_minimum_size.x = 130
		spin.size_flags_horizontal = Control.SIZE_SHRINK_END
		spin.value_changed.connect(_on_balance_value_changed.bind(str(setting["id"])))
		row.add_child(spin)


func _on_balance_value_changed(value: float, setting_id: String) -> void:
	Balance.set_debug_value(setting_id, value)
