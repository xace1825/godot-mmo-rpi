extends Node2D

@onready var tile_map: TileMap = $TileMap
@onready var camera: Camera2D = $Camera2D
@onready var build_ui: CanvasLayer = $BuildUI
@onready var chat_input: LineEdit = $ChatUI/ChatPanel/VBoxContainer/HBoxContainer/ChatInput
@onready var chat_log: RichTextLabel = $ChatUI/ChatPanel/VBoxContainer/ChatLog
@onready var send_button: Button = $ChatUI/ChatPanel/VBoxContainer/HBoxContainer/SendButton

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
var client_resources: Dictionary = {"wood": 0, "food": 0, "stone": 0, "prepared_food": 0, "planks": 0, "blocks": 0, "tools": 0}
var client_stockpile_labels: Dictionary = {}
var client_stockpile_sprites: Dictionary = {}
var client_villager_nodes: Dictionary = {}
var client_ground_item_nodes: Dictionary = {}
var explored_tiles: Dictionary = {}
var fog_of_war: TileMap = null
var is_server: bool = false
var camera_frames: int = 0
var camera_speed: float = 1200.0
var zoom_speed: float = 0.1
var world_data: Array = []
var _last_world_seed: int = -1
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

# Settlement choice state
var _settle_mode: bool = false
var _settle_overlay: Control = null
var _settle_label: Label = null
var _settle_cursor: ColorRect = null
var _settle_last_tile: Vector2i = Vector2i(-1, -1)

func _ready():
	is_server = OS.has_feature("dedicated_server") or GameLaunch.mode == "host"
	var launch_mode := GameLaunch.mode

	if is_server or launch_mode == "host":
		print("Starting SERVER/HOST mode")
		Network.start_server()
		GameState.load_world()
		get_tree().set_auto_accept_quit(false)
	elif launch_mode == "singleplayer":
		print("Starting SINGLEPLAYER mode")
		# Use offline peer so multiplayer.is_server() is true for local ticks,
		# but no network connection is required.
		var offline := OfflineMultiplayerPeer.new()
		multiplayer.multiplayer_peer = offline
		GameState.ensure_world_generated()
		if GameState.stockpiles.is_empty():
			GameState.create_default_stockpile()
		setup_client()
		# Manually trigger a full sync from local state so the world renders immediately.
		var data := GameState.get_world_data()
		call_deferred("_on_full_sync", data)
	elif launch_mode == "client":
		print("Starting CLIENT mode")
		setup_client()
		target_server_ip = GameLaunch.server_ip
		target_server_port = GameLaunch.server_port
		_parse_server_args()
		Network.base_settled_at.connect(_on_base_settled)
	elif GameLaunch.mode_set_by_cmdline:
		# A mode was explicitly requested via --mode but not recognized.
		print("Unknown launch mode: ", launch_mode)
		get_tree().quit(1)
	else:
		# Fallback for direct launch without menu and without --mode: behave as singleplayer.
		print("Starting SINGLEPLAYER mode (fallback)")
		var offline := OfflineMultiplayerPeer.new()
		multiplayer.multiplayer_peer = offline
		GameState.ensure_world_generated()
		if GameState.stockpiles.is_empty():
			GameState.create_default_stockpile()
		setup_client()
		var data := GameState.get_world_data()
		call_deferred("_on_full_sync", data)
		GameLaunch.mode = "singleplayer"

func _enter_settle_mode():
	if _settle_overlay != null:
		return
	_settle_mode = true
	_build_settle_ui()
	print("Client: entering settle mode")

func _build_settle_ui():
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_settle_overlay = Control.new()
	_settle_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settle_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_settle_overlay)

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE)
	panel.offset_top = 20
	panel.offset_bottom = 80
	panel.custom_minimum_size = Vector2(560, 60)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)
	_settle_overlay.add_child(panel)

	_settle_label = Label.new()
	_settle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_settle_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settle_label.text = "Choose an empty tile for your base (click to settle)"
	_settle_label.add_theme_font_size_override("font_size", 22)
	_settle_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_settle_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	_settle_label.add_theme_constant_override("shadow_offset_x", 2)
	_settle_label.add_theme_constant_override("shadow_offset_y", 2)
	panel.add_child(_settle_label)

func _exit_settle_mode():
	_settle_mode = false
	if _settle_overlay != null and is_instance_valid(_settle_overlay):
		var layer = _settle_overlay.get_parent()
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
		else:
			_settle_overlay.queue_free()
		_settle_overlay = null
		_settle_label = null
	if _settle_cursor != null and is_instance_valid(_settle_cursor):
		_settle_cursor.queue_free()
		_settle_cursor = null

func _on_base_settled(pos: Vector2i):
	print("Client: base settled at ", pos)
	_exit_settle_mode()
	_reveal_fog_around(pos, FOG_RADIUS)
	_focus_camera_on(Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2))

func _focus_camera_on(target: Vector2):
	if not camera:
		return
	camera.global_position = target
	camera.position = target
	camera.offset = Vector2.ZERO
	camera.make_current()
	camera.force_update_scroll()
	camera.reset_smoothing()
	camera_target_position = target
	if chunk_manager:
		chunk_manager.update(target)

func _is_valid_settle_tile_client(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= WORLD_SIZE or pos.y < 0 or pos.y >= WORLD_SIZE:
		return false
	var type := PlanetGenerator.get_tile_type_from_world(world_data, pos)
	if not PlanetGenerator.is_buildable(type):
		return false
	var key := "%d,%d" % [pos.x, pos.y]
	if client_buildings.has(key) or client_blueprints.has(key) or client_stockpiles.has(key) or client_floors.has(key):
		return false
	var bases: Dictionary = Network.last_full_sync.get("player_bases", {})
	var my_id := str(multiplayer.get_unique_id())
	for pid in bases:
		if pid == my_id:
			continue
		var base: Dictionary = bases[pid]
		var base_x: int = int(base.get("x", 0))
		var base_y: int = int(base.get("y", 0))
		var dx: int = abs(base_x - pos.x)
		var dy: int = abs(base_y - pos.y)
		if dx < 20 and dy < 20:
			return false
	return true

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_server:
		print("Server: saving world before shutdown")
		GameState.save_world()
		get_tree().quit()

func setup_client():
	fog_of_war = $FogOfWar
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
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	Network.chat_message.connect(_on_chat_message)
	build_ui.build_type_selected.connect(_on_build_type_selected)
	build_ui.reset_requested.connect(_on_reset_requested)
	build_ui.spawn_requested.connect(_on_spawn_requested)
	if send_button:
		send_button.pressed.connect(_on_send_chat)
	if chat_input:
		chat_input.text_submitted.connect(_on_chat_input_submitted)
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
	var server_ip := target_server_ip
	var server_port := target_server_port
	var args := OS.get_cmdline_args()
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
	if positional.size() >= 1 and server_ip == "":
		server_ip = positional[0]
	if positional.size() >= 2:
		server_port = int(positional[1])
	if server_ip == "":
		server_ip = DEFAULT_SERVER_IP
	server_port = max(1, min(65535, server_port))
	target_server_ip = server_ip
	target_server_port = server_port
	print("[CLIENT] parsed server ", target_server_ip, ":", target_server_port)
	if not multiplayer.connected_to_server.is_connected(_on_client_connected):
		multiplayer.connected_to_server.connect(_on_client_connected)
	if not multiplayer.connection_failed.is_connected(_on_client_connection_failed):
		multiplayer.connection_failed.connect(_on_client_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_client_disconnected):
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
	if reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
		print("[CLIENT] giving up after ", reconnect_attempts, " attempts")
		_show_connection_failed_and_return_to_menu()
		return
	_schedule_reconnect()

func _show_connection_failed_and_return_to_menu():
	# Show a popup with the failure reason, then return to main menu.
	var dialog := AcceptDialog.new()
	dialog.title = "Connection Failed"
	dialog.dialog_text = "Could not connect to server at\n%s:%d\n\nCheck that the server is running and reachable." % [target_server_ip, target_server_port]
	add_child(dialog)
	dialog.confirmed.connect(_return_to_menu)
	dialog.canceled.connect(_return_to_menu)
	dialog.popup_centered()

func _return_to_menu():
	GameLaunch.mode = "client"
	GameLaunch.server_ip = ""
	GameLaunch.server_port = DEFAULT_SERVER_PORT
	get_tree().change_scene_to_file("res://main_menu.tscn")

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
			camera.zoom = camera.zoom.clamp(Vector2(0.1, 0.1), Vector2(4.0, 4.0))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = camera.zoom / (1.0 + zoom_speed)
			camera.zoom = camera.zoom.clamp(Vector2(0.1, 0.1), Vector2(4.0, 4.0))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
			if tile.x < 0 or tile.x >= WORLD_SIZE or tile.y < 0 or tile.y >= WORLD_SIZE:
				return
			# Settlement choice: left click selects base tile before any building is chosen
			if _settle_mode:
				if _is_valid_settle_tile_client(tile):
					print("Client requesting settle base at ", tile)
					Network.ask_settle_base(tile)
				else:
					print("Client: invalid settle tile ", tile)
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
	elif event is InputEventMouseMotion:
		var tile := tile_map.local_to_map(tile_map.get_local_mouse_position())
		if tile.x >= 0 and tile.x < WORLD_SIZE and tile.y >= 0 and tile.y < WORLD_SIZE:
			if _settle_mode:
				_update_settle_cursor(tile)
			if is_dragging_stockpile:
				drag_current_tile = tile
				queue_redraw()
			elif is_dragging_farm:
				farm_drag_current = tile
				queue_redraw()
			elif is_dragging_room:
				room_drag_current = tile
				queue_redraw()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		camera.position = Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2)

func _update_settle_cursor(tile: Vector2i):
	if _settle_cursor == null or not is_instance_valid(_settle_cursor):
		_settle_cursor = ColorRect.new()
		_settle_cursor.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		_settle_cursor.z_index = 10
		add_child(_settle_cursor)
	_settle_cursor.position = Vector2(tile.x * TILE_SIZE + 1, tile.y * TILE_SIZE + 1)
	if _is_valid_settle_tile_client(tile):
		_settle_cursor.color = Color(0.2, 1.0, 0.2, 0.6)
	else:
		_settle_cursor.color = Color(1.0, 0.2, 0.2, 0.6)
	_settle_last_tile = tile

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
		add_child(b)
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
	add_child(b)
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
	add_child(b)
	client_blueprints[pos] = b
	print("Client placed blueprint at ", pos, " type ", type_id)
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(b, "scale", Vector2.ONE, 0.25)

var camera_initialized: bool = false
var camera_target_position: Vector2 = Vector2.ZERO

const FOG_RADIUS: int = 12

func _reveal_fog_around(pos: Vector2i, radius: int = FOG_RADIUS):
	if fog_of_war == null:
		return
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var t := Vector2i(PlanetGenerator.wrap_x(pos.x + dx), pos.y + dy)
			if t.y < 0 or t.y >= WORLD_SIZE:
				continue
			explored_tiles[_pos_key(t)] = true
			fog_of_war.erase_cell(0, t)

func _reset_fog_of_war():
	if fog_of_war == null:
		return
	fog_of_war.clear()
	for y in range(WORLD_SIZE):
		for x in range(WORLD_SIZE):
			fog_of_war.set_cells_terrain_connect(0, [Vector2i(x, y)], 0, 0)

func _pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

func _on_full_sync(data: Dictionary):
	var buildings: Dictionary = data.get("buildings", {})
	var floors: Dictionary = data.get("floors", {})
	var blueprints: Dictionary = data.get("blueprints", {})
	var stockpiles: Dictionary = data.get("stockpiles", {})
	var player_bases: Dictionary = data.get("player_bases", {})
	print("Client received full sync with ", buildings.size(), " buildings, ", floors.size(), " floors, ", blueprints.size(), " blueprints, ", stockpiles.size(), " stockpiles, ", player_bases.size(), " player bases")
	var seed_value := data.get("seed", 12345) as int
	if world_data.is_empty() or _last_world_seed != seed_value:
		world_data = PlanetGenerator.generate_world(seed_value)
		chunk_manager = ChunkManager.new(tile_map, world_data)
		_last_world_seed = seed_value
		_reset_fog_of_war()
	_current_time_of_day = data.get("time_of_day", 6.0)
	_current_day_count = data.get("day_count", 1)
	_update_time_label()
	_update_night_overlay()
	# Apply tilemap chunks now that world data exists.
	if chunk_manager:
		chunk_manager.update(camera.global_position if camera else Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2))
		# Reveal fog around camera center as the player explores
		if fog_of_war != null and camera != null and camera.zoom.x > 0.0:
			var cam_tile := Vector2i(int(camera.global_position.x / TILE_SIZE), int(camera.global_position.y / TILE_SIZE))
			var reveal_radius := maxi(8, int(FOG_RADIUS / camera.zoom.x))
			_reveal_fog_around(cam_tile, reveal_radius)
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
	
	# Initialize camera once, focused on the player's own base if settled,
	# otherwise enter RimWorld-style settlement choice mode.
	if not camera_initialized and camera:
		var my_id := str(multiplayer.get_unique_id())
		var my_base: Dictionary = player_bases.get(my_id, {})
		if my_base.has("x") and my_base.has("y"):
			var base_pos := Vector2i(int(my_base["x"]), int(my_base["y"]))
			_reveal_fog_around(base_pos, FOG_RADIUS)
			_focus_camera_on(Vector2(base_pos.x * TILE_SIZE + TILE_SIZE / 2, base_pos.y * TILE_SIZE + TILE_SIZE / 2))
			camera_initialized = true
		elif not Network.last_full_sync.get("stockpiles", {}).is_empty():
			var stocks: Dictionary = Network.last_full_sync["stockpiles"]
			var first_id: String = stocks.keys()[0]
			var sdata: Dictionary = stocks[first_id]
			var pos := Vector2i(int(sdata["topleft"]["x"]), int(sdata["topleft"]["y"]))
			_reveal_fog_around(pos, FOG_RADIUS)
			_focus_camera_on(Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2))
			camera_initialized = true
		else:
			_focus_camera_on(Vector2(WORLD_SIZE * TILE_SIZE / 2, WORLD_SIZE * TILE_SIZE / 2))
			camera_initialized = true
			if GameLaunch.mode != "singleplayer":
				_enter_settle_mode()
	else:
		if chunk_manager:
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
	client_resources = {"wood": 0, "food": 0, "stone": 0, "prepared_food": 0, "planks": 0, "blocks": 0, "tools": 0}
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
	add_child(node)
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
		add_child(marker)
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
		add_child(bg)
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
		add_child(label)
		client_stockpile_labels[id] = label
		_update_stockpile_labels()

func _on_villager_sync(villagers: Dictionary):
	for id in villagers:
		var v = villagers[id] as Dictionary
		var x := float(v.get("pos", {}).get("x", 0.0))
		var y := float(v.get("pos", {}).get("y", 0.0))
		# Reject obvious garbage coordinates that could come from malformed sync data
		if not is_finite(x) or not is_finite(y):
			push_warning("Client: villager ", id, " has non-finite position (", x, ",", y, ") — skipping")
			continue
		if x < -1.0 or x >= PlanetGenerator.WORLD_SIZE or y < -1.0 or y >= PlanetGenerator.WORLD_SIZE:
			push_warning("Client: villager ", id, " position out of world bounds (", x, ",", y, ") — skipping")
			continue
		var target := Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
		var job := v.get("job", "idle") as String
		var carrying: Dictionary = v.get("carrying", {"resource": "", "amount": 0})
		if client_villagers.has(id):
			var node = client_villagers[id]
			node.set_next_position(target)
			node.setup(job)
			node.set_carrying(carrying.get("resource", ""), carrying.get("amount", 0))
		else:
			var node = villager_scene.instantiate()
			node.position = target
			add_child(node)
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

func _on_send_chat():
	var text := chat_input.text.strip_edges()
	if text != "":
		PlayerManager.send_chat(text)
		chat_input.text = ""

func _on_chat_input_submitted(text: String):
	_on_send_chat()

func _on_chat_message(id: int, text: String):
	var name := PlayerManager.get_player_name(id)
	var color := Color.WHITE
	if PlayerManager.players.has(id):
		color = PlayerManager.players[id].get("color", Color.WHITE)
	chat_log.append_text("[color=#%s]%s[/color]: %s\n" % [color.to_html(false), name, text])

func _on_player_joined(id: int, data: Dictionary):
	chat_log.append_text("[color=gray]%s joined[/color]\n" % data.get("name", "Player %d" % id))

func _on_player_left(id: int):
	chat_log.append_text("[color=gray]%s left[/color]\n" % PlayerManager.get_player_name(id))

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
