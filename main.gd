extends Node2D

@onready var tile_map: TileMap = $TileMap
@onready var camera: Camera2D = $Camera2D
@onready var build_ui: CanvasLayer = $BuildUI

const TILE_SIZE: int = PlanetGenerator.TILE_SIZE
const WORLD_SIZE: int = PlanetGenerator.WORLD_SIZE

const DEFAULT_SERVER_IP: String = "192.168.0.102"
const DEFAULT_SERVER_PORT: int = 7777
const RECONNECT_DELAY: float = 3.0
const MAX_RECONNECT_ATTEMPTS: int = 10

var building_scene = preload("res://building.tscn")
var blueprint_scene = preload("res://building.tscn")
var villager_scene = preload("res://villager.tscn")
var client_buildings: Dictionary = {}
var client_floors: Dictionary = {}
var client_blueprints: Dictionary = {}
var client_stockpiles: Dictionary = {}
var client_villagers: Dictionary = {}
var ground_item_scene = preload("res://ground_item.tscn")
var client_resources: Dictionary = {"wood": 0, "food": 0, "stone": 0, "prepared_food": 0, "planks": 0, "blocks": 0}
var client_stockpile_labels: Dictionary = {}
var client_stockpile_sprites: Dictionary = {}
var client_villager_nodes: Dictionary = {}
var client_ground_item_nodes: Dictionary = {}
var is_server: bool = false
var camera_frames: int = 0
var camera_speed: float = 1200.0
var zoom_speed: float = 0.1
var world_data: Array = []
var chunk_manager: ChunkManager = null
var reconnect_attempts: int = 0
var target_server_ip: String = ""
var target_server_port: int = 7777
var info_panel: CanvasLayer = null
var selected_entity: Variant = null

# Stockpile drag selection
var is_dragging_stockpile: bool = false
var drag_start_tile: Vector2i = Vector2i(-1, -1)
var drag_current_tile: Vector2i = Vector2i(-1, -1)

# Room drag selection
var is_dragging_room: bool = false
var room_drag_start: Vector2i = Vector2i(-1, -1)
var room_drag_current: Vector2i = Vector2i(-1, -1)
var is_dragging_farm: bool = false
var farm_drag_start: Vector2i = Vector2i(-1, -1)
var farm_drag_current: Vector2i = Vector2i(-1, -1)

func _ready():
	is_server = OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless"

	if is_server:
		print("Starting DEDICATED SERVER mode")
		Network.start_server()
		GameState.load_world()
		# Starting resources are now placed into the first stockpile, not globally
		print("Server: waiting for first stockpile for starting resources")
		get_tree().set_auto_accept_quit(false)
	else:
		print("Starting CLIENT mode")
		setup_client()
		_parse_server_args()

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_server:
		print("Server: saving world before shutdown")
		GameState.save_world()
		get_tree().quit()

func setup_client():
	Network.building_placed.connect(_on_building_placed)
	Network.blueprint_placed.connect(_on_blueprint_placed)
	Network.stockpile_added.connect(_on_stockpile_added)
	Network.full_sync.connect(_on_full_sync)
	Network.villager_sync.connect(_on_villager_sync)
	Network.resource_sync.connect(_on_resource_sync)
	Network.world_reset.connect(_on_world_reset)
	Network.ground_items_sync.connect(_on_ground_items_sync)
	Network.day_night_sync.connect(_on_day_night_sync)
	Network.job_priority_sync.connect(_on_job_priority_sync)
	build_ui.build_type_selected.connect(_on_build_type_selected)
	build_ui.reset_requested.connect(_on_reset_requested)
	build_ui.spawn_requested.connect(_on_spawn_requested)
	info_panel = $InfoPanel
	_setup_day_night_overlay()

var _night_overlay: ColorRect = null
var _time_label: Label = null
var _current_time_of_day: float = 6.0
var _current_day_count: int = 1

func _setup_day_night_overlay():
	_night_overlay = ColorRect.new()
	_night_overlay.color = Color(0.05, 0.05, 0.25, 0.0)
	_night_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_night_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_overlay.z_index = 100
	get_tree().root.call_deferred("add_child", _night_overlay)
	
	_time_label = Label.new()
	_time_label.position = Vector2(10, 10)
	_time_label.add_theme_font_size_override("font_size", 18)
	get_tree().root.call_deferred("add_child", _time_label)
	call_deferred("_update_time_label")

func _on_day_night_sync(time_of_day: float, day_count: int):
	_current_time_of_day = time_of_day
	_current_day_count = day_count
	_update_time_label()
	_update_night_overlay()

func _on_job_priority_sync(priorities: Dictionary):
	build_ui.update_job_priorities(priorities)

func _update_time_label():
	if _time_label == null:
		return
	var hour: int = int(_current_time_of_day)
	var minute: int = int((_current_time_of_day - hour) * 60.0)
	_time_label.text = "Day %d - %02d:%02d" % [_current_day_count, hour, minute]

func _update_night_overlay():
	if _night_overlay == null:
		return
	# Night is 20:00 - 04:00; peak darkness at midnight
	var darkness: float = 0.0
	if _current_time_of_day >= 20.0 or _current_time_of_day <= 4.0:
		var dist_from_midnight: float = 0.0
		if _current_time_of_day >= 20.0:
			dist_from_midnight = (_current_time_of_day - 20.0) / 8.0
		else:
			dist_from_midnight = (4.0 - _current_time_of_day) / 8.0
		dist_from_midnight = clamp(dist_from_midnight, 0.0, 1.0)
		darkness = sin(dist_from_midnight * PI) * 0.5
	_night_overlay.color = Color(0.05, 0.05, 0.35, darkness)

var selected_build_type: int = -1

func _on_build_type_selected(type_id: int):
	selected_build_type = type_id
	print("Client selected build type: ", type_id)

func _parse_server_args():
	var server_ip = DEFAULT_SERVER_IP
	var server_port = DEFAULT_SERVER_PORT
	var args = OS.get_cmdline_args()
	print("[CLIENT] raw cmdline args: ", args)
	var positional: Array = []
	var i = 0
	while i < args.size():
		if args[i] == "--server-ip" and i + 1 < args.size():
			server_ip = args[i + 1]
			i += 2
		elif args[i] == "--server-port" and i + 1 < args.size():
			server_port = int(args[i + 1])
			i += 2
		elif args[i] == "--scene" and i + 1 < args.size():
			i += 2
		elif not args[i].begins_with("--"):
			positional.append(args[i])
			i += 1
		else:
			i += 1
	if positional.size() >= 1:
		server_ip = positional[0]
	if positional.size() >= 2:
		server_port = int(positional[1])
	target_server_ip = server_ip
	target_server_port = server_port
	print("[CLIENT] parsed server ", target_server_ip, ":", target_server_port)
	multiplayer.connected_to_server.connect(_on_client_connected)
	multiplayer.connection_failed.connect(_on_client_connection_failed)
	multiplayer.server_disconnected.connect(_on_client_disconnected)
	_start_client_connection()

func _start_client_connection():
	reconnect_attempts += 1
	print("[CLIENT] connection attempt ", reconnect_attempts, "/", MAX_RECONNECT_ATTEMPTS, " to ", target_server_ip, ":", target_server_port)
	if not Network.start_client(target_server_ip, target_server_port):
		_on_client_connection_failed()

func _on_client_connected():
	reconnect_attempts = 0
	print("[CLIENT] connected to server, peer id: ", multiplayer.get_unique_id())

func _on_client_connection_failed():
	print("[CLIENT] connection failed to ", target_server_ip, ":", target_server_port, " attempt ", reconnect_attempts)
	_schedule_reconnect()

func _on_client_disconnected():
	print("[CLIENT] disconnected from server")
	_schedule_reconnect()

func _schedule_reconnect():
	if reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
		print("[CLIENT] giving up after ", reconnect_attempts, " attempts")
		return
	print("[CLIENT] retrying in ", RECONNECT_DELAY, " seconds...")
	await get_tree().create_timer(RECONNECT_DELAY).timeout
	_start_client_connection()

func _process(delta):
	if is_server:
		return
	_handle_camera_input(delta)
	if camera and camera_frames < 60:
		camera.make_current()
		camera.reset_smoothing()
		camera.global_position = Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2)
		camera.offset = Vector2.ZERO
		camera.force_update_scroll()
		camera_frames += 1
	if chunk_manager:
		chunk_manager.update(camera.global_position)

func _handle_camera_input(delta):
	if not camera:
		return
	var direction := Vector2.ZERO
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		direction.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		direction.y += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		direction.x += 1
	if direction != Vector2.ZERO:
		direction = direction.normalized()
	camera.position += direction * camera_speed * delta / camera.zoom.x

func _unhandled_input(event):
	if is_server:
		return
	# Ignore clicks that hit the UI
	if event is InputEventMouseButton:
		var hovered = get_viewport().gui_get_hovered_control()
		if hovered != null:
			print("[CLIENT] click over UI control ", hovered.name, " — ignoring for world input")
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = camera.zoom * (1.0 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = camera.zoom / (1.0 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
			if tile.x < 0 or tile.x >= WORLD_SIZE or tile.y < 0 or tile.y >= WORLD_SIZE:
				return
			# Info click when no build type selected
			if selected_build_type == -1:
				var stock_id := _get_stockpile_at_tile(tile)
				if stock_id != "":
					selected_entity = {"type": "stockpile", "id": stock_id}
					if info_panel:
						info_panel.show_stockpile(stock_id, Network.last_full_sync.get("stockpiles", {}).get(stock_id, {}))
					return
				# Check villager click by distance
				var nearest_villager := _get_villager_at_tile(tile)
				if nearest_villager != "":
					selected_entity = {"type": "villager", "id": nearest_villager}
					if info_panel:
						info_panel.show_villager(nearest_villager, Network.last_full_sync.get("villagers", {}).get(nearest_villager, {}))
					return
				return
			if selected_build_type == PlanetGenerator.BuildingType.STOCKPILE:
				if event.pressed:
					is_dragging_stockpile = true
					drag_start_tile = tile
					drag_current_tile = tile
				else:
					if is_dragging_stockpile:
						is_dragging_stockpile = false
						var top_left := Vector2i(min(drag_start_tile.x, drag_current_tile.x), min(drag_start_tile.y, drag_current_tile.y))
						var bottom_right := Vector2i(max(drag_start_tile.x, drag_current_tile.x), max(drag_start_tile.y, drag_current_tile.y))
						var size := Vector2i(bottom_right.x - top_left.x + 1, bottom_right.y - top_left.y + 1)
						if size.x > 0 and size.y > 0:
							print("Client requesting stockpile at ", top_left, " size ", size)
							Network.ask_stockpile(top_left, size)
						drag_start_tile = Vector2i(-1, -1)
						drag_current_tile = Vector2i(-1, -1)
			elif selected_build_type == PlanetGenerator.BuildingType.FARM:
				if event.pressed:
					is_dragging_farm = true
					farm_drag_start = tile
					farm_drag_current = tile
				else:
					if is_dragging_farm:
						is_dragging_farm = false
						var start := Vector2i(min(farm_drag_start.x, farm_drag_current.x), min(farm_drag_start.y, farm_drag_current.y))
						var end := Vector2i(max(farm_drag_start.x, farm_drag_current.x), max(farm_drag_start.y, farm_drag_current.y))
						if end.x >= start.x and end.y >= start.y:
							print("Client requesting farm plots from ", start, " to ", end)
							Network.ask_build_farm_plots(start, end)
						farm_drag_start = Vector2i(-1, -1)
						farm_drag_current = Vector2i(-1, -1)
						build_ui.clear_selection()
			elif build_ui.is_room_mode():
				if event.pressed:
					is_dragging_room = true
					room_drag_start = tile
					room_drag_current = tile
				else:
					if is_dragging_room:
						is_dragging_room = false
						var start := Vector2i(min(room_drag_start.x, room_drag_current.x), min(room_drag_start.y, room_drag_current.y))
						var end := Vector2i(max(room_drag_start.x, room_drag_current.x), max(room_drag_start.y, room_drag_current.y))
						if end.x > start.x and end.y > start.y:
							print("Client requesting room from ", start, " to ", end)
							Network.ask_build_room(start, end)
						room_drag_start = Vector2i(-1, -1)
						room_drag_current = Vector2i(-1, -1)
						build_ui.clear_selection()
			else:
				if event.pressed:
					print("Client clicked tile: ", tile, " type: ", selected_build_type)
					Network.ask_build(tile, selected_build_type)
	elif event is InputEventMouseMotion and is_dragging_stockpile:
		var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
		if tile.x >= 0 and tile.x < WORLD_SIZE and tile.y >= 0 and tile.y < WORLD_SIZE:
			drag_current_tile = tile
	elif event is InputEventMouseMotion and is_dragging_farm:
		var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
		if tile.x >= 0 and tile.x < WORLD_SIZE and tile.y >= 0 and tile.y < WORLD_SIZE:
			farm_drag_current = tile
	elif event is InputEventMouseMotion and is_dragging_room:
		var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
		if tile.x >= 0 and tile.x < WORLD_SIZE and tile.y >= 0 and tile.y < WORLD_SIZE:
			room_drag_current = tile
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		camera.position = Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2)

func _input(event):
	if is_server:
		return
	# Camera pan via keys (handled by Godot's input map) or mouse drag could go here
	pass

func _draw():
	if is_dragging_stockpile and drag_start_tile.x >= 0 and drag_current_tile.x >= 0:
		var top_left := Vector2i(min(drag_start_tile.x, drag_current_tile.x), min(drag_start_tile.y, drag_current_tile.y))
		var bottom_right := Vector2i(max(drag_start_tile.x, drag_current_tile.x), max(drag_start_tile.y, drag_current_tile.y))
		var rect_pos := Vector2(top_left.x * TILE_SIZE, top_left.y * TILE_SIZE)
		var rect_size := Vector2((bottom_right.x - top_left.x + 1) * TILE_SIZE, (bottom_right.y - top_left.y + 1) * TILE_SIZE)
		draw_rect(Rect2(rect_pos, rect_size), Color(0.9, 0.8, 0.3, 0.4), true)
		draw_rect(Rect2(rect_pos, rect_size), Color(0.9, 0.8, 0.3, 0.8), false, 2.0)
	if is_dragging_room and room_drag_start.x >= 0 and room_drag_current.x >= 0:
		var top_left := Vector2i(min(room_drag_start.x, room_drag_current.x), min(room_drag_start.y, room_drag_current.y))
		var bottom_right := Vector2i(max(room_drag_start.x, room_drag_current.x), max(room_drag_start.y, room_drag_current.y))
		var rect_pos := Vector2(top_left.x * TILE_SIZE, top_left.y * TILE_SIZE)
		var rect_size := Vector2((bottom_right.x - top_left.x + 1) * TILE_SIZE, (bottom_right.y - top_left.y + 1) * TILE_SIZE)
		draw_rect(Rect2(rect_pos, rect_size), Color(0.5, 0.7, 0.9, 0.4), true)
		draw_rect(Rect2(rect_pos, rect_size), Color(0.5, 0.7, 0.9, 0.8), false, 2.0)
		# Outline walls
		for x in range(top_left.x, bottom_right.x + 1):
			for y in range(top_left.y, bottom_right.y + 1):
				if x == top_left.x or x == bottom_right.x or y == top_left.y or y == bottom_right.y:
					draw_rect(Rect2(Vector2(x * TILE_SIZE, y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)), Color(0.6, 0.6, 0.65, 0.6), true)
				else:
					draw_rect(Rect2(Vector2(x * TILE_SIZE, y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)), Color(0.7, 0.6, 0.45, 0.4), true)
	if is_dragging_farm and farm_drag_start.x >= 0 and farm_drag_current.x >= 0:
		var farm_top_left := Vector2i(min(farm_drag_start.x, farm_drag_current.x), min(farm_drag_start.y, farm_drag_current.y))
		var farm_bottom_right := Vector2i(max(farm_drag_start.x, farm_drag_current.x), max(farm_drag_start.y, farm_drag_current.y))
		var farm_rect_pos := Vector2(farm_top_left.x * TILE_SIZE, farm_top_left.y * TILE_SIZE)
		var farm_rect_size := Vector2((farm_bottom_right.x - farm_top_left.x + 1) * TILE_SIZE, (farm_bottom_right.y - farm_top_left.y + 1) * TILE_SIZE)
		draw_rect(Rect2(farm_rect_pos, farm_rect_size), Color(0.3, 0.8, 0.3, 0.3), true)
		draw_rect(Rect2(farm_rect_pos, farm_rect_size), Color(0.3, 0.9, 0.3, 0.8), false, 2.0)

func _on_building_placed(pos: Vector2i, type_id: int):
	# Floors are stored separately so furniture/buildings can be placed on top
	if type_id == PlanetGenerator.BuildingType.FLOOR:
		if client_floors.has(pos):
			return
		# Remove blueprint if exists
		if client_blueprints.has(pos):
			client_blueprints[pos].queue_free()
			client_blueprints.erase(pos)
		var b = building_scene.instantiate()
		b.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
		var sprite := b.get_node("Sprite") as Sprite2D
		if sprite:
			sprite.region_rect = PlanetGenerator.building_type_to_rect(type_id)
			sprite.modulate = Color(1, 1, 1, 1)
		b.scale = Vector2.ZERO
		add_child.call_deferred(b)
		client_floors[pos] = b
		print("Client placed floor at ", pos)
		var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(b, "scale", Vector2.ONE, 0.35)
		return
	
	if client_buildings.has(pos):
		return
	# Remove blueprint if exists
	if client_blueprints.has(pos):
		client_blueprints[pos].queue_free()
		client_blueprints.erase(pos)
	var b = building_scene.instantiate()
	b.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
	var sprite := b.get_node("Sprite") as Sprite2D
	if sprite:
		sprite.region_rect = PlanetGenerator.building_type_to_rect(type_id)
		sprite.modulate = Color(1, 1, 1, 1)
	b.scale = Vector2.ZERO
	# If a floor exists here, render the building above it
	if client_floors.has(pos):
		b.z_index = 1
	add_child.call_deferred(b)
	client_buildings[pos] = b
	print("Client placed building at ", pos, " type ", type_id)
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(b, "scale", Vector2.ONE, 0.35)

func _on_blueprint_placed(pos: Vector2i, type_id: int):
	if client_blueprints.has(pos) or client_buildings.has(pos):
		return
	var b = blueprint_scene.instantiate()
	b.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
	var sprite := b.get_node("Sprite") as Sprite2D
	if sprite:
		sprite.region_rect = PlanetGenerator.building_type_to_rect(type_id)
		sprite.modulate = Color(1, 1, 1, 0.5)
	b.scale = Vector2.ZERO
	if client_floors.has(pos):
		b.z_index = 1
	add_child.call_deferred(b)
	client_blueprints[pos] = b
	print("Client placed blueprint at ", pos, " type ", type_id)
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(b, "scale", Vector2.ONE, 0.25)

var camera_initialized: bool = false
var camera_target_position: Vector2 = Vector2.ZERO

func _on_full_sync(data: Dictionary):
	var buildings: Dictionary = data.get("buildings", {})
	var floors: Dictionary = data.get("floors", {})
	var blueprints: Dictionary = data.get("blueprints", {})
	var stockpiles: Dictionary = data.get("stockpiles", {})
	print("Client received full sync with ", buildings.size(), " buildings, ", floors.size(), " floors, ", blueprints.size(), " blueprints, ", stockpiles.size(), " stockpiles")
	var seed_value := data.get("seed", 12345) as int
	world_data = PlanetGenerator.generate_world(seed_value)
	chunk_manager = ChunkManager.new(tile_map, world_data)
	_current_time_of_day = data.get("time_of_day", 6.0)
	_current_day_count = data.get("day_count", 1)
	_update_time_label()
	_update_night_overlay()
	for pos_str in floors:
		var parts: PackedStringArray = pos_str.split(",")
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		_on_building_placed(pos, floors[pos_str])
	for pos_str in buildings:
		var parts: PackedStringArray = pos_str.split(",")
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		_on_building_placed(pos, buildings[pos_str])
	for pos_str in blueprints:
		var parts: PackedStringArray = pos_str.split(",")
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		_on_blueprint_placed(pos, blueprints[pos_str]["type"])
	for stock_id in stockpiles:
		_on_stockpile_added(stock_id, stockpiles[stock_id])
	
	# Initialize camera once, focused on the first stockpile or world center
	if not camera_initialized and camera:
		var first_stock_pos: Vector2i = Vector2i(-1, -1)
		for stock_id in data.get("stockpiles", {}):
			var sdata = data["stockpiles"][stock_id]
			first_stock_pos = Vector2i(int(sdata["topleft"]["x"]), int(sdata["topleft"]["y"]))
			break
		var target: Vector2
		if first_stock_pos.x >= 0:
			target = Vector2(first_stock_pos.x * TILE_SIZE + TILE_SIZE / 2, first_stock_pos.y * TILE_SIZE + TILE_SIZE / 2)
		else:
			target = Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2)
		camera.global_position = target
		camera.position = target
		camera.offset = Vector2.ZERO
		camera.make_current()
		camera.force_update_scroll()
		camera.reset_smoothing()
		camera_frames = 999
		camera_target_position = target
		chunk_manager.update(target)
		camera_initialized = true
	else:
		chunk_manager.update(camera.global_position if camera else Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2))
	_on_villager_sync(data.get("villagers", {}))
	_on_resource_sync(data.get("resources", {"wood": 0, "food": 0, "stone": 0}))

func _on_world_reset(data: Dictionary):
	print("Client: world reset received, clearing local state")
	camera_initialized = false
	camera_target_position = Vector2.ZERO
	camera_frames = 0
	_current_time_of_day = data.get("time_of_day", 6.0)
	_current_day_count = data.get("day_count", 1)
	_update_time_label()
	_update_night_overlay()
	if data.has("seed"):
		var seed_value := data["seed"] as int
		world_data = PlanetGenerator.generate_world(seed_value)
		if chunk_manager:
			chunk_manager = ChunkManager.new(tile_map, world_data)
	# Clear local buildings
	for pos in client_buildings:
		if is_instance_valid(client_buildings[pos]):
			client_buildings[pos].queue_free()
	client_buildings.clear()
	# Clear local floors
	for pos in client_floors:
		if is_instance_valid(client_floors[pos]):
			client_floors[pos].queue_free()
	client_floors.clear()
	# Clear local blueprints
	for pos in client_blueprints:
		if is_instance_valid(client_blueprints[pos]):
			client_blueprints[pos].queue_free()
	client_blueprints.clear()
	# Clear stockpiles
	for stock_id in client_stockpile_sprites:
		if is_instance_valid(client_stockpile_sprites[stock_id]):
			client_stockpile_sprites[stock_id].queue_free()
	client_stockpile_sprites.clear()
	for stock_id in client_stockpile_labels:
		if is_instance_valid(client_stockpile_labels[stock_id]):
			client_stockpile_labels[stock_id].queue_free()
	client_stockpile_labels.clear()
	client_stockpiles.clear()
	# Clear villagers
	for id in client_villagers:
		if is_instance_valid(client_villagers[id]):
			client_villagers[id].queue_free()
	client_villagers.clear()
	# Reset resources display
	client_resources = {"wood": 0, "food": 0, "stone": 0, "prepared_food": 0, "planks": 0, "blocks": 0}
	# Re-apply sync only if it contains the expected world fields.
	if data.has("buildings"):
		_on_full_sync(data)
	else:
		push_warning("Client: world reset data missing buildings, skipping full sync re-apply")

func _on_ground_items_sync(items: Dictionary):
	# Remove items no longer present
	for key in client_ground_item_nodes.keys():
		if not items.has(key):
			var node = client_ground_item_nodes[key]
			if is_instance_valid(node):
				node.queue_free()
			client_ground_item_nodes.erase(key)
	# Add/update items
	for key in items:
		var item: Dictionary = items[key]
		var parts: PackedStringArray = key.split(",")
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		if client_ground_item_nodes.has(key):
			var node = client_ground_item_nodes[key]
			if is_instance_valid(node):
				_update_ground_item_node(node, item)
			continue
		var node := _create_ground_item_node(pos, item)
		client_ground_item_nodes[key] = node

func _create_ground_item_node(pos: Vector2i, item: Dictionary) -> Node2D:
	var type: String = item.get("resource", "")
	var amount: int = item.get("amount", 0)
	var node := ground_item_scene.instantiate()
	node.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
	node.setup(type, amount)
	add_child.call_deferred(node)
	return node

func _update_ground_item_node(node: Node2D, item: Dictionary):
	node.setup(item.get("resource", ""), item.get("amount", 0))

func _on_resource_sync(resources: Dictionary):
	client_resources = resources.duplicate()
	_update_stockpile_labels()
	print("Client resources: wood=", client_resources.get("wood", 0), " stone=", client_resources.get("stone", 0), " food=", client_resources.get("food", 0), " prepared=", client_resources.get("prepared_food", 0), " planks=", client_resources.get("planks", 0), " blocks=", client_resources.get("blocks", 0))

func _update_stockpile_labels():
	for stock_id in client_stockpile_labels:
		var label: Label = client_stockpile_labels[stock_id]
		if label == null or not is_instance_valid(label):
			continue
		var data = Network.last_full_sync.get("stockpiles", {}).get(stock_id, null)
		if data == null:
			continue
		var res: Dictionary = data.get("resources", {})
		var text := "Д:%d К:%d Е:%d Г:%d Дс:%d Бл:%d" % [res.get("wood", 0), res.get("stone", 0), res.get("food", 0), res.get("prepared_food", 0), res.get("planks", 0), res.get("blocks", 0)]
		label.text = text

func _on_stockpile_added(id: String, data: Dictionary):
	print("Client: stockpile added/updated ", id)
	if not Network.last_full_sync.has("stockpiles"):
		Network.last_full_sync["stockpiles"] = {}
	Network.last_full_sync["stockpiles"][id] = data
	
	if client_stockpiles.has(id):
		_update_stockpile_labels()
		return
	
	var center_x: float = 0.0
	var center_y: float = 0.0
	var count: int = 0
	for key in data.get("zone", []):
		var parts: PackedStringArray = key.split(",")
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		center_x += pos.x
		center_y += pos.y
		count += 1
		var marker := ColorRect.new()
		marker.position = Vector2(pos.x * TILE_SIZE + 1, pos.y * TILE_SIZE + 1)
		marker.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		marker.color = Color(0.9, 0.8, 0.3, 0.25)
		marker.z_index = 1
		add_child.call_deferred(marker)
		marker.mouse_filter = Control.MOUSE_FILTER_STOP
		marker.gui_input.connect(_on_stockpile_marker_clicked.bind(id))
		if not client_stockpiles.has(id):
			client_stockpiles[id] = []
		client_stockpiles[id].append(marker)
	if count > 0:
		center_x = center_x / count * TILE_SIZE + TILE_SIZE / 2
		center_y = center_y / count * TILE_SIZE
		var bg := ColorRect.new()
		bg.position = Vector2(center_x - 40, center_y - 34)
		bg.size = Vector2(80, 18)
		bg.color = Color(0, 0, 0, 0.7)
		bg.z_index = 9
		add_child.call_deferred(bg)
		client_stockpiles[id].append(bg)
		
		var label := Label.new()
		label.text = "Д:0 К:0 Е:0 Г:0"
		label.position = Vector2(center_x - 40, center_y - 34)
		label.size = Vector2(80, 18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(1, 1, 1))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.z_index = 10
		add_child.call_deferred(label)
		client_stockpile_labels[id] = label
		_update_stockpile_labels()

func _on_villager_sync(villagers: Dictionary):
	for id in villagers:
		var v = villagers[id] as Dictionary
		var x := float(v["pos"]["x"])
		var y := float(v["pos"]["y"])
		var target := Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
		var job := v["job"] as String
		var carrying: Dictionary = v.get("carrying", {"resource": "", "amount": 0})
		if client_villagers.has(id):
			var node = client_villagers[id]
			node.set_next_position(target)
			node.setup(job)
			node.set_carrying(carrying.get("resource", ""), carrying.get("amount", 0))
		else:
			var node = villager_scene.instantiate()
			node.position = target
			add_child.call_deferred(node)
			node.setup(job)
			node.set_carrying(carrying.get("resource", ""), carrying.get("amount", 0))
			client_villagers[id] = node
			node.click_area.input_event.connect(_on_villager_clicked.bind(id, v))
	# Remove villagers that are no longer present
	for id in client_villagers.keys():
		if not villagers.has(id):
			if is_instance_valid(client_villagers[id]):
				client_villagers[id].queue_free()
			client_villagers.erase(id)
	
	# Update info panel if a villager is selected
	if info_panel and info_panel.target_type == "villager" and villagers.has(info_panel.target_id):
		info_panel.show_villager(info_panel.target_id, villagers[info_panel.target_id])

func _on_villager_clicked(_viewport: Node, event: InputEvent, _shape_idx: int, id: String, data: Dictionary):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_entity = {"type": "villager", "id": id}
		if info_panel:
			info_panel.show_villager(id, data)

func _on_stockpile_marker_clicked(event: InputEvent, id: String):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_entity = {"type": "stockpile", "id": id}
		if info_panel:
			info_panel.show_stockpile(id, Network.last_full_sync.get("stockpiles", {}).get(id, {}))

func _on_reset_requested():
	print("Client: requesting world reset")
	Network.ask_reset_world()

func _on_spawn_requested():
	print("Client: requesting villager spawn")
	Network.ask_spawn_villager()

func _get_stockpile_at_tile(tile: Vector2i) -> String:
	for stock_id in Network.last_full_sync.get("stockpiles", {}):
		var data: Dictionary = Network.last_full_sync["stockpiles"][stock_id]
		for key in data.get("zone", []):
			var parts: PackedStringArray = key.split(",")
			var pos := Vector2i(int(parts[0]), int(parts[1]))
			if pos == tile:
				return stock_id
	return ""

func _get_villager_at_tile(tile: Vector2i) -> String:
	var best_id := ""
	var best_dist := 999999.0
	var tile_center := Vector2(tile.x * TILE_SIZE + TILE_SIZE / 2, tile.y * TILE_SIZE + TILE_SIZE / 2)
	for id in client_villagers:
		var node = client_villagers[id]
		if not is_instance_valid(node):
			continue
		var dist: float = node.global_position.distance_to(tile_center)
		if dist < TILE_SIZE and dist < best_dist:
			best_dist = dist
			best_id = id
	return best_id
