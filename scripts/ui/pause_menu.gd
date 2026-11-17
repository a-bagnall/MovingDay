extends CanvasLayer
## Autoload "PauseMenu". Esc or gamepad Start opens it on any screen: Resume, Controls,
## Settings, Back to main menu, Quit game. Offline it pauses the game; online the host
## keeps simulating for everyone, so it only covers this player's screen.
##
## Driven by Godot's UI focus like the other cards (d-pad or arrows, A or Enter, mouse),
## so keyboards and gamepads both work. Esc or gamepad B goes back a page, then closes. Leaving a game
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
	var toggle := (key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE) \
		or (pad != null and pad.pressed and pad.button_index == JOY_BUTTON_START)
	# Once open, B (ui_cancel) goes back like Esc. Closed, B must not open the menu: in play
	# it is heave-ho.
	var back := _is_open and event.is_action_pressed("ui_cancel")
	if not toggle and not back:
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
	# Remember a manually resized window as well as sizes chosen in Settings.
	if not GameSettings.fullscreen:
		GameSettings.windowed_resolution = DisplayServer.window_get_size()
		GameSettings.save()
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
	# Keep the guide inside the current window's safe area instead of forcing a
	# fixed-width panel that can clip when the player uses a smaller window.
	var available_width := get_viewport().get_visible_rect().size.x / UIKit.UI_SCALE - 2.0 * UIKit.SAFE_X
	var guide_width := minf(CONTROLS_WIDTH, maxf(1200.0, available_width))
	_reset(guide_width)
	_content.add_child(UIKit.label("CONTROLS", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	var intro := UIKit.label("A quick guide to every input device", UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel")
	_content.add_child(intro)

	# Show the actual device artwork added to the project, with a generic controller
	# fallback when no gamepad is connected.
	var devices := HBoxContainer.new()
	devices.add_theme_constant_override("separation", UIKit.SPACE_M)
	devices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(devices)
	var device_width := (guide_width - 2.0 * UIKit.SPACE_M) / 3.0
	devices.add_child(_device_card("KEYBOARD · WASD", InputSetup.KB_WASD, "Move with W A S D", device_width))
	devices.add_child(_device_card("KEYBOARD · ARROWS", InputSetup.KB_ARROWS, "Move with the arrow keys", device_width))
	var pads := Input.get_connected_joypads()
	var pad_source: int = pads[0] if not pads.is_empty() else -99
	var pad_name := Input.get_joy_name(pad_source) if pad_source >= 0 else "Any compatible controller"
	devices.add_child(_device_card("CONTROLLER", pad_source, pad_name, device_width))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", UIKit.SPACE_M)
	grid.add_theme_constant_override("v_separation", UIKit.SPACE_S)
	_content.add_child(grid)
	for row: Dictionary in CONTROL_ROWS:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 250)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var body := HBoxContainer.new()
		body.add_theme_constant_override("separation", UIKit.SPACE_M)
		card.add_child(body)

		var detail := VBoxContainer.new()
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_child(UIKit.label(row["name"], UIKit.FONT_BIG))
		var what := UIKit.label(row["what"], UIKit.FONT_SMALL)
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.add_theme_color_override("font_color", UIKit.MUTED)
		detail.add_child(what)
		body.add_child(detail)

		var bindings := VBoxContainer.new()
		bindings.add_theme_constant_override("separation", 6)
		bindings.add_child(_binding_row("WASD", InputSetup.KB_WASD, str(row["action"])))
		bindings.add_child(_binding_row("ARROWS", InputSetup.KB_ARROWS, str(row["action"])))
		bindings.add_child(_binding_row("PAD", pad_source, str(row["action"])))
		body.add_child(bindings)
		grid.add_child(card)

	_content.add_child(UIKit.label("A / Enter confirms  ·  B / Esc goes back  ·  Start / Esc opens this menu",
		UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel"))
	var back := UIKit.button("Back", _show_main, true)
	_content.add_child(back)
	back.grab_focus.call_deferred()


func _binding_row(device: String, source: int, action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var caption := UIKit.label(device, UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_LEFT, &"MutedLabel")
	caption.custom_minimum_size.x = 210
	row.add_child(caption)
	row.add_child(UIKit.input_glyph(source, action))
	return row


func _device_card(title: String, source: int, description: String, card_width: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_width, 360)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIKit.SPACE_S)
	card.add_child(column)
	column.add_child(UIKit.label(title, UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))
	var illustration_width := minf(card_width - 80.0, 620.0)
	column.add_child(UIKit.device_image(source, Vector2(illustration_width, 210)))
	var caption := UIKit.label(description, UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel")
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(caption)
	return card


func _show_settings() -> void:
	_page = &"settings"
	_reset(CARD_WIDTH)
	if not GameSettings.fullscreen:
		GameSettings.windowed_resolution = DisplayServer.window_get_size()
	_content.add_child(UIKit.label("SETTINGS", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))

	var volume_row := _row("Master volume")
	var volume_value := UIKit.label("%d%%" % roundi(GameSettings.master_volume * 100.0), UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_RIGHT)
	volume_value.custom_minimum_size.x = 180
	var volume_slider := HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = GameSettings.master_volume
	volume_slider.custom_minimum_size = Vector2(560, 64)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(func(value: float) -> void:
		GameSettings.master_volume = value
		GameSettings.apply()
		GameSettings.save()
		volume_value.text = "%d%%" % roundi(value * 100.0))
	volume_row.add_child(volume_slider)
	volume_row.add_child(volume_value)

	var mode_row := _row("Display mode")
	var mode_picker := OptionButton.new()
	mode_picker.add_item("Windowed", 0)
	mode_picker.add_item("Fullscreen", 1)
	mode_picker.select(1 if GameSettings.fullscreen else 0)
	mode_picker.custom_minimum_size.x = 520
	mode_row.add_child(mode_picker)

	var resolution_row := _row("Window size")
	var resolution_picker := OptionButton.new()
	for resolution: Vector2i in GameSettings.RESOLUTIONS:
		resolution_picker.add_item("%d × %d" % [resolution.x, resolution.y])
	var current_resolution := GameSettings.windowed_resolution
	var selected_resolution := 1
	for i in range(GameSettings.RESOLUTIONS.size()):
		if GameSettings.RESOLUTIONS[i] == current_resolution:
			selected_resolution = i
	resolution_picker.select(selected_resolution)
	resolution_picker.custom_minimum_size.x = 520
	resolution_picker.disabled = GameSettings.fullscreen
	resolution_picker.item_selected.connect(func(index: int) -> void:
		_set_window_resolution(index))
	resolution_row.add_child(resolution_picker)
	mode_picker.item_selected.connect(func(index: int) -> void:
		_set_fullscreen(index == 1)
		resolution_picker.disabled = index == 1)

	_add_toggle("VSync", GameSettings.vsync_enabled, _set_vsync)
	_add_toggle("Reduce motion", GameSettings.reduce_motion, _set_reduce_motion)

	var back := UIKit.button("Back", _show_main, true)
	_content.add_child(back)
	_content.add_child(UIKit.label("Windowed mode can also be resized by dragging its edges", UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel"))
	back.grab_focus.call_deferred()


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


func _set_window_resolution(index: int) -> void:
	if index < 0 or index >= GameSettings.RESOLUTIONS.size():
		return
	GameSettings.windowed_resolution = GameSettings.RESOLUTIONS[index]
	GameSettings.apply()
	GameSettings.save()


func _set_vsync(value: bool) -> void:
	GameSettings.vsync_enabled = value
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
