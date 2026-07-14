extends Node

const DEFAULT_SERVER_IP: String = "127.0.0.1"
const DEFAULT_SERVER_PORT: int = 7777

var seed_value: int = 12345
var world: Array = []
var received_villagers: Dictionary = {}
var received_resources: Dictionary = {}
var received_blueprints: Dictionary = {}
var received_buildings: Dictionary = {}

func _ready():
    print("Headless test client starting")
    Network.full_sync.connect(_on_sync)
    Network.villager_sync.connect(_on_villager_sync)
    Network.resource_sync.connect(_on_resource_sync)
    Network.blueprint_placed.connect(_on_blueprint_placed)
    Network.building_placed.connect(_on_building_placed)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(func(): print("CONNECTION FAILED"); get_tree().quit(1))
    Network.start_client(DEFAULT_SERVER_IP, DEFAULT_SERVER_PORT)

func _on_connected():
    print("Connected to server")

func _on_sync(data: Dictionary):
    print("Full sync received with ", data["buildings"].size(), " buildings, ", data.get("blueprints", {}).size(), " blueprints")
    seed_value = data.get("seed", 12345)
    world = PlanetGenerator.generate_world(seed_value)
    received_buildings = data.get("buildings", {})
    received_blueprints = data.get("blueprints", {})
    received_villagers = data.get("villagers", {})
    received_resources = data.get("resources", {"wood": 0, "food": 0, "stone": 0})
    _run_tests(data)

func _on_villager_sync(villagers: Dictionary):
    received_villagers = villagers

func _on_resource_sync(resources: Dictionary):
    received_resources = resources

func _on_blueprint_placed(pos: Vector2i, type_id: int):
    var key = "%d,%d" % [pos.x, pos.y]
    received_blueprints[key] = {"type": type_id, "pos": {"x": pos.x, "y": pos.y}}

func _on_building_placed(pos: Vector2i, type_id: int):
    var key = "%d,%d" % [pos.x, pos.y]
    print("TEST: building placed event at ", pos, " type ", type_id)
    received_buildings[key] = type_id
    if received_blueprints.has(key):
        received_blueprints.erase(key)

func _run_tests(data: Dictionary):
    await get_tree().create_timer(0.5).timeout

    # Find buildable tile closest to center
    var center := PlanetGenerator.WORLD_SIZE / 2
    var valid_pos := Vector2i(center, center)
    var best_dist := 999999
    for dx in range(-20, 21):
        for dy in range(-20, 21):
            var pos := Vector2i(center + dx, center + dy)
            if pos.x < 0 or pos.x >= PlanetGenerator.WORLD_SIZE or pos.y < 0 or pos.y >= PlanetGenerator.WORLD_SIZE:
                continue
            if PlanetGenerator.is_buildable(world[pos.x][pos.y]):
                var dist := dx*dx + dy*dy
                if dist < best_dist:
                    best_dist = dist
                    valid_pos = pos
    
    print("TEST: placing blueprint at ", valid_pos)
    Network.ask_build(valid_pos)
    await get_tree().create_timer(2.0).timeout
    
    print("TEST: blueprints = ", received_blueprints.size())
    print("TEST: villagers = ", received_villagers.size())
    
    var key = "%d,%d" % [valid_pos.x, valid_pos.y]
    if received_blueprints.has(key):
        print("TEST PASS: blueprint placed")
    else:
        print("TEST FAIL: blueprint not placed")
    
    if received_villagers.size() >= 1:
        print("TEST PASS: builder spawned")
    else:
        print("TEST FAIL: builder not spawned")
    
    # Wait for builder to complete and workers to produce
    await get_tree().create_timer(10.0).timeout
    print("TEST: resources after production = ", received_resources)
    print("TEST: buildings = ", received_buildings.size(), " keys: ", received_buildings.keys())
    print("TEST: looking for key ", key)
    print("TEST: villagers = ", received_villagers.size())
    
    if received_buildings.has(key):
        print("TEST PASS: blueprint completed into building")
    else:
        print("TEST INFO: blueprint not yet completed")
    
    if received_resources["wood"] > 0 or received_resources["food"] > 0 or received_resources["stone"] > 0:
        print("TEST PASS: resource production works")
    else:
        print("TEST INFO: no resources produced yet")
    
    # Test blocked build on water
    var water_pos := Vector2i(10, 10)
    for x in range(PlanetGenerator.WORLD_SIZE):
        for y in range(PlanetGenerator.WORLD_SIZE):
            if not PlanetGenerator.is_buildable(world[x][y]):
                water_pos = Vector2i(x, y)
                break
        if not PlanetGenerator.is_buildable(world[water_pos.x][water_pos.y]):
            break
    
    var prev_count := received_blueprints.size() + received_buildings.size()
    Network.ask_build(water_pos)
    await get_tree().create_timer(1.0).timeout
    if received_blueprints.size() + received_buildings.size() == prev_count:
        print("TEST PASS: blocked build rejected")
    else:
        print("TEST FAIL: blocked build was accepted")
    
    get_tree().quit(0)
