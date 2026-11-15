extends Node
## Autoload "NetworkManager". Direct-IP ENet sessions: one player hosts, up to
## InputSetup.MAX_PLAYERS - 1 friends join. The host owns the roster (peer id ->
## player id) and tells every client about it; player ids are stable for as long
## as a peer stays connected (host = 1, friends take the lowest free id).
##
## Hosting also asks the router, over UPnP, to forward the port so friends need no
## router setup. It works on most home routers with UPnP on (usually the default);
## it cannot work behind an ISP-shared address or with UPnP off, and then the
## status says so.
##
## Connection and roster only. Synchronised scenes, movement and furniture build
## on this in later steps. Online play uses one local player per machine.

signal roster_changed
## Client only: connected to the host (the roster follows).
signal joined_server
## Client only: the connection attempt failed. The session is already closed.
signal join_failed
## Client only: the host went away. The session is already closed.
signal connection_lost
## Host only: `port_status` or `public_address` changed.
signal port_status_changed

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

var _roster := {}   # peer id -> player id; on a client, a copy sent by the host
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


## Copy of the roster: peer id -> player id.
func roster() -> Dictionary:
	return _roster.duplicate()


## This machine's player id, or 0 if there is none yet (offline, or still joining).
func local_player_id() -> int:
	return _roster.get(multiplayer.get_unique_id(), 0)


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
	_roster = {multiplayer.get_unique_id(): 1}
	roster_changed.emit()
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
	var player_id := _free_player_id()
	assert(player_id > 0, "Peer %d connected but every player id is taken" % peer_id)
	_roster[peer_id] = player_id
	_broadcast_roster()


func _on_peer_disconnected(peer_id: int) -> void:
	if mode != Mode.HOST:
		return
	_roster.erase(peer_id)
	_broadcast_roster()


func _free_player_id() -> int:
	for player_id in range(1, InputSetup.MAX_PLAYERS + 1):
		if not _roster.values().has(player_id):
			return player_id
	return 0


func _broadcast_roster() -> void:
	roster_changed.emit()
	_receive_roster.rpc(_roster)


@rpc("authority", "call_remote", "reliable")
func _receive_roster(roster: Dictionary) -> void:
	_roster = roster
	roster_changed.emit()


# --- connection events (client side) ----------------------------------------

func _on_connected_to_server() -> void:
	joined_server.emit()


func _on_connection_failed() -> void:
	_end_session.call_deferred(join_failed)


func _on_server_disconnected() -> void:
	_end_session.call_deferred(connection_lost)


func _end_session(reason: Signal) -> void:
	leave()
	reason.emit()
