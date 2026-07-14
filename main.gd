extends Node2D

@onready var tile_map: TileMap = $TileMap
@onready var camera: Camera2D = $Camera2D

const TILE_SIZE: int = PlanetGenerator.TILE_SIZE
const WORLD_SIZE: int = PlanetGenerator.WORLD_SIZE

const DEFAULT_SERVER_IP: String = "192.168.0.102"
const DEFAULT_SERVER_PORT: int = 7777

var building_scene = preload("res://building.tscn")
var villager_scene = preload("res://villager.tscn")
var client_buildings: Dictionary = {}
var client_villagers: Dictionary = {}
var client_resources: Dictionary = {"wood": 0, "food": 0, "stone": 0}
var is_server: bool = false
var camera_frames: int = 0
var camera_speed: float = 1200.0
var zoom_speed: float = 0.1
var world_data: Array = []
var chunk_manager: ChunkManager = null

func _ready():
	is_server = OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless"

	if is_server:
		print("Starting DEDICATED SERVER mode")
		Network.start_server()
		GameState.load_world()
	else:
		print("Starting CLIENT mode")
		setup_client()
		_parse_server_args()

func _parse_server_args():
	var server_ip = DEFAULT_SERVER_IP
	var server_port = DEFAULT_SERVER_PORT
	var args = OS.get_cmdline_args()
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
	print("Connecting to server ", server_ip, ":", server_port)
	Network.start_client(server_ip, server_port)

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
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = camera.zoom * (1.0 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = camera.zoom / (1.0 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
			if tile.x >= 0 and tile.x < WORLD_SIZE and tile.y >= 0 and tile.y < WORLD_SIZE:
				print("Client clicked tile: ", tile)
				Network.ask_build(tile)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		camera.position = Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2)

func setup_client():
	Network.building_placed.connect(_on_building_placed)
	Network.full_sync.connect(_on_full_sync)
	Network.villager_sync.connect(_on_villager_sync)
	Network.resource_sync.connect(_on_resource_sync)

func _on_building_placed(pos: Vector2i, type_id: int):
	if client_buildings.has(pos):
		return
	var b = building_scene.instantiate()
	b.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
	var sprite := b.get_node("Sprite") as Sprite2D
	if sprite:
		sprite.region_rect = PlanetGenerator.building_type_to_rect(type_id)
	add_child(b)
	client_buildings[pos] = b
	print("Client placed building at ", pos, " type ", type_id)

func _on_full_sync(data: Dictionary):
	print("Client received full sync with ", data["buildings"].size(), " buildings")
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
			node.setup(job)
			add_child(node)
			client_villagers[id] = node

func _on_resource_sync(resources: Dictionary):
	client_resources = resources.duplicate()
	print("Client resources: wood=", client_resources.get("wood", 0), " food=", client_resources.get("food", 0), " stone=", client_resources.get("stone", 0))

func _draw():
	pass
