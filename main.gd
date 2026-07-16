extends Node2D

@onready var tile_map: TileMap = $TileMap
@onready var camera: Camera2D = $Camera2D
@onready var build_ui: CanvasLayer = $BuildUI

const TILE_SIZE: int = PlanetGenerator.TILE_SIZE
const WORLD_SIZE: int = PlanetGenerator.WORLD_SIZE

const DEFAULT_SERVER_IP: String = "192.168.0.102"
const DEFAULT_SERVER_PORT: int = 7777
const RECONNECT_DELAY: float = 3.0
const MAX_RECONNECT_ATTEMPTS: int = 10

var building_scene = preload("res://building.tscn")
var blueprint_scene = preload("res://building.tscn")
var villager_scene = preload("res://villager.tscn")
var client_buildings: Dictionary = {}
var client_blueprints: Dictionary = {}
var client_stockpiles: Dictionary = {}
var client_villagers: Dictionary = {}
var client_resources: Dictionary = {"wood": 0, "food": 0, "stone": 0}
var is_server: bool = false
var camera_frames: int = 0
var camera_speed: float = 1200.0
var zoom_speed: float = 0.1
var world_data: Array = []
var chunk_manager: ChunkManager = null
var reconnect_attempts: int = 0
var target_server_ip: String = ""
var target_server_port: int = 7777

# Stockpile drag selection
var is_dragging_stockpile: bool = false
var drag_start_tile: Vector2i = Vector2i(-1, -1)
var drag_current_tile: Vector2i = Vector2i(-1, -1)

func _ready():
	is_server = OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless"

	if is_server:
		print("Starting DEDICATED SERVER mode")
		Network.start_server()
		GameState.load_world()
		# Starting resources are now placed into the first stockpile, not globally
		print("Server: waiting for first stockpile for starting resources")
	else:
		print("Starting CLIENT mode")
		setup_client()
		_parse_server_args()

func setup_client():
	Network.building_placed.connect(_on_building_placed)
	Network.blueprint_placed.connect(_on_blueprint_placed)
	Network.stockpile_added.connect(_on_stockpile_added)
	Network.full_sync.connect(_on_full_sync)
	Network.villager_sync.connect(_on_villager_sync)
	Network.resource_sync.connect(_on_resource_sync)
	Network.world_reset.connect(_on_world_reset)
	build_ui.build_type_selected.connect(_on_build_type_selected)
	build_ui.reset_requested.connect(_on_reset_requested)
	build_ui.spawn_requested.connect(_on_spawn_requested)

var selected_build_type: int = -1

func _on_build_type_selected(type_id: int):
	selected_build_type = type_id
	print("Client selected build type: ", type_id)

func _parse_server_args():
	var server_ip = DEFAULT_SERVER_IP
	var server_port = DEFAULT_SERVER_PORT
	var args = OS.get_cmdline_args()
	print("[CLIENT] raw cmdline args: ", args)
	var positional: Array = []
	var i = 0
	while i < args.size():
		if args[i] == "--server-ip" and i + 1 < args.size():
			server_ip = args[i + 1]
			i += 2
		elif args[i] == "--server-port" and i + 1 < args.size():
			server_port = int(args[i + 1])
			i += 2
		elif args[i] == "--scene" and i + 1 < args.size():
			i += 2
		elif not args[i].begins_with("--"):
			positional.append(args[i])
			i += 1
		else:
			i += 1
	if positional.size() >= 1:
		server_ip = positional[0]
	if positional.size() >= 2:
		server_port = int(positional[1])
	target_server_ip = server_ip
	target_server_port = server_port
	print("[CLIENT] parsed server ", target_server_ip, ":", target_server_port)
	multiplayer.connected_to_server.connect(_on_client_connected)
	multiplayer.connection_failed.connect(_on_client_connection_failed)
	multiplayer.server_disconnected.connect(_on_client_disconnected)
	_start_client_connection()

func _start_client_connection():
	reconnect_attempts += 1
	print("[CLIENT] connection attempt ", reconnect_attempts, "/", MAX_RECONNECT_ATTEMPTS, " to ", target_server_ip, ":", target_server_port)
	if not Network.start_client(target_server_ip, target_server_port):
		_on_client_connection_failed()

func _on_client_connected():
	reconnect_attempts = 0
	print("[CLIENT] connected to server, peer id: ", multiplayer.get_unique_id())

func _on_client_connection_failed():
	print("[CLIENT] connection failed to ", target_server_ip, ":", target_server_port, " attempt ", reconnect_attempts)
	_schedule_reconnect()

func _on_client_disconnected():
	print("[CLIENT] disconnected from server")
	_schedule_reconnect()

func _schedule_reconnect():
	if reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
		print("[CLIENT] giving up after ", reconnect_attempts, " attempts")
		return
	print("[CLIENT] retrying in ", RECONNECT_DELAY, " seconds...")
	await get_tree().create_timer(RECONNECT_DELAY).timeout
	_start_client_connection()

func _process(delta):
	if is_server:
		return
	_handle_camera_input(delta)
	if camera and camera_frames < 60:
		camera.make_current()
		camera.reset_smoothing()
		camera.global_position = Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2)
		camera.offset = Vector2.ZERO
		camera.force_update_scroll()
		camera_frames += 1
	if chunk_manager:
		chunk_manager.update(camera.global_position)

func _handle_camera_input(delta):
	if not camera:
		return
	var direction := Vector2.ZERO
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		direction.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		direction.y += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		direction.x += 1
	if direction != Vector2.ZERO:
		direction = direction.normalized()
	camera.position += direction * camera_speed * delta / camera.zoom.x

func _input(event):
	if is_server:
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered != null and hovered != tile_map:
			return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = camera.zoom * (1.0 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = camera.zoom / (1.0 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
			if tile.x < 0 or tile.x >= WORLD_SIZE or tile.y < 0 or tile.y >= WORLD_SIZE:
				return
			if selected_build_type == PlanetGenerator.BuildingType.STOCKPILE:
				if event.pressed:
					is_dragging_stockpile = true
					drag_start_tile = tile
					drag_current_tile = tile
				else:
					if is_dragging_stockpile:
						is_dragging_stockpile = false
						var top_left := Vector2i(min(drag_start_tile.x, drag_current_tile.x), min(drag_start_tile.y, drag_current_tile.y))
						var bottom_right := Vector2i(max(drag_start_tile.x, drag_current_tile.x), max(drag_start_tile.y, drag_current_tile.y))
						var size := Vector2i(bottom_right.x - top_left.x + 1, bottom_right.y - top_left.y + 1)
						if size.x > 0 and size.y > 0:
							print("Client requesting stockpile at ", top_left, " size ", size)
							Network.ask_stockpile(top_left, size)
						drag_start_tile = Vector2i(-1, -1)
						drag_current_tile = Vector2i(-1, -1)
			else:
				if event.pressed:
					print("Client clicked tile: ", tile, " type: ", selected_build_type)
					Network.ask_build(tile, selected_build_type)
	elif event is InputEventMouseMotion and is_dragging_stockpile:
		var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
		if tile.x >= 0 and tile.x < WORLD_SIZE and tile.y >= 0 and tile.y < WORLD_SIZE:
			drag_current_tile = tile
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		camera.position = Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2)

func _draw():
	if is_dragging_stockpile and drag_start_tile.x >= 0 and drag_current_tile.x >= 0:
		var top_left := Vector2i(min(drag_start_tile.x, drag_current_tile.x), min(drag_start_tile.y, drag_current_tile.y))
		var bottom_right := Vector2i(max(drag_start_tile.x, drag_current_tile.x), max(drag_start_tile.y, drag_current_tile.y))
		var rect_pos := Vector2(top_left.x * TILE_SIZE, top_left.y * TILE_SIZE)
		var rect_size := Vector2((bottom_right.x - top_left.x + 1) * TILE_SIZE, (bottom_right.y - top_left.y + 1) * TILE_SIZE)
		draw_rect(Rect2(rect_pos, rect_size), Color(0.9, 0.8, 0.3, 0.4), true)
		draw_rect(Rect2(rect_pos, rect_size), Color(0.9, 0.8, 0.3, 0.8), false, 2.0)

func _on_blueprint_placed(pos: Vector2i, type_id: int):
	if client_blueprints.has(pos) or client_buildings.has(pos):
		return
	var b = blueprint_scene.instantiate()
	b.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
	var sprite := b.get_node("Sprite") as Sprite2D
	if sprite:
		sprite.region_rect = PlanetGenerator.building_type_to_rect(type_id)
		sprite.modulate = Color(1, 1, 1, 0.5)
	add_child(b)
	client_blueprints[pos] = b
	print("Client placed blueprint at ", pos, " type ", type_id)

func _on_building_placed(pos: Vector2i, type_id: int):
	if client_buildings.has(pos):
		return
	# Remove blueprint if exists
	if client_blueprints.has(pos):
		client_blueprints[pos].queue_free()
		client_blueprints.erase(pos)
	var b = building_scene.instantiate()
	b.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
	var sprite := b.get_node("Sprite") as Sprite2D
	if sprite:
		sprite.region_rect = PlanetGenerator.building_type_to_rect(type_id)
		sprite.modulate = Color(1, 1, 1, 1)
	add_child(b)
	client_buildings[pos] = b
	print("Client placed building at ", pos, " type ", type_id)

func _on_full_sync(data: Dictionary):
	print("Client received full sync with ", data["buildings"].size(), " buildings, ", data.get("blueprints", {}).size(), " blueprints, ", data.get("stockpiles", {}).size(), " stockpiles")
	var seed_value := data.get("seed", 12345) as int
	world_data = PlanetGenerator.generate_world(seed_value)
	chunk_manager = ChunkManager.new(tile_map, world_data)
	var first_building_pos := Vector2i(-1, -1)
	for pos_str in data["buildings"]:
		var parts: PackedStringArray = pos_str.split(",")
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		_on_building_placed(pos, data["buildings"][pos_str])
		if first_building_pos.x < 0:
			first_building_pos = pos
	for pos_str in data.get("blueprints", {}):
		var parts: PackedStringArray = pos_str.split(",")
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		_on_blueprint_placed(pos, data["blueprints"][pos_str]["type"])
	for stock_id in data.get("stockpiles", {}):
		_on_stockpile_added(stock_id, data["stockpiles"][stock_id])
	if first_building_pos.x >= 0 and camera:
		var target := Vector2(first_building_pos.x * TILE_SIZE + TILE_SIZE / 2, first_building_pos.y * TILE_SIZE + TILE_SIZE / 2)
		camera.global_position = target
		camera.position = target
		camera.offset = Vector2.ZERO
		camera.make_current()
		camera.force_update_scroll()
		camera.reset_smoothing()
		camera_frames = 999
		chunk_manager.update(target)
	else:
		chunk_manager.update(Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2))
	_on_villager_sync(data.get("villagers", {}))
	_on_resource_sync(data.get("resources", {"wood": 0, "food": 0, "stone": 0}))

func _on_stockpile_added(id: String, data: Dictionary):
	print("Client: stockpile added ", id)
	# Draw a semi-transparent yellow overlay over each tile
	for key in data.get("zone", []):
		var parts: PackedStringArray = key.split(",")
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		var marker := ColorRect.new()
		marker.position = Vector2(pos.x * TILE_SIZE + 1, pos.y * TILE_SIZE + 1)
		marker.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		marker.color = Color(0.9, 0.8, 0.3, 0.25)
		marker.z_index = 1
		add_child(marker)
		if not client_stockpiles.has(id):
			client_stockpiles[id] = []
		client_stockpiles[id].append(marker)

func _on_villager_sync(villagers: Dictionary):
	for id in villagers:
		var v = villagers[id] as Dictionary
		var pos := Vector2i(int(v["pos"]["x"]), int(v["pos"]["y"]))
		var job := v["job"] as String
		if client_villagers.has(id):
			var node = client_villagers[id]
			node.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
			node.setup(job)
		else:
			var node = villager_scene.instantiate()
			node.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
			add_child(node)
			node.setup(job)
			client_villagers[id] = node

func _on_reset_requested():
	print("Client: requesting world reset")
	Network.ask_reset_world()

func _on_spawn_requested():
	print("Client: requesting villager spawn")
	Network.ask_spawn_villager()

func _on_world_reset(data: Dictionary):
	print("Client: world reset received, clearing local state")
	# Clear local buildings
	for pos in client_buildings:
		if is_instance_valid(client_buildings[pos]):
			client_buildings[pos].queue_free()
	client_buildings.clear()
	# Clear local blueprints
	for pos in client_blueprints:
		if is_instance_valid(client_blueprints[pos]):
			client_blueprints[pos].queue_free()
	client_blueprints.clear()
	# Clear local stockpile overlays
	for id in client_stockpiles:
		for marker in client_stockpiles[id]:
			if is_instance_valid(marker):
				marker.queue_free()
	client_stockpiles.clear()
	# Clear villagers
	for id in client_villagers:
		if is_instance_valid(client_villagers[id]):
			client_villagers[id].queue_free()
	client_villagers.clear()
	# Reset resources display
	client_resources = {"wood": 0, "food": 0, "stone": 0}
	# Re-apply sync
	_on_full_sync(data)

func _on_resource_sync(resources: Dictionary):
	client_resources = resources.duplicate()
	print("Client resources: wood=", client_resources.get("wood", 0), " food=", client_resources.get("food", 0), " stone=", client_resources.get("stone", 0))
