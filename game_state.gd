extends Node

const SAVE_PATH: String = "user://world_save.json"

var buildings: Dictionary = {}
var blueprints: Dictionary = {}
var stockpiles: Dictionary = {}
var rooms: Array = []
var room_station_status: Dictionary = {}
var world_seed: int = 12345
var world: Array = []
var resources: Dictionary = {
	"wood": 0,
	"food": 0,
	"stone": 0
}
var villagers: Dictionary = {}
var next_villager_id: int = 1

func ensure_world_generated():
	if world.is_empty():
		world = PlanetGenerator.generate_world(world_seed)
		print("Server: generated planet with seed ", world_seed, " size ", PlanetGenerator.WORLD_SIZE)

func get_tile_type(pos: Vector2i) -> int:
	ensure_world_generated()
	if pos.x < 0 or pos.x >= PlanetGenerator.WORLD_SIZE or pos.y < 0 or pos.y >= PlanetGenerator.WORLD_SIZE:
		return PlanetGenerator.TileType.DEEP_OCEAN
	return world[pos.x][pos.y]

func can_build_at(pos: Vector2i) -> bool:
	var type := get_tile_type(pos)
	return PlanetGenerator.is_buildable(type)

func get_room_at(pos: Vector2i) -> int:
	var key: String = _pos_key(pos)
	for i in range(rooms.size()):
		if key in rooms[i]["tiles"]:
			return i
	return -1

func is_indoor_station(pos: Vector2i) -> bool:
	var key: String = _pos_key(pos)
	return room_station_status.get(key, false)

func recalculate_rooms():
	rooms.clear()
	room_station_status.clear()
	# Gather floor, door and station tiles as room-passable; walls block
	var floor_tiles: Dictionary = {}
	var door_tiles: Dictionary = {}
	var walls: Dictionary = {}
	for key: String in buildings:
		var type_id: int = buildings[key]
		if type_id == PlanetGenerator.BuildingType.WALL:
			walls[key] = true
		elif type_id == PlanetGenerator.BuildingType.DOOR:
			door_tiles[key] = true
			floor_tiles[key] = true
		elif type_id == PlanetGenerator.BuildingType.FLOOR or PlanetGenerator.is_station(type_id):
			floor_tiles[key] = true
	# Stockpile zones are passable (they are just floor designations)
	for stock_id: String in stockpiles:
		for key: String in stockpiles[stock_id]["zone"]:
			floor_tiles[key] = true
	
	var visited: Dictionary = {}
	for start_key: String in floor_tiles:
		if visited.has(start_key):
			continue
		var room: Dictionary = {
			"tiles": [],
			"is_enclosed": true,
			"stations": []
		}
		var queue: Array = [start_key]
		visited[start_key] = true
		while queue.size() > 0:
			var current_key: String = queue.pop_front()
			room["tiles"].append(current_key)
			var pos: Vector2i = _key_pos(current_key)
			var current_is_door: bool = door_tiles.has(current_key)
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbor: Vector2i = pos + dir
				var nkey: String = _pos_key(neighbor)
				# Stop at walls and world borders
				if walls.has(nkey):
					continue
				if neighbor.x < 0 or neighbor.x >= PlanetGenerator.WORLD_SIZE or neighbor.y < 0 or neighbor.y >= PlanetGenerator.WORLD_SIZE:
					room["is_enclosed"] = false
					continue
				# Empty outdoor space adjacent to non-door tile breaks enclosure
				if not floor_tiles.has(nkey):
					if not current_is_door:
						room["is_enclosed"] = false
					continue
				if not visited.has(nkey):
					visited[nkey] = true
					queue.append(nkey)
		rooms.append(room)
	
	# Mark stations
	for key: String in buildings:
		var type_id: int = buildings[key]
		if not PlanetGenerator.is_station(type_id):
			continue
		var pos: Vector2i = _key_pos(key)
		var room_idx: int = get_room_at(pos)
		var indoor: bool = false
		if room_idx >= 0:
			indoor = rooms[room_idx]["is_enclosed"]
			rooms[room_idx]["stations"].append(pos)
		room_station_status[key] = indoor
	print("Server: recalculated ", rooms.size(), " rooms, indoor stations: ", room_station_status.values().count(true), ", outdoor: ", room_station_status.values().count(false))
	for i in range(rooms.size()):
		print("  room ", i, " enclosed=", rooms[i]["is_enclosed"], " tiles=", rooms[i]["tiles"].size(), " stations=", rooms[i]["stations"])

func _key_pos(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

func _pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

func add_blueprint(pos: Vector2i, building_type: int = -1) -> int:
	ensure_world_generated()
	var key = _pos_key(pos)
	if buildings.has(key) or blueprints.has(key):
		print("Server: tile already occupied")
		return -1
	if not can_build_at(pos):
		print("Server: cannot build on this terrain")
		return -1
	var tile_type := get_tile_type(pos)
	var type_id := building_type
	if type_id < 0:
		type_id = PlanetGenerator.get_station_type(tile_type)
	var cost := PlanetGenerator.get_build_cost(type_id)
	blueprints[key] = {
		"type": type_id,
		"pos": {"x": pos.x, "y": pos.y},
		"progress": 0.0,
		"cost": cost,
		"paid": {"wood": 0, "stone": 0, "food": 0}
	}
	print("Server: added blueprint ", key, " type ", type_id, " cost ", cost)
	# Production stations need a floor tile under them to count as indoor
	if PlanetGenerator.is_station(type_id):
		if not buildings.has(key):
			buildings[key] = PlanetGenerator.BuildingType.FLOOR
			print("Server: placed floor under station at ", pos)
	Network.broadcast_blueprint_placed(pos, type_id)
	return type_id

func add_stockpile(topleft: Vector2i, size: Vector2i) -> bool:
	ensure_world_generated()
	var zone: Array = []
	for dx in range(size.x):
		for dy in range(size.y):
			var pos := Vector2i(topleft.x + dx, topleft.y + dy)
			var key: String = _pos_key(pos)
			if not can_build_at(pos):
				print("Server: cannot place stockpile on non-buildable tile ", pos)
				return false
			if buildings.has(key) or blueprints.has(key):
				print("Server: stockpile overlaps building at ", pos)
				return false
			zone.append(key)
	var stock_id: String = "stock_%d_%d_%d" % [topleft.x, topleft.y, zone.size()]
	var is_first_stockpile: bool = stockpiles.is_empty()
	stockpiles[stock_id] = {
		"topleft": {"x": topleft.x, "y": topleft.y},
		"size": {"x": size.x, "y": size.y},
		"zone": zone,
		"resources": {"wood": 0, "food": 0, "stone": 0}
	}
	# Starting resources go to the first stockpile so construction can happen
	if is_first_stockpile:
		stockpiles[stock_id]["resources"] = {"wood": 500, "stone": 500, "food": 500}
		print("Server: placed starting resources into first stockpile ", stock_id)
	_recalc_total_resources()
	print("Server: added stockpile ", stock_id, " with ", zone.size(), " tiles")
	Network.broadcast_stockpile_added(stock_id, stockpiles[stock_id])
	return true

func spawn_builder_for_blueprint(pos: Vector2i) -> Dictionary:
	var id := next_villager_id
	next_villager_id += 1
	var v := {
		"id": id,
		"name": "Builder %d" % id,
		"pos": {"x": pos.x, "y": pos.y},
		"home": {"x": pos.x, "y": pos.y},
		"workplace": {"x": pos.x, "y": pos.y},
		"job": "builder",
		"state": "idle",
		"progress": 0.0,
		"carrying": {"resource": "", "amount": 0},
		"target_blueprint": "%d,%d" % [pos.x, pos.y],
		"building_type": -1
	}
	villagers[str(id)] = v
	print("Server: spawned builder ", id, " at ", pos.x, ",", pos.y)
	return v

func complete_blueprint(pos: Vector2i) -> bool:
	var key: String = _pos_key(pos)
	if not blueprints.has(key):
		return false
	var bp: Dictionary = blueprints[key]
	var cost: Dictionary = bp["cost"]
	var already_paid: bool = true
	for res: String in cost:
		if bp["paid"].get(res, 0) < cost[res]:
			already_paid = false
			break
	
	if not already_paid:
		var stock_id: String = find_nearest_stockpile(pos)
		if stock_id == "":
			print("Server: no stockpile available to complete blueprint ", key)
			return false
		var stock: Dictionary = stockpiles[stock_id]
		for res: String in cost:
			if stock["resources"][res] < cost[res]:
				print("Server: stockpile ", stock_id, " lacks ", res, " for blueprint ", key)
				return false
		for res: String in cost:
			stock["resources"][res] -= cost[res]
			bp["paid"][res] = cost[res]
	
	buildings[key] = bp["type"]
	var completed_type: int = bp["type"]
	blueprints.erase(key)
	_recalc_total_resources()
	# Only spawn workers for production stations, not walls/doors/floors/stockpiles
	if completed_type < PlanetGenerator.BuildingType.WALL:
		spawn_villagers_for_station(pos, completed_type)
	print("Server: blueprint completed at ", key, " type ", completed_type)
	recalculate_rooms()
	Network.broadcast_building_completed(pos, completed_type)
	return true

func pay_blueprint_cost(pos: Vector2i) -> bool:
	var key: String = _pos_key(pos)
	if not blueprints.has(key):
		return false
	var bp: Dictionary = blueprints[key]
	var cost: Dictionary = bp.get("cost", {})
	var stock_id: String = find_nearest_stockpile(pos)
	if stock_id == "":
		return false
	var stock: Dictionary = stockpiles[stock_id]
	for res: String in cost:
		if stock["resources"][res] < cost[res] - bp["paid"].get(res, 0):
			return false
	for res: String in cost:
		var needed: int = cost[res] - bp["paid"].get(res, 0)
		if needed > 0:
			stock["resources"][res] -= needed
			bp["paid"][res] = bp["paid"].get(res, 0) + needed
	_recalc_total_resources()
	print("Server: blueprint ", key, " paid, remaining stockpile resources: ", stock["resources"])
	return true

func add_building(pos: Vector2i, type_id: int = -1) -> int:
	return add_blueprint(pos, type_id)

func spawn_villagers_for_station(pos: Vector2i, station_type: int) -> Array:
	var job_type := PlanetGenerator.get_job_type(station_type)
	if job_type == "":
		return []
	var key = _pos_key(pos)
	var slots := PlanetGenerator.get_job_slots(station_type)
	var spawned := []
	for i in range(slots):
		var id := next_villager_id
		next_villager_id += 1
		var v := {
			"id": id,
			"name": "Worker %d" % id,
			"pos": {"x": pos.x, "y": pos.y},
			"home": {"x": pos.x, "y": pos.y},
			"workplace": {"x": pos.x, "y": pos.y},
			"job": job_type,
			"state": "idle",
			"progress": 0.0,
			"carrying": {"resource": "", "amount": 0},
			"building_type": station_type
		}
		villagers[str(id)] = v
		spawned.append(v)
		print("Server: spawned villager ", id, " as ", job_type, " at ", key)
	return spawned

func find_nearest_stockpile(pos: Vector2i) -> String:
	var best_id := ""
	var best_dist := 999999.0
	for stock_id: String in stockpiles:
		var stock: Dictionary = stockpiles[stock_id]
		var cx: float = stock["topleft"]["x"] + stock["size"]["x"] / 2.0
		var cy: float = stock["topleft"]["y"] + stock["size"]["y"] / 2.0
		var dist := sqrt(pow(cx - pos.x, 2) + pow(cy - pos.y, 2))
		if dist < best_dist:
			best_dist = dist
			best_id = stock_id
	return best_id

func deposit_to_nearest_stockpile(pos: Vector2i, resource: String, amount: int) -> bool:
	var stock_id: String = find_nearest_stockpile(pos)
	if stock_id == "":
		return false
	var stock: Dictionary = stockpiles[stock_id]
	stock["resources"][resource] += amount
	_recalc_total_resources()
	Network.broadcast_resource_sync()
	return true

func _recalc_total_resources():
	resources = {"wood": 0, "food": 0, "stone": 0}
	for stock_id: String in stockpiles:
		var stock: Dictionary = stockpiles[stock_id]
		for res: String in resources:
			resources[res] += stock["resources"][res]

func get_stockpile_at(pos: Vector2i) -> String:
	var key: String = _pos_key(pos)
	for stock_id: String in stockpiles:
		if key in stockpiles[stock_id]["zone"]:
			return stock_id
	return ""

func get_world_data() -> Dictionary:
	ensure_world_generated()
	return {
		"seed": world_seed,
		"buildings": buildings.duplicate(),
		"blueprints": blueprints.duplicate(),
		"stockpiles": stockpiles.duplicate(),
		"resources": resources.duplicate(),
		"villagers": villagers.duplicate()
	}

func load_world():
	ensure_world_generated()
	if not FileAccess.file_exists(SAVE_PATH):
		print("Server: no save file, starting fresh planet")
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err == OK:
		var data = json.get_data()
		world_seed = data.get("seed", world_seed)
		world = PlanetGenerator.generate_world(world_seed)
		buildings = data.get("buildings", {})
		blueprints = data.get("blueprints", {})
		stockpiles = data.get("stockpiles", {})
		resources = data.get("resources", {"wood": 0, "food": 0, "stone": 0})
		villagers = data.get("villagers", {})
		next_villager_id = data.get("next_villager_id", 1)
		print("Server: loaded planet with ", buildings.size(), " buildings, ", blueprints.size(), " blueprints, ", stockpiles.size(), " stockpiles, ", villagers.size(), " villagers")
	else:
		push_error("Failed to parse save file")

func save_world():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"seed": world_seed,
		"buildings": buildings,
		"blueprints": blueprints,
		"stockpiles": stockpiles,
		"resources": resources,
		"villagers": villagers,
		"next_villager_id": next_villager_id
	}, "	"))
	file.close()
	print("Server: world saved")

func reset_world():
	buildings.clear()
	blueprints.clear()
	stockpiles.clear()
	rooms.clear()
	room_station_status.clear()
	villagers.clear()
	next_villager_id = 1
	resources = {"wood": 0, "food": 0, "stone": 0}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	print("Server: world reset, save cleared")
