extends Node

const SAVE_PATH: String = "user://world_save.json"

var buildings: Dictionary = {}
var world_seed: int = 12345
var world: Array = []
var world_generator_loaded: bool = false

func ensure_world_generated():
	if world.is_empty():
		world = WorldGenerator.generate_world(world_seed)
		print("Server: generated world with seed ", world_seed)

func get_tile_type(pos: Vector2i) -> int:
	ensure_world_generated()
	if pos.x < 0 or pos.x >= WorldGenerator.WORLD_SIZE or pos.y < 0 or pos.y >= WorldGenerator.WORLD_SIZE:
		return WorldGenerator.TileType.WATER
	return world[pos.x][pos.y]

func can_build_at(pos: Vector2i) -> bool:
	var type := get_tile_type(pos)
	return WorldGenerator.is_buildable(type)

func add_building(pos: Vector2i, type_id: int = -1) -> bool:
	ensure_world_generated()
	var key = "%d,%d" % [pos.x, pos.y]
	if buildings.has(key):
		print("Server: tile already occupied")
		return false
	if not can_build_at(pos):
		print("Server: cannot build on this terrain")
		return false
	var tile_type := get_tile_type(pos)
	var building_type := type_id
	if building_type < 0:
		building_type = WorldGenerator.get_building_type(tile_type)
	buildings[key] = building_type
	print("Server: added building ", key, " type ", building_type)
	return true

func get_world_data() -> Dictionary:
	ensure_world_generated()
	return {
		"seed": world_seed,
		"buildings": buildings.duplicate()
	}

func load_world():
	ensure_world_generated()
	if not FileAccess.file_exists(SAVE_PATH):
		print("Server: no save file, starting fresh world")
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err == OK:
		var data = json.get_data()
		world_seed = data.get("seed", world_seed)
		# regenerate world in case seed changed
		world = WorldGenerator.generate_world(world_seed)
		buildings = data.get("buildings", {})
		print("Server: loaded world with ", buildings.size(), " buildings")
	else:
		push_error("Failed to parse save file")

func save_world():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(get_world_data(), "\t"))
	file.close()
	print("Server: world saved")
