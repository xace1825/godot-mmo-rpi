extends Node

const TICK_RATE: float = 1.0
const WORK_UNITS_PER_TICK: float = 0.33
const BUILD_UNITS_PER_TICK: float = 0.25
const PRODUCTION_AMOUNT: int = 1
const VILLAGER_MOVE_SPEED: float = 1.0
const HUNGER_RATE: float = 0.2
const ENERGY_RATE: float = 0.2
const NEEDS_THRESHOLD: float = 25.0
const HOURS_PER_DAY: float = 24.0
const REAL_SECONDS_PER_GAME_HOUR: float = 10.0

var _tick_timer: float = 0.0
var _tick_count: int = 0
var _sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.2

func _ready():
	set_physics_process(false)
	multiplayer.peer_connected.connect(_on_peer_connected)
	get_tree().root.set_as_audio_listener_2d(true)
	if multiplayer.is_server():
		GameState.time_of_day = 6.0
		GameState.day_count = 1
		print("Server: day-night cycle initialized at hour ", GameState.time_of_day)

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if multiplayer.is_server():
			print("Server: shutting down, saving world")
			GameState.save_world()
			get_tree().quit()

func _on_peer_connected(id: int):
	if multiplayer.is_server():
		set_physics_process(true)
		print("Server: peer connected, starting tick loop")

func _physics_process(delta: float):
	_update_villager_movement(delta)
	_tick_timer += delta * Engine.time_scale
	if _tick_timer >= TICK_RATE:
		_tick_timer -= TICK_RATE
		_tick()
	# Sync villagers frequently for smooth client interpolation
	if multiplayer.is_server():
		_sync_timer += delta * Engine.time_scale
		if _sync_timer >= SYNC_INTERVAL:
			_sync_timer -= SYNC_INTERVAL
			Network.broadcast_villager_sync()

func _tick():
	# Advance day-night cycle on the server
	if multiplayer.is_server():
		GameState.time_of_day += TICK_RATE * Engine.time_scale / REAL_SECONDS_PER_GAME_HOUR
		if GameState.time_of_day >= HOURS_PER_DAY:
			GameState.time_of_day -= HOURS_PER_DAY
			GameState.day_count += 1
			print("Server: new day ", GameState.day_count)
		Network.broadcast_day_night_sync()
	
	_update_needs()
	_process_needs()
	_assign_idle_villagers()
	_assign_manual_jobs()
	_process_builders()
	_process_workers()
	Network.broadcast_resource_sync()
	_tick_count += 1
	if _tick_count % 30 == 0:
		GameState.save_world()

func _update_villager_movement(delta: float):
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		if v["from_pos"] == v["to_pos"]:
			continue
		v["move_progress"] += delta * Engine.time_scale * VILLAGER_MOVE_SPEED
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

		# Priority: if there are any unfinished blueprints, become a builder first.
		var bp_key := _find_nearest_blueprint(sid)
		if bp_key != "":
			var bp = GameState.blueprints[bp_key] as Dictionary
			var pos = Vector2i(int(bp["pos"]["x"]), int(bp["pos"]["y"]))
			v["job"] = "builder"
			v["target_blueprint"] = bp_key
			v["workplace"] = {"x": pos.x, "y": pos.y}
			if _is_paid(bp["cost"], bp["paid"]):
				v["state"] = "moving_to_blueprint"
			else:
				v["state"] = "moving_to_stockpile"
			print("Server: idle villager ", id, " assigned as builder for ", bp_key, " state ", v["state"])
			continue

		# Only if no blueprints exist, assign to functional production stations
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
				continue
		# If nothing else, become a hauler and pick up ground items
		if GameState.ground_items.size() > 0:
			v["job"] = "hauler"
			v["workplace"] = {}
			v["state"] = "idle"
			print("Server: idle villager ", id, " assigned as hauler")
			continue

func _assign_manual_jobs():
	# Handle villagers whose job was manually set but they have no workplace yet
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		if _is_satisfying_needs(v):
			continue
		if v["state"] != "idle":
			continue
		if v["job"] == "idle":
			continue
		var sid := str(id)
		var wp = v.get("workplace", {}) as Dictionary
		if wp.has("x") and wp.has("y"):
			continue

		if v["job"] == "builder":
			var bp_key := _find_nearest_blueprint(sid)
			if bp_key != "":
				var bp = GameState.blueprints[bp_key] as Dictionary
				var pos = Vector2i(int(bp["pos"]["x"]), int(bp["pos"]["y"]))
				v["target_blueprint"] = bp_key
				v["workplace"] = {"x": pos.x, "y": pos.y}
				if _is_paid(bp["cost"], bp["paid"]):
					v["state"] = "moving_to_blueprint"
				else:
					v["state"] = "moving_to_stockpile"
				print("Server: manual builder ", id, " assigned to blueprint ", bp_key, " state ", v["state"])
		else:
			var station_pos := _find_station_without_worker(sid, v["job"])
			if station_pos != Vector2i(-1, -1):
				v["workplace"] = {"x": station_pos.x, "y": station_pos.y}
				v["state"] = "moving_to_work"
				print("Server: manual ", v["job"], " ", id, " assigned to station at ", station_pos)

func _find_station_without_worker(exclude_id: String = "", required_job: String = "") -> Vector2i:
	for key: String in GameState.buildings:
		var type_id: int = GameState.buildings[key]
		if not PlanetGenerator.is_station(type_id):
			continue
		var job_type := PlanetGenerator.get_job_type(type_id)
		if job_type == "":
			continue
		if required_job != "" and job_type != required_job:
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
	return _find_nearest_blueprint(exclude_id)

func _find_nearest_blueprint(exclude_id: String = "") -> String:
	var best_key := ""
	var best_dist: int = 999999
	for key in GameState.blueprints:
		if _is_blueprint_reserved(key, exclude_id):
			continue
		var bp = GameState.blueprints[key] as Dictionary
		var pos = Vector2i(int(bp["pos"]["x"]), int(bp["pos"]["y"]))
		# Skip blueprints that are fully surrounded by unwalkable tiles
		# (e.g. a floor tile inside a room with no door yet)
		if not _is_blueprint_reachable(pos):
			continue
		var owner = GameState.villagers.get(exclude_id) as Dictionary
		var current := Vector2i(0, 0)
		if owner and owner.has("pos"):
			current = Vector2i(int(round(owner["pos"]["x"])), int(round(owner["pos"]["y"])))
		var d: int = abs(current.x - pos.x) + abs(current.y - pos.y)
		if d < best_dist:
			best_dist = d
			best_key = key
	return best_key

func _is_blueprint_reachable(pos: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if GameState.is_walkable(pos + d):
			return true
	return false

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
		if _is_satisfying_needs(v):
			continue
		if v["job"] != "builder":
			continue
		var sid := str(id)
		var bp_key: String = v.get("target_blueprint", "")
		if bp_key == "" or not GameState.blueprints.has(bp_key):
			bp_key = _find_nearest_blueprint(sid)
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
			"idle":
				if already_paid:
					v["state"] = "moving_to_blueprint"
					v["to_pos"] = _step_toward_dict(current_tile, pos)
				else:
					v["state"] = "moving_to_stockpile"
					v["to_pos"] = _step_toward_dict(current_tile, pos)
			"moving_to_blueprint":
				if current_tile == pos:
					if already_paid:
						v["state"] = "building"
						print("Server: builder ", id, " reached blueprint at ", pos)
					else:
						v["state"] = "moving_to_stockpile"
				elif v["from_pos"] == v["to_pos"]:
					v["to_pos"] = _step_toward_dict(current_tile, pos)
			"building":
				bp["progress"] += BUILD_UNITS_PER_TICK
				if bp["progress"] >= 1.0:
					bp["progress"] = 1.0
					if GameState.complete_blueprint(pos):
						# Look for the next blueprint before going idle
						v["progress"] = 0.0
						v["carrying"] = {"resource": "", "amount": 0}
						v["target_blueprint"] = ""
						v["workplace"] = {}
						var next_bp := _find_nearest_blueprint(sid)
						if next_bp != "":
							var bp2 = GameState.blueprints[next_bp] as Dictionary
							var pos2 = Vector2i(int(bp2["pos"]["x"]), int(bp2["pos"]["y"]))
							v["target_blueprint"] = next_bp
							v["workplace"] = {"x": pos2.x, "y": pos2.y}
							if _is_paid(bp2["cost"], bp2["paid"]):
								v["state"] = "moving_to_blueprint"
							else:
								v["state"] = "moving_to_stockpile"
							print("Server: builder ", id, " finished ", bp_key, " and moving to next blueprint ", next_bp, " state ", v["state"])
						else:
							v["job"] = "idle"
							v["state"] = "idle"
							v["to_pos"] = v["pos"].duplicate()
							v["from_pos"] = v["pos"].duplicate()
							v["move_progress"] = 0.0
							print("Server: builder ", id, " finished building at ", pos, " and found no more blueprints")
					else:
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

func _process_workers():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		if _is_satisfying_needs(v):
			continue
		var job: String = v["job"]
		if job == "idle" or job == "builder":
			continue
		if job == "hauler":
			_process_hauler(str(id), v)
			continue
		var wp = v.get("workplace", {}) as Dictionary
		if not wp.has("x") or not wp.has("y"):
			continue
		var workplace = Vector2i(int(wp["x"]), int(wp["y"]))
		var current_tile = Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
		var res := PlanetGenerator.get_resource_for_job(job)
		if res == "":
			continue
		var station_type: int = GameState.buildings.get(_pos_key(workplace), -1)
		if station_type == -1:
			continue
		var speed_mult := 1.0
		var station_is_indoor := GameState.is_indoor_station(workplace)
		if PlanetGenerator.is_indoor_building(station_type):
			if not station_is_indoor:
				speed_mult = 0.5
		else:
			if station_is_indoor:
				speed_mult = 0.6

		match v["state"]:
			"moving_to_work":
				if current_tile == workplace:
					v["state"] = "working"
					v["progress"] = 0.0
					print("Server: worker ", id, " reached workplace ", workplace)
				elif v["from_pos"] == v["to_pos"]:
					v["to_pos"] = _step_toward_dict(current_tile, workplace)
			"working":
				var consumes: String = PlanetGenerator.get_consumes_for_job(job)
				if consumes != "":
					if not GameState.consume_from_nearest_stockpile(current_tile, consumes, 1):
						v["state"] = "idle"
						print("Server: worker ", id, " waiting for ", consumes)
						continue
				v["progress"] += WORK_UNITS_PER_TICK * speed_mult
				v["state"] = "working"
				if v["progress"] >= 1.0:
					v["progress"] = 0.0
					v["carrying"] = {"resource": res, "amount": PRODUCTION_AMOUNT}
					v["state"] = "hauling"
					print("Server: worker ", id, " produced ", res, " at ", workplace)
			"hauling":
				var carrying = v.get("carrying", {}) as Dictionary
				var amount: int = carrying.get("amount", 0)
				var resource: String = carrying.get("resource", "")
				if resource == "" or amount <= 0:
					v["state"] = "idle"
					v["carrying"] = {"resource": "", "amount": 0}
					continue
				var target_stock_id = GameState.find_nearest_stockpile(current_tile)
				if target_stock_id == "":
					v["to_pos"] = v["pos"].duplicate()
					v["from_pos"] = v["pos"].duplicate()
					v["state"] = "idle"
					v["carrying"] = {"resource": "", "amount": 0}
					continue
				var target_stock = GameState.stockpiles[target_stock_id]
				var target_pos = Vector2i(int(target_stock["topleft"]["x"]), int(target_stock["topleft"]["y"]))
				if GameState.get_stockpile_at(current_tile) == target_stock_id:
					GameState.deposit_to_nearest_stockpile(current_tile, resource, amount)
					v["carrying"] = {"resource": "", "amount": 0}
					v["state"] = "idle"
					print("Server: worker ", id, " deposited ", amount, " ", resource, " to ", target_stock_id)
				elif v["from_pos"] == v["to_pos"]:
					v["to_pos"] = _step_toward_dict(current_tile, target_pos)

func _process_hauler(id: String, v: Dictionary):
	var current_tile := Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
	match v["state"]:
		"idle", "moving_to_ground":
			# Find nearest ground item
			var best_key := ""
			var best_dist: int = 999999
			for key: String in GameState.ground_items:
				var item: Dictionary = GameState.ground_items[key]
				var parts := key.split(",")
				var ipos := Vector2i(int(parts[0]), int(parts[1]))
				var d: int = abs(ipos.x - current_tile.x) + abs(ipos.y - current_tile.y)
				if d < best_dist:
					best_dist = d
					best_key = key
			if best_key == "":
				# Nothing to haul
				v["state"] = "idle"
				return
			var parts := best_key.split(",")
			var target_pos := Vector2i(int(parts[0]), int(parts[1]))
			if current_tile == target_pos:
				var item: Dictionary = GameState.ground_items[best_key]
				var picked: int = GameState.pickup_ground_item(target_pos, item["resource"], 5)
				if picked > 0:
					v["carrying"] = {"resource": item["resource"], "amount": picked}
					v["state"] = "hauling_to_stockpile"
					print("Server: hauler ", id, " picked up ", picked, " ", item["resource"], " at ", target_pos)
				else:
					v["state"] = "idle"
					return
			elif v["from_pos"] == v["to_pos"]:
				v["to_pos"] = _step_toward_dict(current_tile, target_pos)
				v["state"] = "moving_to_ground"
		"hauling_to_stockpile":
			var carrying = v.get("carrying", {}) as Dictionary
			var amount: int = carrying.get("amount", 0)
			var resource: String = carrying.get("resource", "")
			if resource == "" or amount <= 0:
				v["state"] = "idle"
				v["carrying"] = {"resource": "", "amount": 0}
				return
			var target_stock_id := GameState.find_nearest_stockpile(current_tile)
			if target_stock_id == "":
				v["state"] = "idle"
				v["carrying"] = {"resource": "", "amount": 0}
				return
			var target_stock: Dictionary = GameState.stockpiles[target_stock_id]
			var target_pos := Vector2i(int(target_stock["topleft"]["x"]), int(target_stock["topleft"]["y"]))
			if GameState.get_stockpile_at(current_tile) == target_stock_id:
				GameState.deposit_to_nearest_stockpile(current_tile, resource, amount)
				v["carrying"] = {"resource": "", "amount": 0}
				v["state"] = "idle"
				print("Server: hauler ", id, " deposited ", amount, " ", resource, " to ", target_stock_id)
			elif v["from_pos"] == v["to_pos"]:
				v["to_pos"] = _step_toward_dict(current_tile, target_pos)

func _update_needs():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		var needs: Dictionary = v["needs"]
		var state: String = v["state"]
		if state == "eating" or state == "sleeping":
			continue
		needs["hunger"] = max(needs["hunger"] - HUNGER_RATE, 0.0)
		needs["energy"] = max(needs["energy"] - ENERGY_RATE, 0.0)
		# Comfort decays slowly outdoors, recovers indoors on floor
		var current_tile = Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
		if state == "seeking_bed" or state == "sleeping":
			# Comfort change handled in _process_needs while sleeping
			pass
		elif GameState.is_indoor(current_tile) and GameState.has_floor_or_stockpile(current_tile):
			needs["comfort"] = min(needs["comfort"] + 0.5, 100.0)
		else:
			needs["comfort"] = max(needs["comfort"] - 0.3, 0.0)
		# Prioritize finishing the current need before switching to the other one.
		if state == "seeking_bed":
			# Do not interrupt sleep for food unless starving
			if needs["hunger"] <= 10.0:
				v["state"] = "seeking_food"
				v["to_pos"] = v["pos"].duplicate()
				v["from_pos"] = v["pos"].duplicate()
				print("Server: villager ", id, " is starving, seeking food before bed")
		elif state == "seeking_food":
			# Only interrupt eating for sleep if hunger is already decent
			if needs["energy"] <= NEEDS_THRESHOLD and needs["hunger"] >= 80.0:
				v["state"] = "seeking_bed"
				v["to_pos"] = v["pos"].duplicate()
				v["from_pos"] = v["pos"].duplicate()
				print("Server: villager ", id, " is tired, seeking bed")
		elif needs["hunger"] <= NEEDS_THRESHOLD:
			v["state"] = "seeking_food"
			v["to_pos"] = v["pos"].duplicate()
			v["from_pos"] = v["pos"].duplicate()
			print("Server: villager ", id, " is hungry, seeking food")
		elif needs["energy"] <= NEEDS_THRESHOLD:
			v["state"] = "seeking_bed"
			v["to_pos"] = v["pos"].duplicate()
			v["from_pos"] = v["pos"].duplicate()
			print("Server: villager ", id, " is tired, seeking bed")
		# Resume normal work when needs are satisfied
		if state == "seeking_food" and needs["hunger"] >= 80.0:
			v["state"] = "idle"
			if v["job"] != "builder" and v["job"] != "idle" and v["job"] != "hauler":
				v["state"] = "moving_to_work"
		if state == "seeking_bed" and needs["energy"] >= 80.0:
			v["state"] = "idle"
			if v["job"] != "builder" and v["job"] != "idle" and v["job"] != "hauler":
				v["state"] = "moving_to_work"
				# If we were sleeping on the ground and have a blueprint, resume building
				if v["job"] == "builder":
					v["state"] = "idle"

func _process_needs():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		var state: String = v["state"]
		var current_tile = Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
		if state == "seeking_food":
			# Prefer prepared_food, fall back to raw food
			var stock_id := GameState.find_stockpile_with_resources(current_tile, {"prepared_food": 1, "food": 0, "wood": 0, "stone": 0}, {"prepared_food": 0, "food": 0, "wood": 0, "stone": 0})
			if stock_id == "":
				stock_id = GameState.find_stockpile_with_resources(current_tile, {"food": 1, "prepared_food": 0, "wood": 0, "stone": 0}, {"food": 0, "prepared_food": 0, "wood": 0, "stone": 0})
			if stock_id == "":
				continue
			var stock = GameState.stockpiles[stock_id]
			var stock_pos = Vector2i(int(stock["topleft"]["x"]), int(stock["topleft"]["y"]))
			if current_tile == stock_pos:
				if GameState.consume_food_for_villager(id):
					v["state"] = "eating"
					print("Server: villager ", id, " is eating at ", stock_id)
			elif v["from_pos"] == v["to_pos"]:
				v["to_pos"] = _step_toward_dict(current_tile, stock_pos)
		elif state == "eating":
			v["needs"]["hunger"] = min(v["needs"]["hunger"] + 25.0, 100.0)
			if v["needs"]["hunger"] >= 80.0:
				v["state"] = "idle"
				if v["job"] != "builder" and v["job"] != "idle":
					v["state"] = "moving_to_work"
				print("Server: villager ", id, " finished eating")
		elif state == "sleeping":
			var bed_boost := 1.0
			var comfort_boost := -1.0
			# Check if actually on a bed tile
			if GameState.buildings.has(GameState._pos_key(current_tile)) and GameState.buildings[GameState._pos_key(current_tile)] == PlanetGenerator.BuildingType.BED:
				bed_boost = 3.0
				comfort_boost = 5.0
			v["needs"]["energy"] = min(v["needs"]["energy"] + 25.0 * bed_boost, 100.0)
			v["needs"]["comfort"] = min(v["needs"]["comfort"] + comfort_boost, 100.0)
			if v["needs"]["energy"] >= 90.0:
				v["state"] = "idle"
				if v["job"] != "builder" and v["job"] != "idle":
					v["state"] = "moving_to_work"
				print("Server: villager ", id, " woke up")
		elif state == "seeking_bed":
			var bed_pos := GameState.find_nearest_bed(current_tile)
			if bed_pos.x == -1 and bed_pos.y == -1:
				v["needs"]["energy"] = min(v["needs"]["energy"] + 10.0, 100.0)
				v["needs"]["comfort"] = max(v["needs"]["comfort"] - 2.0, 0.0)
				if v["needs"]["energy"] >= 90.0:
					v["state"] = "idle"
					if v["job"] != "builder" and v["job"] != "idle":
						v["state"] = "moving_to_work"
						print("Server: villager ", id, " slept on the ground and recovered")
				continue
			if current_tile == bed_pos:
				GameState.sleep_at_bed(id, bed_pos)
				v["state"] = "sleeping"
				print("Server: villager ", id, " is sleeping at bed ", bed_pos)
			elif v["from_pos"] == v["to_pos"]:
				v["to_pos"] = _step_toward_dict(current_tile, bed_pos)
			if v["needs"]["energy"] >= 90.0:
				v["state"] = "idle"
				if v["job"] != "builder" and v["job"] != "idle":
					v["state"] = "moving_to_work"
				print("Server: villager ", id, " woke up")

func _is_satisfying_needs(v: Dictionary) -> bool:
	var state: String = v["state"]
	return state == "seeking_food" or state == "eating" or state == "seeking_bed" or state == "sleeping"

func _is_paid(cost: Dictionary, paid: Dictionary) -> bool:
	for res: String in cost:
		if paid.get(res, 0) < cost[res]:
			return false
	return true

func _step_toward_dict(from_pos: Vector2i, to_pos: Vector2i) -> Dictionary:
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
			var g: int = g_score.get(_key(current), 999999) + 1
			var ng: int = g_score.get(_key(neighbor), 999999)
			if g < ng:
				came_from[_key(neighbor)] = current
				g_score[_key(neighbor)] = g
				f_score[_key(neighbor)] = g + _manhattan(neighbor, goal)
				if not open_set.has(neighbor):
					open_set.append(neighbor)

	return {"x": from_pos.x, "y": from_pos.y}

func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
