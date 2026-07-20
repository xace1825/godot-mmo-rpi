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
var bed_requested := false
var villager_id := ""
var start_energy := 0.0
var start_comfort := 0.0
var peak_energy := 0.0
var peak_comfort := 0.0
var measured := false

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
				# Build a 3x3 room with a bed inside, adjacent to default stockpile
				Network.ask_build_room(Vector2i(65, 63), Vector2i(67, 65))
				Network.ask_build(Vector2i(66, 64), PlanetGenerator.BuildingType.BED)
				print("TEST: requested room and bed adjacent to stockpile")
			if elapsed > 2.0:
				test_phase = "spawn"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"spawn":
			if not phase_entered:
				phase_entered = true
				Network.ask_spawn_villager()
				Network.ask_spawn_villager()
				print("TEST: spawned 2 villagers")
			if elapsed > 2.0:
				test_phase = "assign_build"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"assign_build":
			if not phase_entered:
				phase_entered = true
				if sync_data.has("villagers"):
					for id: Variant in sync_data["villagers"].keys():
						Network.ask_set_job(str(id), "builder")
				print("TEST: assigned villagers as builders")
			if elapsed > 2.0:
				test_phase = "wait_build"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"wait_build":
			if sync_data.has("villagers") and sync_data["villagers"].size() >= 1:
				var ids: Array = sync_data["villagers"].keys()
				villager_id = str(ids[0])
			var room_built := true
			for x in range(65, 68):
				for y in range(63, 66):
					var key: String = "%d,%d" % [x, y]
					if x == 65 or x == 67 or y == 63 or y == 65:
						if not (sync_data.get("buildings", {}).has(key) or sync_data.get("blueprints", {}).has(key)):
							room_built = false
					else:
						if not (sync_data.get("floors", {}).has(key) or sync_data.get("blueprints", {}).has(key)):
							room_built = false
			if room_built and villager_id != "" and elapsed > 5.0:
				test_phase = "tire"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
			elif elapsed > 120.0:
				_fail("room/bed not built in time")
		"tire":
			if not phase_entered:
				phase_entered = true
				if sync_data.has("villagers"):
					for id: Variant in sync_data["villagers"].keys():
						Network.ask_set_job(str(id), "idle")
				print("TEST: set villagers idle to force rest")
			if elapsed > 10.0 and not measured and villager_id != "":
				measured = true
				var v: Dictionary = sync_data.get("villagers", {}).get(villager_id, {})
				start_energy = v.get("needs", {}).get("energy", 0.0)
				start_comfort = v.get("needs", {}).get("comfort", 0.0)
				print("TEST: pre-sleep energy=", start_energy, " comfort=", start_comfort)
			if villager_id != "":
				var v: Dictionary = sync_data.get("villagers", {}).get(villager_id, {})
				var cur_energy: float = v.get("needs", {}).get("energy", 0.0)
				var cur_comfort: float = v.get("needs", {}).get("comfort", 0.0)
				peak_energy = max(peak_energy, cur_energy)
				peak_comfort = max(peak_comfort, cur_comfort)
			if elapsed > 60.0:
				_verify()
	if elapsed_total > 90.0:
		_fail("overall timeout")

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	sync_data = data.duplicate()

func _verify():
	print("TEST: pre-sleep energy=", start_energy, " comfort=", start_comfort)
	print("TEST: peak energy=", peak_energy, " comfort=", peak_comfort)
	if peak_energy > start_energy and peak_comfort > start_comfort:
		print("TEST PASS: comfort and energy improved with bed/room")
		get_tree().quit(0)
	else:
		_fail("comfort/energy did not improve (peak_energy=" + str(peak_energy) + " peak_comfort=" + str(peak_comfort) + ")")

func _fail(msg: String):
	print("TEST FAIL: " + msg)
	get_tree().quit(1)
