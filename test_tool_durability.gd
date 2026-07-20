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
var smithy_pos := Vector2i(67, 64)

var saw_done := false
var smithy_done := false

var equipped_villager := ""
var observed_durability_drop := false
var observed_broken := false
var last_tool_info: Dictionary = {}

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
				print("TEST: placing sawmill and smithy blueprints and spawning villagers")
				Network.ask_build(saw_pos, PlanetGenerator.BuildingType.SAWMILL)
				Network.ask_build(smithy_pos, PlanetGenerator.BuildingType.SMITHY)
				Network.ask_spawn_villager()
				Network.ask_spawn_villager()
				test_phase = "wait_villagers"
				test_start_time = Time.get_ticks_msec()
		"wait_villagers":
			if elapsed > 3.0:
				test_phase = "wait_buildings"
				test_start_time = Time.get_ticks_msec()
		"wait_buildings":
			if saw_done and smithy_done:
				print("TEST: buildings ready")
				phase_entered = false
				test_phase = "assign"
				test_start_time = Time.get_ticks_msec()
			if elapsed > 60.0:
				_fail("buildings did not complete")
		"assign":
			if elapsed > 3.0:
				var villagers: Dictionary = Network.last_full_sync.get("villagers", {})
				var ids := villagers.keys()
				if ids.size() >= 2:
					print("TEST: assigning ", ids[0], " to lumberjack and ", ids[1], " to toolsmith")
					Network.ask_set_job(ids[0], "lumberjack")
					Network.ask_set_job(ids[1], "toolsmith")
					test_phase = "wait_equip"
					test_start_time = Time.get_ticks_msec()
				else:
					_fail("not enough villagers")
			if elapsed > 20.0:
				_fail("could not assign jobs")
		"wait_equip":
			# Wait until lumberjack equips a tool
			if equipped_villager != "":
				print("TEST: ", equipped_villager, " equipped a tool")
				test_phase = "wait_wear"
				test_start_time = Time.get_ticks_msec()
			if elapsed > 30.0:
				_fail("tool was not equipped")
		"wait_wear":
			if observed_durability_drop and not passed.has("tool durability decreased during work"):
				_pass("tool durability decreased during work")
			if observed_broken and not passed.has("tool eventually broke"):
				_pass("tool eventually broke")
				_finish()
			if elapsed > 120.0:
				if observed_durability_drop:
					_finish()
				else:
					_fail("tool durability did not decrease")

func _on_blueprint(pos: Vector2i, type_id: int):
	print("TEST: blueprint placed at ", pos, " type ", type_id)

func _on_building_completed(pos: Vector2i, type_id: int):
	print("TEST: building completed at ", pos, " type ", type_id)
	if pos == saw_pos:
		saw_done = true
	elif pos == smithy_pos:
		smithy_done = true

func _on_villager_sync(villagers: Dictionary):
	for id: String in villagers:
		var v: Dictionary = villagers[id]
		var eq: Dictionary = v.get("equipment", {})
		var tool: Dictionary = eq.get("tool", {})
		if tool.get("type", "") == "tool":
			if equipped_villager == "":
				equipped_villager = id
			var dur: int = int(tool.get("durability", 0))
			var max_dur: int = int(tool.get("max_durability", 0))
			if max_dur > 0 and dur < max_dur:
				observed_durability_drop = true
			if dur == 0:
				observed_broken = true
			last_tool_info = tool.duplicate()

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
	print("LAST TOOL INFO: ", last_tool_info)
	print("OBSERVED durability drop=", observed_durability_drop, " broken=", observed_broken)
	print("PASSED: ", passed.size(), " FAILED: ", failed.size())
	get_tree().quit(0)
