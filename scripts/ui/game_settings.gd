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

static var master_volume := 0.8   # 0.0 to 1.0
static var fullscreen := false
static var windowed_resolution := Vector2i(1600, 900)
static var vsync_enabled := true
## Skips UI fades and similar flourishes for players who find motion uncomfortable.
static var reduce_motion := false


## A missing file is normal on first launch. An unreadable one is reported and the
## defaults stay.
static func load_and_apply() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err == OK:
		master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
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
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "window_width", windowed_resolution.x)
	cfg.set_value("display", "window_height", windowed_resolution.y)
	cfg.set_value("display", "vsync", vsync_enabled)
	cfg.set_value("accessibility", "reduce_motion", reduce_motion)
	var err := cfg.save(PATH)
	if err != OK:
		push_error("GameSettings: could not write %s: %s" % [PATH, error_string(err)])


static func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	if not fullscreen:
		DisplayServer.window_set_size(windowed_resolution)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)


