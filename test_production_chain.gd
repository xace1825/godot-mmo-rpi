extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0
var phase_start_time := 0
var test_phase := "init"
var phase_entered := false

var carpenter_pos := Vector2i(65, 64)
var mason_pos := Vector2i(66, 64)

var last_resources: Dictionary = {"wood": 0, "stone": 0, "planks": 0, "blocks": 0}
var sync_data: Dictionary = {}
var assigned := false

func _ready():
	Network.full_sync.connect(_on_full_sync)
	Network.building_placed.connect(_on_building_completed)
	Network.blueprint_placed.connect(_on_blueprint)
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
				Network.ask_build(carpenter_pos, PlanetGenerator.BuildingType.CARPENTER)
				Network.ask_build(mason_pos, PlanetGenerator.BuildingType.MASON)
				print("TEST: placed carpenter + mason blueprints")
			if elapsed > 3.0:
				test_phase = "spawn"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"spawn":
			if not phase_entered:
				phase_entered = true
				Network.ask_spawn_villager()
				Network.ask_spawn_villager()
				print("TEST: spawned 2 villagers")
			if elapsed > 3.0:
				test_phase = "assign"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"assign":
			if not phase_entered:
				phase_entered = true
				if sync_data.has("villagers"):
					var ids: Array = sync_data["villagers"].keys()
					if ids.size() >= 2 and not assigned:
						assigned = true
						Network.ask_set_job(ids[0], "carpenter")
						Network.ask_set_job(ids[1], "mason")
						print("TEST: assigned carpenter + mason jobs")
			if elapsed > 3.0:
				test_phase = "wait_production"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"wait_production":
			if elapsed > 120.0:
				_verify()
	if elapsed_total > 180.0:
		_fail("overall timeout")

func _on_blueprint(pos: Vector2i, type_id: int):
	print("TEST: blueprint placed at ", pos, " type ", type_id)

func _on_building_completed(pos: Vector2i, type_id: int):
	print("TEST: building completed at ", pos, " type ", type_id)

func _on_resource_sync(resources: Dictionary):
	last_resources = resources.duplicate()
	print("TEST: resources wood=", resources.get("wood", 0), " stone=", resources.get("stone", 0), " planks=", resources.get("planks", 0), " blocks=", resources.get("blocks", 0))
	if test_phase == "wait_production":
		if resources.get("planks", 0) > 100 and resources.get("blocks", 0) > 100:
			print("TEST: refined resources produced")
			test_phase = "verify"
			phase_entered = false
			phase_start_time = Time.get_ticks_msec()
	if test_phase == "verify":
		_verify()

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	sync_data = data.duplicate()

func _verify():
	var ok := true
	var wood: int = last_resources.get("wood", 0)
	var stone: int = last_resources.get("stone", 0)
	var planks: int = last_resources.get("planks", 0)
	var blocks: int = last_resources.get("blocks", 0)

	if wood >= 500:
		_fail("carpenter did not consume wood (" + str(wood) + ")")
		ok = false
	if stone >= 500:
		_fail("mason did not consume stone (" + str(stone) + ")")
		ok = false
	if planks <= 100:
		_fail("planks not produced (" + str(planks) + ")")
		ok = false
	if blocks <= 100:
		_fail("blocks not produced (" + str(blocks) + ")")
		ok = false
	if ok:
		print("TEST PASS: production chain wood->planks and stone->blocks works")
		get_tree().quit(0)

func _fail(msg: String):
	print("TEST FAIL: " + msg)
	get_tree().quit(1)
