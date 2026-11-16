extends CanvasLayer
class_name ModifierPicker
## "Choose one" card shown in the hub every few days: pick one of three run modifiers.
## Each is a drawback that stays for the rest of the run, so the title says so.
##
## Driven by Godot's normal UI focus (arrow keys or d-pad to move, Enter or gamepad A to
## press, mouse works too). There is no Esc: the choice has to be made. While it is open
## `InputSetup.ui_captured` keeps keyboard players still.

signal chosen(id: String)


func _ready() -> void:
	layer = 20
	visible = false


func _exit_tree() -> void:
	InputSetup.ui_captured = false


## Shows `ids` (RunModifiers ids) as the choices.
func open(ids: Array[String]) -> void:
	for child in get_children():
		child.queue_free()
	var root := UIKit.setup(self)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1500, 0)
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	panel.add_child(content)
	content.add_child(UIKit.label("CHOOSE ONE", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	var sub := UIKit.label("It lasts for the rest of the run, and it makes things harder.",
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(sub)

	var first: Button = null
	for id in ids:
		var button := Button.new()
		button.text = "%s\n%s" % [RunModifiers.modifier_name(id), RunModifiers.ENTRIES[id]["description"]]
		button.pressed.connect(_on_pressed.bind(id))
		content.add_child(button)
		if first == null:
			first = button

	visible = true
	InputSetup.ui_captured = true
	if first:
		first.grab_focus.call_deferred()


func _on_pressed(id: String) -> void:
	visible = false
	InputSetup.ui_captured = false
	get_viewport().gui_release_focus()
	chosen.emit(id)
