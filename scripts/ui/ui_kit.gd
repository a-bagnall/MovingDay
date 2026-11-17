extends RefCounted
class_name UIKit
## Shared UI theme and small helpers, built from the Cozy UI pack in assets/ui.
##
## The pack's art is large (buttons are ~160px tall), so every screen is authored
## at 1/UI_SCALE size and its CanvasLayer is scaled down by UI_SCALE. Use
## `UIKit.setup(layer)` to get a root Control that fills the screen in those units.
##
## Panel variations (set `theme_type_variation`):
##   PanelContainer  default terracotta tile (HUD chips, result rows)
##   BannerPanel     wide wooden banner (titles)
##   NotePanel       cream note with punched holes (hints; pair with DarkLabel)
##   ButtonPanel     wooden button (key prompts)

const PACK := "res://assets/ui/DEMO_Cozy_UI_Pack_doboui/"
const INPUT_ART := "res://assets/ui/Controllers and Keyboard/"
const UI_SCALE := 0.4

## Fonts. The main font is Peaberry (a pixel font, crispest at 16px multiples); the
## typewriter face is for things that are physically paper (letters, receipts).
const MAIN_FONT_PATH := "res://assets/fonts/Peaberry-Font-v2.0/Peaberry-Font-v2.0/Peaberry Font Family/Peaberry Base/PeaberryBase.ttf"
const PAPER_FONT_PATH := "res://assets/fonts/XTypewriter_Font_0_96/TrueType (.ttf)/XTypewriter-Regular.ttf"

## What players actually press. Prompts say this, never the word "interact".
const INTERACT_KEYS := "E, Enter or gamepad A"
const LIFT_KEYS := "Q, Right Shift or the left trigger"
const ACTION_KEYS := "R, Right Ctrl or gamepad X"
const HEAVE_KEYS := "Space, . or gamepad B"

const CREAM := Color("fffbe8")
const BROWN := Color("9a5444")
const BROWN_DARK := Color("5e2f25")
const NOTE_TEXT := Color("7a4034")
const GOLD := Color("ffe58a")
const PINK := Color("ffb3a3")      # warnings, damage
const SUCCESS := Color("c4eda6")   # ready, delivered, good news
const MUTED := Color(CREAM, 0.72)  # secondary text: labels beside a value, hints

## Spacing scale, in UI units. Use these instead of ad hoc numbers so screens share one rhythm.
const SPACE_S := 14
const SPACE_M := 22
const SPACE_L := 32

## Motion. Short and ease-out, so screens settle instead of popping.
const FADE_TIME := 0.25

## Screen edges kept clear of UI (about 4% of the screen, authored units) so nothing
## is clipped by a TV's overscan or sits hard against the window edge.
const SAFE_X := 120
const SAFE_Y := 72

const FONT_SMALL := 40
const FONT_BODY := 52
const FONT_BIG := 76
const FONT_TITLE := 96

static var _theme: Theme
static var _main_font: Font
static var _paper_font: Font


## Scales the layer down and adds a screen-filling, themed root to author into.
static func setup(layer: CanvasLayer) -> Control:
	layer.scale = Vector2.ONE * UI_SCALE
	var root := UIRoot.new()
	root.name = "UIRoot"
	layer.add_child(root)
	fade_in(root)
	return root


## A centred card of `width` over a dimmed screen: the shape every pop-up uses. Returns
## the card's content column to add to. `dim` false leaves the room undimmed and
## clickable-through (the online panel).
static func modal(layer: CanvasLayer, width: float, dim := true) -> VBoxContainer:
	var root := setup(layer)
	if dim:
		var shade := ColorRect.new()
		shade.color = Color(0.0, 0.0, 0.0, 0.45)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", SPACE_M)
	panel.add_child(content)
	return content


static func label(text: String, size: int = FONT_BODY,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = align
	if variation != &"":
		l.theme_type_variation = variation
	return l


## A small wooden tag (a modifier name, a status). `color` tints the text.
static func chip(text: String, color: Color = PINK) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ButtonPanel"
	var l := label(text, FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_color", color)
	panel.add_child(l)
	return panel


## Fades a screen in so it settles rather than pops. Does nothing outside the tree
## (a tween cannot run there), so it is always safe to call.
static func fade_in(node: CanvasItem, duration: float = FADE_TIME) -> void:
	if not node.is_inside_tree() or GameSettings.reduce_motion:
		return
	node.modulate.a = 0.0
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## A full-screen container inset by the safe area. Put a screen's layout inside it.
static func safe_area(root: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SAFE_X)
	margin.add_theme_constant_override("margin_right", SAFE_X)
	margin.add_theme_constant_override("margin_top", SAFE_Y)
	margin.add_theme_constant_override("margin_bottom", SAFE_Y)
	root.add_child(margin)
	return margin


## The wide wooden title banner every screen opens with.
static func banner(text: String, width: float = 1300.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BannerPanel"
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_child(label(text, FONT_TITLE, HORIZONTAL_ALIGNMENT_CENTER))
	return panel


## A button that behaves the same for mouse, keyboard and gamepad: hovering moves focus to
## it, so there is only ever one highlighted button. `primary` marks the main action (gold
## text), so the default choice reads at a glance. `min_width` keeps a column of buttons
## the same width.
static func button(text: String, on_pressed: Callable, primary: bool = false,
		min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	if min_width > 0.0:
		b.custom_minimum_size.x = min_width
	b.pressed.connect(on_pressed)
	b.mouse_entered.connect(func() -> void:
		if b.is_inside_tree() and not b.disabled:
			b.grab_focus())
	return b


## A two-column grid for label / value rows (receipts, run stats).
static func stat_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 12)
	return grid


## Adds one row: a muted label on the left, the value on the right. `value_color` picks out
## good (SUCCESS, GOLD) and bad (PINK) numbers; the text always says what it is as well, so
## colour is never the only signal.
static func add_stat(grid: GridContainer, left: String, right: String,
		value_color: Color = CREAM, font: Font = null) -> void:
	var l := label(left, FONT_BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", MUTED)
	var r := label(right, FONT_BODY, HORIZONTAL_ALIGNMENT_RIGHT)
	r.add_theme_color_override("font_color", value_color)
	if font != null:
		l.add_theme_font_override("font", font)
		r.add_theme_font_override("font", font)
	grid.add_child(l)
	grid.add_child(r)


## The "Press X to ..." strip at the bottom of a screen. Returns its label so the text can
## change (a typewriter finishing, a lockout ending).
static func key_prompt(parent: Control, text: String, show_devices := true) -> Label:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ButtonPanel"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_S)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if show_devices:
		row.add_child(device_image(InputSetup.KB_WASD, Vector2(150, 72)))
		var pads := Input.get_connected_joypads()
		var pad_source: int = pads[0] if not pads.is_empty() else -99
		row.add_child(device_image(pad_source, Vector2(150, 72)))
	var l := label(text, FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	row.add_child(l)
	panel.add_child(row)
	parent.add_child(panel)
	return l


## A thin progress bar in the UI palette. `fill` colours the bar.
static func progress_bar(fill: Color = GOLD) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 22)
	bar.min_value = 0.0
	bar.max_value = 1.0
	set_bar_color(bar, fill)
	return bar


static func set_bar_color(bar: ProgressBar, fill: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(10)
	bar.add_theme_stylebox_override("fill", sb)


static func main_font() -> Font:
	if _main_font == null:
		_main_font = load(MAIN_FONT_PATH)
	return _main_font


static func paper_font() -> Font:
	if _paper_font == null:
		_paper_font = load(PAPER_FONT_PATH)
	return _paper_font


## Gives a 3D label the same font and outline colour as the 2D UI.
static func style_label3d(label: Label3D) -> void:
	label.font = main_font()
	label.outline_modulate = BROWN_DARK


## Controller or keyboard artwork for the currently assigned input source.
## Unknown controllers use the minimal universal illustration.
static func device_texture(source: int) -> Texture2D:
	var path := "controller_minimal.png"
	if source == InputSetup.KB_WASD or source == InputSetup.KB_ARROWS:
		path = "kb_dark_all.png"
	elif source >= 0:
		var device_name := Input.get_joy_name(source).to_lower()
		if device_name.contains("playstation") or device_name.contains("dualshock") \
				or device_name.contains("dualsense") or device_name.contains("sony"):
			path = "controller_ps.png"
		elif device_name.contains("switch") or device_name.contains("nintendo"):
			path = "controller_switch.png"
		elif device_name.contains("xbox") or device_name.contains("x-input"):
			path = "controller_xbox.png"
	return load(INPUT_ART + path) as Texture2D


## A consistently sized, aspect-preserving device illustration.
static func device_image(source: int, image_size: Vector2 = Vector2(560, 240)) -> TextureRect:
	var image := TextureRect.new()
	image.texture = device_texture(source)
	image.custom_minimum_size = image_size
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


static func money(amount: float) -> String:
	var whole := roundi(amount)
	return ("-$%d" % -whole) if whole < 0 else ("$%d" % whole)


static func format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = main_font()
	t.default_font_size = FONT_BODY

	# Text: cream with a dark brown outline reads on every panel colour.
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", BROWN_DARK)
	t.set_constant("outline_size", "Label", 16)
	t.set_font_size("font_size", "Label", FONT_BODY)
	t.set_constant("line_spacing", "Label", 6)

	t.add_type("DarkLabel")
	t.set_type_variation("DarkLabel", "Label")
	t.set_color("font_color", "DarkLabel", NOTE_TEXT)
	t.set_constant("outline_size", "DarkLabel", 0)

	# Secondary text: key hints, captions. Softer than body text but still outlined to read.
	t.add_type("MutedLabel")
	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", MUTED)
	t.set_constant("outline_size", "MutedLabel", 12)

	# Panels
	t.set_stylebox("panel", "PanelContainer",
		_box("Containers/Containers/Container1.png", Vector4(60, 55, 60, 70), Vector4(60, 36, 60, 56)))
	_variation(t, "BannerPanel", "PanelContainer",
		_box("Containers/Containers/WoodenContainer1.png", Vector4(80, 60, 80, 70), Vector4(90, 36, 90, 56)))
	_variation(t, "NotePanel", "PanelContainer",
		_box("Containers/Containers/NoteContainerSimple.png", Vector4(110, 40, 50, 40), Vector4(140, 28, 60, 28)))
	_variation(t, "ButtonPanel", "PanelContainer",
		_box("Buttons/Square/SquareButton2_wood.png", Vector4(70, 60, 70, 75), Vector4(80, 26, 80, 46)))

	# Dividers (the briefing's letter header): a soft cream rule instead of the default grey.
	var rule := StyleBoxLine.new()
	rule.color = Color(CREAM, 0.45)
	rule.thickness = 4
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_constant("separation", "HSeparator", 28)

	# Buttons.
	var button_margins := Vector4(70, 60, 70, 75)
	var button_pad := Vector4(80, 26, 80, 46)
	t.set_stylebox("normal", "Button", _box("Buttons/Square/SquareButton2_wood.png", button_margins, button_pad))
	t.set_stylebox("hover", "Button", _box("Buttons/Square/SquareButton2_white.png", button_margins, button_pad))
	t.set_stylebox("pressed", "Button", _box("Buttons/Square/SquareButton2_red.png", button_margins, button_pad))
	# Keyboard and gamepad players move with focus, so the focused button must be obvious:
	# it looks like the hovered one (white), and stays that way while the mouse is elsewhere.
	t.set_stylebox("focus", "Button", _box("Buttons/Square/SquareButton2_white.png", button_margins, button_pad))
	t.set_stylebox("hover_pressed", "Button", _box("Buttons/Square/SquareButton2_red.png", button_margins, button_pad))
	t.set_stylebox("disabled", "Button", _box("Buttons/Square/SquareButton2_wood.png", button_margins, button_pad))
	t.set_color("font_focus_color", "Button", BROWN_DARK)
	t.set_color("font_disabled_color", "Button", Color(CREAM, 0.5))
	t.set_color("font_hover_pressed_color", "Button", CREAM)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", BROWN_DARK)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_outline_color", "Button", BROWN_DARK)
	t.set_constant("outline_size", "Button", 12)
	t.set_font_size("font_size", "Button", FONT_BODY)
	t.set_constant("line_spacing", "Button", 6)

	# The main action on a screen: same button, gold text.
	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	t.set_color("font_color", "PrimaryButton", GOLD)
	t.set_color("font_hover_color", "PrimaryButton", BROWN_DARK)
	t.set_color("font_focus_color", "PrimaryButton", BROWN_DARK)

	# Progress bars (delivery progress): a dark trough with a rounded fill.
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(BROWN_DARK, 0.85)
	trough.border_color = BROWN
	trough.set_border_width_all(4)
	trough.set_corner_radius_all(10)
	t.set_stylebox("background", "ProgressBar", trough)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(10)
	t.set_stylebox("fill", "ProgressBar", fill)

	# Text fields (the host address box): a cream note with a brown edge.
	var field := StyleBoxFlat.new()
	field.bg_color = CREAM
	field.border_color = BROWN
	field.set_border_width_all(6)
	field.set_corner_radius_all(14)
	field.content_margin_left = 28
	field.content_margin_right = 28
	field.content_margin_top = 16
	field.content_margin_bottom = 16
	t.set_stylebox("normal", "LineEdit", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = BROWN_DARK
	field_focus.set_border_width_all(10)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", BROWN_DARK)
	t.set_color("font_placeholder_color", "LineEdit", Color(NOTE_TEXT, 0.6))
	t.set_color("caret_color", "LineEdit", BROWN_DARK)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.8))
	t.set_font_size("font_size", "LineEdit", FONT_BODY)

	_theme = t
	return t


static func _variation(t: Theme, variation: StringName, base: StringName, style: StyleBox) -> void:
	t.add_type(variation)
	t.set_type_variation(variation, base)
	t.set_stylebox("panel", variation, style)


## margins = nine-patch corners in texture pixels (left, top, right, bottom);
## pad = space between the panel edge and its content, same order.
static func _box(file: String, margins: Vector4, pad: Vector4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(PACK + file)
	sb.texture_margin_left = margins.x
	sb.texture_margin_top = margins.y
	sb.texture_margin_right = margins.z
	sb.texture_margin_bottom = margins.w
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	return sb
