extends Node

const SAVE_PATH: String = "user://world_save.json"

var buildings: Dictionary = {}
var blueprints: Dictionary = {}
var stockpiles: Dictionary = {}
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
		stockpiles[stock_id]["resources"] = {"wood": 50, "stone": 50, "food": 50}
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
	# Try to consume resources from nearest stockpile
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
	buildings[key] = bp["type"]
	var completed_type: int = bp["type"]
	blueprints.erase(key)
	_recalc_total_resources()
	# Only spawn workers for production stations, not walls/doors/floors/stockpiles
	if completed_type < PlanetGenerator.BuildingType.WALL:
		spawn_villagers_for_station(pos, completed_type)
	print("Server: blueprint completed at ", key, " type ", completed_type, " using stockpile ", stock_id)
	Network.broadcast_building_completed(pos, completed_type)
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
	}, "\t"))
	file.close()
	print("Server: world saved")
