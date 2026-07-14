extends Node

signal building_placed(pos: Vector2i, type_id: int)
signal blueprint_placed(pos: Vector2i, type_id: int)
signal blueprint_completed(pos: Vector2i, type_id: int)
signal full_sync(world_data: Dictionary)
signal villager_sync(villagers: Dictionary)
signal resource_sync(resources: Dictionary)

const PORT: int = 7777
const MAX_CLIENTS: int = 100
const SYNC_INTERVAL: float = 2.0

var multiplayer_peer: ENetMultiplayerPeer = null
var sync_timer: float = 0.0

func start_server():
	multiplayer_peer = ENetMultiplayerPeer.new()
	var err = multiplayer_peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("Failed to start server: %d" % err)
		return
	multiplayer.multiplayer_peer = multiplayer_peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	print("Server listening on port ", PORT)

func start_client(address: String, port: int):
	multiplayer_peer = ENetMultiplayerPeer.new()
	var err = multiplayer_peer.create_client(address, port)
	if err != OK:
		push_error("Failed to connect: %d" % err)
		return
	multiplayer.multiplayer_peer = multiplayer_peer
	print("Connecting to ", address, ":", port)

func _process(delta):
	if not multiplayer.is_server():
		return
	sync_timer += delta
	if sync_timer >= SYNC_INTERVAL:
		sync_timer -= SYNC_INTERVAL
		_broadcast_state()

func _broadcast_state():
	var data := GameState.get_world_data()
	if multiplayer.has_multiplayer_peer():
		rpc("sync_world_state", data)

func broadcast_building_completed(pos: Vector2i, type_id: int):
	if multiplayer.has_multiplayer_peer():
		rpc("place_building", pos, type_id)

func _on_peer_connected(id: int):
	print("Peer connected: ", id)
	rpc_id(id, "sync_world", GameState.get_world_data())

func ask_build(tile_pos: Vector2i):
	if multiplayer.is_server():
		return
	rpc_id(1, "request_build", tile_pos)

@rpc("any_peer", "call_remote", "reliable")
func request_build(tile_pos: Vector2i):
	print("Server: build request at ", tile_pos)
	var type_id := GameState.add_blueprint(tile_pos)
	print("Server: blueprint success=", type_id)
	if type_id >= 0:
		var builder := GameState.spawn_builder_for_blueprint(tile_pos)
		GameState.save_world()
		var key := "%d,%d" % [tile_pos.x, tile_pos.y]
		rpc("place_blueprint", tile_pos, type_id)
		_broadcast_state()

@rpc("authority", "call_local", "reliable")
func place_blueprint(pos: Vector2i, type_id: int):
	blueprint_placed.emit(pos, type_id)

@rpc("authority", "call_remote", "reliable")
func place_building(pos: Vector2i, type_id: int):
	building_placed.emit(pos, type_id)

@rpc("authority", "call_remote", "reliable")
func sync_world(world_data: Dictionary):
	print("Client: received sync_world with ", world_data["buildings"].size(), " buildings, ", world_data.get("blueprints", {}).size(), " blueprints")
	full_sync.emit(world_data)

@rpc("authority", "call_remote", "reliable")
func sync_world_state(world_data: Dictionary):
	villager_sync.emit(world_data.get("villagers", {}))
	resource_sync.emit(world_data.get("resources", {"wood": 0, "food": 0, "stone": 0}))

@rpc("authority", "call_local", "reliable")
func spawn_villager(villager: Dictionary):
	pass
