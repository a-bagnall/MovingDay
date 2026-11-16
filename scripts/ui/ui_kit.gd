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
const UI_SCALE := 0.4

## Fonts. The main font is Peaberry (a pixel font, crispest at 16px multiples); the
## typewriter face is for things that are physically paper (letters, receipts).
const MAIN_FONT_PATH := "res://assets/fonts/Peaberry-Font-v2.0/Peaberry-Font-v2.0/Peaberry Font Family/Peaberry Base/PeaberryBase.ttf"
const PAPER_FONT_PATH := "res://assets/fonts/XTypewriter_Font_0_96/TrueType (.ttf)/XTypewriter-Regular.ttf"

## What players actually press. Prompts say this, never the word "interact".
const INTERACT_KEYS := "E, Enter or gamepad A"
const LIFT_KEYS := "Q, Right Shift or the left trigger"
const ACTION_KEYS := "R, Right Ctrl or gamepad X"

const CREAM := Color("fffbe8")
const BROWN := Color("9a5444")
const BROWN_DARK := Color("5e2f25")
const NOTE_TEXT := Color("7a4034")
const GOLD := Color("ffe58a")
const PINK := Color("ffb3a3")      # warnings, damage

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
	content.add_theme_constant_override("separation", 22)
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
