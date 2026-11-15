extends Node
## Network session (SPEC.md section 4): hosting and joining over ENet, LAN
## discovery and the lobby the host shares with everyone. The host is the
## server: it owns the lobby state and simulates the race. Every machine has
## one player; the lobby slots live in GameState.players as in local play.

## Role or connection state changed.
signal session_changed
## The shared lobby (players and race settings) changed.
signal lobby_updated
## The list of games found on the LAN changed.
signal servers_changed
## Host only: a client left; its slot is now free (or computer driven in a race).
signal peer_left(slot: int)
## Host only: a client has the race scene loaded and can receive race updates.
signal race_loaded(peer_id: int)

enum Role { OFFLINE, HOST, CLIENT }
## Which lobby tab the session belongs to.
enum Kind { LAN, INTERNET }

const GAME_ID: String = "sorakuninkaat"
const DEFAULT_PORT: int = 24616
## LAN announcements go to this port and the next few, so several copies of
## the game on one machine can each listen on their own port.
const DISCOVERY_PORT: int = 24617
const DISCOVERY_PORT_COUNT: int = 4
const MAX_CLIENTS: int = GameState.MAX_PLAYERS - 1
const HOST_PEER_ID: int = 1
const BROADCAST_ADDRESS: String = "255.255.255.255"
## Seconds between LAN announcements, and how long a silent game stays listed.
const BROADCAST_INTERVAL: float = 1.0
const SERVER_EXPIRY: float = 3.5
## A refused client is dropped this long after being told why, so the message arrives.
const REJECT_GRACE: float = 0.5
## Address prefixes in order of how likely they are to be the LAN address.
const PREFERRED_PREFIXES: Array[String] = ["192.168.", "10.", "172."]

var role: Role = Role.OFFLINE
var kind: Kind = Kind.LAN
## True between join_game() and the server accepting us.
var connecting: bool = false
## Slot of this machine's player (-1 until the host has assigned one).
var local_slot: int = -1
## Host: a race is running, so new players are turned away.
var in_race: bool = false
## Damage rule of the host's game, shown to clients.
var remote_damage: bool = true
## Last problem to show in the lobby ("" = none).
var last_error: String = ""
## Games heard on the LAN: "address:port" -> {address, port, name, players, racing, expires}.
var servers: Dictionary = {}

## The running race's NetSync on this machine, or null (set by NetSync itself).
var race_sync: NetSync

## Host: clients that have loaded the current race. Kept here rather than in
## the race scene, because a client can finish loading before the host does.
var _loaded_peers: Array[int] = []
var _announcer: PacketPeerUDP
var _listener: PacketPeerUDP
var _announce_timer: float = 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return role != Role.OFFLINE and not connecting


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


## This machine's IPv4 addresses that other machines can connect to, the
## likeliest home network address first (virtual adapters often use 172.x).
func get_local_addresses() -> PackedStringArray:
	var found: Array[String] = []
	for address: String in IP.get_local_addresses():
		var is_ipv4: bool = address.count(".") == 3
		if is_ipv4 and not address.begins_with("127.") and not address.begins_with("169.254."):
			found.append(address)
	found.sort_custom(func(a: String, b: String) -> bool: return _address_rank(a) < _address_rank(b))
	return PackedStringArray(found)


func _address_rank(address: String) -> int:
	for i: int in PREFERRED_PREFIXES.size():
		if address.begins_with(PREFERRED_PREFIXES[i]):
			return i
	return PREFERRED_PREFIXES.size()


# --- Session -------------------------------------------------------------

## port: another port lets two hosts run on one machine (players then join
## with "address:port").
func host_game(session_kind: Kind, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		last_error = tr("Pelin luominen epäonnistui (portti %d varattu?)") % port
		return error
	multiplayer.multiplayer_peer = peer
	stop_discovery()
	role = Role.HOST
	kind = session_kind
	last_error = ""
	local_slot = 0
	GameState.mode = GameState.Mode.NET
	_reset_slots()
	GameState.players[0].peer_id = HOST_PEER_ID
	GameState.players[0].display_name = Settings.get_player_name(0)
	if kind == Kind.LAN:
		_announcer = PacketPeerUDP.new()
		_announcer.set_broadcast_enabled(true)
	session_changed.emit()
	broadcast_lobby()
	return OK


func join_game(address: String, port: int, session_kind: Kind) -> Error:
	leave()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address.strip_edges(), port)
	if error != OK:
		last_error = tr("Osoitteeseen ei voitu yhdistää")
		return error
	multiplayer.multiplayer_peer = peer
	stop_discovery()
	role = Role.CLIENT
	kind = session_kind
	connecting = true
	last_error = ""
	session_changed.emit()
	return OK


## Closes the connection and returns the lobby to local split screen.
func leave() -> void:
	if role == Role.OFFLINE:
		return
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE
	connecting = false
	in_race = false
	local_slot = -1
	_announcer = null
	GameState.mode = GameState.Mode.MULTI
	_reset_slots()
	session_changed.emit()
	lobby_updated.emit()


## Slot 0 is this machine's player; the others are empty.
func _reset_slots() -> void:
	for i: int in GameState.MAX_PLAYERS:
		var setup: PlayerSetup = GameState.players[i]
		setup.joined = i == 0
		setup.is_ai = false
		setup.is_ready = false
		setup.peer_id = 0
		setup.stand_in = false
		# Back to this machine's own names for split screen.
		setup.display_name = Settings.get_player_name(i)


# --- Discovery -----------------------------------------------------------

## Starts listening for games announced on the LAN.
func start_discovery() -> void:
	if _listener != null:
		return
	_listener = PacketPeerUDP.new()
	for offset: int in DISCOVERY_PORT_COUNT:
		if _listener.bind(DISCOVERY_PORT + offset) == OK:
			return
	# Every port is held by other copies of the game or other programs.
	_listener = null


func stop_discovery() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	servers.clear()
	servers_changed.emit()


func _process(delta: float) -> void:
	if _announcer != null and role == Role.HOST:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_timer = BROADCAST_INTERVAL
			_announce()
	if _listener != null:
		_read_announcements()


func _announce() -> void:
	var message: Dictionary = {
		"game": GAME_ID, "port": DEFAULT_PORT, "track": GameState.selected_track.display_name,
		"players": GameState.get_joined_players().size(), "racing": in_race,
	}
	var packet: PackedByteArray = JSON.stringify(message).to_utf8_buffer()
	for offset: int in DISCOVERY_PORT_COUNT:
		_announcer.set_dest_address(BROADCAST_ADDRESS, DISCOVERY_PORT + offset)
		_announcer.put_packet(packet)


func _read_announcements() -> void:
	var changed: bool = false
	var now: float = Time.get_ticks_msec() / 1000.0
	while _listener.get_available_packet_count() > 0:
		var packet: PackedByteArray = _listener.get_packet()
		var address: String = _listener.get_packet_ip()
		var message: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not message is Dictionary or message.get("game", "") != GAME_ID:
			continue
		var port: int = int(message.get("port", DEFAULT_PORT))
		var key: String = "%s:%d" % [address, port]
		changed = changed or not servers.has(key)
		servers[key] = {
			"address": address, "port": port, "track": str(message.get("track", "")),
			"players": int(message.get("players", 1)), "racing": bool(message.get("racing", false)),
			"expires": now + SERVER_EXPIRY,
		}
	for key: String in servers.keys():
		if servers[key]["expires"] < now:
			servers.erase(key)
			changed = true
	if changed:
		servers_changed.emit()


# --- Lobby state ---------------------------------------------------------

func serialize_lobby() -> Dictionary:
	var slots: Array = []
	for setup: PlayerSetup in GameState.players:
		slots.append({
			"joined": setup.joined, "ai": setup.is_ai, "ready": setup.is_ready, "peer": setup.peer_id,
			"car": Catalog.CARS.find(setup.stats), "color": setup.color.to_html(), "pattern": setup.pattern,
			"name": setup.display_name,
		})
	return {
		"slots": slots, "track": Catalog.TRACKS.find(GameState.selected_track), "laps": GameState.lap_count,
		"weather": GameState.weather, "time": GameState.time_of_day, "damage": Settings.damage_enabled,
	}


func _apply_lobby(state: Dictionary) -> void:
	var slots: Array = state["slots"]
	local_slot = -1
	for i: int in mini(slots.size(), GameState.MAX_PLAYERS):
		var data: Dictionary = slots[i]
		var setup: PlayerSetup = GameState.players[i]
		setup.joined = data["joined"]
		setup.is_ai = data["ai"]
		setup.is_ready = data["ready"]
		setup.peer_id = data["peer"]
		setup.stats = Catalog.CARS[clampi(data["car"], 0, Catalog.CARS.size() - 1)]
		setup.color = Color.html(data["color"])
		setup.pattern = data["pattern"]
		setup.display_name = GameState.sanitize_name(str(data.get("name", "")))
		if setup.joined and setup.peer_id == multiplayer.get_unique_id():
			local_slot = i
	GameState.selected_track = Catalog.TRACKS[clampi(state["track"], 0, Catalog.TRACKS.size() - 1)]
	GameState.lap_count = state["laps"]
	GameState.weather = state["weather"]
	GameState.time_of_day = state["time"]
	remote_damage = state["damage"]
	lobby_updated.emit()


## Host: sends the current lobby to every client.
func broadcast_lobby() -> void:
	if role != Role.HOST:
		return
	remote_damage = Settings.damage_enabled
	_receive_lobby.rpc(serialize_lobby())
	lobby_updated.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_lobby(state: Dictionary) -> void:
	_apply_lobby(state)


## Sends this machine's car, paint and pattern to the host.
func submit_local_setup() -> void:
	if local_slot < 0:
		return
	var setup: PlayerSetup = GameState.players[local_slot]
	if role == Role.HOST:
		broadcast_lobby()
	elif role == Role.CLIENT:
		_request_setup.rpc_id(
			HOST_PEER_ID, Catalog.CARS.find(setup.stats), setup.color.to_html(), setup.pattern, setup.display_name
		)


func set_local_ready(is_ready: bool) -> void:
	if local_slot < 0:
		return
	if role == Role.HOST:
		GameState.players[local_slot].is_ready = is_ready
		broadcast_lobby()
	elif role == Role.CLIENT:
		_request_ready.rpc_id(HOST_PEER_ID, is_ready)


## Host: fills an empty slot with a computer driver, or removes one.
func set_slot_ai(slot: int, enabled: bool) -> void:
	if role != Role.HOST or slot == local_slot:
		return
	var setup: PlayerSetup = GameState.players[slot]
	if enabled and not setup.joined:
		setup.joined = true
		setup.is_ai = true
		setup.is_ready = true
		setup.peer_id = 0
		setup.stats = Catalog.CARS.pick_random()
		setup.color = GameState.get_player_color(slot)
		setup.pattern = PlayerSetup.random_pattern()
	elif not enabled and setup.is_ai:
		setup.joined = false
		setup.is_ai = false
	broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _request_setup(car_index: int, color_html: String, pattern: int, player_name: String) -> void:
	var slot: int = _get_sender_slot()
	if slot < 0:
		return
	GameState.players[slot].display_name = GameState.sanitize_name(player_name)
	var setup: PlayerSetup = GameState.players[slot]
	setup.stats = Catalog.CARS[clampi(car_index, 0, Catalog.CARS.size() - 1)]
	setup.color = Color.html(color_html)
	setup.pattern = clampi(pattern, 0, PlayerSetup.Pattern.size() - 1) as PlayerSetup.Pattern
	broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _request_ready(is_ready: bool) -> void:
	var slot: int = _get_sender_slot()
	if slot >= 0:
		GameState.players[slot].is_ready = is_ready
		broadcast_lobby()


## Slot of the client that sent the current RPC, or -1.
func _get_sender_slot() -> int:
	return get_slot_of_peer(multiplayer.get_remote_sender_id())


func get_slot_of_peer(peer_id: int) -> int:
	for i: int in GameState.MAX_PLAYERS:
		var setup: PlayerSetup = GameState.players[i]
		if setup.joined and not setup.is_ai and setup.peer_id == peer_id:
			return i
	return -1


# --- Race flow -----------------------------------------------------------

## Host: everyone into the race with the current lobby.
func start_race() -> void:
	if role != Role.HOST:
		return
	in_race = true
	_loaded_peers.clear()
	_begin_race.rpc(serialize_lobby())
	GameState.start_race()


## Host: clients that have reported the current race as loaded.
func get_loaded_peers() -> Array[int]:
	return _loaded_peers


## Client: tells the host this machine has the race loaded.
func report_race_loaded() -> void:
	if role == Role.CLIENT:
		_race_loaded.rpc_id(HOST_PEER_ID)


## Client: this tick's driving input for the host's race. Goes through this
## autoload so a packet still in flight when the host leaves the race lands
## somewhere instead of on a missing node.
func send_race_input(input: PlayerInput) -> void:
	if role == Role.CLIENT and not connecting:
		_race_input.rpc_id(HOST_PEER_ID, input.throttle, input.brake, input.steer, input.handbrake, input.is_reset_held())


## Client: leaving the race for the lobby while it goes on.
func send_left_race() -> void:
	if role == Role.CLIENT and not connecting:
		_left_race.rpc_id(HOST_PEER_ID)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _race_input(throttle: float, brake: float, steer: float, handbrake: bool, reset_held: bool) -> void:
	if race_sync != null and is_instance_valid(race_sync):
		race_sync.receive_input(multiplayer.get_remote_sender_id(), throttle, brake, steer, handbrake, reset_held)


@rpc("any_peer", "call_remote", "reliable")
func _left_race() -> void:
	if race_sync != null and is_instance_valid(race_sync):
		race_sync.receive_left(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _race_loaded() -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	if role != Role.HOST or not in_race or _loaded_peers.has(peer_id):
		return
	_loaded_peers.append(peer_id)
	race_loaded.emit(peer_id)


## Host: everyone back to the lobby, ready flags cleared.
func return_to_lobby() -> void:
	if role != Role.HOST:
		return
	in_race = false
	for setup: PlayerSetup in GameState.players:
		if setup.stand_in:
			# A computer driver that only finished the race for a player who dropped out.
			setup.joined = false
			setup.is_ai = false
			setup.stand_in = false
		elif not setup.is_ai:
			setup.is_ready = false
	_end_race.rpc()
	broadcast_lobby()
	go_to_lobby()


func go_to_lobby() -> void:
	GameState.go_to_menu(MenuScreen.LOBBY, {"tab": int(kind) + 1})


@rpc("authority", "call_remote", "reliable")
func _begin_race(state: Dictionary) -> void:
	_apply_lobby(state)
	in_race = true
	GameState.start_race()


@rpc("authority", "call_remote", "reliable")
func _end_race() -> void:
	in_race = false
	go_to_lobby()


# --- Connection events ---------------------------------------------------

func _on_connected_to_server() -> void:
	connecting = false
	GameState.mode = GameState.Mode.NET
	session_changed.emit()
	_register.rpc_id(HOST_PEER_ID, Settings.get_player_name(0))


## Host: a client introduces itself and gets the first free slot.
@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	if in_race:
		_reject(peer_id, tr("Kisa on käynnissä, yritä hetken päästä uudelleen"))
		return
	for i: int in range(1, GameState.MAX_PLAYERS):
		var setup: PlayerSetup = GameState.players[i]
		if not setup.joined:
			setup.joined = true
			setup.is_ai = false
			setup.is_ready = false
			setup.peer_id = peer_id
			setup.stats = Catalog.get_default_car()
			setup.color = GameState.get_player_color(i)
			setup.display_name = GameState.sanitize_name(player_name)
			broadcast_lobby()
			return
	_reject(peer_id, tr("Peli on täynnä"))


func _reject(peer_id: int, reason: String) -> void:
	_rejected.rpc_id(peer_id, reason)
	await get_tree().create_timer(REJECT_GRACE).timeout
	var peer: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null and role == Role.HOST:
		peer.disconnect_peer(peer_id)


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	leave()
	last_error = reason
	session_changed.emit()


func _on_peer_connected(_peer_id: int) -> void:
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	if role != Role.HOST:
		return
	var slot: int = get_slot_of_peer(peer_id)
	if slot < 0:
		return
	var setup: PlayerSetup = GameState.players[slot]
	if in_race:
		# The car stays on the track with the computer at the wheel until the
		# race is over; then the slot is freed for whoever joins next.
		setup.is_ai = true
		setup.stand_in = true
		setup.peer_id = 0
	else:
		setup.joined = false
		setup.peer_id = 0
	peer_left.emit(slot)
	broadcast_lobby()


func _on_connection_failed() -> void:
	leave()
	last_error = tr("Yhteyttä peliin ei saatu")
	session_changed.emit()


func _on_server_disconnected() -> void:
	var was_racing: bool = in_race
	leave()
	last_error = tr("Yhteys isäntään katkesi")
	session_changed.emit()
	if was_racing or get_tree().current_scene == null or get_tree().current_scene.name != "MenuRoot":
		go_to_lobby()
