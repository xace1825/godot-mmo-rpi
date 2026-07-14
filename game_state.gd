extends Node

const SAVE_PATH: String = "user://world_save.json"

var buildings: Dictionary = {}
var blueprints: Dictionary = {}
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

func add_blueprint(pos: Vector2i, station_type: int = -1) -> int:
	ensure_world_generated()
	var key = "%d,%d" % [pos.x, pos.y]
	if buildings.has(key) or blueprints.has(key):
		print("Server: tile already occupied")
		return -1
	if not can_build_at(pos):
		print("Server: cannot build on this terrain")
		return -1
	var tile_type := get_tile_type(pos)
	var type_id := station_type
	if type_id < 0:
		type_id = PlanetGenerator.get_station_type(tile_type)
	var cost := PlanetGenerator.get_station_cost(type_id)
	blueprints[key] = {
		"type": type_id,
		"pos": {"x": pos.x, "y": pos.y},
		"progress": 0.0,
		"cost": cost,
		"paid": {"wood": 0, "stone": 0, "food": 0}
	}
	print("Server: added blueprint ", key, " type ", type_id, " cost ", cost)
	return type_id

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
		"carrying": 0,
		"target_blueprint": "%d,%d" % [pos.x, pos.y],
		"building_type": -1
	}
	villagers[str(id)] = v
	print("Server: spawned builder ", id, " at ", pos.x, ",", pos.y)
	return v

func complete_blueprint(pos: Vector2i) -> bool:
	var key = "%d,%d" % [pos.x, pos.y]
	if not blueprints.has(key):
		return false
	var bp = blueprints[key]
	var cost: Dictionary = bp["cost"]
	for res in cost:
		if resources[res] < cost[res]:
			print("Server: not enough ", res, " to complete blueprint ", key)
			return false
	for res in cost:
		resources[res] -= cost[res]
	buildings[key] = bp["type"]
	var completed_type: int = bp["type"]
	blueprints.erase(key)
	spawn_villagers_for_station(pos, completed_type)
	print("Server: blueprint completed at ", key, " type ", completed_type)
	Network.broadcast_building_completed(pos, completed_type)
	return true

func add_building(pos: Vector2i, type_id: int = -1) -> int:
	return add_blueprint(pos, type_id)

func spawn_villagers_for_station(pos: Vector2i, station_type: int) -> Array:
	var job_type := PlanetGenerator.get_job_type(station_type)
	if job_type == "":
		return []
	var key = "%d,%d" % [pos.x, pos.y]
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
			"carrying": 0,
			"building_type": station_type
		}
		villagers[str(id)] = v
		spawned.append(v)
		print("Server: spawned villager ", id, " as ", job_type, " at ", key)
	return spawned

func get_world_data() -> Dictionary:
	ensure_world_generated()
	return {
		"seed": world_seed,
		"buildings": buildings.duplicate(),
		"blueprints": blueprints.duplicate(),
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
		resources = data.get("resources", {"wood": 0, "food": 0, "stone": 0})
		villagers = data.get("villagers", {})
		next_villager_id = data.get("next_villager_id", 1)
		print("Server: loaded planet with ", buildings.size(), " buildings, ", blueprints.size(), " blueprints, ", villagers.size(), " villagers")
	else:
		push_error("Failed to parse save file")

func save_world():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"seed": world_seed,
		"buildings": buildings,
		"blueprints": blueprints,
		"resources": resources,
		"villagers": villagers,
		"next_villager_id": next_villager_id
	}, "\t"))
	file.close()
	print("Server: world saved")
