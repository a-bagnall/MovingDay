extends WalkableArea
class_name Hub
## In-run area reached every GameFlow.HUB_EVERY_N_DAYS days. Walk to the truck pad
## with every player on it to start the next job (short countdown, cancelled if
## anyone steps off). The shop is a placeholder for now.

const COUNTDOWN_TIME := 3.0
const TRUCK_FOOT_X := 2.0
const TRUCK_PAD_CENTER := Vector3(0.5, 0.0, 0.0)
const TRUCK_PAD_SIZE := Vector3(3.5, 0.1, 4.0)
const TRUCK_PAD_COLOR := Color(0.4, 0.8, 0.5)
const SHOP_CENTER := Vector3(-6.0, 0.0, -3.0)
const SHOP_COLOR := Color(0.6, 0.6, 0.65)

var _truck_pad: InteractZone
var _status: Label
var _countdown := -1.0


func _init() -> void:
	room_size = Vector2(30.0, 12.0)


func _ready() -> void:
	super()
	assert(SaveManager.run != null, "Hub opened with no active run; start from the main menu")
	_status = _build_hud("HUB")

	var truck := MovingTruck.new()
	truck.position = Vector3(TRUCK_FOOT_X, 0.0, 0.0)
	add_child(truck)
	truck.zone.active = false   # nothing is delivered in the hub

	_truck_pad = add_zone(TRUCK_PAD_CENTER, TRUCK_PAD_SIZE, TRUCK_PAD_COLOR, _pad_text())
	add_zone(SHOP_CENTER, Vector3(4.0, 0.1, 3.0), SHOP_COLOR, "Shop\nComing soon")


func _spawn_point(player_id: int) -> Vector3:
	return Vector3(-10.0 + (player_id - 1) * 1.5, 0.1, 3.0)


func _process(delta: float) -> void:
	var total := get_tree().get_nodes_in_group("players").size()
	if total > 0 and _truck_pad.players_inside().size() == total:
		if _countdown < 0.0:
			_countdown = COUNTDOWN_TIME
		_countdown -= delta
		if _countdown <= 0.0:
			GameFlow.start_job()
			set_process(false)
			return
	else:
		_countdown = -1.0

	_truck_pad.set_text(_pad_text() if _countdown < 0.0 else "Starting in %d" % ceili(_countdown))
	_status.text = "Day %d   Wallet %s\nAll players on the truck pad to start the day" % [
		SaveManager.run.day, UIKit.money(SaveManager.run.wallet)]


func _pad_text() -> String:
	return "Truck\nStart day %d" % SaveManager.run.day
