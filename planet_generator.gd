class_name PlanetGenerator

const WORLD_SIZE: int = 128
const TILE_SIZE: int = 32
const CHUNK_SIZE: int = 32

enum TileType {
	DEEP_OCEAN,
	OCEAN,
	SHORE,
	GRASSLAND,
	FOREST,
	JUNGLE,
	DESERT,
	TAIGA,
	TUNDRA,
	SNOW,
	HILLS,
	MOUNTAIN,
	PEAK
}

enum BuildingType {
	SAWMILL,
	FARM,
	MINE,
	WALL,
	DOOR,
	FLOOR
}

const HEIGHT_DEEP: float = -0.85
const HEIGHT_OCEAN: float = -0.45
const HEIGHT_SHORE: float = -0.15
const HEIGHT_LOW: float = 0.25
const HEIGHT_MID: float = 0.55
const HEIGHT_HIGH: float = 0.75
const HEIGHT_PEAK: float = 0.9

const TEMP_HOT: float = 0.5
const TEMP_WARM: float = 0.15
const TEMP_COLD: float = -0.25
const TEMP_FROZEN: float = -0.55

const WET_DRY: float = -0.2
const WET_WET: float = 0.2

static func _make_noise(seed_value: int, freq: float, octaves: int, type: int = FastNoiseLite.TYPE_SIMPLEX) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = type
	noise.frequency = freq
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.5
	return noise

static func generate_world(seed_value: int = 0) -> Array:
	var continent_noise := _make_noise(seed_value, 0.015, 5, FastNoiseLite.TYPE_SIMPLEX)
	var detail_noise := _make_noise(seed_value + 1, 0.06, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	var river_noise := _make_noise(seed_value + 2, 0.04, 4, FastNoiseLite.TYPE_SIMPLEX)
	var temperature_noise := _make_noise(seed_value + 3, 0.02, 3, FastNoiseLite.TYPE_SIMPLEX)
	var moisture_noise := _make_noise(seed_value + 4, 0.03, 4, FastNoiseLite.TYPE_SIMPLEX)

	var world := []
	for x in range(WORLD_SIZE):
		var col := []
		for y in range(WORLD_SIZE):
			var height: float = continent_noise.get_noise_2d(float(x), float(y)) * 0.8 + detail_noise.get_noise_2d(float(x), float(y)) * 0.25
			var river: float = river_noise.get_noise_2d(float(x), float(y))
			if height > HEIGHT_LOW and height < HEIGHT_HIGH and river > 0.6:
				height -= 0.25

			var latitude: float = 1.0 - 2.0 * (float(y) / float(WORLD_SIZE - 1))
			var temp: float = -abs(latitude) + 0.5 + temperature_noise.get_noise_2d(float(x), float(y)) * 0.3
			var moisture: float = moisture_noise.get_noise_2d(float(x), float(y))

			col.append(_resolve_tile(height, temp, moisture))
		world.append(col)
	return world

static func _resolve_tile(height: float, temp: float, moisture: float) -> int:
	if height < HEIGHT_DEEP:
		return TileType.DEEP_OCEAN
	if height < HEIGHT_OCEAN:
		return TileType.OCEAN
	if height < HEIGHT_SHORE:
		return TileType.SHORE
	if height >= HEIGHT_PEAK:
		return TileType.PEAK
	if height >= HEIGHT_HIGH:
		return TileType.MOUNTAIN
	if height >= HEIGHT_MID:
		return TileType.HILLS

	if temp < TEMP_FROZEN:
		return TileType.SNOW
	if temp < TEMP_COLD:
		return TileType.TAIGA if moisture > WET_WET else TileType.TUNDRA
	if temp < TEMP_WARM:
		if moisture < WET_DRY:
			return TileType.DESERT
		return TileType.FOREST if moisture > WET_WET else TileType.GRASSLAND
	if temp < TEMP_HOT:
		if moisture < WET_DRY:
			return TileType.DESERT
		return TileType.JUNGLE if moisture > WET_WET else TileType.FOREST

	if moisture < WET_DRY:
		return TileType.DESERT
	return TileType.JUNGLE if moisture > WET_WET else TileType.GRASSLAND

static func tile_to_atlas_coords(type: int) -> Vector2i:
	return Vector2i(type, 0)

static func is_buildable(type: int) -> bool:
	match type:
		TileType.DEEP_OCEAN, TileType.OCEAN, TileType.SHORE, TileType.HILLS, TileType.MOUNTAIN, TileType.PEAK, TileType.SNOW:
			return false
		_:
			return true

static func get_station_type(tile_type: int) -> int:
	match tile_type:
		TileType.FOREST, TileType.JUNGLE, TileType.TAIGA:
			return BuildingType.SAWMILL
		TileType.HILLS, TileType.MOUNTAIN:
			return BuildingType.MINE
		_:
			return BuildingType.FARM

static func get_build_cost(building_type: int) -> Dictionary:
	match building_type:
		BuildingType.SAWMILL:
			return {"wood": 10, "stone": 0, "food": 0}
		BuildingType.FARM:
			return {"wood": 5, "stone": 0, "food": 0}
		BuildingType.MINE:
			return {"wood": 5, "stone": 15, "food": 0}
		BuildingType.WALL:
			return {"wood": 0, "stone": 3, "food": 0}
		BuildingType.DOOR:
			return {"wood": 5, "stone": 0, "food": 0}
		BuildingType.FLOOR:
			return {"wood": 1, "stone": 0, "food": 0}
		_:
			return {"wood": 0, "stone": 0, "food": 0}

static func get_job_type(building_type: int) -> String:
	match building_type:
		BuildingType.SAWMILL:
			return "lumberjack"
		BuildingType.MINE:
			return "miner"
		BuildingType.FARM:
			return "farmer"
		_:
			return ""

static func get_job_slots(building_type: int) -> int:
	if get_job_type(building_type) != "":
		return 2
	return 0

static func is_station(type: int) -> bool:
	return get_job_type(type) != ""

static func get_resource_for_job(job: String) -> String:
	match job:
		"lumberjack":
			return "wood"
		"miner":
			return "stone"
		"farmer":
			return "food"
		_:
			return ""

static func get_resource_for_building(building_type: int) -> String:
	return get_resource_for_job(get_job_type(building_type))

static func building_type_to_rect(type: int) -> Rect2:
	if type < 3:
		return Rect2(type * 64, 0, 64, 64)
	# Fallback sizes for wall/door/floor placeholders
	match type:
		BuildingType.WALL:
			return Rect2(0, 64, 32, 32)
		BuildingType.DOOR:
			return Rect2(32, 64, 32, 32)
		BuildingType.FLOOR:
			return Rect2(64, 64, 32, 32)
		_:
			return Rect2(0, 0, 32, 32)

static func get_chunk_coords(x: int, y: int) -> Vector2i:
	return Vector2i(floor(float(x) / CHUNK_SIZE), floor(float(y) / CHUNK_SIZE))

static func get_chunk_count() -> int:
	return ceili(float(WORLD_SIZE) / CHUNK_SIZE)
