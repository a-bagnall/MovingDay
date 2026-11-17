extends CanvasLayer
## Autoload "PauseMenu". Esc or gamepad Start opens it on any screen: Resume, Controls,
## Settings, Back to main menu, Quit game. Offline it pauses the game; online the host
## keeps simulating for everyone, so it only covers this player's screen.
##
## Driven by Godot's UI focus like the other cards (d-pad or arrows, A or Enter, mouse),
## so keyboards and gamepads both work. Esc goes back a page, then closes. Leaving a game
## or quitting asks first, with the safe choice focused.

const CARD_WIDTH := 1300.0
const CONTROLS_WIDTH := 2500.0
const VOLUME_STEP := 0.1

## One row per button. `action` is the InputSetup action name ("move" covers the four
## directions); `pad` is the gamepad button (see InputSetup's gamepad reader).
const CONTROL_ROWS := [
	{"name": "Move", "what": "Walk around", "action": "move", "pad": "Left stick"},
	{"name": "Interact", "what": "Grab or drop, step on pads, confirm", "action": "interact", "pad": "A"},
	{"name": "Lift", "what": "Hold to raise what you carry", "action": "lift", "pad": "Left trigger"},
	{"name": "Action", "what": "Shove; hold and release to throw", "action": "action", "pad": "X"},
	{"name": "Ping", "what": "Mark a spot for your team", "action": "ping", "pad": "Y"},
	{"name": "Heave-ho", "what": "Both carriers together: speed burst", "action": "heave", "pad": "B"},
]
const KEY_NAMES := {KEY_PERIOD: ".", KEY_SLASH: "/", KEY_ENTER: "Enter", KEY_SPACE: "Space"}

var _is_open := false
var _paused_by_us := false
var _was_captured := false
var _page := &"main"
var _content: VBoxContainer


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the game is paused
	GameSettings.load_and_apply()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	var pressed := (key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE) \
		or (pad != null and pad.pressed and pad.button_index == JOY_BUTTON_START)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if not _is_open:
		_open()
	elif _page == &"main":
		_close()
	else:
		_show_main()


func _open() -> void:
	_is_open = true
	_was_captured = InputSetup.ui_captured
	InputSetup.ui_captured = true   # nobody walks around behind the card
	if not NetworkManager.is_online():
		get_tree().paused = true
		_paused_by_us = true
	_content = UIKit.modal(self, CARD_WIDTH)
	_show_main()


func _close() -> void:
	_is_open = false
	InputSetup.ui_captured = _was_captured
	if _paused_by_us:
		get_tree().paused = false
		_paused_by_us = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	get_viewport().gui_release_focus()


# --- pages ----------------------------------------------------------------

func _show_main() -> void:
	_page = &"main"
	_reset(CARD_WIDTH)
	_content.add_child(UIKit.label("PAUSED", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	var resume := UIKit.button("Resume", _close, true)
	_content.add_child(resume)
	_content.add_child(UIKit.button("Controls", _show_controls))
	_content.add_child(UIKit.button("Settings", _show_settings))
	if not _in_main_menu():
		_content.add_child(UIKit.button("Back to main menu", _confirm_leave))
	_content.add_child(UIKit.button("Quit game", _confirm_quit))
	resume.grab_focus.call_deferred()


func _show_controls() -> void:
	_page = &"controls"
	_reset(CONTROLS_WIDTH)
	_content.add_child(UIKit.label("CONTROLS", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 50)
	grid.add_theme_constant_override("v_separation", UIKit.SPACE_S)
	_content.add_child(grid)
	for heading in ["", "What it does", "Keyboard 1", "Keyboard 2", "Gamepad"]:
		var h := UIKit.label(heading, UIKit.FONT_SMALL)
		h.add_theme_color_override("font_color", UIKit.GOLD)
		grid.add_child(h)
	for row: Dictionary in CONTROL_ROWS:
		var name_label := UIKit.label(row["name"], UIKit.FONT_SMALL)
		name_label.add_theme_color_override("font_color", UIKit.GOLD)
		grid.add_child(name_label)
		var what := UIKit.label(row["what"], UIKit.FONT_SMALL)
		what.add_theme_color_override("font_color", UIKit.MUTED)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(what)
		grid.add_child(UIKit.label(key_text(InputSetup.KB_WASD, row["action"]), UIKit.FONT_SMALL))
		grid.add_child(UIKit.label(key_text(InputSetup.KB_ARROWS, row["action"]), UIKit.FONT_SMALL))
		grid.add_child(UIKit.label(row["pad"], UIKit.FONT_SMALL))
	_content.add_child(UIKit.label("Esc or Start opens this menu.", UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))

	var back := UIKit.button("Back", _show_main, true)
	_content.add_child(back)
	back.grab_focus.call_deferred()


func _show_settings() -> void:
	_page = &"settings"
	_reset(CARD_WIDTH)
	_content.add_child(UIKit.label("SETTINGS", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))

	var volume_value := UIKit.label("", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	volume_value.custom_minimum_size.x = 260
	var set_volume := func(delta: float) -> void:
		GameSettings.master_volume = clampf(snappedf(GameSettings.master_volume + delta, VOLUME_STEP), 0.0, 1.0)
		GameSettings.apply()
		GameSettings.save()
		volume_value.text = "%d%%" % roundi(GameSettings.master_volume * 100.0)
	var volume_row := _row("Volume")
	var down := UIKit.button("-", func() -> void: set_volume.call(-VOLUME_STEP), false, 120)
	volume_row.add_child(down)
	volume_row.add_child(volume_value)
	volume_row.add_child(UIKit.button("+", func() -> void: set_volume.call(VOLUME_STEP), false, 120))
	set_volume.call(0.0)   # shows the current value

	_add_toggle("Fullscreen", GameSettings.fullscreen, _set_fullscreen)
	_add_toggle("Reduce motion", GameSettings.reduce_motion, _set_reduce_motion)

	var back := UIKit.button("Back", _show_main, true)
	_content.add_child(back)
	down.grab_focus.call_deferred()


func _confirm_leave() -> void:
	_page = &"confirm"
	_reset(CARD_WIDTH)
	_content.add_child(UIKit.label("Leave this game?", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	var warning := "Progress since the day began is lost. The game saves at the start and end of each day."
	if NetworkManager.is_host():
		warning = "This ends the game for everyone."
	elif NetworkManager.is_online():
		warning = "You will leave the host's game."
	_add_warning(warning)
	var stay := UIKit.button("Stay", _show_main, true)
	_content.add_child(stay)
	_content.add_child(UIKit.button("Leave", _leave))
	stay.grab_focus.call_deferred()


func _confirm_quit() -> void:
	_page = &"confirm"
	_reset(CARD_WIDTH)
	_content.add_child(UIKit.label("Quit to desktop?", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	_add_warning("Progress since the day began is lost. The game saves at the start and end of each day.")
	var stay := UIKit.button("Stay", _show_main, true)
	_content.add_child(stay)
	_content.add_child(UIKit.button("Quit", _quit))
	stay.grab_focus.call_deferred()


func _leave() -> void:
	_close()
	NetworkManager.leave()
	GameFlow.open_main_menu()


func _quit() -> void:
	NetworkManager.leave()   # closes the session and removes the router port mapping
	get_tree().quit()


# --- helpers ----------------------------------------------------------------

## Empties the card for the next page and sets its width.
func _reset(width: float) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_content.get_parent().custom_minimum_size.x = width


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIKit.SPACE_M)
	var l := UIKit.label(title, UIKit.FONT_BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	_content.add_child(row)
	return row


func _add_warning(text: String) -> void:
	var l := UIKit.label(text, UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_color", UIKit.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)


## A row with an On/Off button. `setter` takes the new bool and applies and saves it.
func _add_toggle(title: String, value: bool, setter: Callable) -> void:
	var state: Array[bool] = [value]   # shared with the handler below
	var holder: Array[Button] = []
	var button := UIKit.button(_on_off(value), func() -> void:
		state[0] = not state[0]
		setter.call(state[0])
		holder[0].text = _on_off(state[0]), false, 340)
	holder.append(button)
	_row(title).add_child(button)


func _set_fullscreen(value: bool) -> void:
	GameSettings.fullscreen = value
	GameSettings.apply()
	GameSettings.save()


func _set_reduce_motion(value: bool) -> void:
	GameSettings.reduce_motion = value
	GameSettings.save()


func _on_off(value: bool) -> String:
	return "On" if value else "Off"


func _in_main_menu() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == GameFlow.MAIN_MENU_SCENE


## How a key reads on the controls card, from the real bindings in InputSetup.
func key_text(source: int, action: String) -> String:
	if action == "move":
		return "WASD" if source == InputSetup.KB_WASD else "Arrows"
	var key: int = InputSetup.KEYS[source][action]
	var text: String = KEY_NAMES.get(key, OS.get_keycode_string(key))
	if source == InputSetup.KB_ARROWS and InputSetup.RIGHT_SIDE_ONLY.has(key):
		text = "Right " + text
	return text
