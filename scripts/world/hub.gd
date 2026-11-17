extends WalkableArea
class_name Hub
## In-run area reached every GameFlow.HUB_EVERY_N_DAYS days. Players can buy
## one-day drinks and permanent outfit unlocks before walking to the truck pad.

const COUNTDOWN_TIME := 3.0
const TRUCK_FOOT_X := 2.0
const TRUCK_PAD_CENTER := Vector3(0.5, 0.0, 0.0)
const TRUCK_PAD_SIZE := Vector3(3.5, 0.1, 4.0)
const TRUCK_PAD_COLOR := Color(0.4, 0.8, 0.5)

## Built from Balance, so prices and effect text always match the numbers.
static var SHOP_ITEMS := {
	"coffee": {"name": "Coffee", "price": Balance.COFFEE_PRICE,
		"description": "+%d%% move speed for the next day" % roundi((Balance.COFFEE_SPEED - 1.0) * 100.0)},
	"energy": {"name": "Energy Drink", "price": Balance.ENERGY_PRICE,
		"description": "+%d%% acceleration for the next day" % roundi((Balance.ENERGY_ACCELERATION - 1.0) * 100.0)},
	"workwear": {"name": "Company Outfit", "price": Balance.WORKWEAR_PRICE,
		"description": "+%d%% earnings style bonus" % roundi(Balance.WORKWEAR_STYLE_BONUS * 100.0)},
	"enchanted_workwear": {"name": "Lucky Enchanted Outfit", "price": Balance.ENCHANTED_WORKWEAR_PRICE,
		"description": "+%d%% earnings style bonus" % roundi(Balance.ENCHANTED_WORKWEAR_STYLE_BONUS * 100.0)},
}

var _truck_pad: InteractZone
var _picker: ModifierPicker
var _choosing := false   # the "choose one" card is up on this machine
var _status: Label
var _countdown := -1.0
var _notice := ""
var _notice_time := 0.0


func _init() -> void:
	room_size = Vector2(30.0, 12.0)


func _ready() -> void:
	super()
	assert(SaveManager.run != null, "Hub opened with no active run; start from the main menu")
	_status = _build_hud("HUB SHOP")

	var truck := MovingTruck.new()
	truck.position = Vector3(TRUCK_FOOT_X, 0.0, 0.0)
	add_child(truck)
	truck.zone.active = false   # nothing is delivered in the hub

	_truck_pad = add_zone(TRUCK_PAD_CENTER, TRUCK_PAD_SIZE, TRUCK_PAD_COLOR, _pad_text())
	_add_shop_pad("coffee", Vector3(-10.0, 0.0, -3.0), Color("#9b704e"))
	_add_shop_pad("energy", Vector3(-6.0, 0.0, -3.0), Color("#8b9d55"))
	_add_shop_pad("workwear", Vector3(-2.0, 0.0, -3.0), Color("#668ca8"))
	_add_shop_pad("enchanted_workwear", Vector3(-10.0, 0.0, 0.0), Color("#a58ac5"))

	_picker = ModifierPicker.new()
	_picker.chosen.connect(_on_modifier_chosen)
	add_child(_picker)
	# The host decides; clients see the result when the host's run reaches them.
	if GameFlow.is_authority() and RunModifiers.choice_due(SaveManager.run):
		_choosing = true
		_picker.open(RunModifiers.offer(SaveManager.run))


func _add_shop_pad(item_id: String, center: Vector3, color: Color) -> void:
	var item: Dictionary = SHOP_ITEMS[item_id]
	var text := "%s\n%s\n%s" % [item.name, UIKit.money(float(item.price)), item.description]
	var zone := add_zone(center, Vector3(3.2, 0.1, 2.2), color, text)
	zone.interacted.connect(_on_shop_interacted.bind(item_id))


func _spawn_point(player_id: int) -> Vector3:
	return Vector3(-13.0 + (player_id - 1) * 1.5, 0.1, 3.0)


func _on_modifier_chosen(id: String) -> void:
	SaveManager.run.modifiers.append(id)
	SaveManager.run.modifier_day = SaveManager.run.day
	_choosing = false
	_set_notice("%s is in for the rest of this run" % RunModifiers.modifier_name(id))
	GameFlow.sync_run()


func _process(delta: float) -> void:
	var total := get_tree().get_nodes_in_group("players").size()
	var waiting_for_choice := _choosing or (not GameFlow.is_authority() and RunModifiers.choice_due(SaveManager.run))
	if total > 0 and not _choosing and _truck_pad.players_inside().size() == total:
		if _countdown < 0.0:
			_countdown = COUNTDOWN_TIME
		_countdown -= delta
		if _countdown <= 0.0:
			if GameFlow.is_authority():
				GameFlow.start_job()
				set_process(false)
				return
			_countdown = 0.0   # a client waits for the host to start the job
	else:
		_countdown = -1.0

	_truck_pad.set_text(_pad_text() if _countdown < 0.0 else "Starting in %d" % ceili(_countdown))
	_notice_time = maxf(0.0, _notice_time - delta)
	var status_text := "DAY %d  |  WALLET %s  |  RUNNING COSTS %s a day\nBuy a boost or outfit, then all players stand on the truck pad" % [
		SaveManager.run.day, UIKit.money(SaveManager.run.wallet),
		UIKit.money(GameFlow.overhead_for_day(SaveManager.run.day))]
	if not SaveManager.run.modifiers.is_empty():
		status_text += "\nModifiers: " + RunModifiers.names(SaveManager.run.modifiers)
	if waiting_for_choice and not _choosing:
		status_text += "\nThe host is picking a modifier..."
	if _notice_time > 0.0:
		status_text += "\n" + _notice
	_status.text = status_text


func _on_shop_interacted(_player_id: int, item_id: String) -> void:
	var item: Dictionary = SHOP_ITEMS[item_id]
	var price := int(item.price)
	if item_id in ["workwear", "enchanted_workwear"] and SaveManager.profile.cosmetics.has(item_id):
		SaveManager.profile.equipped_outfit = item_id
		_set_notice("%s equipped" % item.name)
		return
	if SaveManager.run.wallet < price:
		_set_notice("Not enough money for %s" % item.name)
		return

	match item_id:
		"coffee":
			if SaveManager.run.speed_boost_day == SaveManager.run.day:
				_set_notice("Coffee is already active for this day")
				return
			SaveManager.run.speed_boost_day = SaveManager.run.day
			SaveManager.run.speed_boost = Balance.COFFEE_SPEED
		"energy":
			if SaveManager.run.acceleration_boost_day == SaveManager.run.day:
				_set_notice("Your energy drink is already active for this day")
				return
			SaveManager.run.acceleration_boost_day = SaveManager.run.day
			SaveManager.run.acceleration_boost = Balance.ENERGY_ACCELERATION
		"workwear", "enchanted_workwear":
			SaveManager.profile.cosmetics.append(item_id)
			SaveManager.profile.equipped_outfit = item_id

	SaveManager.run.wallet -= price
	_set_notice("Bought %s for %s" % [item.name, UIKit.money(price)])
	GameFlow.sync_run()   # other machines show the new wallet


func _set_notice(message: String) -> void:
	_notice = message
	_notice_time = 3.0


func _pad_text() -> String:
	return "Truck\nStart day %d" % SaveManager.run.day
