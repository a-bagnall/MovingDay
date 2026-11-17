extends RefCounted
class_name GameSettings
## Player settings kept in user://settings.cfg: audio, display, and accessibility.
## Loaded and applied once at start-up by the PauseMenu autoload; the pause menu edits them.

const PATH := "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const AUDIO_BUSES := ["Music", "SFX", "UI", "Ambience"]

static var master_volume := 0.8
static var music_volume := 0.65
static var sfx_volume := 0.8
static var ui_volume := 0.75
static var ambience_volume := 0.35
static var fullscreen := false
static var windowed_resolution := Vector2i(1600, 900)
static var vsync_enabled := true
## Skips UI fades and similar flourishes for players who find motion uncomfortable.
static var reduce_motion := false


## Add the mix buses if this is a first run or the project has no custom bus layout.
static func ensure_audio_buses() -> void:
	for bus_name: String in AUDIO_BUSES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


static func get_volume(bus_name: String) -> float:
	match bus_name:
		"master": return master_volume
		"Music": return music_volume
		"SFX": return sfx_volume
		"UI": return ui_volume
		"Ambience": return ambience_volume
	return 1.0


static func set_volume(bus_name: String, value: float) -> void:
	var volume := clampf(value, 0.0, 1.0)
	match bus_name:
		"master": master_volume = volume
		"Music": music_volume = volume
		"SFX": sfx_volume = volume
		"UI": ui_volume = volume
		"Ambience": ambience_volume = volume
	apply_audio()


## A missing file is normal on first launch. An unreadable one is reported and the
## defaults stay.
static func load_and_apply() -> void:
	ensure_audio_buses()
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err == OK:
		master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
		music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
		ui_volume = clampf(float(cfg.get_value("audio", "ui_volume", ui_volume)), 0.0, 1.0)
		ambience_volume = clampf(float(cfg.get_value("audio", "ambience_volume", ambience_volume)), 0.0, 1.0)
		fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
		var saved_width := int(cfg.get_value("display", "window_width", windowed_resolution.x))
		var saved_height := int(cfg.get_value("display", "window_height", windowed_resolution.y))
		windowed_resolution = Vector2i(clampi(saved_width, 960, 3840), clampi(saved_height, 540, 2160))
		vsync_enabled = bool(cfg.get_value("display", "vsync", vsync_enabled))
		reduce_motion = bool(cfg.get_value("accessibility", "reduce_motion", reduce_motion))
	elif err != ERR_FILE_NOT_FOUND:
		push_error("GameSettings: could not read %s: %s" % [PATH, error_string(err)])
	apply()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "ui_volume", ui_volume)
	cfg.set_value("audio", "ambience_volume", ambience_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "window_width", windowed_resolution.x)
	cfg.set_value("display", "window_height", windowed_resolution.y)
	cfg.set_value("display", "vsync", vsync_enabled)
	cfg.set_value("accessibility", "reduce_motion", reduce_motion)
	var err := cfg.save(PATH)
	if err != OK:
		push_error("GameSettings: could not write %s: %s" % [PATH, error_string(err)])


static func apply_audio() -> void:
	ensure_audio_buses()
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("UI", ui_volume)
	_set_bus_volume("Ambience", ambience_volume)


static func _set_bus_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	AudioServer.set_bus_mute(index, value <= 0.0)


static func apply() -> void:
	apply_audio()
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	if not fullscreen:
		DisplayServer.window_set_size(windowed_resolution)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
