class_name ChunkManager

const RENDER_RADIUS: int = 3

var tile_map: TileMap
var loaded_chunks: Dictionary = {}
var requested_chunks: Dictionary = {}
var pending_chunks: Dictionary = {}

func _init(map: TileMap):
	tile_map = map

func update(camera_pos: Vector2):
	var cx := floori(camera_pos.x / (PlanetGenerator.CHUNK_SIZE * PlanetGenerator.TILE_SIZE))
	var cy := floori(camera_pos.y / (PlanetGenerator.CHUNK_SIZE * PlanetGenerator.TILE_SIZE))
	var needed := []
	for dx in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
		for dy in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
			var cx2 := cx + dx
			var cy2 := cy + dy
			if cx2 < 0 or cy2 < 0 or cx2 >= PlanetGenerator.get_chunk_count() or cy2 >= PlanetGenerator.get_chunk_count():
				continue
			needed.append(Vector2i(cx2, cy2))
			var key := _key(cx2, cy2)
			if not loaded_chunks.has(key) and not requested_chunks.has(key):
				requested_chunks[key] = true
				Network.request_chunk(cx2, cy2)

func receive_chunk(cx: int, cy: int, tiles: Array):
	var key := _key(cx, cy)
	loaded_chunks[key] = true
	pending_chunks[key] = tiles

func flush_pending_chunks():
	for key in pending_chunks.keys():
		var parts: PackedStringArray = key.split(",")
		var cx := int(parts[0])
		var cy := int(parts[1])
		var tiles: Array = pending_chunks[key]
		_render_chunk(cx, cy, tiles)
	pending_chunks.clear()

func _render_chunk(cx: int, cy: int, tiles: Array):
	for lx in range(tiles.size()):
		var x := cx * PlanetGenerator.CHUNK_SIZE + lx
		if x >= PlanetGenerator.WORLD_SIZE:
			continue
		var col: Array = tiles[lx]
		for ly in range(col.size()):
			var y := cy * PlanetGenerator.CHUNK_SIZE + ly
			if y >= PlanetGenerator.WORLD_SIZE:
				continue
			var type := col[ly] as int
			tile_map.set_cell(0, Vector2i(x, y), 0, PlanetGenerator.tile_to_atlas_coords(type))

func _key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]

func is_ready() -> bool:
	return loaded_chunks.size() > 0
