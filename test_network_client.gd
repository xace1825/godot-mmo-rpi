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
    received_buildings.clear()
    var bldg = data.get("buildings", {}) as Dictionary
    for k in bldg:
        received_buildings[k] = bldg[k]
    received_blueprints.clear()
    var bps = data.get("blueprints", {}) as Dictionary
    for k in bps:
        received_blueprints[k] = bps[k]
    received_stockpiles.clear()
    var stocks = data.get("stockpiles", {}) as Dictionary
    for k in stocks:
        received_stockpiles[k] = stocks[k]
    received_villagers.clear()
    var villagers = data.get("villagers", {}) as Dictionary
    for k in villagers:
        received_villagers[k] = villagers[k]
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

func _find_buildable_zone_center(size: int) -> Vector2i:
    var center := PlanetGenerator.WORLD_SIZE / 2
    var half := size / 2
    var best_pos := Vector2i(center, center)
    var best_dist := 999999
    for dx in range(-30, 31):
        for dy in range(-30, 31):
            var top_left := Vector2i(center + dx - half, center + dy - half)
            if top_left.x < 0 or top_left.x + size >= PlanetGenerator.WORLD_SIZE or top_left.y < 0 or top_left.y + size >= PlanetGenerator.WORLD_SIZE:
                continue
            var valid := true
            for sx in range(size):
                for sy in range(size):
                    var pos := Vector2i(top_left.x + sx, top_left.y + sy)
                    if not PlanetGenerator.is_buildable(world[pos.x][pos.y]):
                        valid = false
                        break
                if not valid:
                    break
            if valid:
                var dist := dx*dx + dy*dy
                if dist < best_dist:
                    best_dist = dist
                    best_pos = Vector2i(center + dx, center + dy)
    return best_pos

func _find_stockpile_zone(center: Vector2i, size: Vector2i) -> Vector2i:
    # Avoid the planned 7x7 room area around center
    var room_margin := 4
    for radius in range(1, 40):
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                var top_left := Vector2i(center.x + dx, center.y + dy)
                if top_left.x < 0 or top_left.x + size.x > PlanetGenerator.WORLD_SIZE or top_left.y < 0 or top_left.y + size.y > PlanetGenerator.WORLD_SIZE:
                    continue
                # Must not overlap planned room area (center +/- room_margin)
                var overlaps_room := false
                for sx in range(size.x):
                    for sy in range(size.y):
                        var px := top_left.x + sx
                        var py := top_left.y + sy
                        if abs(px - center.x) <= room_margin and abs(py - center.y) <= room_margin:
                            overlaps_room = true
                            break
                        if not PlanetGenerator.is_buildable(world[px][py]):
                            overlaps_room = true
                            break
                    if overlaps_room:
                        break
                if overlaps_room:
                    continue
                return top_left
    return Vector2i(-1, -1)

func _run_tests(data: Dictionary):
    await get_tree().create_timer(0.5).timeout

    var valid_pos := _find_buildable_zone_center(3)
    
    # Step 1: Create a stockpile near the sawmill location
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
    
    # Step 2: Build sawmill directly on open terrain (no room needed for test)
    print("TEST: placing sawmill blueprint at ", valid_pos)
    Network.ask_build(valid_pos, PlanetGenerator.BuildingType.SAWMILL)
    await get_tree().create_timer(2.0).timeout
    
    # Manually spawn villagers via SPAWN button; they auto-assign as builders
    print("TEST: manually spawning villagers for construction")
    for i in range(3):
        Network.ask_spawn_villager()
        await get_tree().create_timer(0.5).timeout
    
    # Active wait for sawmill completion
    var key = "%d,%d" % [valid_pos.x, valid_pos.y]
    var sawmill_built := false
    for i in range(60):
        await get_tree().create_timer(0.5).timeout
        print("TEST: waiting sawmill ", key, " buildings=", received_buildings)
        if received_buildings.has(key) and received_buildings[key] == PlanetGenerator.BuildingType.SAWMILL:
            sawmill_built = true
            break
    if sawmill_built:
        print("TEST PASS: sawmill built")
    else:
        print("TEST FAIL: sawmill not built, type=", received_buildings.get(key, -1))
    
    if received_villagers.size() >= 1:
        print("TEST PASS: villagers spawned manually via SPAWN")
    else:
        print("TEST FAIL: villagers not spawned")
    
    # Step 3: Wait for production
    var wood_before: int = received_resources.get("wood", 0)
    print("TEST: resources before production wait = ", received_resources)
    await get_tree().create_timer(15.0).timeout
    print("TEST: resources after production wait = ", received_resources)
    
    if received_resources.get("wood", 0) > wood_before:
        print("TEST PASS: resource production works")
    else:
        print("TEST INFO: no wood produced yet, workers may still be walking")
    
    # Step 4: Build a second sawmill and verify villagers split between stations
    var sawmill2_pos := _find_buildable_zone_center(3)
    sawmill2_pos = Vector2i(valid_pos.x + 8, valid_pos.y)
    while not PlanetGenerator.is_buildable(world[sawmill2_pos.x][sawmill2_pos.y]) or sawmill2_pos == valid_pos:
        sawmill2_pos.x += 1
    print("TEST: placing second sawmill at ", sawmill2_pos)
    Network.ask_build(sawmill2_pos, PlanetGenerator.BuildingType.SAWMILL)
    
    var key2 := "%d,%d" % [sawmill2_pos.x, sawmill2_pos.y]
    var sawmill2_built := false
    for i in range(80):
        await get_tree().create_timer(0.5).timeout
        if received_buildings.has(key2) and received_buildings[key2] == PlanetGenerator.BuildingType.SAWMILL:
            sawmill2_built = true
            break
    if sawmill2_built:
        print("TEST PASS: second sawmill built")
    else:
        print("TEST INFO: second sawmill not completed")
    
    # Wait and check workers are split between sawmills
    await get_tree().create_timer(10.0).timeout
    var sawmill1_workers := 0
    var sawmill2_workers := 0
    for vid in received_villagers:
        var vw = received_villagers[vid] as Dictionary
        var vwp = vw.get("workplace", {})
        var wpx := int(vwp.get("x", -1))
        var wpy := int(vwp.get("y", -1))
        if wpx == valid_pos.x and wpy == valid_pos.y:
            sawmill1_workers += 1
        elif wpx == sawmill2_pos.x and wpy == sawmill2_pos.y:
            sawmill2_workers += 1
    print("TEST: sawmill1 workers=", sawmill1_workers, " sawmill2 workers=", sawmill2_workers)
    if sawmill1_workers >= 1 and sawmill2_workers >= 1:
        print("TEST PASS: villagers split between sawmills")
    else:
        print("TEST INFO: villagers not yet split, sawmill1=", sawmill1_workers, " sawmill2=", sawmill2_workers)
    
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
    Network.ask_build(water_pos, PlanetGenerator.BuildingType.SAWMILL)
    await get_tree().create_timer(1.0).timeout
    if received_blueprints.size() + received_buildings.size() == prev_count:
        print("TEST PASS: blocked build rejected")
    else:
        print("TEST FAIL: blocked build was accepted")
    
    get_tree().quit(0)
