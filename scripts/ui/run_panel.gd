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
var _confirming := false   # on the "Delete?" page, so back returns to the details


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
	if visible and event.is_action_pressed("ui_cancel"):   # Esc or gamepad B
		if _confirming:
			_show_details()   # back out of "Delete?" without losing the card
		else:
			close()
		get_viewport().set_input_as_handled()


func _show_details() -> void:
	_confirming = false
	_clear()
	var state := SaveManager.peek_run(_slot)
	assert(state != null, "RunPanel opened for empty slot %d" % _slot)

	_content.add_child(UIKit.label("SLOT %d" % _slot, UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := UIKit.stat_grid()
	_content.add_child(grid)
	UIKit.add_stat(grid, "Day", str(state.day), UIKit.GOLD)
	UIKit.add_stat(grid, "Wallet", UIKit.money(state.wallet), UIKit.GOLD)
	UIKit.add_stat(grid, "Contracts completed", str(state.contracts_completed))
	UIKit.add_stat(grid, "Total earned", UIKit.money(state.total_earned))
	UIKit.add_stat(grid, "Damage costs", UIKit.money(state.total_damage),
		UIKit.PINK if state.total_damage > 0.5 else UIKit.CREAM)
	UIKit.add_stat(grid, "Running costs", UIKit.money(state.total_overhead))
	UIKit.add_stat(grid, "Best day", UIKit.money(state.best_day))
	if not state.perks.is_empty():
		UIKit.add_stat(grid, "Perks", ", ".join(state.perks))
	UIKit.add_stat(grid, "Modifiers", RunModifiers.names(state.modifiers) if not state.modifiers.is_empty() else "None yet")
	var saved := SaveManager.slot_saved_at(_slot)
	if saved > 0:
		UIKit.add_stat(grid, "Last saved", Time.get_datetime_string_from_unix_time(saved, true).substr(0, 16))

	# Continue is the primary action and starts focused; Delete is kept apart from it.
	var continue_button := UIKit.button("Continue", func() -> void: continue_requested.emit(_slot), true)
	_content.add_child(continue_button)
	_content.add_child(UIKit.button("Delete run", _show_confirm))
	_content.add_child(UIKit.button("Back", close))
	_content.add_child(UIKit.label("Esc to go back", UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel"))
	continue_button.grab_focus.call_deferred()


func _show_confirm() -> void:
	_confirming = true
	_clear()
	var state := SaveManager.peek_run(_slot)
	assert(state != null, "RunPanel confirm for empty slot %d" % _slot)
	_content.add_child(UIKit.label("Delete slot %d?" % _slot, UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	var warning := UIKit.label("Day %d, %s in the wallet. This cannot be undone." % [state.day, UIKit.money(state.wallet)],
		UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_color_override("font_color", UIKit.PINK)
	_content.add_child(warning)

	# The safe choice is first and focused, so a stray press never deletes a run.
	var keep := UIKit.button("Keep it", _show_details, true)
	_content.add_child(keep)
	_content.add_child(UIKit.button("Delete", _delete))
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
