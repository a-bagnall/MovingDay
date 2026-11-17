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
	draw_rect(Rect2(28, 34, 344, 152), ink, true, 18)
	draw_rect(Rect2(36, 42, 328, 136), Color("9a5444"), true, 12)

	# Four compact rows of keys. Highlight only the active movement cluster.
	var rows := [
		["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
		["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
		["A", "S", "D", "F", "G", "H", "J", "K", "L"],
		["Z", "X", "C", "V", "B", "N", "M"]
	]
	for row_index in range(rows.size()):
		var row: Array = rows[row_index]
		var row_width := row.size() * 29.0 + (row.size() - 1) * 3.0
		var start_x := (400.0 - row_width) * 0.5
		for col_index in range(row.size()):
			var letter: String = row[col_index]
			var is_active := keyboard_layout == "wasd" and letter in ["W", "A", "S", "D"]
			var rect := Rect2(start_x + col_index * 32.0, 51 + row_index * 28.0, 29, 23)
			draw_rect(rect, active if is_active else key, true, 4)
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(14, 17),
				letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, ink)

	# Space bar and a separate, familiar arrow-key cluster.
	draw_rect(Rect2(100, 165, 145, 10), key, true, 4)
	var arrow_positions := {
		"up": Rect2(306, 145, 25, 20),
		"left": Rect2(278, 166, 25, 20),
		"down": Rect2(306, 166, 25, 20),
		"right": Rect2(334, 166, 25, 20),
	}
	for direction in arrow_positions:
		var rect: Rect2 = arrow_positions[direction]
		var is_active := keyboard_layout == "arrows"
		draw_rect(rect, active if is_active else key, true, 4)
		var glyph := {"up": "↑", "left": "←", "down": "↓", "right": "→"}[direction]
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, 15),
			glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, ink)

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
