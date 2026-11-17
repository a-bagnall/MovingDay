extends Control
## Crisp, scalable device illustrations for the controls guide.
## Drawn in code rather than stretched sprite-sheet artwork, so every window size
## gets clean edges and the highlighted keys are always legible.

var device_kind := "keyboard"
var keyboard_layout := "wasd"


func _ready() -> void:
	custom_minimum_size = Vector2(320, 210)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(size.x / 400.0, size.y / 220.0))
	if device_kind == "controller":
		_draw_controller()
	else:
		_draw_keyboard()


func _draw_keyboard() -> void:
	var ink := Color("5e2f25")
	var key := Color("fffbe8")
	var active := Color("ffe58a")
	draw_rect(Rect2(35, 42, 330, 142), ink, true, 18)
	draw_rect(Rect2(43, 50, 314, 126), Color("9a5444"), true, 12)
	var labels := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
		"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
		"A", "S", "D", "F", "G", "H", "J", "K", "L", "↵",
		"⇧", "Z", "X", "C", "V", "B", "N", "M", "←", "→"]
	for i in range(labels.size()):
		var row := i / 10
		var col := i % 10
		var rect := Rect2(51 + col * 30, 59 + row * 27, 25, 21)
		var letter := labels[i]
		var is_active := false
		if keyboard_layout == "wasd":
			is_active = letter in ["W", "A", "S", "D"]
		else:
			is_active = letter in ["↑", "↓", "←", "→"]
		draw_rect(rect, active if is_active else key, true, 4)
	# Make the arrow layout unmistakable while retaining a tidy keyboard silhouette.
	if keyboard_layout == "arrows":
		draw_rect(Rect2(282, 143, 25, 21), active, true, 4)
		draw_string(ThemeDB.fallback_font, Vector2(300, 161), "↑", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, ink)
		draw_string(ThemeDB.fallback_font, Vector2(330, 161), "↓", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, ink)
	else:
		draw_rect(Rect2(81, 86, 25, 21), active, true, 4)
		draw_rect(Rect2(51, 113, 25, 21), active, true, 4)
		draw_rect(Rect2(81, 113, 25, 21), active, true, 4)
		draw_rect(Rect2(111, 113, 25, 21), active, true, 4)
	for i in range(labels.size()):
		var row := i / 10
		var col := i % 10
		var letter := labels[i]
		if keyboard_layout == "arrows" and letter in ["←", "→"]:
			continue
		var rect := Rect2(51 + col * 30, 59 + row * 27, 25, 21)
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 12, rect.position.y + 16),
			letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, ink)


func _draw_controller() -> void:
	var ink := Color("5e2f25")
	var shell := Color("fffbe8")
	var gold := Color("ffe58a")
	var body := PackedVector2Array([
		Vector2(80, 70), Vector2(125, 48), Vector2(275, 48), Vector2(320, 70),
		Vector2(355, 160), Vector2(330, 180), Vector2(275, 135), Vector2(125, 135),
		Vector2(70, 180), Vector2(45, 160)
	])
	draw_colored_polygon(body, shell)
	draw_polyline(body + PackedVector2Array([body[0]]), ink, 9.0, true)
	# D-pad
	draw_rect(Rect2(105, 82, 22, 66), ink, true, 5)
	draw_rect(Rect2(83, 104, 66, 22), ink, true, 5)
	# Face buttons
	draw_circle(Vector2(280, 88), 14, gold)
	draw_circle(Vector2(310, 112), 14, gold)
	draw_circle(Vector2(265, 126), 14, gold)
	draw_circle(Vector2(290, 145), 14, gold)
	# Sticks and shoulder details
	draw_circle(Vector2(180, 112), 22, Color("9a5444"))
	draw_circle(Vector2(180, 112), 11, ink)
	draw_circle(Vector2(225, 112), 22, Color("9a5444"))
	draw_circle(Vector2(225, 112), 11, ink)
	draw_line(Vector2(125, 58), Vector2(275, 58), ink, 8.0, true)
