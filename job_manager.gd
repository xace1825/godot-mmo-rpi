extends Node

const TICK_RATE: float = 1.0
const WORK_UNITS_PER_TICK: float = 0.33
const BUILD_UNITS_PER_TICK: float = 0.25
const PRODUCTION_AMOUNT: int = 1
const VILLAGER_MOVE_SPEED: float = 1.0
const SYNC_INTERVAL: float = 0.1

var tick_timer: float = 0.0
var sync_timer: float = 0.0

func _physics_process(delta):
	if not multiplayer.is_server():
		return
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
	_assign_idle_villagers()
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

func _assign_idle_villagers():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		if v["job"] != "idle":
			continue
		var sid := str(id)
		var bp_key := _find_blueprint(sid)
		if bp_key != "":
			var bp = GameState.blueprints[bp_key] as Dictionary
			var pos = Vector2i(int(bp["pos"]["x"]), int(bp["pos"]["y"]))
			v["job"] = "builder"
			v["target_blueprint"] = bp_key
			v["state"] = "moving_to_blueprint"
			v["workplace"] = {"x": pos.x, "y": pos.y}
			print("Server: idle villager ", id, " assigned as builder for ", bp_key)
			continue
		var station_pos := _find_station_without_worker(sid)
		if station_pos != Vector2i(-1, -1):
			var key: String = _pos_key(station_pos)
			var station_type: int = GameState.buildings[key]
			var job := PlanetGenerator.get_job_type(station_type)
			if job != "":
				v["job"] = job
				v["workplace"] = {"x": station_pos.x, "y": station_pos.y}
				v["state"] = "moving_to_work"
				print("Server: idle villager ", id, " assigned as ", job, " at ", station_pos)

func _find_station_without_worker(exclude_id: String = "") -> Vector2i:
	for key: String in GameState.buildings:
		var type_id: int = GameState.buildings[key]
		if not PlanetGenerator.is_station(type_id):
			continue
		var job_type := PlanetGenerator.get_job_type(type_id)
		if job_type == "":
			continue
		var slots: int = PlanetGenerator.get_job_slots(type_id)
		var current: int = 0
		for vid in GameState.villagers:
			if str(vid) == exclude_id:
				continue
			var v = GameState.villagers[vid] as Dictionary
			var wp = v.get("workplace", {}) as Dictionary
			var vjob: String = v["job"]
			var at_station: bool = wp.get("x", -1) == int(key.split(",")[0]) and wp.get("y", -1) == int(key.split(",")[1])
			if at_station and (vjob == job_type or v["state"] == "moving_to_work"):
				current += 1
		if current < slots:
			var parts := key.split(",")
			return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(-1, -1)

func _find_blueprint(exclude_id: String = "") -> String:
	for key in GameState.blueprints:
		if _is_blueprint_reserved(key, exclude_id):
			continue
		return key
	return ""

func _is_blueprint_reserved(key: String, exclude_id: String = "") -> bool:
	for vid in GameState.villagers:
		if str(vid) == exclude_id:
			continue
		var v = GameState.villagers[vid] as Dictionary
		if v.get("target_blueprint", "") == key:
			return true
		var wp = v.get("workplace", {}) as Dictionary
		var parts := key.split(",")
		if wp.get("x", -1) == int(parts[0]) and wp.get("y", -1) == int(parts[1]) and v["job"] == "builder":
			return true
	return false

func _pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

func _process_builders():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		if v["job"] != "builder":
			continue
		var sid := str(id)
		var bp_key: String = v.get("target_blueprint", "")
		if bp_key == "" or not GameState.blueprints.has(bp_key):
			bp_key = _find_blueprint(sid)
			if bp_key == "":
				v["job"] = "idle"
				v["state"] = "idle"
				v["workplace"] = {}
				v["target_blueprint"] = ""
				continue
			v["target_blueprint"] = bp_key
			var bp2 = GameState.blueprints[bp_key] as Dictionary
			var pos2 = Vector2i(int(bp2["pos"]["x"]), int(bp2["pos"]["y"]))
			v["workplace"] = {"x": pos2.x, "y": pos2.y}
			# Decide initial route: fetch resources first, or go straight to blueprint
			if _is_paid(bp2["cost"], bp2["paid"]):
				v["state"] = "moving_to_blueprint"
			else:
				v["state"] = "moving_to_stockpile"
			print("Server: builder ", id, " assigned to blueprint ", bp_key, " state ", v["state"])
		
		var bp = GameState.blueprints[bp_key] as Dictionary
		var pos = Vector2i(int(bp["pos"]["x"]), int(bp["pos"]["y"]))
		var cost: Dictionary = bp["cost"]
		var paid: Dictionary = bp["paid"]
		var current_tile = Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
		var already_paid := _is_paid(cost, paid)
		
		match v["state"]:
			"moving_to_blueprint":
				if current_tile == pos:
					if already_paid:
						v["state"] = "building"
						print("Server: builder ", id, " reached blueprint at ", pos)
					else:
						v["state"] = "moving_to_stockpile"
						print("Server: builder ", id, " reached blueprint but needs resources first")
				elif v["from_pos"] == v["to_pos"]:
					v["to_pos"] = _step_toward_dict(current_tile, pos)
			"building":
				bp["progress"] += BUILD_UNITS_PER_TICK
				if bp["progress"] >= 1.0:
					bp["progress"] = 1.0
					if GameState.complete_blueprint(pos):
						v["job"] = "idle"
						v["target_blueprint"] = ""
						v["state"] = "idle"
						v["workplace"] = {}
						v["to_pos"] = v["pos"].duplicate()
						v["from_pos"] = v["pos"].duplicate()
						v["move_progress"] = 0.0
						print("Server: builder ", id, " finished building at ", pos)
					else:
						# Could not complete (e.g. resources missing); try to fetch them
						v["state"] = "moving_to_stockpile"
						print("Server: builder ", id, " could not complete, fetching resources")
			"moving_to_stockpile":
				if already_paid:
					v["state"] = "returning_to_blueprint"
					v["to_pos"] = _step_toward_dict(current_tile, pos)
					continue
				var stock_id = GameState.find_stockpile_with_resources(pos, cost, paid)
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
					print("Server: builder ", id, " returned to blueprint at ", pos)
				elif v["from_pos"] == v["to_pos"]:
					v["to_pos"] = _step_toward_dict(current_tile, pos)
			"waiting_resources":
				v["state"] = "moving_to_stockpile"

func _is_paid(cost: Dictionary, paid: Dictionary) -> bool:
	for res: String in cost:
		if paid.get(res, 0) < cost[res]:
			return false
	return true

func _step_toward_dict(from_pos: Vector2i, to_pos: Vector2i) -> Dictionary:
	# Use A* to find the next step toward the target, avoiding walls and water.
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var start := from_pos
	var goal := to_pos
	if start == goal:
		return {"x": start.x, "y": start.y}
	
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	g_score[_key(start)] = 0
	var f_score: Dictionary = {}
	f_score[_key(start)] = _manhattan(start, goal)
	var visited: int = 0
	var max_visited: int = 5000
	
	while open_set.size() > 0 and visited < max_visited:
		visited += 1
		var current: Vector2i = open_set[0]
		var best_idx: int = 0
		for i in range(open_set.size()):
			var k: String = _key(open_set[i])
			if f_score.get(k, 999999) < f_score.get(_key(current), 999999):
				current = open_set[i]
				best_idx = i
		open_set.remove_at(best_idx)
		if current == goal:
			# Reconstruct path and return first step after start
			var path: Array[Vector2i] = [current]
			while came_from.has(_key(current)):
				current = came_from[_key(current)]
				path.append(current)
			path.reverse()
			if path.size() >= 2:
				var next_step: Vector2i = path[1]
				return {"x": next_step.x, "y": next_step.y}
			return {"x": start.x, "y": start.y}

		for d in dirs:
			var neighbor: Vector2i = current + d
			if neighbor.x < 0 or neighbor.x >= PlanetGenerator.WORLD_SIZE or neighbor.y < 0 or neighbor.y >= PlanetGenerator.WORLD_SIZE:
				continue
			if not GameState.is_walkable(neighbor):
				continue
			var nk: String = _key(neighbor)
			var tentative_g: int = g_score.get(_key(current), 999999) + 1
			if tentative_g < g_score.get(nk, 999999):
				came_from[nk] = current
				g_score[nk] = tentative_g
				f_score[nk] = tentative_g + _manhattan(neighbor, goal)
				if not open_set.has(neighbor):
					open_set.append(neighbor)

	return {"x": from_pos.x, "y": from_pos.y}

func _key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _process_workers():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		var res := PlanetGenerator.get_resource_for_job(v["job"])
		if res == "":
			continue
		var current_tile = Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
		var workplace := Vector2i(int(v["workplace"]["x"]), int(v["workplace"]["y"]))
		match v["state"]:
			"idle", "working", "moving_to_work":
				if current_tile != workplace:
					if v["from_pos"] == v["to_pos"]:
						v["to_pos"] = _step_toward_dict(current_tile, workplace)
					v["state"] = "moving_to_work"
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
