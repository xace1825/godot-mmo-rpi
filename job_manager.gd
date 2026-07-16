extends Node

const TICK_RATE: float = 1.0
const WORK_UNITS_PER_TICK: float = 0.33
const BUILD_UNITS_PER_TICK: float = 0.25
const PRODUCTION_AMOUNT: int = 1
const VILLAGER_MOVE_SPEED: float = 1.0  # tiles per second (one tile per tick, smooth continuous movement)
const SYNC_INTERVAL: float = 0.1

var tick_timer: float = 0.0
var sync_timer: float = 0.0

func _physics_process(delta):
	if not multiplayer.is_server():
		return
	
	# Smooth movement interpolation on server
	_update_villager_movement(delta)
	
	sync_timer += delta
	if sync_timer >= SYNC_INTERVAL:
		sync_timer -= SYNC_INTERVAL
		if GameState.villagers.size() > 0:
			Network.rpc("sync_villagers", GameState.villagers.duplicate())
	
	tick_timer += delta
	if tick_timer >= TICK_RATE:
		tick_timer -= TICK_RATE
		_tick()

func _ready():
	set_physics_process(false)
	multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(id: int):
	if multiplayer.is_server():
		set_physics_process(true)
		print("JobManager enabled for server")

func _tick():
	_process_builders()
	_process_workers()
	Network.broadcast_resource_sync()

func _update_villager_movement(delta: float):
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		if v["from_pos"] == v["to_pos"]:
			continue
		v["move_progress"] += delta * VILLAGER_MOVE_SPEED
		if v["move_progress"] >= 1.0:
			v["move_progress"] = 0.0
			v["from_pos"] = v["to_pos"].duplicate()
			v["pos"] = v["to_pos"].duplicate()
		else:
			var from := Vector2(float(v["from_pos"]["x"]), float(v["from_pos"]["y"]))
			var to := Vector2(float(v["to_pos"]["x"]), float(v["to_pos"]["y"]))
			var interp := from.lerp(to, v["move_progress"])
			v["pos"] = {"x": interp.x, "y": interp.y}

func _process_builders():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		if v["job"] != "builder":
			continue
		var bp_key: String = v.get("target_blueprint", "")
		if bp_key == "" or not GameState.blueprints.has(bp_key):
			bp_key = _find_blueprint()
			if bp_key == "":
				v["state"] = "idle"
				continue
			v["target_blueprint"] = bp_key
			v["state"] = "moving_to_blueprint"
			print("Server: builder ", id, " assigned to blueprint ", bp_key)
		
		var bp = GameState.blueprints[bp_key] as Dictionary
		var pos = Vector2i(int(bp["pos"]["x"]), int(bp["pos"]["y"]))
		var current_tile = Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
		
		match v["state"]:
			"moving_to_blueprint":
				if current_tile == pos:
					v["state"] = "building"
					print("Server: builder ", id, " reached blueprint at ", pos)
				elif v["from_pos"] == v["to_pos"]:
					v["to_pos"] = _step_toward_dict(current_tile, pos)
			"building":
				bp["progress"] += BUILD_UNITS_PER_TICK
				if bp["progress"] >= 1.0:
					bp["progress"] = 1.0
					if GameState.pay_blueprint_cost(pos):
						if GameState.complete_blueprint(pos):
							v["target_blueprint"] = ""
							v["state"] = "idle"
							v["to_pos"] = v["pos"].duplicate()
							v["from_pos"] = v["pos"].duplicate()
							v["move_progress"] = 0.0
							print("Server: builder ", id, " finished building at ", pos)
						else:
							v["state"] = "moving_to_stockpile"
					else:
						v["state"] = "moving_to_stockpile"
						print("Server: builder ", id, " needs resources for blueprint at ", pos)
			"moving_to_stockpile":
				var stock_id = GameState.find_nearest_stockpile(pos)
				if stock_id == "":
					v["state"] = "waiting_resources"
					continue
				var stock = GameState.stockpiles[stock_id]
				var stock_pos = Vector2i(int(stock["topleft"]["x"]), int(stock["topleft"]["y"]))
				if current_tile == stock_pos:
					if GameState.pay_blueprint_cost(pos):
						v["state"] = "returning_to_blueprint"
						v["to_pos"] = _step_toward_dict(current_tile, pos)
						print("Server: builder ", id, " fetched resources from ", stock_id)
					else:
						v["state"] = "waiting_resources"
						print("Server: builder ", id, " waiting for resources at ", stock_id)
				elif v["from_pos"] == v["to_pos"]:
					v["to_pos"] = _step_toward_dict(current_tile, stock_pos)
			"returning_to_blueprint":
				if current_tile == pos:
					v["state"] = "building"
				elif v["from_pos"] == v["to_pos"]:
					v["to_pos"] = _step_toward_dict(current_tile, pos)
			"waiting_resources":
				# Retry moving to stockpile next tick in case resources arrived
				v["state"] = "moving_to_stockpile"

func _step_toward_dict(from_pos: Vector2i, to_pos: Vector2i) -> Dictionary:
	var dx = signi(to_pos.x - from_pos.x)
	var dy = signi(to_pos.y - from_pos.y)
	if dx != 0 and dy != 0:
		if randf() < 0.5:
			dy = 0
		else:
			dx = 0
	return {"x": from_pos.x + dx, "y": from_pos.y + dy}

func _find_blueprint() -> String:
	for key in GameState.blueprints:
		return key
	return ""

func _process_workers():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		var res := PlanetGenerator.get_resource_for_job(v["job"])
		if res == "":
			continue
		var current_tile = Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
		var workplace := Vector2i(int(v["workplace"]["x"]), int(v["workplace"]["y"]))
		match v["state"]:
			"idle", "working":
				# Walk to workplace if not there
				if current_tile != workplace:
					if v["from_pos"] == v["to_pos"]:
						v["to_pos"] = _step_toward_dict(current_tile, workplace)
				else:
					var speed_mult: float = 1.0
					if not GameState.is_indoor_station(workplace):
						speed_mult = 0.6
					v["progress"] += WORK_UNITS_PER_TICK * speed_mult
					v["state"] = "working"
					if v["progress"] >= 1.0:
						v["progress"] = 0.0
						v["carrying"] = {"resource": res, "amount": PRODUCTION_AMOUNT}
						v["state"] = "hauling"
						print("Server: worker ", id, " produced ", res, " at ", workplace, " (speed x", speed_mult, ")")
			"hauling":
				var stock_id := GameState.find_nearest_stockpile(workplace)
				if stock_id == "":
					# No stockpile yet; keep carrying and retry
					v["state"] = "hauling"
					continue
				var stock = GameState.stockpiles[stock_id]
				var stock_pos = Vector2i(int(stock["topleft"]["x"]), int(stock["topleft"]["y"]))
				if current_tile == stock_pos:
					if GameState.deposit_to_nearest_stockpile(workplace, v["carrying"]["resource"], v["carrying"]["amount"]):
						v["carrying"] = {"resource": "", "amount": 0}
						v["state"] = "idle"
						v["to_pos"] = v["pos"].duplicate()
						v["from_pos"] = v["pos"].duplicate()
					else:
						v["state"] = "hauling"
				elif v["from_pos"] == v["to_pos"]:
					v["to_pos"] = _step_toward_dict(current_tile, stock_pos)
