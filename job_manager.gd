extends Node

const TICK_RATE: float = 1.0
const WORK_UNITS_PER_TICK: float = 0.33
const BUILD_UNITS_PER_TICK: float = 0.25
const PRODUCTION_AMOUNT: int = 1

var tick_timer: float = 0.0

func _physics_process(delta):
	if not multiplayer.is_server():
		return
	tick_timer += delta
	if tick_timer >= TICK_RATE:
		tick_timer -= TICK_RATE
		_tick()

func _ready():
	if not multiplayer.is_server():
		set_physics_process(false)

func _tick():
	_process_builders()
	_process_workers()
	Network.broadcast_resource_sync()
	Network.rpc("sync_villagers", GameState.villagers.duplicate())

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
		var current_pos = Vector2i(int(v["pos"]["x"]), int(v["pos"]["y"]))
		
		match v["state"]:
			"moving_to_blueprint":
				if current_pos == pos:
					v["state"] = "building"
					print("Server: builder ", id, " reached blueprint at ", pos)
				else:
					v["pos"] = _step_toward(current_pos, pos)
					v["state"] = "moving_to_blueprint"
			"building":
				bp["progress"] += BUILD_UNITS_PER_TICK
				if bp["progress"] >= 1.0:
					bp["progress"] = 1.0
					if GameState.pay_blueprint_cost(pos):
						if GameState.complete_blueprint(pos):
							# For production stations, builder becomes worker
							if bp["type"] < PlanetGenerator.BuildingType.WALL:
								v["job"] = PlanetGenerator.get_job_type(bp["type"])
								v["workplace"] = {"x": pos.x, "y": pos.y}
								v["home"] = {"x": pos.x, "y": pos.y}
								v["building_type"] = bp["type"]
								v["carrying"] = {"resource": "", "amount": 0}
								print("Server: builder ", id, " became ", v["job"], " at ", pos)
							v["target_blueprint"] = ""
							v["state"] = "idle"
						else:
							# complete_blueprint failed unexpectedly, retry next tick
							v["state"] = "moving_to_stockpile"
					else:
						# Not enough resources, go fetch them
						v["state"] = "moving_to_stockpile"
						print("Server: builder ", id, " needs resources for blueprint at ", pos)
			"moving_to_stockpile":
				var stock_id = GameState.find_nearest_stockpile(pos)
				if stock_id == "":
					v["state"] = "waiting_resources"
					continue
				var stock = GameState.stockpiles[stock_id]
				var stock_pos = Vector2i(int(stock["topleft"]["x"]), int(stock["topleft"]["y"]))
				if current_pos == stock_pos:
					if GameState.pay_blueprint_cost(pos):
						v["state"] = "returning_to_blueprint"
						print("Server: builder ", id, " fetched resources from ", stock_id)
					else:
						v["state"] = "waiting_resources"
						print("Server: builder ", id, " waiting for resources at ", stock_id)
				else:
					v["pos"] = _step_toward(current_pos, stock_pos)
			"returning_to_blueprint":
				if current_pos == pos:
					v["state"] = "building"
				else:
					v["pos"] = _step_toward(current_pos, pos)
			"waiting_resources":
				# Retry moving to stockpile next tick in case resources arrived
				v["state"] = "moving_to_stockpile"

func _step_toward(from_pos: Vector2i, to_pos: Vector2i) -> Dictionary:
	var dx = signi(to_pos.x - from_pos.x)
	var dy = signi(to_pos.y - from_pos.y)
	if dx != 0 and dy != 0:
		# Move diagonally one axis at a time to keep simple
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
		match v["state"]:
			"idle", "working":
				# Apply indoor/outdoor work speed modifier
				var wp := Vector2i(int(v["workplace"]["x"]), int(v["workplace"]["y"]))
				var speed_mult: float = 1.0
				if not GameState.is_indoor_station(wp):
					speed_mult = 0.6
				v["progress"] += WORK_UNITS_PER_TICK * speed_mult
				v["state"] = "working"
				if v["progress"] >= 1.0:
					v["progress"] = 0.0
					v["carrying"] = {"resource": res, "amount": PRODUCTION_AMOUNT}
					v["state"] = "hauling"
					print("Server: worker ", id, " produced ", res, " at ", wp, " (speed x", speed_mult, ")")
			"hauling":
				var wp := Vector2i(int(v["workplace"]["x"]), int(v["workplace"]["y"]))
				if GameState.deposit_to_nearest_stockpile(wp, v["carrying"]["resource"], v["carrying"]["amount"]):
					v["carrying"] = {"resource": "", "amount": 0}
					v["state"] = "idle"
				else:
					# No stockpile yet; drop resources on ground? For now keep carrying and retry
					v["state"] = "hauling"
