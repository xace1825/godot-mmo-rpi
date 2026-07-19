extends Node

var peer = ENetMultiplayerPeer.new()
var connected := false
var full_sync_received := false
var test_start_time := 0
var phase_start_time := 0
var test_phase := "init"
var phase_entered := false

var last_resources: Dictionary = {"wood": 0, "stone": 0, "food": 0}
var sync_data: Dictionary = {}
var assigned := false
var ground_item_dropped := false
var ground_item_pos := Vector2i(66, 66)

func _ready():
	Network.full_sync.connect(_on_full_sync)
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
				# Ask server to drop wood on the ground near default stockpile (64,64)
				Network.ask_drop_item(ground_item_pos, "wood", 5)
				print("TEST: asked to drop 5 wood on ground at ", ground_item_pos)
			if elapsed > 1.0:
				test_phase = "spawn"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"spawn":
			if not phase_entered:
				phase_entered = true
				Network.ask_spawn_villager()
				print("TEST: spawned villager")
			if elapsed > 2.0:
				test_phase = "assign"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"assign":
			if not phase_entered:
				phase_entered = true
				if sync_data.has("villagers") and not assigned:
					var ids: Array = sync_data["villagers"].keys()
					if ids.size() >= 1:
						assigned = true
						Network.ask_set_job(ids[0], "hauler")
						print("TEST: assigned hauler job to villager ", ids[0])
			if elapsed > 2.0:
				test_phase = "wait_haul"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
		"wait_haul":
			if elapsed > 60.0:
				_verify()
	if elapsed_total > 90.0:
		_fail("overall timeout")

func _on_resource_sync(resources: Dictionary):
	last_resources = resources.duplicate()
	print("TEST: resources wood=", resources.get("wood", 0), " stone=", resources.get("stone", 0), " food=", resources.get("food", 0))

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	sync_data = data.duplicate()

func _verify():
	var wood: int = last_resources.get("wood", 0)
	if wood >= 505:
		print("TEST PASS: hauler moved ground wood to stockpile (wood=", wood, ")")
		get_tree().quit(0)
	else:
		_fail("hauler did not move ground wood to stockpile (wood=" + str(wood) + ")")

func _fail(msg: String):
	print("TEST FAIL: " + msg)
	get_tree().quit(1)
