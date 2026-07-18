extends Node

const DEFAULT_SERVER_IP: String = "127.0.0.1"
const DEFAULT_SERVER_PORT: int = 7777

var test_start_time := 0.0
var passed := []
var failed := []
var completed_buildings := 0
var buildings_seen := {}
var full_sync_ok := false
var total_blueprints := 20

func _ready():
    print("Headless test client starting")
    Network.full_sync.connect(_on_sync)
    Network.building_placed.connect(_on_building_placed)
    Network.blueprint_placed.connect(_on_blueprint_placed)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(func(): print("CONNECTION FAILED"); _finish())
    Network.start_client(DEFAULT_SERVER_IP, DEFAULT_SERVER_PORT)
    test_start_time = Time.get_ticks_msec() / 1000.0

func _on_connected():
    print("Connected to server")

func _on_sync(data: Dictionary):
    if full_sync_ok:
        return
    full_sync_ok = true
    print("Full sync received")
    await get_tree().create_timer(0.5).timeout
    Network.ask_spawn_villager()
    await get_tree().create_timer(0.2).timeout
    Network.ask_spawn_villager()
    await get_tree().create_timer(0.2).timeout
    Network.ask_spawn_villager()
    await get_tree().create_timer(0.5).timeout
    _place_blueprints()

func _place_blueprints():
    # Walls x=88..94 at y=62 (7 walls), door at 95,62
    for x in range(88, 95):
        Network.ask_place_blueprint(Vector2i(x, 62), 3)
        await get_tree().create_timer(0.05).timeout
    Network.ask_place_blueprint(Vector2i(95, 62), 4)  # DOOR
    await get_tree().create_timer(0.05).timeout
    # Floors y=63 x=88..94 (7 floors)
    for x in range(88, 95):
        Network.ask_place_blueprint(Vector2i(x, 63), 5)
        await get_tree().create_timer(0.05).timeout
    # Walls y=64 x=88..94 (7 walls)
    for x in range(88, 95):
        Network.ask_place_blueprint(Vector2i(x, 64), 3)
        await get_tree().create_timer(0.05).timeout
    print("Client: placed ", total_blueprints, " blueprints")

func _on_blueprint_placed(pos: Vector2i, type_id: int):
    pass

func _on_building_placed(pos: Vector2i, type_id: int):
    var key := "%d,%d" % [pos.x, pos.y]
    if buildings_seen.has(key):
        return
    buildings_seen[key] = true
    completed_buildings += 1
    print("Client: building completed at ", pos, " type ", type_id, " total ", completed_buildings)

func _process(delta):
    var elapsed := Time.get_ticks_msec() / 1000.0 - test_start_time
    if elapsed > 180.0:
        print("TIMEOUT: completed ", completed_buildings, " / ", total_blueprints, " buildings")
        failed.append("timeout")
        _finish()
    elif completed_buildings >= total_blueprints:
        print("PASS: all ", completed_buildings, " blueprints completed")
        passed.append("room build completed")
        _finish()

func _finish():
    var f := FileAccess.open("user://test_room_build_result.txt", FileAccess.WRITE)
    if f:
        f.store_line("passed: " + str(passed.size()))
        f.store_line("failed: " + str(failed.size()))
        f.store_line("completed: " + str(completed_buildings))
        f.close()
    get_tree().quit()
