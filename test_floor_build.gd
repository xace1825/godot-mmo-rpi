extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0.0
var test_phase := "init"
var passed := []
var failed := []
var phase_entered := false
var floor_pos := Vector2i(68, 66)
var bed_pos := Vector2i(69, 66)
var sawmill_pos := Vector2i(70, 66)
var sync_data: Dictionary = {}

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
				Network.ask_build(floor_pos, PlanetGenerator.BuildingType.FLOOR)
				Network.ask_build(bed_pos, PlanetGenerator.BuildingType.FLOOR)
				Network.ask_build(sawmill_pos, PlanetGenerator.BuildingType.FLOOR)
				print("TEST: placed 3 floor blueprints")
				test_phase = "spawn"
				phase_entered = false
				test_start_time = Time.get_ticks_msec()
		"spawn":
			if not phase_entered:
				phase_entered = true
				print("TEST: spawning 3 villagers")
				Network.ask_spawn_villager()
				Network.ask_spawn_villager()
				Network.ask_spawn_villager()
				test_phase = "wait_floors"
				test_start_time = Time.get_ticks_msec()
		"wait_floors":
			if elapsed > 60.0:
				_fail("floor blueprints did not complete")
		"place_buildings":
			if not phase_entered:
				phase_entered = true
				Network.ask_build(bed_pos, PlanetGenerator.BuildingType.BED)
				Network.ask_build(sawmill_pos, PlanetGenerator.BuildingType.SAWMILL)
				print("TEST: placed bed and sawmill on top of floors")
				test_phase = "wait_buildings"
				test_start_time = Time.get_ticks_msec()
		"wait_buildings":
			if elapsed > 30.0:
				_fail("building blueprints on floors did not complete")
		"verify":
			if not phase_entered:
				phase_entered = true
				_verify()

func _on_blueprint(pos: Vector2i, type_id: int):
	print("TEST: blueprint placed at ", pos, " type ", type_id)

func _on_building_completed(pos: Vector2i, type_id: int):
	print("TEST: building completed at ", pos, " type ", type_id)
	var key := "%d,%d" % [pos.x, pos.y]
	if type_id == PlanetGenerator.BuildingType.FLOOR:
		if not sync_data.has("floors"):
			sync_data["floors"] = {}
		sync_data["floors"][key] = type_id
	else:
		if not sync_data.has("buildings"):
			sync_data["buildings"] = {}
		sync_data["buildings"][key] = type_id
	if test_phase == "wait_floors":
		var floors_done := true
		for p in [floor_pos, bed_pos, sawmill_pos]:
			var k := "%d,%d" % [p.x, p.y]
			if not sync_data.get("floors", {}).has(k):
				floors_done = false
				break
		if floors_done:
			test_phase = "place_buildings"
			phase_entered = false
			test_start_time = Time.get_ticks_msec()
	elif test_phase == "wait_buildings":
		var bed_done := false
		var saw_done := false
		var bkey := "%d,%d" % [bed_pos.x, bed_pos.y]
		var skey := "%d,%d" % [sawmill_pos.x, sawmill_pos.y]
		if sync_data.get("buildings", {}).get(bkey, -1) == PlanetGenerator.BuildingType.BED:
			bed_done = true
		if sync_data.get("buildings", {}).get(skey, -1) == PlanetGenerator.BuildingType.SAWMILL:
			saw_done = true
		if bed_done and saw_done:
			test_phase = "verify"
			phase_entered = false
			test_start_time = Time.get_ticks_msec()

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	sync_data = data

func _verify():
	var fkey := "%d,%d" % [floor_pos.x, floor_pos.y]
	var bkey := "%d,%d" % [bed_pos.x, bed_pos.y]
	var skey := "%d,%d" % [sawmill_pos.x, sawmill_pos.y]
	var floors: Dictionary = sync_data.get("floors", {})
	var buildings: Dictionary = sync_data.get("buildings", {})
	var ok := true
	if not floors.has(fkey):
		_fail("floor missing at " + fkey)
		ok = false
	if buildings.get(bkey, -1) != PlanetGenerator.BuildingType.BED:
		_fail("bed missing on floor at " + bkey)
		ok = false
	if floors.get(bkey, -1) != PlanetGenerator.BuildingType.FLOOR:
		_fail("floor missing under bed at " + bkey)
		ok = false
	if buildings.get(skey, -1) != PlanetGenerator.BuildingType.SAWMILL:
		_fail("sawmill missing on floor at " + skey)
		ok = false
	if floors.get(skey, -1) != PlanetGenerator.BuildingType.FLOOR:
		_fail("floor missing under sawmill at " + skey)
		ok = false
	if ok:
		_pass("floor + building stacking works")
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
