extends Node

signal full_sync(data: Dictionary)
signal villager_sync(villagers: Dictionary)
signal resource_sync(resources: Dictionary)
signal blueprint_placed(pos: Vector2i, type_id: int)
signal building_placed(pos: Vector2i, type_id: int)
signal stockpile_added(id: String, data: Dictionary)

const DEFAULT_PORT: int = 7777

var peer: ENetMultiplayerPeer

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)

func start_server(port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("Failed to create server: %d" % err)
		return false
	multiplayer.multiplayer_peer = peer
	print("Server listening on port ", port)
	return true

func start_client(ip: String, port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to create client: %d" % err)
		return false
	multiplayer.multiplayer_peer = peer
	print("Client connecting to ", ip, ":", port)
	return true

func is_server() -> bool:
	return multiplayer.is_server()

@rpc("authority", "call_remote", "reliable")
func sync_world_state(data: Dictionary):
	full_sync.emit(data)

@rpc("authority", "call_remote", "reliable")
func sync_villagers(villagers: Dictionary):
	villager_sync.emit(villagers)

@rpc("authority", "call_remote", "reliable")
func sync_resources(resources: Dictionary):
	resource_sync.emit(resources)

@rpc("authority", "call_remote", "reliable")
func sync_stockpile(id: String, data: Dictionary):
	stockpile_added.emit(id, data)

@rpc("authority", "call_remote", "reliable")
func place_building(pos: Vector2i, type_id: int):
	building_placed.emit(pos, type_id)

@rpc("authority", "call_remote", "reliable")
func place_blueprint(pos: Vector2i, type_id: int):
	blueprint_placed.emit(pos, type_id)

func ask_build(tile_pos: Vector2i, building_type: int = -1):
	if multiplayer.is_server():
		return
	rpc_id(1, "request_build", tile_pos, building_type)

func ask_stockpile(topleft: Vector2i, size: Vector2i):
	if multiplayer.is_server():
		return
	rpc_id(1, "request_stockpile", topleft, size)

@rpc("any_peer", "call_remote", "reliable")
func request_build(tile_pos: Vector2i, building_type: int = -1):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	print("Server: build request from ", peer_id, " at ", tile_pos, " type ", building_type)
	var type_id := GameState.add_blueprint(tile_pos, building_type)
	if type_id >= 0:
		GameState.spawn_builder_for_blueprint(tile_pos)
		rpc("place_blueprint", tile_pos, type_id)
		_broadcast_state()

@rpc("any_peer", "call_remote", "reliable")
func request_stockpile(topleft: Vector2i, size: Vector2i):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	print("Server: stockpile request from ", peer_id, " at ", topleft, " size ", size)
	GameState.add_stockpile(topleft, size)
	_broadcast_state()

func _broadcast_state():
	var data := GameState.get_world_data()
	if multiplayer.has_multiplayer_peer():
		rpc("sync_world_state", data)

func broadcast_resource_sync():
	if multiplayer.has_multiplayer_peer():
		rpc("sync_resources", GameState.resources.duplicate())

func broadcast_building_completed(pos: Vector2i, type_id: int):
	if multiplayer.has_multiplayer_peer():
		rpc("place_building", pos, type_id)
		_broadcast_state()

func broadcast_stockpile_added(id: String, data: Dictionary):
	if multiplayer.has_multiplayer_peer():
		rpc("sync_stockpile", id, data.duplicate())
		_broadcast_state()

func _on_peer_connected(id: int):
	print("Peer connected: ", id)
	if multiplayer.is_server():
		_broadcast_state()
		rpc_id(id, "sync_villagers", GameState.villagers.duplicate())
