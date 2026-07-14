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
	# n is typically in range [-1, 1]
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
