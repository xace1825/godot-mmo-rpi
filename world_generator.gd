class_name WorldGenerator

const WORLD_SIZE: int = 64
const TILE_SIZE: int = 32

enum TileType {
	WATER,
	GRASS,
	FOREST,
	MOUNTAIN,
	DESERT
}

enum BuildingType {
	SAWMILL,
	FARM,
	MINE
}

static func generate_world(seed_value: int = 0) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	
	var world := []
	for x in range(WORLD_SIZE):
		var col := []
		for y in range(WORLD_SIZE):
			var n := noise.get_noise_2d(float(x), float(y))
			var type := _noise_to_tile(n)
			col.append(type)
		world.append(col)
	return world

static func _noise_to_tile(n: float) -> int:
	if n < -0.3:
		return TileType.WATER
	elif n < 0.1:
		return TileType.GRASS
	elif n < 0.4:
		return TileType.FOREST
	elif n < 0.7:
		return TileType.MOUNTAIN
	else:
		return TileType.DESERT

static func tile_to_atlas_coords(type: int) -> Vector2i:
	return Vector2i(type, 0)

static func is_buildable(type: int) -> bool:
	return type != TileType.WATER and type != TileType.MOUNTAIN

static func get_building_type(tile_type: int) -> int:
	match tile_type:
		TileType.FOREST:
			return BuildingType.SAWMILL
		TileType.MOUNTAIN:
			return BuildingType.MINE
		_:
			return BuildingType.FARM

static func building_type_to_rect(type: int) -> Rect2:
	# atlas is 192x64, each building 64x64
	return Rect2(type * 64, 0, 64, 64)
