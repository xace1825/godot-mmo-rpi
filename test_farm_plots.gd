extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0.0
var test_phase := "init"
var passed := []
var failed := []
var phase_entered := false

var farm_start := Vector2i(72, 64)
var farm_end := Vector2i(73, 65)
var expected_food: int = 500

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
				Network.ask_build_farm_plots(farm_start, farm_end)
				print("TEST: requested farm plots from ", farm_start, " to ", farm_end)
				test_phase = "wait_blueprints"
				test_start_time = Time.get_ticks_msec()
		"wait_blueprints":
			if elapsed > 30.0:
				_fail("farm plot blueprints did not appear")
		"spawn":
			if not phase_entered:
				phase_entered = true
				print("TEST: spawning 2 villagers")
				Network.ask_spawn_villager()
				Network.ask_spawn_villager()
				test_phase = "wait_food"
				test_start_time = Time.get_ticks_msec()
		"wait_food":
			if elapsed > 120.0:
				_fail("no food produced in 120s")

func _on_blueprint(pos: Vector2i, type_id: int):
	print("TEST: blueprint placed at ", pos, " type ", type_id)
	if test_phase == "wait_blueprints":
		test_phase = "spawn"
		phase_entered = false
		test_start_time = Time.get_ticks_msec()

func _on_building_completed(pos: Vector2i, type_id: int):
	print("TEST: building completed at ", pos)

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	var resources: Dictionary = data.get("resources", {})
	var food_now: int = resources.get("food", 0)
	if test_phase == "wait_food" and food_now > expected_food:
		_pass("farmers produced food: %d" % food_now)
		_finish()

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
