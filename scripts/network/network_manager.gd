extends Node
## Autoload "NetworkManager". Direct-IP ENet sessions: one player hosts and friends
## join. The host owns the roster (peer id -> that machine's player ids) and tells
## every client about it. Every machine can have several local players; across the
## whole session there are at most InputSetup.MAX_PLAYERS. Ids are stable while a
## player stays (new players take the lowest free id), and are pushed into
## InputSetup so the rest of the game just sees "player 3 is local, player 1 is not".
##
## Hosting also asks the router, over UPnP, to forward the port so friends need no
## router setup. It works on most home routers with UPnP on (usually the default);
## it cannot work behind an ISP-shared address or with UPnP off, and then the
## status says so.
##
## Also streams each machine's player positions and button state to the others so
## walkable areas (main menu, hub) and jobs can show everyone.
##
## Jobs are host-authoritative: the host simulates the furniture and streams its state
## to the clients (see JobSync); clients send back grab/drop requests and shoves. This
## script only carries those messages. Everything is an RPC on this autoload, so a
## message that arrives while a scene is still loading is simply dropped, never an error.

signal roster_changed
## Client only: connected to the host (the roster follows).
signal joined_server
## Client only: the connection attempt failed. The session is already closed.
signal join_failed
## Client only: the host went away. The session is already closed.
signal connection_lost
## Host only: `port_status` or `public_address` changed.
signal port_status_changed
## Another machine's player states arrived: [id, position, velocity, facing, move, interact] each.
signal player_states_received(peer_id: int, states: Array)
## Host only: a client asked to grab (furniture_id >= 0) or drop (-1) with one of its players.
signal interact_requested(peer_id: int, player_id: int, furniture_id: int)
## Host only: a client shoved furniture. `pushes` is [[furniture id, impulse], ...].
signal pushes_received(peer_id: int, pushes: Array)
## Client only: the host's snapshot of the job: [scene serial, sequence number, furniture states].
signal job_state_received(payload: Array)
## Client only: the host says one of this machine's players lost its grip.
signal stumble_received(player_id: int)
## Someone (on another machine) pinged a spot: [player id, world position].
signal ping_received(player_id: int, position: Vector3)
## Local player `player_id` was shoved: add `kick` (m/s) to its velocity.
signal shove_received(player_id: int, kick: Vector3)
## Host: a client shoved furniture `furniture_id` along `direction`.
signal furniture_shove_requested(peer_id: int, furniture_id: int, direction: Vector3)

const DEFAULT_PORT := 7777

enum Mode { OFFLINE, HOST, CLIENT }
## Result of asking the router to forward the port (host only).
## OPEN: forwarded. FAILED: no UPnP router, or it refused. SHARED_ADDRESS: forwarded,
## but the "public" address is private, so the ISP shares one address between customers.
enum PortStatus { NONE, OPENING, OPEN, FAILED, SHARED_ADDRESS }

var mode := Mode.OFFLINE
var port_status := PortStatus.NONE
## The router's public address once known (can be empty even when the port is open).
var public_address := ""

var _roster := {}   # peer id -> Array of player ids; on a client, a copy sent by the host
var _upnp: UPNP                # kept so the mapping can be removed on leave
var _mapped_port := 0
var _upnp_thread: Thread


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	if _upnp_thread != null and not _upnp_thread.is_alive():
		_finish_upnp(_upnp_thread.wait_to_finish())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave()   # removes the router mapping before the game quits


func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


## Copy of the roster: peer id -> Array of that machine's player ids.
func roster() -> Dictionary:
	return _roster.duplicate(true)


## The ids the host has given this machine's players (empty offline).
func local_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _roster.get(multiplayer.get_unique_id(), []):
		out.append(id)
	return out


## Ids of players on other machines.
func remote_player_ids() -> Array[int]:
	var out: Array[int] = []
	for peer_id: int in _roster:
		if peer_id != multiplayer.get_unique_id():
			for id: int in _roster[peer_id]:
				out.append(id)
	return out


## Players in the whole session.
func player_count() -> int:
	var total := 0
	for peer_id: int in _roster:
		total += (_roster[peer_id] as Array).size()
	return total


## Players that make up this game: everyone online, or the players on this machine when
## offline.
func session_player_count() -> int:
	return player_count() if is_online() else InputSetup.assigned_count()


## True when one player is the whole team. Jobs stay possible alone: two-player items can
## be carried by one person, slowly (Balance.SOLO_HEAVY_SPEED).
func is_solo() -> bool:
	return session_player_count() <= 1


## Connected machines, including this one.
func peer_count() -> int:
	return _roster.size()


## Whether another local player may join: there is room in the session, and the host
## has answered the previous request (so we never ask for two at once).
func can_add_local_player() -> bool:
	if mode == Mode.OFFLINE:
		return InputSetup.assigned_count() < InputSetup.MAX_PLAYERS
	return player_count() < InputSetup.MAX_PLAYERS \
		and InputSetup.assigned_count() <= local_ids().size()


## Tell the session how many local players this machine has. Call after a local
## player joins. Does nothing offline.
func set_local_player_count(count: int) -> void:
	if mode == Mode.HOST:
		var granted := _apply_count(multiplayer.get_unique_id(), count)
		if granted < count:
			InputSetup.truncate(granted)
	elif mode == Mode.CLIENT and _is_connected():
		_report_count.rpc_id(1, count)


## Streams this machine's local player states to everyone else. Unreliable on
## purpose: the next packet supersedes a lost one.
func send_player_states(states: Array) -> void:
	if mode != Mode.OFFLINE and _is_connected() and _roster.size() > 1:
		_receive_player_states.rpc(states)


## Host: sends the job's furniture state to one client. Unreliable on purpose: the
## next snapshot supersedes a lost one.
func send_job_state(peer_id: int, payload: Array) -> void:
	if mode == Mode.HOST and _is_connected():
		_receive_job_state.rpc_id(peer_id, payload)


## Client: asks the host to grab furniture `furniture_id` (or drop what is held, with -1)
## for the local player `player_id`.
func send_interact_request(player_id: int, furniture_id: int) -> void:
	if mode == Mode.CLIENT and _is_connected():
		_request_interact.rpc_id(1, player_id, furniture_id)


## Client: tells the host about shoves: [[furniture id, impulse], ...].
func send_pushes(pushes: Array) -> void:
	if mode == Mode.CLIENT and _is_connected():
		_receive_pushes.rpc_id(1, pushes)


## Host: tells the client that owns `player_id` that it lost its grip.
func send_stumble(peer_id: int, player_id: int) -> void:
	if mode == Mode.HOST and _is_connected():
		_receive_stumble.rpc_id(peer_id, player_id)


## Tells everyone else that local player `player_id` pinged `position`. A client sends it
## to the host, which checks the player is the sender's and passes it on.
func send_ping(player_id: int, position: Vector3) -> void:
	if not _is_connected():
		return
	if mode == Mode.CLIENT:
		_request_ping.rpc_id(1, player_id, position)
	elif mode == Mode.HOST:
		_relay_ping.rpc(player_id, position)


## Shoves player `target_id` (on any machine) with velocity change `kick`. Always goes
## through the host, which passes it to the machine that owns that player.
func send_shove_player(target_id: int, kick: Vector3) -> void:
	if not _is_connected():
		return
	if mode == Mode.CLIENT:
		_request_shove_player.rpc_id(1, target_id, kick)
	elif mode == Mode.HOST:
		_route_shove(target_id, kick)


## Client: asks the host to shove furniture `furniture_id` (the host simulates it).
func send_shove_furniture(furniture_id: int, direction: Vector3) -> void:
	if mode == Mode.CLIENT and _is_connected():
		_request_shove_furniture.rpc_id(1, furniture_id, direction)


func _route_shove(target_id: int, kick: Vector3) -> void:
	kick = kick.limit_length(Balance.SHOVE_PLAYER_SPEED * 1.25)   # never trust a size from the network
	for peer_id: int in _roster:
		if (_roster[peer_id] as Array).has(target_id):
			if peer_id == 1:
				shove_received.emit(target_id, kick)
			else:
				_deliver_shove.rpc_id(peer_id, target_id, kick)
			return


## Whether messages can be sent right now (online and the connection is up).
func can_send() -> bool:
	return mode != Mode.OFFLINE and _is_connected()


## Host: whether new machines may join. A run in progress cannot take newcomers,
## so GameFlow turns this off outside the main menu.
func set_accepting_connections(accepting: bool) -> void:
	if mode == Mode.HOST and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.refuse_new_connections = not accepting


func _is_connected() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Non-loopback IPv4 addresses of this machine, for telling friends on the same network.
func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			out.append(address)
	return out


## Starts hosting. Returns OK or the ENet error.
func host(port: int = DEFAULT_PORT) -> Error:
	assert(mode == Mode.OFFLINE, "host() called while already online")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, InputSetup.MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	_roster = {multiplayer.get_unique_id(): []}
	set_local_player_count(InputSetup.assigned_count())   # players already in the room keep their place
	_set_port_status(PortStatus.OPENING)
	_upnp_thread = Thread.new()
	_upnp_thread.start(_open_port.bind(port))
	return OK


## Starts connecting to a host. Returns OK if the attempt started; the outcome
## arrives as joined_server or join_failed.
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	assert(mode == Mode.OFFLINE, "join() called while already online")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return OK


## Closes the session (host or client) and returns to offline.
func leave() -> void:
	if mode == Mode.OFFLINE:
		return
	if _upnp_thread != null:
		_finish_upnp(_upnp_thread.wait_to_finish())   # blocks up to the discovery timeout
	_close_port()
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	_roster.clear()
	public_address = ""
	_set_port_status(PortStatus.NONE)
	InputSetup.reset_ids()
	roster_changed.emit()


# --- router port forwarding (UPnP) --------------------------------------------

## Runs on a worker thread: discovery and the mapping request can block for seconds.
func _open_port(port: int) -> Dictionary:
	var upnp := UPNP.new()
	var result := {"upnp": upnp, "port": port, "status": PortStatus.FAILED, "address": ""}
	if upnp.discover() != UPNP.UPNP_RESULT_SUCCESS:
		return result
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return result
	if upnp.add_port_mapping(port, port, "Moving Day", "UDP") != UPNP.UPNP_RESULT_SUCCESS:
		return result
	var address := upnp.query_external_address()
	result["address"] = address
	result["status"] = PortStatus.SHARED_ADDRESS if _is_private_ipv4(address) else PortStatus.OPEN
	return result


func _finish_upnp(result: Dictionary) -> void:
	_upnp_thread = null
	if result["status"] != PortStatus.FAILED:
		_upnp = result["upnp"]
		_mapped_port = result["port"]
	if mode == Mode.HOST:
		public_address = result["address"]
		_set_port_status(result["status"])


## Removes the router mapping, if one was made.
func _close_port() -> void:
	if _mapped_port == 0:
		return
	_upnp.delete_port_mapping(_mapped_port, "UDP")
	_upnp = null
	_mapped_port = 0


func _set_port_status(status: PortStatus) -> void:
	port_status = status
	port_status_changed.emit()


## True for addresses that are not public: private ranges, carrier-grade NAT
## (100.64.0.0/10), loopback and link-local. An empty address is not private.
static func _is_private_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	var a := int(parts[0])
	var b := int(parts[1])
	return a == 10 or a == 127 or (a == 100 and b >= 64 and b <= 127) \
		or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254)


# --- roster (host side) -----------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if mode != Mode.HOST:
		return
	_roster[peer_id] = []   # connected; asks for its players with _report_count
	_broadcast_roster()


func _on_peer_disconnected(peer_id: int) -> void:
	if mode != Mode.HOST:
		return
	_roster.erase(peer_id)
	_broadcast_roster()


## Gives `peer_id` exactly `count` players if there is room, keeping the ones it
## already has. Returns how many it ended up with.
func _apply_count(peer_id: int, count: int) -> int:
	var ids: Array = _roster.get(peer_id, [])
	count = clampi(count, 0, InputSetup.MAX_PLAYERS)
	while ids.size() > count:
		ids.pop_back()
	while ids.size() < count:
		var player_id := _free_player_id()
		if player_id == 0:
			break   # session is full
		ids.append(player_id)
	_roster[peer_id] = ids
	_broadcast_roster()
	return ids.size()


func _free_player_id() -> int:
	var taken := {}
	for peer_id: int in _roster:
		for id: int in _roster[peer_id]:
			taken[id] = true
	for player_id in range(1, InputSetup.MAX_PLAYERS + 1):
		if not taken.has(player_id):
			return player_id
	return 0


func _broadcast_roster() -> void:
	_emit_roster()
	if _roster.size() > 1:
		_receive_roster.rpc(_roster)


## Pushes this machine's ids into InputSetup, then lets the UI and rooms react.
func _emit_roster() -> void:
	InputSetup.apply_ids(local_ids())
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_roster(roster: Dictionary) -> void:
	_roster = roster
	_emit_roster()


## Client -> host: "I have this many local players".
@rpc("any_peer", "call_remote", "reliable")
func _report_count(count: int) -> void:
	if mode != Mode.HOST:
		return
	var peer_id := multiplayer.get_remote_sender_id()   # only a connected peer can send this
	_count_result.rpc_id(peer_id, _apply_count(peer_id, count))


## Host -> client: how many of the requested players fit.
@rpc("authority", "call_remote", "reliable")
func _count_result(granted: int) -> void:
	InputSetup.truncate(granted)
	_emit_roster()


@rpc("any_peer", "call_remote", "unreliable")
func _receive_player_states(states: Array) -> void:
	player_states_received.emit(multiplayer.get_remote_sender_id(), states)


@rpc("authority", "call_remote", "unreliable")
func _receive_job_state(payload: Array) -> void:
	job_state_received.emit(payload)


@rpc("any_peer", "call_remote", "reliable")
func _request_interact(player_id: int, furniture_id: int) -> void:
	if mode == Mode.HOST:
		interact_requested.emit(multiplayer.get_remote_sender_id(), player_id, furniture_id)


@rpc("any_peer", "call_remote", "unreliable")
func _receive_pushes(pushes: Array) -> void:
	if mode == Mode.HOST:
		pushes_received.emit(multiplayer.get_remote_sender_id(), pushes)


@rpc("authority", "call_remote", "reliable")
func _receive_stumble(player_id: int) -> void:
	stumble_received.emit(player_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_ping(player_id: int, position: Vector3) -> void:
	if mode != Mode.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _roster.get(sender, []).has(player_id):
		return   # not one of that machine's players
	ping_received.emit(player_id, position)
	for peer in multiplayer.get_peers():
		if peer != sender:
			_relay_ping.rpc_id(peer, player_id, position)


@rpc("authority", "call_remote", "reliable")
func _relay_ping(player_id: int, position: Vector3) -> void:
	ping_received.emit(player_id, position)


@rpc("any_peer", "call_remote", "reliable")
func _request_shove_player(target_id: int, kick: Vector3) -> void:
	if mode == Mode.HOST:
		_route_shove(target_id, kick)


@rpc("authority", "call_remote", "reliable")
func _deliver_shove(target_id: int, kick: Vector3) -> void:
	shove_received.emit(target_id, kick)


@rpc("any_peer", "call_remote", "reliable")
func _request_shove_furniture(furniture_id: int, direction: Vector3) -> void:
	if mode == Mode.HOST:
		furniture_shove_requested.emit(multiplayer.get_remote_sender_id(), furniture_id, direction)


# --- connection events (client side) ----------------------------------------

func _on_connected_to_server() -> void:
	joined_server.emit()
	_report_count.rpc_id(1, InputSetup.assigned_count())   # bring any local players along


func _on_connection_failed() -> void:
	_end_session.call_deferred(join_failed)


func _on_server_disconnected() -> void:
	_end_session.call_deferred(connection_lost)


func _end_session(reason: Signal) -> void:
	leave()
	reason.emit()
