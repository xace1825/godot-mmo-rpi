class_name ChunkManager

const RENDER_RADIUS: int = 2

var tile_map: TileMap
var world: Array
var rendered_chunks: Dictionary = {}

func _init(map: TileMap, planet: Array):
	tile_map = map
	world = planet

func update(camera_pos: Vector2):
	var cx := floori(camera_pos.x / (PlanetGenerator.CHUNK_SIZE * PlanetGenerator.TILE_SIZE))
	var cy := floori(camera_pos.y / (PlanetGenerator.CHUNK_SIZE * PlanetGenerator.TILE_SIZE))
	for dx in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
		for dy in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
			var cx2 := cx + dx
			var cy2 := cy + dy
			if cx2 < 0 or cy2 < 0 or cx2 >= PlanetGenerator.get_chunk_count() or cy2 >= PlanetGenerator.get_chunk_count():
				continue
			var key := _key(cx2, cy2)
			if not rendered_chunks.has(key):
				rendered_chunks[key] = true
				_render_chunk(cx2, cy2)

func _render_chunk(cx: int, cy: int):
	var start_x := cx * PlanetGenerator.CHUNK_SIZE
	var start_y := cy * PlanetGenerator.CHUNK_SIZE
	for lx in range(PlanetGenerator.CHUNK_SIZE):
		var x := start_x + lx
		if x >= PlanetGenerator.WORLD_SIZE:
			continue
		for ly in range(PlanetGenerator.CHUNK_SIZE):
			var y := start_y + ly
			if y >= PlanetGenerator.WORLD_SIZE:
				continue
			var type := world[x][y] as int
			tile_map.set_cell(0, Vector2i(x, y), 0, PlanetGenerator.tile_to_atlas_coords(type))
	tile_map.queue_redraw()

func _key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]

func is_ready() -> bool:
	return rendered_chunks.size() > 0
