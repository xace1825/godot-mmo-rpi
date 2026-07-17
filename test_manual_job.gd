extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0.0
var test_phase := "init"
var passed := []
var failed := []
var phase_entered := false
var target_villager_id := ""

func _ready():
	Network.full_sync.connect(_on_full_sync)
	Network.building_placed.connect(_on_building_completed)
	Network.villager_sync.connect(_on_villager_sync)
	
	var server_ip := "127.0.0.1"
	var server_port := 7777
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--server-ip="):
			server_ip = arg.split("=")[1]
		if arg.begins_with("--server-port="):
			server_port = int(arg.split("=")[1])
	
	peer.create_client(server_ip, server_port)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): connected = true; print("TEST: connected"))
	multiplayer.connection_failed.connect(func(): print("TEST FAIL: connection failed"); get_tree().quit(1))
	multiplayer.server_disconnected.connect(func(): print("TEST: server disconnected"))
	test_start_time = Time.get_ticks_msec()
	print("Manual job assignment test starting")

func _physics_process(_delta):
	if not connected or not full_sync_received:
		return
	var elapsed: float = (Time.get_ticks_msec() - test_start_time) / 1000.0
	match test_phase:
		"init":
			if not phase_entered:
				phase_entered = true
				print("TEST: placing stockpile at (66,66)")
				Network.ask_stockpile(Vector2i(66, 66), Vector2i(2, 2))
				test_phase = "wait_stockpile"
				test_start_time = Time.get_ticks_msec()
		"wait_stockpile":
			if elapsed > 3.0:
				print("TEST: placing mine blueprint at (72,66)")
				Network.ask_build(Vector2i(72, 66), PlanetGenerator.BuildingType.MINE)
				test_phase = "wait_mine_blueprint"
				test_start_time = Time.get_ticks_msec()
		"wait_mine_blueprint":
			if elapsed > 8.0:
				_fail("mine blueprint did not appear in sync")
		"spawn_for_mine":
			if not phase_entered:
				phase_entered = true
				print("TEST: spawning 2 villagers for mine construction")
				Network.ask_spawn_villager()
				Network.ask_spawn_villager()
				test_phase = "wait_mine_built"
				test_start_time = Time.get_ticks_msec()
		"wait_mine_built":
			if elapsed > 60.0:
				_fail("mine was not built within 60s")
		"mine_done":
			if not phase_entered:
				phase_entered = true
				print("TEST: spawning villager for manual miner assignment")
				Network.ask_spawn_villager()
				test_phase = "wait_villager_spawn"
				test_start_time = Time.get_ticks_msec()
		"wait_villager_spawn":
			if elapsed > 10.0:
				_fail("villager did not spawn within 10s")
		"set_miner":
			if not phase_entered:
				phase_entered = true
				print("TEST: setting job to miner for ", target_villager_id)
				Network.ask_set_job(target_villager_id, "miner")
				test_phase = "wait_miner"
				test_start_time = Time.get_ticks_msec()
		"wait_miner":
			if elapsed > 30.0:
				_fail("miner job was not assigned within 30s")

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	print("TEST: full sync buildings=", data.get("buildings", {}).size(), " blueprints=", data.get("blueprints", {}).size(), " villagers=", data.get("villagers", {}).size())
	if test_phase == "wait_mine_blueprint" and data.get("blueprints", {}).size() >= 1:
		test_phase = "spawn_for_mine"
		phase_entered = false
		test_start_time = Time.get_ticks_msec()
	if test_phase == "wait_villager_spawn" and data.get("villagers", {}).size() >= 3:
		# pick a villager that is idle
		for id in data["villagers"]:
			var v = data["villagers"][id] as Dictionary
			if v.get("job", "") == "idle":
				target_villager_id = id
				break
		if target_villager_id != "":
			test_phase = "set_miner"
			phase_entered = false
			test_start_time = Time.get_ticks_msec()
		else:
			_fail("no idle villager found to assign")
	if test_phase == "wait_miner":
		for id in data.get("villagers", {}):
			if id == target_villager_id:
				var v = data["villagers"][id] as Dictionary
				if v.get("job", "") == "miner":
					_pass("manual miner assignment works")
					_finish()
					break

func _on_building_completed(pos: Vector2i, type_id: int):
	print("TEST: building completed at ", pos, " type ", type_id)
	if test_phase == "wait_mine_built" and type_id == PlanetGenerator.BuildingType.MINE:
		test_phase = "mine_done"
		phase_entered = false
		test_start_time = Time.get_ticks_msec()

func _on_villager_sync(villagers: Dictionary):
	pass

func _pass(msg: String):
	passed.append(msg)
	print("TEST PASS: ", msg)

func _fail(msg: String):
	failed.append(msg)
	print("TEST FAIL: ", msg)
	get_tree().quit(1)

func _finish():
	print("=== Manual job test finished ===")
	print("PASSED: ", passed.size(), " FAILED: ", failed.size())
	for p in passed:
		print("  PASS: ", p)
	for f in failed:
		print("  FAIL: ", f)
	if failed.is_empty():
		get_tree().quit(0)
	else:
		get_tree().quit(1)
