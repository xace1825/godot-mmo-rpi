extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0
var phase_start_time := 0
var test_phase := "init"
var phase_entered := false

var bp1_pos := Vector2i(72, 64)
var sync_data: Dictionary = {}

func _ready():
	Network.full_sync.connect(_on_full_sync)
	Network.villager_sync.connect(_on_villager_sync)
	Network.blueprint_placed.connect(_on_blueprint_placed)
	peer.create_client("127.0.0.1", 7777)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): connected = true)
	multiplayer.connection_failed.connect(func(): _fail("connection failed"))
	test_start_time = Time.get_ticks_msec()
	phase_start_time = test_start_time

func _physics_process(_delta):
	var elapsed_total: float = (Time.get_ticks_msec() - test_start_time) / 1000.0
	if not connected or not full_sync_received:
		if elapsed_total > 20.0:
			_fail("connection or full sync timeout")
		return
	var elapsed: float = (Time.get_ticks_msec() - phase_start_time) / 1000.0
	match test_phase:
		"init":
			if not phase_entered:
				phase_entered = true
				Network.ask_toggle_job_priority("builder")
				print("TEST: toggled builder priority off")
			if elapsed > 3.0:
				test_phase = "place"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"place":
			if not phase_entered:
				phase_entered = true
				Network.ask_build(bp1_pos, PlanetGenerator.BuildingType.SAWMILL)
				print("TEST: placed sawmill blueprint at ", bp1_pos, " with builder disabled")
			if elapsed > 3.0:
				test_phase = "spawn"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"spawn":
			if not phase_entered:
				phase_entered = true
				Network.ask_spawn_villager()
				print("TEST: spawned villager")
			if elapsed > 3.0:
				test_phase = "verify"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"verify":
			if elapsed > 20.0:
				_verify()
	if elapsed_total > 60.0:
		_fail("overall timeout")

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	sync_data = data.duplicate()

func _on_villager_sync(villagers: Dictionary):
	sync_data["villagers"] = villagers.duplicate()

func _on_blueprint_placed(pos: Vector2i, type_id: int):
	var key: String = "%d,%d" % [pos.x, pos.y]
	if not sync_data.has("blueprints"):
		sync_data["blueprints"] = {}
	sync_data["blueprints"][key] = type_id
	print("TEST: blueprint placed at ", pos, " type ", type_id)

func _blueprint_exists(pos: Vector2i) -> bool:
	var key: String = "%d,%d" % [pos.x, pos.y]
	var blueprints: Dictionary = sync_data.get("blueprints", {})
	return blueprints.has(key)

func _get_villager_jobs() -> Dictionary:
	var out := {}
	var villagers: Dictionary = sync_data.get("villagers", {})
	for id in villagers:
		out[id] = villagers[id].get("job", "idle")
	return out

func _verify():
	var jobs := _get_villager_jobs()
	var has_builder := false
	for id in jobs:
		if jobs[id] == "builder":
			has_builder = true
			break
	var bp_still_exists := _blueprint_exists(bp1_pos)
	var priorities: Dictionary = sync_data.get("job_priorities", {})
	var builder_priority_off: bool = priorities.get("builder", true) == false
	print("TEST: jobs=", jobs, " blueprint_exists=", bp_still_exists, " builder_priority_off=", builder_priority_off)
	if not builder_priority_off:
		_fail("builder priority was not toggled off")
		return
	if has_builder:
		_fail("builder priority off but villager assigned as builder")
		return
	if not bp_still_exists:
		_fail("blueprint was completed despite builder priority off")
		return
	print("TEST PASS: builder priority toggle prevents auto-assignment and construction")
	get_tree().quit()

func _fail(msg: String):
	print("TEST FAIL: ", msg)
	get_tree().quit(1)
