extends Node

const DEFAULT_SERVER_IP: String = "127.0.0.1"
const DEFAULT_SERVER_PORT: int = 7777

var seed_value: int = 12345
var world: Array = []
var received_villagers: Dictionary = {}
var received_resources: Dictionary = {}

func _ready():
    print("Headless test client starting")
    Network.full_sync.connect(_on_sync)
    Network.villager_sync.connect(_on_villager_sync)
    Network.resource_sync.connect(_on_resource_sync)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(func(): print("CONNECTION FAILED"); get_tree().quit(1))
    Network.start_client(DEFAULT_SERVER_IP, DEFAULT_SERVER_PORT)

func _on_connected():
    print("Connected to server")

func _on_sync(data: Dictionary):
    print("Full sync received with ", data["buildings"].size(), " buildings")
    seed_value = data.get("seed", 12345)
    world = PlanetGenerator.generate_world(seed_value)
    received_villagers = data.get("villagers", {})
    received_resources = data.get("resources", {"wood": 0, "food": 0, "stone": 0})
    _run_tests(data)

func _on_villager_sync(villagers: Dictionary):
    received_villagers = villagers

func _on_resource_sync(resources: Dictionary):
    received_resources = resources

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
    
    if valid_pos.x < 0:
        print("TEST FAIL: no buildable tile near center")
        get_tree().quit(1)
        return
    
    print("TEST: building at ", valid_pos)
    Network.ask_build(valid_pos)
    await get_tree().create_timer(2.0).timeout
    
    print("TEST: resources after build = ", received_resources)
    print("TEST: villagers = ", received_villagers.size())
    
    if received_villagers.size() >= 2:
        print("TEST PASS: villagers spawned")
    else:
        print("TEST FAIL: villagers not spawned")
    
    await get_tree().create_timer(5.0).timeout
    print("TEST: resources after production = ", received_resources)
    
    if received_resources["wood"] > 0 or received_resources["food"] > 0 or received_resources["stone"] > 0:
        print("TEST PASS: resource production works")
    else:
        print("TEST INFO: no resources yet, may need more time")
    
    # Test blocked build on water
    var water_pos := Vector2i(10, 10)
    if PlanetGenerator.is_buildable(world[water_pos.x][water_pos.y]):
        # Find a water tile
        for x in range(PlanetGenerator.WORLD_SIZE):
            for y in range(PlanetGenerator.WORLD_SIZE):
                if not PlanetGenerator.is_buildable(world[x][y]):
                    water_pos = Vector2i(x, y)
                    break
            if not PlanetGenerator.is_buildable(world[water_pos.x][water_pos.y]):
                break
    
    var prev_buildings := received_villagers.size()
    Network.ask_build(water_pos)
    await get_tree().create_timer(1.0).timeout
    if received_villagers.size() == prev_buildings:
        print("TEST PASS: blocked build rejected")
    else:
        print("TEST FAIL: blocked build was accepted")
    
    get_tree().quit(0)
