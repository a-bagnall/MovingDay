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

const CREAM := Color("fffbe8")
const BROWN := Color("9a5444")
const BROWN_DARK := Color("5e2f25")
const NOTE_TEXT := Color("7a4034")
const GOLD := Color("ffe58a")

const FONT_SMALL := 40
const FONT_BODY := 52
const FONT_BIG := 76
const FONT_TITLE := 96

static var _theme: Theme


## Scales the layer down and adds a screen-filling, themed root to author into.
static func setup(layer: CanvasLayer) -> Control:
	layer.scale = Vector2.ONE * UI_SCALE
	var root := UIRoot.new()
	root.name = "UIRoot"
	layer.add_child(root)
	return root


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


static func money(amount: float) -> String:
	return "$%d" % roundi(amount)


static func format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
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

	# Buttons (not used by the couch-co-op screens yet, ready for menus).
	var button_margins := Vector4(70, 60, 70, 75)
	var button_pad := Vector4(80, 26, 80, 46)
	t.set_stylebox("normal", "Button", _box("Buttons/Square/SquareButton2_wood.png", button_margins, button_pad))
	t.set_stylebox("hover", "Button", _box("Buttons/Square/SquareButton2_white.png", button_margins, button_pad))
	t.set_stylebox("pressed", "Button", _box("Buttons/Square/SquareButton2_red.png", button_margins, button_pad))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", BROWN_DARK)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_outline_color", "Button", BROWN_DARK)
	t.set_constant("outline_size", "Button", 12)
	t.set_font_size("font_size", "Button", FONT_BODY)

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
