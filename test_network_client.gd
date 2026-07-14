extends Node

const DEFAULT_SERVER_IP: String = "192.168.0.102"
const DEFAULT_SERVER_PORT: int = 7777

var results: Dictionary = {}
var got_sync: bool = false

func _ready():
    print("Headless test client starting")
    Network.full_sync.connect(_on_full_sync)
    Network.building_placed.connect(_on_building)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(_on_failed)
    
    var server_ip := DEFAULT_SERVER_IP
    var server_port := DEFAULT_SERVER_PORT
    var args := OS.get_cmdline_args()
    for arg in args:
        if arg.begins_with("--server-ip="):
            server_ip = arg.split("=", false)[1]
        elif arg.begins_with("--server-port="):
            server_port = int(arg.split("=", false)[1])
    
    print("Connecting to ", server_ip, ":", server_port)
    Network.start_client(server_ip, server_port)

func _on_connected():
    print("TEST: connected to server")

func _on_failed():
    print("TEST: connection failed")
    get_tree().quit()

func _on_full_sync(data: Dictionary):
    if got_sync:
        return
    got_sync = true
    var seed := data.get("seed", 12345) as int
    print("TEST: received seed ", seed)
    results["seed"] = seed
    results["initial_buildings"] = data["buildings"].size()
    
    var world := PlanetGenerator.generate_world(seed)
    
    var valid_pos := Vector2i(-1, -1)
    var blocked_pos := Vector2i(-1, -1)
    
    for x in range(PlanetGenerator.WORLD_SIZE):
        for y in range(PlanetGenerator.WORLD_SIZE):
            var type := world[x][y] as int
            if valid_pos.x < 0 and PlanetGenerator.is_buildable(type):
                valid_pos = Vector2i(x, y)
            if blocked_pos.x < 0 and not PlanetGenerator.is_buildable(type):
                blocked_pos = Vector2i(x, y)
            if valid_pos.x >= 0 and blocked_pos.x >= 0:
                break
        if valid_pos.x >= 0 and blocked_pos.x >= 0:
            break
    
    print("TEST: valid=", valid_pos, " blocked=", blocked_pos)
    results["valid_pos"] = valid_pos
    results["blocked_pos"] = blocked_pos
    
    await get_tree().create_timer(1.0).timeout
    print("TEST: request build at valid ", valid_pos)
    Network.ask_build(valid_pos)
    
    await get_tree().create_timer(1.0).timeout
    print("TEST: request build at blocked ", blocked_pos)
    Network.ask_build(blocked_pos)
    
    await get_tree().create_timer(2.0).timeout
    print("TEST RESULTS: ", JSON.stringify(results))
    
    if results.get("valid_build", false):
        print("TEST PASS: buildable tile accepted")
    else:
        print("TEST FAIL: buildable tile rejected")
    
    if not results.get("blocked_build", true):
        print("TEST PASS: blocked tile rejected")
    else:
        print("TEST FAIL: blocked tile accepted")
    
    await get_tree().create_timer(0.5).timeout
    get_tree().quit()

func _on_building(pos: Vector2i, type_id: int):
    print("TEST: building placed at ", pos, " type ", type_id)
    var valid_pos: Vector2i = results.get("valid_pos", Vector2i(-1, -1))
    var blocked_pos: Vector2i = results.get("blocked_pos", Vector2i(-1, -1))
    
    if pos == valid_pos:
        results["valid_build"] = true
        results["valid_build_type"] = type_id
    if pos == blocked_pos:
        results["blocked_build"] = true
