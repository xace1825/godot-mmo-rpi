extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0.0
var test_phase := "init"
var passed := []
var failed := []
var phase_entered := false

func _ready():
	Network.full_sync.connect(_on_full_sync)
	Network.building_placed.connect(_on_building_completed)
	Network.blueprint_placed.connect(_on_blueprint)
	peer.create_client("127.0.0.1", 7777)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): connected = true)
	multiplayer.connection_failed.connect(func(): _fail("connection failed"))
	test_start_time = Time.get_ticks_msec()

func _physics_process(_delta):
	if not connected or not full_sync_received:
		return
	var elapsed: float = (Time.get_ticks_msec() - test_start_time) / 1000.0
	match test_phase:
		"init":
			if not phase_entered:
				phase_entered = true
				Network.ask_stockpile(Vector2i(66, 66), Vector2i(2, 2))
				test_phase = "wait_stock"
				test_start_time = Time.get_ticks_msec()
		"wait_stock":
			if elapsed > 3.0:
				Network.ask_build(Vector2i(72, 64), PlanetGenerator.BuildingType.SAWMILL)
				Network.ask_build(Vector2i(72, 68), PlanetGenerator.BuildingType.SAWMILL)
				Network.ask_build(Vector2i(72, 72), PlanetGenerator.BuildingType.SAWMILL)
				print("TEST: placed 3 sawmill blueprints")
				test_phase = "wait_blueprints"
				test_start_time = Time.get_ticks_msec()
		"wait_blueprints":
			if elapsed > 8.0:
				_fail("blueprints did not appear")
		"spawn":
			if not phase_entered:
				phase_entered = true
				print("TEST: spawning 2 villagers")
				Network.ask_spawn_villager()
				Network.ask_spawn_villager()
				test_phase = "wait_buildings"
				test_start_time = Time.get_ticks_msec()
		"wait_buildings":
			if elapsed > 120.0:
				_fail("did not build 3 sawmills in 120s")

var blueprint_count := 0
func _on_blueprint(pos: Vector2i, type_id: int):
	blueprint_count += 1
	print("TEST: blueprint placed at ", pos, " type ", type_id, " count=", blueprint_count)
	if test_phase == "wait_blueprints" and blueprint_count >= 3:
		test_phase = "spawn"
		phase_entered = false
		test_start_time = Time.get_ticks_msec()

var completed := 0
func _on_building_completed(pos: Vector2i, type_id: int):
	completed += 1
	print("TEST: building completed #", completed, " at ", pos)
	if completed >= 3:
		_pass("3 sawmills built sequentially by same builders")
		_finish()

func _on_full_sync(data: Dictionary):
	full_sync_received = true

func _pass(msg: String):
	passed.append(msg)
	print("TEST PASS: ", msg)

func _fail(msg: String):
	failed.append(msg)
	print("TEST FAIL: ", msg)
	get_tree().quit(1)

func _finish():
	print("PASSED: ", passed.size(), " FAILED: ", failed.size())
	get_tree().quit(0)
