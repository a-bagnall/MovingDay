extends CanvasLayer
class_name OnlineMenu
## Host/join panel that floats over the main menu room (opened from the Online pad).
## It is a small card, not a screen: the room stays visible and keeps running, and
## closing it (Close button or Esc) never touches the connection, so you can host or
## join, close it, and walk around with everyone who is connected.
##
## Mouse and keyboard driven, because the host's address has to be typed. While it is
## open `InputSetup.ui_captured` keeps keyboard players still, so typing cannot move
## anyone.

signal closed

var _content: VBoxContainer
var _address_edit: LineEdit
var _address_text := ""   # survives the content being rebuilt
var _status := ""         # last error or note, shown under the controls


func _ready() -> void:
	layer = 20
	_build_frame()
	NetworkManager.roster_changed.connect(_refresh)
	NetworkManager.joined_server.connect(_on_joined_server)
	NetworkManager.port_status_changed.connect(_refresh)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.connection_lost.connect(_on_connection_lost)
	visible = false
	_refresh()


func _exit_tree() -> void:
	InputSetup.ui_captured = false   # never leave the keyboard frozen behind a closed scene


func open() -> void:
	visible = true
	InputSetup.ui_captured = true
	_status = ""
	_refresh()
	if _address_edit:
		_address_edit.grab_focus()


func close() -> void:
	visible = false
	InputSetup.ui_captured = false
	get_viewport().gui_release_focus()
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):   # Esc or gamepad B
		close()
		get_viewport().set_input_as_handled()


func _build_frame() -> void:
	_content = UIKit.modal(self, 1300, false)   # the room stays visible and clickable-through


## Rebuilds the panel for the current network state.
func _refresh() -> void:
	_address_edit = null
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	_content.add_child(UIKit.label("ONLINE", UIKit.FONT_BIG, HORIZONTAL_ALIGNMENT_CENTER))
	if NetworkManager.is_online():
		_build_session()
	else:
		_build_offline()
	if not _status.is_empty():
		var status := UIKit.label(_status, UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER)
		status.add_theme_color_override("font_color", UIKit.PINK)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(status)


func _build_offline() -> void:
	_content.add_child(UIKit.label("Host a game, or join a friend by address",
		UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
	_content.add_child(UIKit.button("Host game", _on_host_pressed, true))

	_address_edit = LineEdit.new()
	_address_edit.placeholder_text = "Host address, e.g. 192.168.1.20 or 203.0.113.5:%d" % NetworkManager.DEFAULT_PORT
	_address_edit.text = _address_text
	_address_edit.add_theme_font_size_override("font_size", UIKit.FONT_BODY)
	_address_edit.custom_minimum_size.y = 120
	_address_edit.text_changed.connect(func(text: String) -> void: _address_text = text)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_content.add_child(_address_edit)
	_content.add_child(UIKit.button("Join game", _on_join_pressed))
	_content.add_child(UIKit.button("Close", close))
	_content.add_child(_esc_hint())


func _build_session() -> void:
	var roster := NetworkManager.roster()
	if roster.is_empty():
		_content.add_child(UIKit.label("Connecting...", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		_content.add_child(UIKit.label("Players (%d/%d)" % [NetworkManager.player_count(), InputSetup.MAX_PLAYERS],
			UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
		var owner_of := {}   # player id -> peer id
		for peer_id: int in roster:
			for player_id: int in roster[peer_id]:
				owner_of[player_id] = peer_id
		var roster_grid := UIKit.stat_grid()
		_content.add_child(roster_grid)
		for player_id in range(1, InputSetup.MAX_PLAYERS + 1):
			if not owner_of.has(player_id):
				continue
			var peer_id: int = owner_of[player_id]
			var where := "this computer" if peer_id == multiplayer.get_unique_id() \
				else ("the host" if peer_id == 1 else "a friend")
			UIKit.add_stat(roster_grid, "Player %d" % player_id, where)
		if NetworkManager.player_count() == 0:
			_content.add_child(UIKit.label("Nobody has joined yet. Hold %s in the room to join." % UIKit.INTERACT_KEYS,
				UIKit.FONT_SMALL))

	if NetworkManager.is_host():
		var help := UIKit.label(_host_help(), UIKit.FONT_SMALL)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(help)
	_content.add_child(UIKit.button("Close", close, true))
	_content.add_child(UIKit.button("Disconnect", _on_disconnect_pressed))
	_content.add_child(_esc_hint())


## What the host tells their friends, based on how the router port forwarding went.
func _host_help() -> String:
	var port := NetworkManager.DEFAULT_PORT
	var addresses := NetworkManager.local_addresses()
	var same_network := "Friends on your own network join with: %s" % (
		", ".join(addresses) if not addresses.is_empty() else "(no network address found)")
	match NetworkManager.port_status:
		NetworkManager.PortStatus.OPENING:
			return "Opening the port on your router...\n" + same_network
		NetworkManager.PortStatus.OPEN:
			if NetworkManager.public_address.is_empty():
				return "Port %d opened on your router. Friends join with your public IP address and port %d.\n%s" \
					% [port, port, same_network]
			return "Friends join with: %s:%d\n%s" % [NetworkManager.public_address, port, same_network]
		NetworkManager.PortStatus.SHARED_ADDRESS:
			return ("Your internet provider shares one public address between customers, so friends outside "
				+ "your network cannot reach you directly. A VPN tool such as Tailscale gets around this.\n") + same_network
		NetworkManager.PortStatus.FAILED:
			return ("Could not open the port automatically (is UPnP turned on in your router?). "
				+ "Forward UDP port %d on your router, or play on the same network.\n" % port) + same_network
	return same_network


func _esc_hint() -> Label:
	return UIKit.label("Esc to close", UIKit.FONT_SMALL,
		HORIZONTAL_ALIGNMENT_CENTER, &"MutedLabel")


# --- actions --------------------------------------------------------------

func _on_host_pressed() -> void:
	_status = ""
	var err := NetworkManager.host()
	if err != OK:
		_status = "Could not host: %s" % error_string(err)
	_refresh()


func _on_join_pressed() -> void:
	_status = ""
	var text := _address_text.strip_edges()
	if text.is_empty():
		_status = "Enter the host's address first"
		_refresh()
		return

	var address := text
	var port := NetworkManager.DEFAULT_PORT
	if text.count(":") == 1:
		var parts := text.split(":")
		address = parts[0]
		if not parts[1].is_valid_int() or int(parts[1]) < 1 or int(parts[1]) > 65535:
			_status = "The port must be a number from 1 to 65535"
			_refresh()
			return
		port = int(parts[1])

	var err := NetworkManager.join(address, port)
	if err != OK:
		_status = "Could not start connecting: %s" % error_string(err)
	# Joining is now under way: rebuild so the Join button is replaced by "Connecting...".
	_refresh()


func _on_disconnect_pressed() -> void:
	_status = ""
	NetworkManager.leave()
	_refresh()


## Connected to the host: get out of the way so everyone can see each other.
func _on_joined_server() -> void:
	_status = ""
	if visible:
		close()
	_refresh()


func _on_join_failed() -> void:
	_status = "Could not connect to the host"
	_refresh()
	if visible and _address_edit:
		_address_edit.grab_focus()


func _on_connection_lost() -> void:
	_status = "Lost connection to the host"
	_refresh()
