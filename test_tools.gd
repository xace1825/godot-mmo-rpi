extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0
var phase_start_time := 0
var test_phase := "init"
var phase_entered := false

var smithy_pos := Vector2i(67, 64)

var last_resources: Dictionary = {"planks": 0, "tools": 0}
var max_tools: int = 0
var sync_data: Dictionary = {}
var assigned := false
var saw_tool_produced := false

func _ready():
	Network.full_sync.connect(_on_full_sync)
	Network.blueprint_placed.connect(_on_blueprint)
	Network.building_placed.connect(_on_building_completed)
	Network.resource_sync.connect(_on_resource_sync)
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
				Network.ask_build(smithy_pos, PlanetGenerator.BuildingType.SMITHY)
				print("TEST: placed smithy blueprint")
			if elapsed > 5.0:
				test_phase = "spawn"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"spawn":
			if not phase_entered:
				phase_entered = true
				Network.ask_spawn_villager()
				print("TEST: spawned villager")
			if elapsed > 3.0:
				test_phase = "assign"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"assign":
			if not phase_entered:
				phase_entered = true
				if sync_data.has("villagers"):
					var ids: Array = sync_data["villagers"].keys()
					if ids.size() >= 1 and not assigned:
						assigned = true
						Network.ask_set_job(ids[0], "toolsmith")
						print("TEST: assigned toolsmith job")
			if elapsed > 3.0:
				test_phase = "wait_production"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"wait_production":
			if saw_tool_produced:
				test_phase = "verify"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
			elif elapsed > 60.0:
				_verify()
		"verify":
			_verify()
	if elapsed_total > 90.0:
		_fail("overall timeout")

func _on_blueprint(pos: Vector2i, type_id: int):
	print("TEST: blueprint placed at ", pos, " type ", type_id)

func _on_building_completed(pos: Vector2i, type_id: int):
	print("TEST: building completed at ", pos, " type ", type_id)

func _on_resource_sync(resources: Dictionary):
	last_resources = resources.duplicate()
	var t: int = int(resources.get("tools", 0))
	if t > max_tools:
		max_tools = t
	print("TEST: resources planks=", resources.get("planks", 0), " tools=", resources.get("tools", 0), " max_tools=", max_tools)
	if t > 20:
		saw_tool_produced = true
		print("TEST: tools produced")

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	sync_data = data.duplicate()

func _verify():
	var ok := true
	var planks: int = last_resources.get("planks", 0)
	var tools: int = last_resources.get("tools", 0)

	if not saw_tool_produced:
		_fail("tools were never produced")
		ok = false
	if planks >= 100:
		_fail("toolsmith did not consume planks (" + str(planks) + ")")
		ok = false
	if max_tools <= 20:
		_fail("tools not produced (max=" + str(max_tools) + ")")
		ok = false
	if ok:
		print("TEST PASS: toolsmith produces tools from planks")
		get_tree().quit()

func _fail(msg: String):
	print("TEST FAIL: ", msg)
	get_tree().quit()
