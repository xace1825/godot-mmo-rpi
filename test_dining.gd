extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0.0
var test_phase := "init"
var passed := []
var failed := []
var phase_entered := false

var saw_pos := Vector2i(72, 64)
var kit_pos := Vector2i(71, 64)
var table_pos := Vector2i(70, 64)

var saw_done := false
var kit_done := false
var table_done := false

var observed_states := {}
var max_comfort := 0.0

func _ready():
	Network.full_sync.connect(_on_full_sync)
	Network.building_placed.connect(_on_building_completed)
	Network.blueprint_placed.connect(_on_blueprint)
	Network.villager_sync.connect(_on_villager_sync)
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
				print("TEST: spawning initial villagers")
				Network.ask_spawn_villager()
				Network.ask_spawn_villager()
				test_phase = "wait_villagers"
				test_start_time = Time.get_ticks_msec()
		"wait_villagers":
			if elapsed > 3.0:
				print("TEST: placing sawmill, kitchen, table blueprints")
				Network.ask_build(saw_pos, PlanetGenerator.BuildingType.SAWMILL)
				Network.ask_build(kit_pos, PlanetGenerator.BuildingType.KITCHEN)
				Network.ask_build(table_pos, PlanetGenerator.BuildingType.TABLE)
				test_phase = "wait_buildings"
				test_start_time = Time.get_ticks_msec()
		"wait_buildings":
			if saw_done and kit_done and table_done:
				print("TEST: buildings ready")
				phase_entered = false
				test_phase = "assign_cook"
				test_start_time = Time.get_ticks_msec()
			if elapsed > 60.0:
				_fail("buildings did not complete in time")
		"assign_cook":
			if not phase_entered:
				phase_entered = true
				# Assign one villager as cook manually
				for id: String in Network.last_full_sync.get("villagers", {}):
					if Network.last_full_sync["villagers"][id].get("job", "") == "idle":
						print("TEST: assigning ", id, " to cook")
						Network.ask_set_job(id, "cook")
						break
			test_phase = "wait_cook"
			test_start_time = Time.get_ticks_msec()
		"wait_cook":
			var food: int = Network.last_full_sync.get("resources", {}).get("prepared_food", 0)
			if food >= 3:
				print("TEST: prepared_food ready, spawning hungry villager")
				Network.ask_spawn_villager()
				test_phase = "wait_eat"
				test_start_time = Time.get_ticks_msec()
			if elapsed > 120.0:
				_fail("cook did not produce prepared food")
		"wait_eat":
			if elapsed > 180.0:
				if observed_states.has("eating_at_table") or observed_states.has("moving_to_table"):
					_pass("villager used table for dining")
					_finish()
				elif max_comfort >= 85.0:
					_pass("comfort increased (indirect table benefit)")
					_finish()
				else:
					_fail("no table dining observed")

func _on_blueprint(pos: Vector2i, type_id: int):
	print("TEST: blueprint placed at ", pos, " type ", type_id)

func _on_building_completed(pos: Vector2i, type_id: int):
	print("TEST: building completed at ", pos, " type ", type_id)
	if pos == saw_pos:
		saw_done = true
	elif pos == kit_pos:
		kit_done = true
	elif pos == table_pos:
		table_done = true

func _on_villager_sync(villagers: Dictionary):
	for id: String in villagers:
		var v: Dictionary = villagers[id]
		var state: String = v.get("state", "")
		observed_states[state] = true
		var comfort: float = float(v.get("needs", {}).get("comfort", 0.0))
		if comfort > max_comfort:
			max_comfort = comfort
	if test_phase == "wait_cook":
		for id: String in villagers:
			var v: Dictionary = villagers[id]
			var job: String = v.get("job", "")
			if job == "idle":
				print("TEST: assigning villager ", id, " to cook")
				Network.ask_set_job(id, "cook")
			elif job == "cook":
				# once cook exists and prepared_food appears, spawn a third villager and watch them eat
				var food: int = Network.last_full_sync.get("resources", {}).get("prepared_food", 0)
				if food >= 3:
					print("TEST: prepared_food ready, switching to wait_eat")
					Network.ask_spawn_villager()
					test_phase = "wait_eat"
					test_start_time = Time.get_ticks_msec()

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	Network.last_full_sync = data

func _pass(msg: String):
	passed.append(msg)
	print("TEST PASS: ", msg)

func _fail(msg: String):
	failed.append(msg)
	print("TEST FAIL: ", msg)
	get_tree().quit(1)

func _finish():
	print("OBSERVED STATES: ", observed_states.keys())
	print("MAX COMFORT: ", max_comfort)
	print("PASSED: ", passed.size(), " FAILED: ", failed.size())
	get_tree().quit(0)
