extends Node

const DEFAULT_SERVER_IP: String = "127.0.0.1"
const DEFAULT_SERVER_PORT: int = 7777

var seed_value: int = 12345
var world: Array = []
var received_villagers: Dictionary = {}
var received_resources: Dictionary = {}
var received_blueprints: Dictionary = {}
var received_buildings: Dictionary = {}
var received_stockpiles: Dictionary = {}
var setup_done: bool = false

func _ready():
    print("Headless test client starting")
    Network.full_sync.connect(_on_sync)
    Network.villager_sync.connect(_on_villager_sync)
    Network.resource_sync.connect(_on_resource_sync)
    Network.blueprint_placed.connect(_on_blueprint_placed)
    Network.building_placed.connect(_on_building_placed)
    Network.stockpile_added.connect(_on_stockpile_added)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(func(): print("CONNECTION FAILED"); get_tree().quit(1))
    Network.start_client(DEFAULT_SERVER_IP, DEFAULT_SERVER_PORT)

func _on_connected():
    print("Connected to server")

func _on_sync(data: Dictionary):
    print("Full sync received with ", data["buildings"].size(), " buildings, ", data.get("blueprints", {}).size(), " blueprints, ", data.get("stockpiles", {}).size(), " stockpiles")
    seed_value = data.get("seed", 12345)
    world = PlanetGenerator.generate_world(seed_value)
    received_buildings = data.get("buildings", {})
    received_blueprints = data.get("blueprints", {})
    received_stockpiles = data.get("stockpiles", {})
    received_villagers = data.get("villagers", {})
    received_resources = data.get("resources", {"wood": 0, "food": 0, "stone": 0})
    if not setup_done:
        setup_done = true
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
    received_buildings[key] = type_id
    if received_blueprints.has(key):
        received_blueprints.erase(key)

func _on_stockpile_added(id: String, data: Dictionary):
    received_stockpiles[id] = data

func _find_buildable_near_center() -> Vector2i:
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
    return valid_pos

func _find_stockpile_zone(center: Vector2i, size: Vector2i) -> Vector2i:
    for radius in range(1, 30):
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                var top_left := Vector2i(center.x + dx, center.y + dy)
                if top_left.x < 0 or top_left.x + size.x > PlanetGenerator.WORLD_SIZE or top_left.y < 0 or top_left.y + size.y > PlanetGenerator.WORLD_SIZE:
                    continue
                var valid := true
                for sx in range(size.x):
                    for sy in range(size.y):
                        var pos := Vector2i(top_left.x + sx, top_left.y + sy)
                        if not PlanetGenerator.is_buildable(world[pos.x][pos.y]):
                            valid = false
                            break
                    if not valid:
                        break
                if valid:
                    return top_left
    return Vector2i(-1, -1)

func _run_tests(data: Dictionary):
    await get_tree().create_timer(0.5).timeout

    var valid_pos := _find_buildable_near_center()
    
    # Step 1: Create a stockpile near center so resources can be stored
    var stock_size := Vector2i(3, 3)
    var stock_top_left := _find_stockpile_zone(valid_pos, stock_size)
    if stock_top_left.x < 0:
        print("TEST FAIL: no buildable zone for stockpile")
        get_tree().quit(1)
        return
    print("TEST: placing stockpile at ", stock_top_left, " size ", stock_size)
    Network.ask_stockpile(stock_top_left, stock_size)
    await get_tree().create_timer(1.0).timeout
    
    if received_stockpiles.size() >= 1:
        print("TEST PASS: stockpile added")
    else:
        print("TEST FAIL: stockpile not added")
    
    # Step 2: Build a sawmill (needs resources from stockpile)
    print("TEST: placing sawmill blueprint at ", valid_pos)
    Network.ask_build(valid_pos)
    await get_tree().create_timer(2.0).timeout
    
    var key = "%d,%d" % [valid_pos.x, valid_pos.y]
    if received_blueprints.has(key):
        print("TEST PASS: blueprint placed")
    else:
        print("TEST FAIL: blueprint not placed")
    
    if received_villagers.size() >= 1:
        print("TEST PASS: builder spawned")
    else:
        print("TEST FAIL: builder not spawned")
    
    await get_tree().create_timer(5.0).timeout
    
    if received_buildings.has(key):
        print("TEST PASS: blueprint completed into building")
    else:
        print("TEST INFO: blueprint not yet completed, resources=", received_resources)
    
    # Step 3: Build walls and floors around the sawmill
    print("TEST: placing walls and floors around sawmill")
    var offsets: Array = [
        Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -2),
        Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
        Vector2i(-2, -1), Vector2i(-2, 0), Vector2i(-2, 1),
        Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1),
    ]
    for off in offsets:
        var pos: Vector2i = valid_pos + off
        if PlanetGenerator.is_buildable(world[pos.x][pos.y]):
            if pos.x == valid_pos.x - 2 or pos.x == valid_pos.x + 2 or pos.y == valid_pos.y - 2 or pos.y == valid_pos.y + 2:
                Network.ask_build(pos, PlanetGenerator.BuildingType.WALL)
            else:
                Network.ask_build(pos, PlanetGenerator.BuildingType.FLOOR)
            await get_tree().create_timer(0.1).timeout
    
    await get_tree().create_timer(10.0).timeout
    print("TEST: buildings after walls/floors = ", received_buildings.size())
    print("TEST: resources = ", received_resources)
    
    if received_buildings.size() >= 5:
        print("TEST PASS: walls and floors built")
    else:
        print("TEST INFO: walls/floors still under construction")
    
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
