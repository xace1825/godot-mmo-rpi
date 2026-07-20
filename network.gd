extends Node

signal full_sync(data: Dictionary)
signal villager_sync(villagers: Dictionary)
signal resource_sync(resources: Dictionary)
signal blueprint_placed(pos: Vector2i, type_id: int)
signal building_placed(pos: Vector2i, type_id: int)
signal stockpile_added(id: String, data: Dictionary)
signal world_reset(data: Dictionary)
signal ground_items_sync(items: Dictionary)
signal day_night_sync(time_of_day: float, day_count: int)

const DEFAULT_PORT: int = 7777

var peer: ENetMultiplayerPeer
var last_full_sync: Dictionary = {}

func _ready():
	Engine.time_scale = 5.0
	print("Game speed set to 5x for faster testing")
	multiplayer.peer_connected.connect(_on_peer_connected)
	GameState.ensure_world_generated()
	if not FileAccess.file_exists(GameState.SAVE_PATH):
		GameState.create_default_stockpile()
		print("Server: created default starting stockpile")
	else:
		print("Server: save file exists, skipping default stockpile creation")

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
	last_full_sync = data
	full_sync.emit(data)

@rpc("authority", "call_remote", "unreliable")
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

@rpc("authority", "call_remote", "reliable")
func sync_ground_items(items: Dictionary):
	ground_items_sync.emit(items)

@rpc("authority", "call_remote", "unreliable")
func sync_day_night(time_of_day: float, day_count: int):
	day_night_sync.emit(time_of_day, day_count)

func _is_peer_connected() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	var p := multiplayer.multiplayer_peer
	if p == null:
		return false
	if p is ENetMultiplayerPeer:
		return p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	return true

func ask_build(tile_pos: Vector2i, building_type: int = -1):
	if multiplayer.is_server():
		return
	if not _is_peer_connected():
		push_warning("Cannot ask_build: peer not connected")
		return
	rpc_id(1, "request_build", tile_pos, building_type)

func ask_place_blueprint(tile_pos: Vector2i, building_type: int = -1):
	ask_build(tile_pos, building_type)

@rpc("any_peer", "call_remote", "reliable")
func request_place_blueprint(tile_pos: Vector2i, building_type: int = -1):
	request_build(tile_pos, building_type)

@rpc("any_peer", "call_remote", "reliable")
func request_build(tile_pos: Vector2i, building_type: int = -1):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	print("Server: build request from ", peer_id, " at ", tile_pos, " type ", building_type)
	var type_id := GameState.add_blueprint(tile_pos, building_type)
	if type_id >= 0:
		# Disabled: builders are spawned manually via SPAWN button
		# GameState.spawn_builder_for_blueprint(tile_pos)
		rpc("place_blueprint", tile_pos, type_id)
		_broadcast_state()

func ask_stockpile(topleft: Vector2i, size: Vector2i):
	if multiplayer.is_server():
		return
	if not _is_peer_connected():
		push_warning("Cannot ask_stockpile: peer not connected")
		return
	rpc_id(1, "request_stockpile", topleft, size)

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

func broadcast_villager_sync():
	if multiplayer.has_multiplayer_peer():
		rpc("sync_villagers", GameState.villagers.duplicate())

func broadcast_resource_sync():
	if multiplayer.has_multiplayer_peer():
		rpc("sync_resources", GameState.resources.duplicate())

func broadcast_blueprint_placed(pos: Vector2i, type_id: int):
	if multiplayer.has_multiplayer_peer():
		rpc("place_blueprint", pos, type_id)
		_broadcast_state()

func broadcast_building_completed(pos: Vector2i, type_id: int):
	if multiplayer.has_multiplayer_peer():
		rpc("place_building", pos, type_id)
		_broadcast_state()

func ask_spawn_villager():
	if multiplayer.is_server():
		return
	if not _is_peer_connected():
		push_warning("Cannot ask_spawn_villager: peer not connected")
		return
	rpc_id(1, "request_spawn_villager")

func ask_set_job(villager_id: String, job: String):
	if multiplayer.is_server():
		return
	if not _is_peer_connected():
		push_warning("Cannot ask_set_job: villager not connected")
		return
	rpc_id(1, "request_set_job", villager_id, job)

func ask_drop_item(pos: Vector2i, resource: String, amount: int):
	if multiplayer.is_server():
		return
	if not _is_peer_connected():
		push_warning("Cannot ask_drop_item: not connected")
		return
	rpc_id(1, "request_drop_item", pos, resource, amount)

func ask_build_room(start: Vector2i, end: Vector2i):
	if multiplayer.is_server():
		return
	if not _is_peer_connected():
		push_warning("Cannot ask_build_room: not connected")
		return
	rpc_id(1, "request_build_room", start, end)

@rpc("any_peer", "call_remote", "reliable")
func request_build_room(start: Vector2i, end: Vector2i):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	print("Server: build room request from ", peer_id, " from ", start, " to ", end)
	GameState.add_room_blueprints(start, end)

@rpc("any_peer", "call_remote", "reliable")
func request_drop_item(pos: Vector2i, resource: String, amount: int):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	print("Server: drop item request from ", peer_id, " at ", pos, " ", resource, " x", amount)
	GameState.drop_item_on_ground(pos, resource, amount)

@rpc("any_peer", "call_remote", "reliable")
func request_set_job(villager_id: String, job: String):
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	print("Server: set job request from ", peer_id, " for villager ", villager_id, " to ", job)
	if GameState.set_villager_job(villager_id, job):
		_broadcast_state()
		rpc("sync_villagers", GameState.villagers.duplicate())
		print("Server: villager ", villager_id, " job set to ", job)
	else:
		print("Server: failed to set job for ", villager_id)

@rpc("any_peer", "call_remote", "reliable")
func request_spawn_villager():
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	print("Server: spawn villager requested by peer ", peer_id)
	# Spawn at the center of the nearest non-empty stockpile so they visibly walk to work
	var pos := GameState.random_walkable_tile()
	var stock_id := GameState.find_nearest_stockpile(pos)
	if stock_id != "":
		var stock: Dictionary = GameState.stockpiles[stock_id]
		var tl := Vector2i(int(stock["topleft"]["x"]), int(stock["topleft"]["y"]))
		var br := tl + Vector2i(int(stock["size"]["x"]), int(stock["size"]["y"])) - Vector2i(1, 1)
		pos = Vector2i((tl.x + br.x) / 2, (tl.y + br.y) / 2)
	var id := GameState.spawn_villager(pos, "idle")
	if id >= 0:
		print("Server: spawned villager ", id, " at ", pos, " for peer ", peer_id)
		_broadcast_state()
		rpc("sync_villagers", GameState.villagers.duplicate())

func ask_reset_world():
	if multiplayer.is_server():
		return
	if not _is_peer_connected():
		push_warning("Cannot ask_reset_world: peer not connected")
		return
	rpc_id(1, "request_reset_world")

@rpc("any_peer", "call_remote", "reliable")
func request_reset_world():
	if not multiplayer.is_server():
		return
	print("Server: reset world requested by peer ", multiplayer.get_remote_sender_id())
	GameState.reset_world()
	GameState._recalc_total_resources()
	if multiplayer.has_multiplayer_peer():
		rpc("sync_world_reset", GameState.get_world_data())
	GameState.save_world()

@rpc("authority", "call_remote", "reliable")
func sync_world_reset(data: Dictionary):
	world_reset.emit(data)

func broadcast_stockpile_added(id: String, data: Dictionary):
	if multiplayer.has_multiplayer_peer():
		rpc("sync_stockpile", id, data.duplicate())
		_broadcast_state()

func broadcast_stockpile_update(id: String, data: Dictionary):
	if multiplayer.has_multiplayer_peer():
		rpc("sync_stockpile", id, data.duplicate())

func broadcast_ground_items_sync():
	if multiplayer.has_multiplayer_peer():
		rpc("sync_ground_items", GameState.ground_items.duplicate())
		_broadcast_state()

func broadcast_day_night_sync():
	if multiplayer.has_multiplayer_peer():
		rpc("sync_day_night", GameState.time_of_day, GameState.day_count)

func _on_peer_connected(id: int):
	print("Peer connected: ", id)
	if multiplayer.is_server():
		_broadcast_state()
		rpc_id(id, "sync_villagers", GameState.villagers.duplicate())
		rpc_id(id, "sync_day_night", GameState.time_of_day, GameState.day_count)
