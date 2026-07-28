extends Node

# Multi-client sanity test. Usage:
#   godot --headless --path . --scene multi_client_sanity.tscn --client-index 0
# Server must already be running on 127.0.0.1:7777.

const DEFAULT_SERVER_IP: String = "127.0.0.1"
const DEFAULT_SERVER_PORT: int = 7777

const BASE_POSITIONS: Array = [Vector2i(60, 60), Vector2i(80, 80)]
const BUILD_OFFSETS: Array = [Vector2i(2, 0), Vector2i(2, 0)]

var client_index: int = 0
var connected := false
var full_sync_received := false
var received_stockpiles: Dictionary = {}
var received_buildings: Dictionary = {}
var received_blueprints: Dictionary = {}
var phase: String = "connect"
var phase_entered: bool = false
var phase_start_time: int = 0
var _finished: bool = false
var _base_settled: bool = false

func _ready():
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--client-index" and i + 1 < args.size():
			client_index = args[i + 1].to_int()
	print("Multi-client test client ", client_index, " starting")
	Network.full_sync.connect(_on_full_sync)
	Network.stockpile_added.connect(_on_stockpile_added)
	Network.building_placed.connect(_on_building_placed)
	Network.blueprint_placed.connect(_on_blueprint_placed)
	Network.base_settled_at.connect(_on_base_settled)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("connection failed"))
	Network.start_client(DEFAULT_SERVER_IP, DEFAULT_SERVER_PORT)
	phase_start_time = Time.get_ticks_msec()

func _on_connected():
	connected = true
	print("Client ", client_index, " connected")

func _on_base_settled(pos: Vector2i):
	_base_settled = true
	print("Client ", client_index, " base settled at ", pos)

func _settle_if_needed():
	if _base_settled:
		return
	var pos: Vector2i = BASE_POSITIONS[client_index % BASE_POSITIONS.size()]
	print("Client ", client_index, " requesting settle at ", pos)
	Network.ask_settle_base(pos)

func _on_full_sync(data: Dictionary):
	full_sync_received = true
	var my_id := str(multiplayer.get_unique_id())
	var bases: Dictionary = data.get("player_bases", {})
	if bases.has(my_id):
		_base_settled = true
		print("Client ", client_index, " already has base at ", bases[my_id])
	received_stockpiles = data.get("stockpiles", {}).duplicate()
	received_buildings = data.get("buildings", {}).duplicate()
	received_blueprints.clear()
	var bps := data.get("blueprints", {}) as Dictionary
	for key in bps:
		received_blueprints[key] = bps[key]
	print("Client ", client_index, " full sync: buildings=", received_buildings.size(), " stockpiles=", received_stockpiles.size(), " blueprints=", received_blueprints.size())
	if not _base_settled:
		_settle_if_needed()

func _on_stockpile_added(id: String, data: Dictionary):
	received_stockpiles[id] = data
	print("Client ", client_index, " saw stockpile added ", id)

func _on_building_placed(pos: Vector2i, type_id: int):
	var key := "%d,%d" % [pos.x, pos.y]
	received_buildings[key] = type_id
	print("Client ", client_index, " saw building completed at ", key, " type ", type_id)

func _on_blueprint_placed(pos: Vector2i, type_id: int):
	var key := "%d,%d" % [pos.x, pos.y]
	received_blueprints[key] = {"type": type_id, "pos": {"x": pos.x, "y": pos.y}}
	print("Client ", client_index, " saw blueprint at ", key, " type ", type_id)

func _physics_process(_delta: float):
	var elapsed: float = (Time.get_ticks_msec() - phase_start_time) / 1000.0
	if not connected or not full_sync_received:
		if elapsed > 20.0:
			_fail("timeout waiting for connection/full sync")
		return
	if not _base_settled:
		if elapsed > 30.0:
			_fail("timeout waiting for base settlement")
		if (Time.get_ticks_msec() % 1000) < 50:
			_settle_if_needed()
		return
	match phase:
		"connect":
			phase = "wait" if client_index == 1 else "act"
			phase_entered = false
			phase_start_time = Time.get_ticks_msec()
		"wait":
			# Client 1 waits until it observes at least one remote blueprint/stockpile,
			# confirming it sees client 0's world changes.
			if not phase_entered:
				phase_entered = true
				print("Client 1 waiting to observe client 0 actions...")
			if received_blueprints.size() >= 1 or received_buildings.size() >= 1 or received_stockpiles.size() >= 2:
				print("TEST PASS client 1: observed remote actions")
				phase = "act"
				phase_entered = false
				phase_start_time = Time.get_ticks_msec()
			elif elapsed > 60.0:
				_fail("client 1 did not observe remote actions")
		"act":
			if not phase_entered:
				phase_entered = true
				var build_pos: Vector2i = BASE_POSITIONS[client_index] + BUILD_OFFSETS[client_index]
				Network.ask_build(build_pos, PlanetGenerator.BuildingType.SAWMILL)
				print("Client ", client_index, " placed sawmill blueprint at ", build_pos)
			if elapsed > 60.0:
				_fail("overall timeout during act phase")
			var bp0 := "%d,%d" % [BASE_POSITIONS[0].x + BUILD_OFFSETS[0].x, BASE_POSITIONS[0].y + BUILD_OFFSETS[0].y]
			if client_index == 0:
				if received_blueprints.has(bp0):
					_finish()
			else:
				var bp1 := "%d,%d" % [BASE_POSITIONS[1].x + BUILD_OFFSETS[1].x, BASE_POSITIONS[1].y + BUILD_OFFSETS[1].y]
				if received_blueprints.has(bp1) and received_blueprints.has(bp0):
					_finish()

func _fail(msg: String):
	if _finished:
		return
	print("TEST FAIL client ", client_index, ": ", msg)
	get_tree().quit(1)

func _finish():
	if _finished:
		return
	_finished = true
	print("TEST PASS client ", client_index, ": observed ", received_buildings.size(), " buildings and ", received_blueprints.size(), " blueprints")
	print("Client ", client_index, " final stockpiles=", received_stockpiles.size())
	get_tree().quit(0)
