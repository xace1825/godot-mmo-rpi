extends Node

signal building_placed(pos: Vector2i, type_id: int)
signal full_sync(world_data: Dictionary)

const PORT: int = 7777
const MAX_CLIENTS: int = 100

var multiplayer_peer: ENetMultiplayerPeer = null

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

func _on_peer_connected(id: int):
	print("Peer connected: ", id)
	rpc_id(id, "sync_world", GameState.get_world_data())

func ask_build(tile_pos: Vector2i):
	# Clients send build requests to the server (peer id 1)
	if multiplayer.is_server():
		return
	rpc_id(1, "request_build", tile_pos)

@rpc("any_peer", "call_remote", "reliable")
func request_build(tile_pos: Vector2i):
	print("request_build called on server at ", tile_pos)
	if not multiplayer.is_server():
		return
	print("Server: build request at ", tile_pos)
	var success = GameState.add_building(tile_pos)
	print("Server: build success=", success)
	if success:
		GameState.save_world()
		var key := "%d,%d" % [tile_pos.x, tile_pos.y]
		var type_id := GameState.buildings[key] as int
		rpc("place_building", tile_pos, type_id)

@rpc("authority", "call_local", "reliable")
func place_building(pos: Vector2i, type_id: int):
	print("place_building called at ", pos)
	building_placed.emit(pos, type_id)

@rpc("authority", "call_remote", "reliable")
func sync_world(world_data: Dictionary):
	print("Client: received sync_world with ", world_data["buildings"].size(), " buildings")
	full_sync.emit(world_data)
