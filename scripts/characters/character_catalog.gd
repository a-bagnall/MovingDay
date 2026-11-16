class_name CharacterCatalog
## The playable characters, and which one each player has picked.
##
## Every model is scaled at runtime to `height` metres (see Player.set_character), so
## the source files' units never matter, and `height` is the only size knob. The
## collision capsule is 1.3 m tall for everyone, so characters stay close to that.
## `yaw` turns a model that faces +Z (all the current ones do) to face the player's
## forward, -Z. If one looks backwards in game, change only its `yaw`.

const ENTRIES: Array[Dictionary] = [
	{"name": "Bear", "path": "res://assets/characters/Animal Plushies/FBX/Bear.fbx", "height": 1.15, "yaw": PI},
	{"name": "Bunny", "path": "res://assets/characters/Animal Plushies/FBX/Bunny.fbx", "height": 1.3, "yaw": PI},
	{"name": "Cat", "path": "res://assets/characters/Animal Plushies/FBX/Cat.fbx", "height": 1.2, "yaw": PI},
	{"name": "Dog", "path": "res://assets/characters/Animal Plushies/FBX/Dog.fbx", "height": 1.2, "yaw": PI},
	{"name": "Robot", "path": "res://assets/characters/Animated Robot by Quaternius/FBX/Robot.fbx", "height": 1.3, "yaw": PI},
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
