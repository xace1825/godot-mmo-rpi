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
	Network.resource_sync.connect(_on_resource_sync)
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
				print("TEST: placed sawmill blueprint")
				test_phase = "wait_blueprint"
				test_start_time = Time.get_ticks_msec()
		"wait_blueprint":
			if elapsed > 8.0:
				_fail("blueprint did not appear")
		"spawn":
			if not phase_entered:
				phase_entered = true
				print("TEST: spawning 1 villager")
				Network.ask_spawn_villager()
				test_phase = "wait_production"
				test_start_time = Time.get_ticks_msec()
		"wait_production":
			if elapsed > 90.0:
				_fail("no wood produced in 90s")
		"done_phase1":
			if not phase_entered:
				phase_entered = true
				print("TEST: phase1 complete, wood=", last_wood)
				_pass("phase1 produced wood")
				_finish()

var last_wood := 0
var sawmill_built := false

func _on_resource_sync(resources: Dictionary):
	last_wood = resources.get("wood", 0)
	print("TEST: resource_sync wood=", last_wood, " sawmill_built=", sawmill_built)
	if test_phase == "wait_production" and sawmill_built and last_wood >= 491:
		test_phase = "done_phase1"
		phase_entered = false
		test_start_time = Time.get_ticks_msec()

func _on_building_completed(pos: Vector2i, type_id: int):
	print("TEST: building completed at ", pos)
	if type_id == PlanetGenerator.BuildingType.SAWMILL:
		sawmill_built = true

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	last_wood = data.get("resources", {}).get("wood", 0)

func _on_blueprint(pos: Vector2i, type_id: int):
	print("TEST: blueprint placed at ", pos, " type ", type_id)
	if test_phase == "wait_blueprint":
		test_phase = "spawn"
		phase_entered = false
		test_start_time = Time.get_ticks_msec()

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
