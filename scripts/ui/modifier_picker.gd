extends CanvasLayer
class_name ModifierPicker
## "Pick One" card shown in the hub every few days: three run modifiers side by side.
## Each is a detriment that adds chaos for the rest of the run, and the card says so.
## Modifiers already in play are listed underneath, so the team sees what it is stacking.
##
## Driven by Godot's normal UI focus (left/right or d-pad to move, Enter or gamepad A to
## press, mouse works too). There is no Esc: the choice has to be made. While it is open
## `InputSetup.ui_captured` keeps keyboard players still.

signal chosen(id: String)

const CARD_SIZE := Vector2(820, 640)


func _ready() -> void:
	layer = 20
	visible = false


func _exit_tree() -> void:
	InputSetup.ui_captured = false


## Shows `ids` (RunModifiers ids) as the choices.
func open(ids: Array[String]) -> void:
	for child in get_children():
		child.queue_free()
	var content := UIKit.modal(self, 2700)
	content.add_theme_constant_override("separation", 28)

	content.add_child(UIKit.label("PICK ONE", UIKit.FONT_TITLE, HORIZONTAL_ALIGNMENT_CENTER))
	var sub := UIKit.label("Every pick makes the run harder, and it stays until the run ends.",
		UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UIKit.PINK)   # a warning: every pick has a cost
	content.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	content.add_child(row)

	var first: Button = null
	for id in ids:
		var button := Button.new()
		button.text = "%s\n\n%s\n\n%s" % [
			RunModifiers.tag(id), RunModifiers.modifier_name(id).to_upper(), RunModifiers.description(id)]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = CARD_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_on_pressed.bind(id))
		# Hovering moves focus, so mouse and keyboard never highlight two cards at once.
		button.mouse_entered.connect(button.grab_focus)
		row.add_child(button)
		if first == null:
			first = button

	var in_play: Array[String] = RunModifiers.active()
	if not in_play.is_empty():
		var stacked := UIKit.label("Already in play: %s" % RunModifiers.names(in_play),
			UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER)
		stacked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(stacked)
	content.add_child(UIKit.label("Left / Right to look, Enter or gamepad A to pick",
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel"))

	visible = true
	InputSetup.ui_captured = true
	if first:
		first.grab_focus.call_deferred()


func _on_pressed(id: String) -> void:
	visible = false
	InputSetup.ui_captured = false
	get_viewport().gui_release_focus()
	chosen.emit(id)
