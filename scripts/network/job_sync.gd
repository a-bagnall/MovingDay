extends Node
class_name JobSync
## Online play inside a job. The host runs everything that matters (furniture physics,
## grabbing, grip, damage, delivery, the contract) exactly as offline. Each client runs
## only its own players and shows the rest as the host reports it:
##
##   host   -> clients   furniture state, ~30 times a second (position, who holds it, damage)
##   client -> host      "grab / drop this" requests, and shoves (so light things still move)
##   everyone <-> all    each machine's own player positions, like the hub and main menu
##
## Added to the job scene by the level when a session is running. Items are named by
## Furniture.net_id, which is the same on every machine because the level spawns them in
## the same order.

const SEND_INTERVAL := 1.0 / 30.0
## A client could send any shove it likes; cap it per kg of the item (a real shove at full
## speed is Player.max_speed * Player.push_strength, about 0.25).
const MAX_PUSH_PER_KG := 0.8
## The host sees a remote player where it was a moment ago, so a grab is judged with
## this much extra reach.
const REACH_TOLERANCE := 1.6

var _items: Dictionary = {}          # furniture net id -> Furniture
var _zone: DeliveryZone
var _net_timer := 0.0
var _seq := 0                        # host: counts snapshots
var _last_seq := -1                  # client: newest snapshot applied
var _push_accum: Dictionary = {}     # client: furniture net id -> impulse not yet sent


## Call once the job's furniture list is final.
func setup(items: Array[Furniture], zone: DeliveryZone) -> void:
	_zone = zone
	for item in items:
		_items[item.net_id] = item


func _ready() -> void:
	add_to_group("job_sync")
	NetworkManager.roster_changed.connect(_drop_departed_players)
	NetworkManager.player_states_received.connect(_on_player_states_received)
	if NetworkManager.is_host():
		NetworkManager.interact_requested.connect(_on_interact_requested)
		NetworkManager.pushes_received.connect(_on_pushes_received)
	else:
		NetworkManager.job_state_received.connect(_on_job_state_received)
		NetworkManager.stumble_received.connect(_on_stumble_received)
		GameFlow.report_scene_ready()   # the host starts sending once it knows we are here


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_online():
		return
	_net_timer += delta
	if _net_timer < SEND_INTERVAL:
		return
	_net_timer = 0.0
	_stream_local_players()
	if NetworkManager.is_host():
		_send_furniture_state()
	else:
		_flush_pushes()


# --- players --------------------------------------------------------------

func _stream_local_players() -> void:
	var states: Array = []
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_local:
			states.append(player.net_state())
	if not states.is_empty():
		NetworkManager.send_player_states(states)


func _on_player_states_received(peer_id: int, states: Array) -> void:
	var allowed: Array = NetworkManager.roster().get(peer_id, [])
	for state in states:
		if not (state is Array) or (state as Array).size() < 6:
			continue
		var player := _find_player(state[0])
		# Only accept states for players that peer actually owns.
		if player == null or player.is_local or not allowed.has(player.player_id):
			continue
		player.apply_net_state(state[1], state[3], state[4], state[5], state[2])


func _find_player(player_id: int) -> Player:
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.player_id == player_id:
			return player
	return null


func _players_by_id() -> Dictionary:
	var out := {}
	for player: Player in get_tree().get_nodes_in_group("players"):
		out[player.player_id] = player
	return out


## A machine left: its players go, and whatever they carried is dropped.
func _drop_departed_players() -> void:
	var wanted := NetworkManager.remote_player_ids()
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_local or wanted.has(player.player_id):
			continue
		if player.held_furniture:
			player.held_furniture.release(player)
		player.remove_from_group("players")   # queue_free is deferred; leave the roster now
		player.queue_free()


## Host: tell the machine that owns `player_id` that it lost its grip.
func notify_stumble(player_id: int) -> void:
	var roster := NetworkManager.roster()
	for peer_id: int in roster:
		if peer_id != 1 and (roster[peer_id] as Array).has(player_id):
			NetworkManager.send_stumble(peer_id, player_id)


func _on_stumble_received(player_id: int) -> void:
	var player := _find_player(player_id)
	if player != null and player.is_local:
		player.stumble()


# --- host: furniture ------------------------------------------------------

func _send_furniture_state() -> void:
	var peers: Array[int] = []
	for peer_id: int in NetworkManager.roster():
		if peer_id != 1 and GameFlow.is_peer_ready(peer_id):
			peers.append(peer_id)
	if peers.is_empty():
		return
	var states: Array = []
	for id: int in _items:
		var item: Furniture = _items[id]
		if is_instance_valid(item):
			states.append(item.net_state())
	var payload := [GameFlow.scene_serial, _seq, states]
	_seq += 1
	for peer_id in peers:
		NetworkManager.send_job_state(peer_id, payload)


## A client's player wants to grab (furniture_id >= 0) or drop (-1). The host re-checks
## everything: the client only suggests.
func _on_interact_requested(peer_id: int, player_id: int, furniture_id: int) -> void:
	if not (NetworkManager.roster().get(peer_id, []) as Array).has(player_id):
		return
	var player := _find_player(player_id)
	if player == null or player.is_local:
		return
	if player.held_furniture:
		player.held_furniture.release(player)
		return
	var item: Furniture = _items.get(furniture_id)
	if item == null or not is_instance_valid(item) or not item.can_be_grabbed_by(player):
		return
	if item.distance_to_nearest_free_grip(player.global_position) > player.reach * REACH_TOLERANCE:
		return
	item.request_grab(player)


func _on_pushes_received(_peer_id: int, pushes: Array) -> void:
	for entry in pushes:
		if not (entry is Array) or (entry as Array).size() < 2 or not (entry[1] is Vector3):
			continue
		var item: Furniture = _items.get(int(entry[0]))
		if item == null or not is_instance_valid(item) or item.is_held() or item.is_delivered:
			continue
		var impulse: Vector3 = entry[1]
		item.apply_central_impulse(impulse.limit_length(item.mass * MAX_PUSH_PER_KG))


# --- client: furniture ----------------------------------------------------

func _on_job_state_received(payload: Array) -> void:
	if payload.size() < 3 or int(payload[0]) != GameFlow.scene_serial:
		return   # from a scene we have left
	var seq := int(payload[1])
	if seq <= _last_seq:
		return   # older than what we have
	_last_seq = seq
	var players := _players_by_id()
	for state in payload[2]:
		if not (state is Array) or (state as Array).is_empty():
			continue
		var item: Furniture = _items.get(int(state[0]))
		if item == null or not is_instance_valid(item):
			continue
		item.net_apply_state(state, players)
		if item.is_delivered and _zone != null and not _zone.delivered_items.has(item):
			_zone.delivered_items.append(item)
			_zone.delivery_changed.emit(_zone.delivered_items.size())


## Called by a local player that is shoving a furniture copy; sent with the next tick.
func queue_push(furniture_id: int, impulse: Vector3) -> void:
	_push_accum[furniture_id] = _push_accum.get(furniture_id, Vector3.ZERO) + impulse


func _flush_pushes() -> void:
	if _push_accum.is_empty():
		return
	var pushes: Array = []
	for id in _push_accum:
		pushes.append([id, _push_accum[id]])
	_push_accum.clear()
	NetworkManager.send_pushes(pushes)
