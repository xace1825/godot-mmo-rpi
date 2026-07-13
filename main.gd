extends Node2D

@onready var tile_map: TileMap = $TileMap
@onready var camera: Camera2D = $Camera2D

const TILE_SIZE: int = 32
const WORLD_SIZE: int = 64

const DEFAULT_SERVER_IP: String = "192.168.0.102"
const DEFAULT_SERVER_PORT: int = 7777

var building_scene = preload("res://building.tscn")
var client_buildings: Dictionary = {}
var is_server: bool = false

func _ready():
	is_server = OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless"
	
	if is_server:
		print("Starting DEDICATED SERVER mode")
		Network.start_server()
		GameState.load_world()
	else:
		print("Starting CLIENT mode")
		setup_client()
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

func setup_client():
    for x in range(WORLD_SIZE):
        for y in range(WORLD_SIZE):
            tile_map.set_cell(0, Vector2i(x, y), 0, Vector2i(0, 0))
    camera.position = Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2)
    Network.building_placed.connect(_on_building_placed)
    Network.full_sync.connect(_on_full_sync)

func _input(event):
    if is_server:
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
        if tile.x >= 0 and tile.x < WORLD_SIZE and tile.y >= 0 and tile.y < WORLD_SIZE:
            print("Client clicked tile: ", tile)
            Network.request_build(tile)

func _on_building_placed(pos: Vector2i, type_id: int):
    if client_buildings.has(pos):
        return
    var b = building_scene.instantiate()
    b.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
    add_child(b)
    client_buildings[pos] = b
    print("Client placed building at ", pos)

func _on_full_sync(world_data: Dictionary):
    print("Client received full sync with ", world_data["buildings"].size(), " buildings")
    for pos_str in world_data["buildings"]:
        var parts = pos_str.split(",")
        var pos = Vector2i(int(parts[0]), int(parts[1]))
        _on_building_placed(pos, world_data["buildings"][pos_str])
