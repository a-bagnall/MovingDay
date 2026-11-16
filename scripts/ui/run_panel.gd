extends CanvasLayer
class_name RunPanel
## Details card for a saved run, opened from a run-slot pad in the main menu: the run's
## stats, then Continue, Delete or Back. Deleting asks for confirmation first (the
## safer button, "Keep it", has the focus) and frees the slot.
##
## Driven by Godot's normal UI focus (arrow keys or d-pad to move, Enter or gamepad A
## to press, mouse works too), so any mix of keyboards and gamepads can use it. While it
## is open `InputSetup.ui_captured` keeps keyboard players still. Esc goes back.

signal continue_requested(slot: int)
signal deleted(slot: int)

var _slot := 0
var _content: VBoxContainer


func _ready() -> void:
	layer = 20
	_content = UIKit.modal(self, 1300)
	visible = false


func _exit_tree() -> void:
	InputSetup.ui_captured = false   # never leave the keyboard frozen behind a closed scene


## True while the card is showing.
func is_open() -> bool:
	return visible


## Shows the saved run in `slot`.
func open(slot: int) -> void:
	_slot = slot
	visible = true
	InputSetup.ui_captured = true
	_show_details()


func close() -> void:
	visible = false
	InputSetup.ui_captured = false
	get_viewport().gui_release_focus()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _show_details() -> void:
	_clear()
	var state := SaveManager.peek_run(_slot)
	assert(state != null, "RunPanel opened for empty slot %d" % _slot)

	_content.add_child(UIKit.label("SLOT %d" % _slot, UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	_add_row(grid, "Day", str(state.day))
	_add_row(grid, "Wallet", UIKit.money(state.wallet))
	_add_row(grid, "Contracts completed", str(state.contracts_completed))
	_add_row(grid, "Total earned", UIKit.money(state.total_earned))
	_add_row(grid, "Damage costs", UIKit.money(state.total_damage))
	_add_row(grid, "Running costs", UIKit.money(state.total_overhead))
	_add_row(grid, "Best day", UIKit.money(state.best_day))
	if not state.perks.is_empty():
		_add_row(grid, "Perks", ", ".join(state.perks))
	_add_row(grid, "Modifiers", RunModifiers.names(state.modifiers) if not state.modifiers.is_empty() else "None yet")
	var saved := SaveManager.slot_saved_at(_slot)
	if saved > 0:
		_add_row(grid, "Last saved", Time.get_datetime_string_from_unix_time(saved, true).substr(0, 16))

	var continue_button := _button("Continue", func() -> void: continue_requested.emit(_slot))
	_content.add_child(continue_button)
	_content.add_child(_button("Delete run", _show_confirm))
	_content.add_child(_button("Back", close))
	continue_button.grab_focus.call_deferred()


func _show_confirm() -> void:
	_clear()
	var state := SaveManager.peek_run(_slot)
	assert(state != null, "RunPanel confirm for empty slot %d" % _slot)
	_content.add_child(UIKit.label("Delete slot %d?" % _slot, UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	var warning := UIKit.label("Day %d, %s in the wallet. This cannot be undone." % [state.day, UIKit.money(state.wallet)],
		UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(warning)

	var keep := _button("Keep it", _show_details)
	_content.add_child(keep)
	_content.add_child(_button("Delete", _delete))
	keep.grab_focus.call_deferred()


func _delete() -> void:
	SaveManager.delete_run(_slot)
	var slot := _slot
	close()
	deleted.emit(slot)


func _clear() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func _add_row(grid: GridContainer, left: String, right: String) -> void:
	var l := UIKit.label(left, UIKit.FONT_BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l)
	grid.add_child(UIKit.label(right, UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_RIGHT))


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button
