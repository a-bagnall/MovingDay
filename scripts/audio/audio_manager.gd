extends Node
## Central placeholder audio setup. Swap these preloads for final assets later without
## changing the settings UI or gameplay call sites.

const MUSIC_TRACK: AudioStream = preload("res://assets/sound/music-loop-bundle-2026-q3/Week 39 - Homesteading MOVING IN.ogg")
const UI_CONFIRM: AudioStream = preload("res://assets/sound/free-game-ui-sound-pack-rate-r2/free_game_ui_sounds/ogg/ui/ui_accept.ogg")
const UI_HOVER: AudioStream = preload("res://assets/sound/free-game-ui-sound-pack-rate-r2/free_game_ui_sounds/ogg/ui/ui_blip_up.ogg")
const PICKUP: AudioStream = preload("res://assets/sound/free-game-ui-sound-pack-rate-r2/free_game_ui_sounds/ogg/ui/ui_drag_start.ogg")
const PLACE: AudioStream = preload("res://assets/sound/free-game-ui-sound-pack-rate-r2/free_game_ui_sounds/ogg/ui/ui_place.ogg")
const COLLISION: AudioStream = preload("res://assets/sound/free-game-ui-sound-pack-rate-r2/free_game_ui_sounds/ogg/game/block_bump.ogg")
const BREAK: AudioStream = preload("res://assets/sound/free-game-ui-sound-pack-rate-r2/free_game_ui_sounds/ogg/game/block_break.ogg")
const DOOR: AudioStream = preload("res://assets/sound/free-game-ui-sound-pack-rate-r2/free_game_ui_sounds/ogg/game/door_open.ogg")
const COUNTDOWN: AudioStream = preload("res://assets/sound/free-game-ui-sound-pack-rate-r2/free_game_ui_sounds/ogg/ui/ui_countdown_beep.ogg")
const COMPLETE: AudioStream = preload("res://assets/sound/free-game-ui-sound-pack-rate-r2/free_game_ui_sounds/ogg/game/stage_clear.ogg")

var _music_player: AudioStreamPlayer


func _ready() -> void:
	GameSettings.ensure_audio_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "PlaceholderMusic"
	_music_player.bus = "Music"
	_music_player.stream = MUSIC_TRACK
	add_child(_music_player)
	if _music_player.stream is AudioStreamOggVorbis:
		(_music_player.stream as AudioStreamOggVorbis).loop = true
	_music_player.play()


func play_ui_confirm() -> void:
	_play(UI_CONFIRM, "UI")


func play_ui_hover() -> void:
	_play(UI_HOVER, "UI", -8.0)


func play_pickup() -> void:
	_play(PICKUP, "SFX")


func play_place() -> void:
	_play(PLACE, "SFX")


func play_collision() -> void:
	_play(COLLISION, "SFX")


func play_break() -> void:
	_play(BREAK, "SFX")


func play_door() -> void:
	_play(DOOR, "SFX")


func play_countdown() -> void:
	_play(COUNTDOWN, "UI")


func play_complete() -> void:
	_play(COMPLETE, "SFX")


func _play(stream: AudioStream, bus_name: String, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus_name
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
