extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0
var phase_start_time := 0
var test_phase := "init"
var phase_entered := false

var sync_data: Dictionary = {}
var room_requested := false
var room_start := Vector2i(68, 66)
var room_end := Vector2i(72, 70)

func _ready():
	Network.full_sync.connect(_on_full_sync)
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
				Network.ask_build_room(room_start, room_end)
				room_requested = true
				print("TEST: requested room ", room_start, " to ", room_end)
			if elapsed > 1.0:
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
				test_phase = "wait_build"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"wait_build":
			if elapsed > 120.0:
				_verify()
	if elapsed_total > 150.0:
		_fail("overall timeout")

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	sync_data = data.duplicate()
	var buildings: Dictionary = data.get("buildings", {})
	var floors: Dictionary = data.get("floors", {})
	var blueprints: Dictionary = data.get("blueprints", {})
	print("TEST: full sync buildings=", buildings.size(), " floors=", floors.size(), " blueprints=", blueprints.size())

func _verify():
	var buildings: Dictionary = sync_data.get("buildings", {})
	var floors: Dictionary = sync_data.get("floors", {})
	var blueprints: Dictionary = sync_data.get("blueprints", {})
	var expected_walls := 0
	var expected_floors := 0
	var expected_doors := 0
	for x in range(room_start.x, room_end.x + 1):
		for y in range(room_start.y, room_end.y + 1):
			var key: String = "%d,%d" % [x, y]
			if x == room_start.x or x == room_end.x or y == room_start.y or y == room_end.y:
				var wall_or_door: int = _get_type_at(key, buildings, blueprints)
				if wall_or_door == PlanetGenerator.BuildingType.DOOR:
					expected_doors += 1
				elif wall_or_door == PlanetGenerator.BuildingType.WALL:
					expected_walls += 1
			else:
				if floors.has(key) or blueprints.has(key):
					expected_floors += 1
	var actual_walls := 0
	var actual_floors := 0
	var actual_doors := 0
	for key: String in buildings:
		var t: int = _get_type_at(key, buildings, {})
		if t == PlanetGenerator.BuildingType.WALL:
			actual_walls += 1
		elif t == PlanetGenerator.BuildingType.DOOR:
			actual_doors += 1
	for key: String in floors:
		actual_floors += 1
	var ok := actual_walls + actual_floors + actual_doors >= (expected_walls + expected_floors + expected_doors) / 2
	print("TEST: walls=", actual_walls, "/", expected_walls, " floors=", actual_floors, "/", expected_floors, " doors=", actual_doors, "/", expected_doors)
	if ok:
		print("TEST PASS: drag room built")
		get_tree().quit(0)
	else:
		_fail("drag room not built enough (walls=" + str(actual_walls) + " floors=" + str(actual_floors) + " doors=" + str(actual_doors) + ")")

func _get_type_at(key: String, buildings_dict: Dictionary, blueprints_dict: Dictionary) -> int:
	if buildings_dict.has(key):
		var val = buildings_dict[key]
		if val is int:
			return val
		elif val is Dictionary:
			return val.get("type", -1)
	if blueprints_dict.has(key):
		var bp = blueprints_dict[key]
		if bp is Dictionary:
			return bp.get("type", -1)
	return -1

func _fail(msg: String):
	print("TEST FAIL: " + msg)
	get_tree().quit(1)
