class_name CharacterCatalog
## The playable characters, and which one each player has picked.
##
## Every model is scaled at runtime to `height` metres (see Player.set_character), so
## the source files' units never matter, and `height` is the only size knob. Characters
## are deliberately smaller than the 1.3 m collision capsule so they look right next to the furniture.
## `yaw` turns a model that faces +Z (all the current ones do) to face the player's
## forward, -Z. If one looks backwards in game, change only its `yaw`.

## `style` shapes the procedural animation so each plushie moves differently (see
## Player._animate_character): rate (step speed), bob (hop height), roll (waddle), leg/arm
## (swing), twist (hip sway), nod (head bob), sync (both legs together, like a bunny).
const ENTRIES: Array[Dictionary] = [
	{"name": "Bear", "path": "res://assets/characters/Animal Plushies/FBX/Bear.fbx", "height": 0.72, "yaw": PI, "style": {"rate": 0.8, "bob": 0.8, "roll": 1.5, "leg": 0.8, "arm": 0.7, "twist": 1.0, "nod": 0.6}},
	{"name": "Bunny", "path": "res://assets/characters/Animal Plushies/FBX/Bunny.fbx", "height": 0.82, "yaw": PI, "style": {"rate": 0.75, "bob": 1.9, "roll": 0.3, "leg": 0.9, "arm": 0.9, "twist": 0.3, "nod": 1.5, "sync": true}},
	{"name": "Cat", "path": "res://assets/characters/Animal Plushies/FBX/Cat.fbx", "height": 0.77, "yaw": PI, "style": {"rate": 1.0, "bob": 0.45, "roll": 0.4, "leg": 1.0, "arm": 0.5, "twist": 2.2, "nod": 0.3}},
	{"name": "Dog", "path": "res://assets/characters/Animal Plushies/FBX/Dog.fbx", "height": 0.77, "yaw": PI, "style": {"rate": 1.25, "bob": 1.2, "roll": 0.8, "leg": 1.1, "arm": 1.1, "twist": 0.8, "nod": 2.2}},
	{"name": "Robot", "path": "res://assets/characters/Animated Robot by Quaternius/FBX/Robot.fbx", "height": 1.2, "yaw": PI, "style": {}},
]

## player id -> index into ENTRIES, for the players on every machine in the session.
static var choices: Dictionary = {}


static func count() -> int:
	return ENTRIES.size()


## Out-of-range or garbage (e.g. from the network) becomes a valid index.
static func clamp_index(index: Variant) -> int:
	if not (index is int):
		return 0
	return clampi(index, 0, ENTRIES.size() - 1)


## What `player_id` is playing as. Nobody has to choose: ids get different characters.
static func choice_for(player_id: int) -> int:
	if choices.has(player_id):
		return clamp_index(choices[player_id])
	return (player_id - 1) % ENTRIES.size()


static func choose(player_id: int, index: int) -> void:
	choices[player_id] = clamp_index(index)


static func character_name(index: int) -> String:
	return ENTRIES[clamp_index(index)]["name"]


# --- player colours -------------------------------------------------------------------
## Each player has a colour: a ring under their feet, and the colour of their pings.

const COLORS: Array[Color] = [
	Color("e0523f"), Color("f29a2e"), Color("f2d33c"), Color("7cc242"),
	Color("2fb5a6"), Color("4aa3e0"), Color("8a63d2"), Color("ec6fa8"),
]
const COLOR_NAMES: Array[String] = ["Tomato", "Tangerine", "Sunshine", "Lime", "Teal", "Sky", "Violet", "Bubblegum"]
## Who gets what until they choose: players 1-4 start with four clearly different colours.
const DEFAULT_COLORS: Array[int] = [5, 0, 3, 7]

## player id -> index into COLORS, like `choices`.
static var colors: Dictionary = {}


static func color_count() -> int:
	return COLORS.size()


static func clamp_color(index: Variant) -> int:
	if not (index is int):
		return 0
	return clampi(index, 0, COLORS.size() - 1)


static func color_index_for(player_id: int) -> int:
	if colors.has(player_id):
		return clamp_color(colors[player_id])
	return DEFAULT_COLORS[posmod(player_id - 1, DEFAULT_COLORS.size())]


static func choose_color(player_id: int, index: int) -> void:
	colors[player_id] = clamp_color(index)


static func color_for(player_id: int) -> Color:
	return COLORS[color_index_for(player_id)]
