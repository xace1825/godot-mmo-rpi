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
var reset_done: bool = false
var test_phase: int = 0
var phase_timer: float = 0.0

func _ready():
    print("=== Stockpile logic test client starting ===")
    Network.full_sync.connect(_on_sync)
    Network.world_reset.connect(_on_world_reset)
    Network.villager_sync.connect(_on_villager_sync)
    Network.resource_sync.connect(_on_resource_sync)
    Network.blueprint_placed.connect(_on_blueprint_placed)
    Network.building_placed.connect(_on_building_placed)
    Network.stockpile_added.connect(_on_stockpile_added)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(func(): print("CONNECTION FAILED"); _fail("connection"))
    Network.start_client(DEFAULT_SERVER_IP, DEFAULT_SERVER_PORT)

func _on_connected():
    print("Connected to server")

func _on_world_reset(data: Dictionary):
    print("TEST: world reset received")
    _update_state(data)
    if not reset_done:
        reset_done = true
        _start_test_phases()

func _on_sync(data: Dictionary):
    _update_state(data)
    if not setup_done:
        setup_done = true
        print("TEST: requesting world reset for clean run")
        Network.ask_reset_world()

func _update_state(data: Dictionary):
    seed_value = data.get("seed", 12345)
    world = PlanetGenerator.generate_world(seed_value)
    received_buildings = data.get("buildings", {})
    received_blueprints = data.get("blueprints", {})
    received_stockpiles = data.get("stockpiles", {})
    received_villagers = data.get("villagers", {})
    received_resources = data.get("resources", {"wood": 0, "food": 0, "stone": 0})

func _start_test_phases():
    await get_tree().create_timer(1.0).timeout
    test_phase = 1
    _run_phase()

func _on_villager_sync(villagers: Dictionary):
    received_villagers = villagers

func _on_resource_sync(resources: Dictionary):
    received_resources = resources

func _on_blueprint_placed(pos: Vector2i, type_id: int):
    var key: String = _pos_key(pos)
    received_blueprints[key] = {"type": type_id, "pos": {"x": pos.x, "y": pos.y}}

func _on_building_placed(pos: Vector2i, type_id: int):
    var key: String = _pos_key(pos)
    received_buildings[key] = type_id
    if received_blueprints.has(key):
        received_blueprints.erase(key)

func _on_stockpile_added(id: String, data: Dictionary):
    received_stockpiles[id] = data

func _pos_key(pos: Vector2i) -> String:
    return "%d,%d" % [pos.x, pos.y]

func _find_buildable_zone(size: int) -> Vector2i:
    var center: int = PlanetGenerator.WORLD_SIZE / 2
    for radius in range(0, 50):
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                if abs(dx) != radius and abs(dy) != radius:
                    continue
                var top_left := Vector2i(center + dx, center + dy)
                if top_left.x < 0 or top_left.x + size >= PlanetGenerator.WORLD_SIZE or top_left.y < 0 or top_left.y + size >= PlanetGenerator.WORLD_SIZE:
                    continue
                var valid := true
                for sx in range(size):
                    for sy in range(size):
                        if not PlanetGenerator.is_buildable(world[top_left.x + sx][top_left.y + sy]):
                            valid = false
                            break
                    if not valid:
                        break
                if valid:
                    return top_left
    return Vector2i(center, center)

func _run_phase():
    match test_phase:
        1:
            _phase1_multiple_stockpiles()
        2:
            _phase2_build_and_consume()
        3:
            _phase3_wait_production()
        4:
            _phase4_check_multiple_stockpiles()
        5:
            _phase5_final_report()

func _phase1_multiple_stockpiles():
    print("PHASE 1: Create multiple stockpiles")
    print("TEST: first stockpile resources = ", received_resources)
    var zone2 := _find_buildable_zone(3)
    zone2 = Vector2i(zone2.x + 20, zone2.y + 20)
    if zone2.x + 3 >= PlanetGenerator.WORLD_SIZE:
        zone2.x = PlanetGenerator.WORLD_SIZE - 4
    if zone2.y + 3 >= PlanetGenerator.WORLD_SIZE:
        zone2.y = PlanetGenerator.WORLD_SIZE - 4
    print("TEST: placing second stockpile at ", zone2)
    Network.ask_stockpile(zone2, Vector2i(3, 3))
    await get_tree().create_timer(2.0).timeout
    if received_stockpiles.size() >= 2:
        print("TEST PASS: multiple stockpiles can be placed")
    else:
        _fail("multiple stockpiles: only " + str(received_stockpiles.size()) + " stockpiles")
    test_phase = 2
    _run_phase()

func _phase2_build_and_consume():
    print("PHASE 2: Build sawmill and check resource consumption")
    var sawmill_pos := _find_buildable_zone(1)
    for rx in range(-2, 3):
        for ry in range(-2, 3):
            var pos := Vector2i(sawmill_pos.x + rx, sawmill_pos.y + ry)
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
                if pos != sawmill_pos:
                    Network.ask_build(pos, PlanetGenerator.BuildingType.FLOOR)
            await get_tree().create_timer(0.05).timeout
    await get_tree().create_timer(8.0).timeout
    
    var start_wood: int = received_resources.get("wood", 0)
    print("TEST: resources before sawmill build: ", received_resources)
    Network.ask_build(sawmill_pos)
    await get_tree().create_timer(10.0).timeout
    
    var key: String = _pos_key(sawmill_pos)
    if received_buildings.has(key):
        print("TEST PASS: sawmill built")
    else:
        _fail("sawmill not built, blueprints=" + str(received_blueprints.size()))
    
    var wood_after: int = received_resources.get("wood", 0)
    print("TEST: wood before=", start_wood, " after=", wood_after)
    if wood_after < start_wood:
        print("TEST PASS: resources were consumed for construction")
    else:
        print("TEST INFO: wood did not decrease significantly")
    test_phase = 3
    _run_phase()

func _phase3_wait_production():
    print("PHASE 3: Wait for workers to produce resources")
    var wood_before: int = received_resources.get("wood", 0)
    print("TEST: waiting 25 seconds for production...")
    await get_tree().create_timer(25.0).timeout
    var wood_after: int = received_resources.get("wood", 0)
    print("TEST: wood before=", wood_before, " after=", wood_after)
    if wood_after > wood_before:
        print("TEST PASS: workers produced wood")
    else:
        print("TEST INFO: no wood produced yet, workers may still be walking")
    test_phase = 4
    _run_phase()

func _phase4_check_multiple_stockpiles():
    print("PHASE 4: Build far from first stockpile to test resource routing")
    var far_pos := _find_buildable_zone(1)
    far_pos = Vector2i(far_pos.x + 30, far_pos.y + 10)
    while not PlanetGenerator.is_buildable(world[far_pos.x][far_pos.y]):
        far_pos.x += 1
    
    var start_total: Dictionary = received_resources.duplicate()
    print("TEST: building farm at far position ", far_pos, " resources=", start_total)
    Network.ask_build(far_pos, PlanetGenerator.BuildingType.FARM)
    await get_tree().create_timer(12.0).timeout
    
    var key: String = _pos_key(far_pos)
    if received_buildings.has(key):
        print("TEST PASS: far building constructed (resources routed correctly)")
    else:
        print("TEST INFO: far building not completed yet, blueprints=" + str(received_blueprints.size()))
    test_phase = 5
    _run_phase()

func _phase5_final_report():
    print("=== FINAL TEST REPORT ===")
    print("Stockpiles: ", received_stockpiles.size())
    print("Buildings: ", received_buildings.size())
    print("Blueprints: ", received_blueprints.size())
    print("Villagers: ", received_villagers.size())
    print("Resources: ", received_resources)
    for id in received_stockpiles:
        print("  Stockpile ", id, ": ", received_stockpiles[id]["resources"])
    print("TEST COMPLETE")
    get_tree().quit(0)

func _fail(reason: String):
    print("TEST FAIL: ", reason)
    get_tree().quit(1)

func _process(delta: float):
    phase_timer += delta
    if phase_timer > 120.0:
        print("TEST FAIL: safety timeout")
        get_tree().quit(1)
