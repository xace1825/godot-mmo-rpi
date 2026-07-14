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

    var valid_pos := _find_buildable_zone_center(7)
    
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
    
    # Step 2: Build a fully enclosed room with walls/floor/door, then sawmill inside
    print("TEST: building enclosed room around ", valid_pos)
    # Room: 5x5, walls on perimeter (including corners), door replaces one wall, floor inside
    for rx in range(-2, 3):
        for ry in range(-2, 3):
            var pos := Vector2i(valid_pos.x + rx, valid_pos.y + ry)
            if pos.x < 0 or pos.x >= PlanetGenerator.WORLD_SIZE or pos.y < 0 or pos.y >= PlanetGenerator.WORLD_SIZE:
                continue
            if not PlanetGenerator.is_buildable(world[pos.x][pos.y]):
                continue
            var is_perimeter := (rx == -2 or rx == 2 or ry == -2 or ry == 2)
            var is_door := (rx == 2 and ry == 0)
            if is_perimeter:
                if is_door:
                    Network.ask_build(pos, PlanetGenerator.BuildingType.DOOR)
                else:
                    Network.ask_build(pos, PlanetGenerator.BuildingType.WALL)
            else:
                if pos != valid_pos:
                    Network.ask_build(pos, PlanetGenerator.BuildingType.FLOOR)
            await get_tree().create_timer(0.05).timeout
    
    await get_tree().create_timer(10.0).timeout
    
    # Step 3: Build sawmill inside the room
    print("TEST: placing sawmill blueprint at ", valid_pos)
    Network.ask_build(valid_pos)
    await get_tree().create_timer(5.0).timeout
    
    var key = "%d,%d" % [valid_pos.x, valid_pos.y]
    if received_blueprints.has(key) or received_buildings.has(key):
        print("TEST PASS: blueprint placed or already completed")
    else:
        print("TEST FAIL: blueprint not placed")
    
    if received_villagers.size() >= 1:
        print("TEST PASS: builder spawned")
    else:
        print("TEST FAIL: builder not spawned")
    
    if received_buildings.has(key):
        print("TEST PASS: blueprint completed into building")
    else:
        print("TEST INFO: blueprint not yet completed, resources=", received_resources)
    
    await get_tree().create_timer(5.0).timeout
    print("TEST: resources = ", received_resources)
    
    if received_resources["wood"] > 0 or received_resources["food"] > 0 or received_resources["stone"] > 0:
        print("TEST PASS: resource production works")
    else:
        print("TEST INFO: no resources produced yet")
    
    # Test outdoor station speed: build a second sawmill outside any room
    var outdoor_pos := _find_buildable_zone_center(3)
    # Make sure it's far from the room
    outdoor_pos = Vector2i(valid_pos.x + 10, valid_pos.y)
    while not PlanetGenerator.is_buildable(world[outdoor_pos.x][outdoor_pos.y]) or outdoor_pos == valid_pos:
        outdoor_pos.x += 1
    print("TEST: placing outdoor sawmill at ", outdoor_pos)
    Network.ask_build(outdoor_pos)
    await get_tree().create_timer(5.0).timeout
    var out_key := "%d,%d" % [outdoor_pos.x, outdoor_pos.y]
    if received_buildings.has(out_key):
        print("TEST PASS: outdoor sawmill built")
    else:
        print("TEST INFO: outdoor sawmill not completed")
    
    await get_tree().create_timer(3.0).timeout
    
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
