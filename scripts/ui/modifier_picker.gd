extends CanvasLayer
class_name ModifierPicker
## "Choose one" card shown in the hub every few days: pick one of three run modifiers.
## Each is a detriment that adds chaos for the rest of the run, so the card says so.
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
	var content := UIKit.modal(self, 1500)
	content.add_child(UIKit.label("CHOOSE ONE", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	var sub := UIKit.label("Each one adds chaos for the rest of the run. Pick your poison.",
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(sub)

	var first: Button = null
	for id in ids:
		var button := Button.new()
		button.text = "%s\n%s" % [RunModifiers.modifier_name(id), RunModifiers.ENTRIES[id]["description"]]
		button.custom_minimum_size = Vector2(0, 230)
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
