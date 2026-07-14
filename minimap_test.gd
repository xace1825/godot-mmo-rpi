extends Node2D

@onready var tile_map: TileMap = $TileMap

func _ready():
	print("Minimal tilemap test")
	print("TileSet: ", tile_map.tile_set)
	print("Atlas source count: ", tile_map.tile_set.get_source_count())
	var src = tile_map.tile_set.get_source(0)
	print("Source 0: ", src)
	print("Atlas texture: ", src.texture)
	print("Atlas size: ", src.get_atlas_grid_size())
	
	# place a few tiles
	tile_map.set_cell(0, Vector2i(0, 0), 0, Vector2i(0, 0))
	tile_map.set_cell(0, Vector2i(1, 0), 0, Vector2i(1, 0))
	tile_map.set_cell(0, Vector2i(2, 0), 0, Vector2i(2, 0))
	print("Placed 3 tiles")
