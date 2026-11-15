extends CanvasLayer
class_name DebugOverlay
## F3 toggles a live readout of every furniture item and player, for tuning
## carrying and damage: grip, damage so far, and the last impact against the
## item's damage limit. If "last hit" never changes when you bump things, the
## physics engine is not reporting contact impulses and damage will not work.

var _label: Label


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(16, 90)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F3:
		_label.visible = not _label.visible


func _process(_delta: float) -> void:
	if not _label.visible:
		return
	var lines: PackedStringArray = ["F3 debug", ""]

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
