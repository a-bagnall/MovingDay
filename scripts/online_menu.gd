extends Node
class_name OnlineMenu
## Direct-IP host/join screen, reached from the main menu's Online pad. Mouse and
## keyboard driven (the address has to be typed), and it has no players in it so
## typing cannot move anyone. Shows the roster once hosting or joined.

var _content: VBoxContainer
var _address_text := ""   # survives the content being rebuilt
var _status := ""         # last error or note, shown under the controls


func _ready() -> void:
	_build_frame()
	NetworkManager.roster_changed.connect(_refresh)
	NetworkManager.joined_server.connect(_refresh)
	NetworkManager.port_status_changed.connect(_refresh)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.connection_lost.connect(_on_connection_lost)
	_refresh()


func _build_frame() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := UIKit.setup(layer)

	var backdrop := ColorRect.new()
	backdrop.color = UIKit.BROWN_DARK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	margin.add_child(column)

	var banner := PanelContainer.new()
	banner.theme_type_variation = &"BannerPanel"
	banner.custom_minimum_size = Vector2(1300, 0)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner.add_child(UIKit.label("ONLINE PLAY", UIKit.FONT_TITLE, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(banner)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1500, 0)
	center.add_child(panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 24)
	panel.add_child(_content)


## Rebuilds the panel for the current network state.
func _refresh() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if NetworkManager.is_online():
		_build_session()
	else:
		_build_offline()
	if not _status.is_empty():
		_content.add_child(UIKit.label(_status, UIKit.FONT_SMALL, HORIZONTAL_ALIGNMENT_CENTER))


func _build_offline() -> void:
	_content.add_child(UIKit.label("Host a game, or join a friend by address",
		UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
	_content.add_child(_button("Host game", _on_host_pressed))

	var address := LineEdit.new()
	address.placeholder_text = "Host address, e.g. 192.168.1.20 or 203.0.113.5:%d" % NetworkManager.DEFAULT_PORT
	address.text = _address_text
	address.add_theme_font_size_override("font_size", UIKit.FONT_BODY)
	address.text_changed.connect(func(text: String) -> void: _address_text = text)
	address.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_content.add_child(address)
	_content.add_child(_button("Join game", _on_join_pressed))
	_content.add_child(_button("Back", _on_back_pressed))


func _build_session() -> void:
	var roster := NetworkManager.roster()
	if roster.is_empty():
		_content.add_child(UIKit.label("Connecting...", UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		_content.add_child(UIKit.label("Players (%d/%d)" % [roster.size(), InputSetup.MAX_PLAYERS],
			UIKit.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
		var entries: Array[Vector2i] = []   # (player id, peer id)
		for peer_id: int in roster:
			entries.append(Vector2i(roster[peer_id], peer_id))
		entries.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		for entry in entries:
			var line := "Player %d" % entry.x
			if entry.x == 1:
				line += " (host)"
			if entry.y == multiplayer.get_unique_id():
				line += " (you)"
			_content.add_child(UIKit.label(line, UIKit.FONT_BODY))

	if NetworkManager.is_host():
		var help := UIKit.label(_host_help(), UIKit.FONT_SMALL)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(help)
	_content.add_child(_button("Disconnect", _on_disconnect_pressed))


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


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button


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


func _on_back_pressed() -> void:
	NetworkManager.leave()
	GameFlow.open_main_menu()


func _on_join_failed() -> void:
	_status = "Could not connect to the host"
	_refresh()


func _on_connection_lost() -> void:
	_status = "Lost connection to the host"
	_refresh()
