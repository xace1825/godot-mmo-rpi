extends Node

const SAVE_PATH: String = "user://world_save.json"

var buildings: Dictionary = {}
var floors: Dictionary = {}
var blueprints: Dictionary = {}
var stockpiles: Dictionary = {}
var ground_items: Dictionary = {}
var rooms: Array = []
var room_station_status: Dictionary = {}
var world_seed: int = 12345
var world: Array = []
var resources: Dictionary = {
	"wood": 0,
	"food": 0,
	"stone": 0,
	"prepared_food": 0,
	"planks": 0,
	"blocks": 0,
	"tools": 0
}
var villagers: Dictionary = {}
var next_villager_id: int = 1
var time_of_day: float = 6.0
var day_count: int = 1
var table_occupants: Dictionary = {}
var job_priorities: Dictionary = {
	"builder": true,
	"lumberjack": true,
	"miner": true,
	"farmer": true,
	"cook": true,
	"carpenter": true,
	"mason": true,
	"toolsmith": true,
	"hauler": true
}

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

func is_walkable(pos: Vector2i) -> bool:
	if not PlanetGenerator.is_walkable_tile(get_tile_type(pos)):
		return false
	var key: String = _pos_key(pos)
	# If a completed building occupies the tile, it controls walkability
	if buildings.has(key):
		return PlanetGenerator.is_walkable_building(buildings[key])
	# Door blueprints are walkable so builders can enter rooms during construction
	if blueprints.has(key):
		var bp: Dictionary = blueprints[key]
		if bp.get("type", -1) == PlanetGenerator.BuildingType.DOOR:
			return true
	# Floors are always walkable
	if floors.has(key):
		return true
	return true

func get_room_at(pos: Vector2i) -> int:
	var key: String = _pos_key(pos)
	for i in range(rooms.size()):
		if key in rooms[i]["tiles"]:
			return i
	return -1

func is_indoor_station(pos: Vector2i) -> bool:
	var key: String = _pos_key(pos)
	return room_station_status.get(key, false)

func recalculate_rooms():
	rooms.clear()
	room_station_status.clear()
	# Gather floor, door and station tiles as room-passable; walls block
	var floor_tiles: Dictionary = {}
	var door_tiles: Dictionary = {}
	var walls: Dictionary = {}
	for key: String in buildings:
		var type_id: int = buildings[key]
		if type_id == PlanetGenerator.BuildingType.WALL:
			walls[key] = true
		elif type_id == PlanetGenerator.BuildingType.DOOR:
			door_tiles[key] = true
			floor_tiles[key] = true
	for key: String in floors:
		floor_tiles[key] = true
	# Stockpile zones are passable (they are just floor designations)
	for stock_id: String in stockpiles:
		for key: String in stockpiles[stock_id]["zone"]:
			floor_tiles[key] = true
	
	var visited: Dictionary = {}
	for start_key: String in floor_tiles:
		if visited.has(start_key):
			continue
		var room: Dictionary = {
			"tiles": [],
			"is_enclosed": true,
			"stations": []
		}
		var queue: Array = [start_key]
		visited[start_key] = true
		while queue.size() > 0:
			var current_key: String = queue.pop_front()
			room["tiles"].append(current_key)
			var pos: Vector2i = _key_pos(current_key)
			var current_is_door: bool = door_tiles.has(current_key)
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbor: Vector2i = pos + dir
				var nkey: String = _pos_key(neighbor)
				# Stop at walls and world borders
				if walls.has(nkey):
					continue
				if neighbor.x < 0 or neighbor.x >= PlanetGenerator.WORLD_SIZE or neighbor.y < 0 or neighbor.y >= PlanetGenerator.WORLD_SIZE:
					room["is_enclosed"] = false
					continue
				# Empty outdoor space adjacent to non-door tile breaks enclosure
				if not floor_tiles.has(nkey):
					if not current_is_door:
						room["is_enclosed"] = false
					continue
				if not visited.has(nkey):
					visited[nkey] = true
					queue.append(nkey)
		rooms.append(room)
	
	# Mark stations
	for key: String in buildings:
		var type_id: int = buildings[key]
		if not PlanetGenerator.is_station(type_id):
			continue
		var pos: Vector2i = _key_pos(key)
		var room_idx: int = get_room_at(pos)
		var indoor: bool = false
		if room_idx >= 0:
			indoor = rooms[room_idx]["is_enclosed"]
			rooms[room_idx]["stations"].append(pos)
		room_station_status[key] = indoor
	print("Server: recalculated ", rooms.size(), " rooms, indoor stations: ", room_station_status.values().count(true), ", outdoor: ", room_station_status.values().count(false))
	for i in range(rooms.size()):
		print("  room ", i, " enclosed=", rooms[i]["is_enclosed"], " tiles=", rooms[i]["tiles"].size(), " stations=", rooms[i]["stations"])

func _key_pos(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

func _pos_in_stockpile(pos: Vector2i) -> bool:
	for stock_id: String in stockpiles:
		var stock: Dictionary = stockpiles[stock_id]
		var tl := Vector2i(int(stock["topleft"]["x"]), int(stock["topleft"]["y"]))
		var size := Vector2i(int(stock["size"]["x"]), int(stock["size"]["y"]))
		if pos.x >= tl.x and pos.x < tl.x + size.x and pos.y >= tl.y and pos.y < tl.y + size.y:
			return true
	return false

func _pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

func add_blueprint(pos: Vector2i, building_type: int = -1) -> int:
	ensure_world_generated()
	var key = _pos_key(pos)
	if blueprints.has(key):
		var existing: Dictionary = blueprints[key]
		# Allow furniture/buildings to replace a planned floor blueprint (RimWorld-style)
		if existing.get("type", -1) == PlanetGenerator.BuildingType.FLOOR and building_type != PlanetGenerator.BuildingType.FLOOR:
			print("Server: replacing floor blueprint with building at ", key)
			blueprints.erase(key)
		else:
			print("Server: tile already occupied")
			return -1
	if buildings.has(key):
		print("Server: tile already occupied")
		return -1
	if _pos_in_stockpile(pos):
		print("Server: cannot build on a stockpile tile")
		return -1
	if not can_build_at(pos):
		print("Server: cannot build on this terrain")
		return -1
	var tile_type := get_tile_type(pos)
	var type_id := building_type
	if type_id < 0:
		type_id = PlanetGenerator.get_station_type(tile_type)
	# Allow buildings on top of existing floors (RimWorld-style)
	var cost := PlanetGenerator.get_build_cost(type_id)
	blueprints[key] = {
		"type": type_id,
		"pos": {"x": pos.x, "y": pos.y},
		"progress": 0.0,
		"cost": cost,
		"paid": {"wood": 0, "stone": 0, "food": 0, "prepared_food": 0}
	}
	print("Server: added blueprint ", key, " type ", type_id, " cost ", cost)
	Network.broadcast_blueprint_placed(pos, type_id)
	return type_id

func add_room_blueprints(start: Vector2i, end: Vector2i) -> bool:
	ensure_world_generated()
	# Normalize
	var tl := Vector2i(min(start.x, end.x), min(start.y, end.y))
	var br := Vector2i(max(start.x, end.x), max(start.y, end.y))
	if br.x <= tl.x or br.y <= tl.y:
		print("Server: room has zero or negative size")
		return false
	if br.x - tl.x < 2 or br.y - tl.y < 2:
		print("Server: room too small")
		return false
	
	# Calculate required resources
	var perimeter: int = 2 * ((br.x - tl.x + 1) + (br.y - tl.y + 1)) - 4
	var interior: int = (br.x - tl.x - 1) * (br.y - tl.y - 1)
	var wall_cost := PlanetGenerator.get_build_cost(PlanetGenerator.BuildingType.WALL)
	var floor_cost := PlanetGenerator.get_build_cost(PlanetGenerator.BuildingType.FLOOR)
	var door_cost := PlanetGenerator.get_build_cost(PlanetGenerator.BuildingType.DOOR)
	var needed := {
		"wood": wall_cost.get("wood", 0) * (perimeter - 1) + floor_cost.get("wood", 0) * interior + door_cost.get("wood", 0),
		"stone": wall_cost.get("stone", 0) * (perimeter - 1) + floor_cost.get("stone", 0) * interior + door_cost.get("stone", 0),
		"food": 0
	}
	# Check available resources in any stockpile (total pool for room placement)
	var total_available := {"wood": resources.get("wood", 0), "stone": resources.get("stone", 0)}
	for res in needed:
		if needed[res] > total_available.get(res, 0):
			print("Server: not enough ", res, " for room (need ", needed[res], ", have ", total_available.get(res, 0), ")")
			return false
	
	# Choose door position on the side closest to drag start, in the middle of that side
	var door_pos := Vector2i((tl.x + br.x) / 2, tl.y)
	var side_top: int = abs(tl.y - start.y)
	var side_bottom: int = abs(br.y - start.y)
	var side_left: int = abs(tl.x - start.x)
	var side_right: int = abs(br.x - start.x)
	var best_side: int = min(side_top, min(side_bottom, min(side_left, side_right)))
	if best_side == side_top:
		door_pos = Vector2i(clamp(start.x, tl.x + 1, br.x - 1), tl.y)
	elif best_side == side_bottom:
		door_pos = Vector2i(clamp(start.x, tl.x + 1, br.x - 1), br.y)
	elif best_side == side_left:
		door_pos = Vector2i(tl.x, clamp(start.y, tl.y + 1, br.y - 1))
	else:
		door_pos = Vector2i(br.x, clamp(start.y, tl.y + 1, br.y - 1))
	# Fallback to ensure door is on perimeter and not a corner
	if door_pos.x == tl.x and door_pos.y == tl.y:
		door_pos = Vector2i(tl.x + 1, tl.y)
	elif door_pos.x == br.x and door_pos.y == tl.y:
		door_pos = Vector2i(br.x - 1, tl.y)
	elif door_pos.x == tl.x and door_pos.y == br.y:
		door_pos = Vector2i(tl.x + 1, br.y)
	elif door_pos.x == br.x and door_pos.y == br.y:
		door_pos = Vector2i(br.x - 1, br.y)
	
	# Pay for the room immediately from nearest stockpile(s)
	var center := Vector2i((tl.x + br.x) / 2, (tl.y + br.y) / 2)
	for res in needed:
		if needed[res] > 0:
			var remaining: int = needed[res]
			while remaining > 0:
				var stock_id := find_stockpile_with_resources(center, {res: remaining}, {res: 0})
				if stock_id == "":
					print("Server: could not find stockpile with ", res, " for room")
					return false
				var stock: Dictionary = stockpiles[stock_id]
				var take: int = min(remaining, stock["resources"].get(res, 0))
				stock["resources"][res] -= take
				remaining -= take
	
	_recalc_total_resources()
	Network.broadcast_resource_sync()
	
	# Place blueprints
	var wall_count := 0
	var floor_count := 0
	for x in range(tl.x, br.x + 1):
		for y in range(tl.y, br.y + 1):
			var pos := Vector2i(x, y)
			if x == tl.x or x == br.x or y == tl.y or y == br.y:
				if pos == door_pos:
					add_blueprint(pos, PlanetGenerator.BuildingType.DOOR)
				else:
					add_blueprint(pos, PlanetGenerator.BuildingType.WALL)
					wall_count += 1
			else:
				add_blueprint(pos, PlanetGenerator.BuildingType.FLOOR)
				floor_count += 1
	print("Server: added room blueprints walls=", wall_count, " floors=", floor_count, " door at ", door_pos)
	return true

func add_farm_plots(start: Vector2i, end: Vector2i) -> bool:
	ensure_world_generated()
	var tl := Vector2i(min(start.x, end.x), min(start.y, end.y))
	var br := Vector2i(max(start.x, end.x), max(start.y, end.y))
	if br.x < tl.x or br.y < tl.y:
		print("Server: farm plot has zero or negative size")
		return false
	var plot_count := 0
	for x in range(tl.x, br.x + 1):
		for y in range(tl.y, br.y + 1):
			var pos := Vector2i(x, y)
			var type_id := add_blueprint(pos, PlanetGenerator.BuildingType.FARM)
			if type_id >= 0:
				plot_count += 1
	print("Server: added ", plot_count, " farm plot blueprints")
	return plot_count > 0

func add_stockpile(topleft: Vector2i, size: Vector2i) -> bool:
	ensure_world_generated()
	var zone: Array = []
	for dx in range(size.x):
		for dy in range(size.y):
			var pos := Vector2i(topleft.x + dx, topleft.y + dy)
			var key: String = _pos_key(pos)
			if not can_build_at(pos):
				print("Server: cannot place stockpile on non-buildable tile ", pos)
				return false
			if buildings.has(key) or blueprints.has(key):
				print("Server: stockpile overlaps building at ", pos)
				return false
			zone.append(key)
	var stock_id: String = "stock_%d_%d_%d" % [topleft.x, topleft.y, zone.size()]
	var is_first_stockpile: bool = stockpiles.is_empty()
	stockpiles[stock_id] = {
		"topleft": {"x": topleft.x, "y": topleft.y},
		"size": {"x": size.x, "y": size.y},
		"zone": zone,
		"resources": {"wood": 0, "food": 0, "stone": 0, "prepared_food": 0, "planks": 0, "blocks": 0, "tools": 0}
	}
	# Starting resources go to the first stockpile so construction can happen
	if is_first_stockpile:
		stockpiles[stock_id]["resources"] = {"wood": 500, "stone": 500, "food": 500, "prepared_food": 100, "planks": 100, "blocks": 100, "tools": 20}
		print("Server: placed starting resources into first stockpile ", stock_id)
	_recalc_total_resources()
	print("Server: added stockpile ", stock_id, " with ", zone.size(), " tiles")
	Network.broadcast_stockpile_added(stock_id, stockpiles[stock_id])
	return true

func spawn_villager(pos: Vector2i, job: String = "idle") -> int:
	var id := next_villager_id
	next_villager_id += 1
	var v := {
		"id": id,
		"name": "Villager %d" % id,
		"pos": {"x": pos.x, "y": pos.y},
		"from_pos": {"x": pos.x, "y": pos.y},
		"to_pos": {"x": pos.x, "y": pos.y},
		"move_progress": 0.0,
		"home": {"x": pos.x, "y": pos.y},
		"workplace": {"x": pos.x, "y": pos.y},
		"job": job,
		"state": "idle",
		"progress": 0.0,
		"carrying": {"resource": "", "amount": 0},
		"target_blueprint": "",
		"building_type": -1,
		"needs": {
			"hunger": 100.0,
			"energy": 100.0,
			"comfort": 80.0
		},
		"equipment": {"tool": {"type": "", "durability": 0, "max_durability": 0, "quality": "normal"}}
	}
	villagers[str(id)] = v
	print("Server: spawned villager ", id, " at ", pos.x, ",", pos.y, " job ", job)
	return id

func random_walkable_tile() -> Vector2i:
	for i in range(1000):
		var x := randi() % PlanetGenerator.WORLD_SIZE
		var y := randi() % PlanetGenerator.WORLD_SIZE
		var tile := Vector2i(x, y)
		if can_build_at(tile):
			return tile
	return Vector2i(PlanetGenerator.WORLD_SIZE / 2, PlanetGenerator.WORLD_SIZE / 2)

func spawn_builder_for_blueprint(pos: Vector2i) -> Dictionary:
	var id := next_villager_id
	next_villager_id += 1
	# Spawn builder near the nearest stockpile so they visibly walk to the blueprint
	var start_pos := pos
	var stock_id := find_nearest_stockpile(pos)
	if stock_id != "":
		var stock: Dictionary = stockpiles[stock_id]
		var tl := Vector2i(int(stock["topleft"]["x"]), int(stock["topleft"]["y"]))
		var br := tl + Vector2i(int(stock["size"]["x"]), int(stock["size"]["y"])) - Vector2i(1, 1)
		start_pos = Vector2i((tl.x + br.x) / 2, (tl.y + br.y) / 2)
	else:
		start_pos = random_walkable_tile()
	var v := {
		"id": id,
		"name": "Builder %d" % id,
		"pos": {"x": start_pos.x, "y": start_pos.y},
		"from_pos": {"x": start_pos.x, "y": start_pos.y},
		"to_pos": {"x": start_pos.x, "y": start_pos.y},
		"move_progress": 0.0,
		"home": {"x": start_pos.x, "y": start_pos.y},
		"workplace": {"x": pos.x, "y": pos.y},
		"job": "builder",
		"state": "moving_to_blueprint",
		"progress": 0.0,
			"carrying": {"resource": "", "amount": 0},
		"target_blueprint": "%d,%d" % [pos.x, pos.y],
		"building_type": -1,
		"needs": {
			"hunger": 80.0,
			"energy": 80.0,
			"comfort": 50.0
		},
		"equipment": {"tool": {"type": "", "durability": 0, "max_durability": 0, "quality": "normal"}}
	}
	villagers[str(id)] = v
	print("Server: spawned builder ", id, " at ", start_pos.x, ",", start_pos.y, " for blueprint ", pos.x, ",", pos.y)
	return v

func complete_blueprint(pos: Vector2i) -> bool:
	var key: String = _pos_key(pos)
	if not blueprints.has(key):
		return false
	var bp: Dictionary = blueprints[key]
	var cost: Dictionary = bp["cost"]
	var already_paid: bool = true
	for res: String in cost:
		if bp["paid"].get(res, 0) < cost[res]:
			already_paid = false
			break
	
	if not already_paid:
		var stock_id: String = find_stockpile_with_resources(pos, cost, bp["paid"])
		if stock_id == "":
			print("Server: no stockpile available to complete blueprint ", key)
			return false
		var stock: Dictionary = stockpiles[stock_id]
		for res: String in cost:
			if stock["resources"][res] < cost[res] - bp["paid"].get(res, 0):
				print("Server: stockpile ", stock_id, " lacks ", res, " for blueprint ", key)
				return false
		for res: String in cost:
			stock["resources"][res] -= cost[res] - bp["paid"].get(res, 0)
			bp["paid"][res] = cost[res]
		Network.broadcast_stockpile_update(stock_id, stock.duplicate())
	
	var completed_type: int = bp["type"]
	if completed_type == PlanetGenerator.BuildingType.FLOOR:
		floors[key] = completed_type
	else:
		buildings[key] = completed_type
		# When a non-floor building completes on a tile that had a floor blueprint,
		# ensure the floor exists underneath for gameplay consistency.
		if not floors.has(key):
			floors[key] = PlanetGenerator.BuildingType.FLOOR
	blueprints.erase(key)
	_recalc_total_resources()
	if PlanetGenerator.is_station(completed_type):
		# DISABLED: villagers are spawned manually via SPAWN button
		# spawn_villagers_for_station(pos, completed_type)
		pass
	print("Server: blueprint completed at ", key, " type ", completed_type)
	recalculate_rooms()
	Network.broadcast_building_completed(pos, completed_type)
	return true

func pay_blueprint_cost(pos: Vector2i) -> bool:
	var key: String = _pos_key(pos)
	if not blueprints.has(key):
		return false
	var bp: Dictionary = blueprints[key]
	var cost: Dictionary = bp.get("cost", {})
	var stock_id: String = find_stockpile_with_resources(pos, cost, bp["paid"])
	if stock_id == "":
		return false
	var stock: Dictionary = stockpiles[stock_id]
	for res: String in cost:
		var needed: int = cost[res] - bp["paid"].get(res, 0)
		if needed > 0:
			stock["resources"][res] -= needed
			bp["paid"][res] = bp["paid"].get(res, 0) + needed
	_recalc_total_resources()
	print("Server: blueprint ", key, " paid using stockpile ", stock_id, ", remaining stockpile resources: ", stock["resources"])
	Network.broadcast_stockpile_update(stock_id, stock.duplicate())
	return true

func add_building(pos: Vector2i, type_id: int = -1) -> int:
	return add_blueprint(pos, type_id)

func spawn_villagers_for_station(pos: Vector2i, station_type: int) -> Array:
	var job_type := PlanetGenerator.get_job_type(station_type)
	if job_type == "":
		return []
	var key = _pos_key(pos)
	var slots := PlanetGenerator.get_job_slots(station_type)
	var spawned := []
	for i in range(slots):
		var id := next_villager_id
		next_villager_id += 1
		var v := {
			"id": id,
			"name": "Worker %d" % id,
			"pos": {"x": pos.x, "y": pos.y},
			"from_pos": {"x": pos.x, "y": pos.y},
			"to_pos": {"x": pos.x, "y": pos.y},
			"move_progress": 0.0,
			"home": {"x": pos.x, "y": pos.y},
			"workplace": {"x": pos.x, "y": pos.y},
			"job": job_type,
			"state": "idle",
						"progress": 0.0,
			"carrying": {"resource": "", "amount": 0},
			"building_type": station_type,
			"needs": {
				"hunger": 80.0,
				"energy": 80.0,
				"comfort": 50.0
			}
		}
		villagers[str(id)] = v
		spawned.append(v)
		print("Server: spawned villager ", id, " as ", job_type, " at ", key)
	return spawned

func find_stockpile_with_resources(pos: Vector2i, cost: Dictionary, paid: Dictionary) -> String:
	var best_id := ""
	var best_dist := 999999.0
	for stock_id: String in stockpiles:
		var stock: Dictionary = stockpiles[stock_id]
		var can_pay := true
		for res: String in cost:
			var needed: int = cost[res] - paid.get(res, 0)
			if needed > 0 and stock["resources"][res] < needed:
				can_pay = false
				break
		if not can_pay:
			continue
		var cx: float = stock["topleft"]["x"] + stock["size"]["x"] / 2.0
		var cy: float = stock["topleft"]["y"] + stock["size"]["y"] / 2.0
		var dist := sqrt(pow(cx - pos.x, 2) + pow(cy - pos.y, 2))
		if dist < best_dist:
			best_dist = dist
			best_id = stock_id
	return best_id

func find_nearest_stockpile(pos: Vector2i) -> String:
	var best_id := ""
	var best_dist := 999999.0
	for stock_id: String in stockpiles:
		var stock: Dictionary = stockpiles[stock_id]
		var cx: float = stock["topleft"]["x"] + stock["size"]["x"] / 2.0
		var cy: float = stock["topleft"]["y"] + stock["size"]["y"] / 2.0
		var dist := sqrt(pow(cx - pos.x, 2) + pow(cy - pos.y, 2))
		if dist < best_dist:
			best_dist = dist
			best_id = stock_id
	return best_id

func deposit_to_nearest_stockpile(pos: Vector2i, resource: String, amount: int) -> bool:
	if resource == "" or amount <= 0:
		return false
	var stock_id: String = find_nearest_stockpile(pos)
	if stock_id == "":
		_drop_item_on_ground(pos, resource, amount)
		return false
	var stock: Dictionary = stockpiles[stock_id]
	stock["resources"][resource] = stock["resources"].get(resource, 0) + amount
	_recalc_total_resources()
	Network.broadcast_stockpile_update(stock_id, stock.duplicate())
	Network.broadcast_resource_sync()
	print("Server: deposited ", amount, " ", resource, " to ", stock_id)
	return true

func consume_from_nearest_stockpile(pos: Vector2i, resource: String, amount: int) -> bool:
	if resource == "" or amount <= 0:
		return false
	var stock_id: String = find_nearest_stockpile(pos)
	if stock_id == "":
		return false
	var stock: Dictionary = stockpiles[stock_id]
	if stock["resources"].get(resource, 0) < amount:
		return false
	stock["resources"][resource] -= amount
	_recalc_total_resources()
	Network.broadcast_stockpile_update(stock_id, stock.duplicate())
	Network.broadcast_resource_sync()
	print("Server: consumed ", amount, " ", resource, " from ", stock_id)
	return true

func drop_item_on_ground(pos: Vector2i, resource: String, amount: int):
	_drop_item_on_ground(pos, resource, amount)

func _drop_item_on_ground(pos: Vector2i, resource: String, amount: int):
	var key: String = _pos_key(pos)
	if ground_items.has(key):
		var existing: Dictionary = ground_items[key]
		if existing.get("resource", "") == resource:
			existing["amount"] += amount
		else:
			# Mixed resources: keep newest on top visually, but merge different types
			existing["amount"] += amount
	else:
		ground_items[key] = {"resource": resource, "amount": amount}
	Network.broadcast_ground_items_sync()
	print("Server: dropped ", amount, " ", resource, " on ground at ", pos)

func pickup_ground_item(pos: Vector2i, resource: String, max_amount: int) -> int:
	var key: String = _pos_key(pos)
	if not ground_items.has(key):
		return 0
	var item: Dictionary = ground_items[key]
	if item.get("resource", "") != resource:
		return 0
	var amount: int = mini(max_amount, item["amount"])
	item["amount"] -= amount
	if item["amount"] <= 0:
		ground_items.erase(key)
	Network.broadcast_ground_items_sync()
	return amount

func get_ground_items_data() -> Dictionary:
	return ground_items.duplicate()

func _recalc_total_resources():
	resources = {"wood": 0, "food": 0, "stone": 0, "prepared_food": 0, "planks": 0, "blocks": 0, "tools": 0}
	for stock_id: String in stockpiles:
		var stock: Dictionary = stockpiles[stock_id]
		for res: String in resources:
			resources[res] += stock["resources"].get(res, 0)

func get_stockpile_resources_at(pos: Vector2i, resource: String) -> int:
	var stock_id := get_stockpile_at(pos)
	if stock_id == "":
		return 0
	return stockpiles[stock_id]["resources"].get(resource, 0)

func get_stockpile_at(pos: Vector2i) -> String:
	var key: String = _pos_key(pos)
	for stock_id: String in stockpiles:
		if key in stockpiles[stock_id]["zone"]:
			return stock_id
	return ""

func consume_food_for_villager(villager_id: String) -> String:
	if not villagers.has(villager_id):
		return ""
	var v: Dictionary = villagers[villager_id]
	var pos := Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
	var stock_id: String = find_stockpile_with_resources(pos, {"prepared_food": 1, "wood": 0, "stone": 0, "food": 0}, {"prepared_food": 0, "wood": 0, "stone": 0, "food": 0})
	var consumed_type: String = ""
	if stock_id != "":
		stockpiles[stock_id]["resources"]["prepared_food"] -= 1
		consumed_type = "prepared_food"
	else:
		stock_id = find_stockpile_with_resources(pos, {"food": 1, "wood": 0, "stone": 0, "prepared_food": 0}, {"food": 0, "wood": 0, "stone": 0, "prepared_food": 0})
		if stock_id == "":
			return ""
		stockpiles[stock_id]["resources"]["food"] -= 1
		consumed_type = "food"
	_recalc_total_resources()
	Network.broadcast_stockpile_update(stock_id, stockpiles[stock_id].duplicate())
	Network.broadcast_resource_sync()
	print("Server: villager ", villager_id, " took ", consumed_type, " from ", stock_id)
	return consumed_type

func set_villager_job(villager_id: String, job: String) -> bool:
	if not villagers.has(villager_id):
		return false
	var valid_jobs: Array[String] = ["idle", "lumberjack", "miner", "farmer", "cook", "builder", "carpenter", "mason", "toolsmith", "hauler"]
	if not valid_jobs.has(job):
		return false
	var v: Dictionary = villagers[villager_id]
	# Unequip tool when leaving a tool-using job
	if v["job"] in ["lumberjack", "miner", "farmer", "cook", "carpenter", "mason", "toolsmith"]:
		_unequip_tool(villager_id)
	release_table(villager_id)
	v["job"] = job
	v["state"] = "idle"
	v["target_blueprint"] = ""
	v["workplace"] = {}
	v["progress"] = 0.0
	v["carrying"] = {"resource": "", "amount": 0}
	v["to_pos"] = v["pos"].duplicate()
	v["from_pos"] = v["pos"].duplicate()
	v["move_progress"] = 0.0
	print("Server: villager ", villager_id, " job manually set to ", job)
	return true

func _unequip_tool(villager_id: String) -> void:
	if not villagers.has(villager_id):
		return
	var v: Dictionary = villagers[villager_id]
	var eq: Dictionary = v.get("equipment", {})
	var tool: Dictionary = eq.get("tool", {})
	if tool.get("type", "") == "":
		return
	var pos := Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
	var durability: int = int(tool.get("durability", 0))
	if durability > 0:
		var stock_id: String = find_nearest_stockpile(pos)
		if stock_id == "":
			_drop_item_on_ground(pos, "tools", 1)
		else:
			stockpiles[stock_id]["resources"]["tools"] += 1
			Network.broadcast_stockpile_update(stock_id, stockpiles[stock_id].duplicate())
		print("Server: villager ", villager_id, " unequipped tool (durability ", durability, ")")
	else:
		print("Server: villager ", villager_id, " tool broke and was discarded")
	eq["tool"] = {"type": "", "durability": 0, "max_durability": 0, "quality": "normal"}
	_recalc_total_resources()
	Network.broadcast_resource_sync()

func equip_tool_from_stockpile(villager_id: String) -> bool:
	if not villagers.has(villager_id):
		return false
	var v: Dictionary = villagers[villager_id]
	var eq: Dictionary = v.get("equipment", {})
	var tool: Dictionary = eq.get("tool", {})
	if tool.get("type", "") == "tool":
		return true
	var pos := Vector2i(int(round(v["pos"]["x"])), int(round(v["pos"]["y"])))
	var stock_id: String = find_stockpile_with_resources(pos, {"tools": 1}, {"tools": 0})
	if stock_id == "":
		return false
	stockpiles[stock_id]["resources"]["tools"] -= 1
	_recalc_total_resources()
	Network.broadcast_stockpile_update(stock_id, stockpiles[stock_id].duplicate())
	Network.broadcast_resource_sync()
	eq["tool"] = {"type": "tool", "durability": 100, "max_durability": 100, "quality": "normal"}
	print("Server: villager ", villager_id, " equipped tool from ", stock_id)
	return true

func damage_tool(villager_id: String, amount: int) -> bool:
	if not villagers.has(villager_id):
		return false
	var v: Dictionary = villagers[villager_id]
	var eq: Dictionary = v.get("equipment", {})
	var tool: Dictionary = eq.get("tool", {})
	if tool.get("type", "") != "tool":
		return false
	tool["durability"] = max(int(tool.get("durability", 0)) - amount, 0)
	print("Server: villager ", villager_id, " tool durability now ", tool["durability"], "/", tool.get("max_durability", 0))
	if tool["durability"] <= 0:
		_unequip_tool(villager_id)
		return true
	return false

func has_tool_equipped(villager_id: String) -> bool:
	if not villagers.has(villager_id):
		return false
	var eq: Dictionary = villagers[villager_id].get("equipment", {})
	var tool: Dictionary = eq.get("tool", {})
	return tool.get("type", "") == "tool" and int(tool.get("durability", 0)) > 0

func get_tool_quality(villager_id: String) -> String:
	if not villagers.has(villager_id):
		return ""
	var eq: Dictionary = villagers[villager_id].get("equipment", {})
	var tool: Dictionary = eq.get("tool", {})
	if tool.get("type", "") != "tool":
		return ""
	return tool.get("quality", "normal")

func set_job_priority(job: String, enabled: bool) -> void:
	if not job_priorities.has(job):
		return
	job_priorities[job] = enabled
	print("Server: job priority ", job, " set to ", enabled)

func is_job_priority_enabled(job: String) -> bool:
	return job_priorities.get(job, true)

func is_indoor(pos: Vector2i) -> bool:
	var room_idx := get_room_at(pos)
	if room_idx < 0:
		return false
	return rooms[room_idx].get("is_enclosed", false)

func has_floor_or_stockpile(pos: Vector2i) -> bool:
	var key := _pos_key(pos)
	return floors.has(key) or _pos_in_stockpile(pos)

func find_nearest_bed(pos: Vector2i) -> Vector2i:
	var best_pos := Vector2i(-1, -1)
	var best_dist := 999999.0
	for key: String in buildings:
		if buildings[key] != PlanetGenerator.BuildingType.BED:
			continue
		var bed_pos := _key_pos(key)
		var dist := sqrt(pow(bed_pos.x - pos.x, 2) + pow(bed_pos.y - pos.y, 2))
		if dist < best_dist:
			best_dist = dist
			best_pos = bed_pos
	return best_pos

func sleep_at_bed(villager_id: String, bed_pos: Vector2i) -> bool:
	if not villagers.has(villager_id):
		return false
	var key: String = _pos_key(bed_pos)
	if not buildings.has(key) or buildings[key] != PlanetGenerator.BuildingType.BED:
		return false
	var v: Dictionary = villagers[villager_id]
	v["needs"]["comfort"] = min(v["needs"]["comfort"] + 5.0, 100.0)
	print("Server: villager ", villager_id, " went to bed ", bed_pos)
	return true

func find_nearest_table(pos: Vector2i) -> Vector2i:
	var best_pos := Vector2i(-1, -1)
	var best_dist := 999999.0
	for key: String in buildings:
		if buildings[key] != PlanetGenerator.BuildingType.TABLE:
			continue
		var table_pos := _key_pos(key)
		if table_occupants.get(key, "") != "":
			continue
		var dist := sqrt(pow(table_pos.x - pos.x, 2) + pow(table_pos.y - pos.y, 2))
		if dist < best_dist:
			best_dist = dist
			best_pos = table_pos
	return best_pos

func occupy_table(villager_id: String, table_pos: Vector2i) -> bool:
	var key: String = _pos_key(table_pos)
	if not buildings.has(key) or buildings[key] != PlanetGenerator.BuildingType.TABLE:
		return false
	if table_occupants.get(key, "") != "":
		return false
	table_occupants[key] = villager_id
	print("Server: villager ", villager_id, " occupied table ", table_pos)
	return true

func release_table(villager_id: String) -> void:
	for key: String in table_occupants:
		if table_occupants[key] == villager_id:
			table_occupants.erase(key)
			print("Server: villager ", villager_id, " released table ")
			return

func get_table_occupant(table_pos: Vector2i) -> String:
	return table_occupants.get(_pos_key(table_pos), "")

func get_world_data() -> Dictionary:
	ensure_world_generated()
	var stock_copy := {}
	for sid in stockpiles:
		var s: Dictionary = stockpiles[sid]
		stock_copy[sid] = {
			"topleft": s["topleft"].duplicate(),
			"size": s["size"].duplicate(),
			"resources": s["resources"].duplicate()
		}
	return {
		"seed": world_seed,
		"buildings": buildings.duplicate(),
		"floors": floors.duplicate(),
		"blueprints": blueprints.duplicate(),
		"stockpiles": stock_copy,
		"ground_items": ground_items.duplicate(),
		"resources": resources.duplicate(),
		"villagers": villagers.duplicate(),
		"time_of_day": time_of_day,
		"day_count": day_count,
		"job_priorities": job_priorities.duplicate()
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
		floors = data.get("floors", {})
		blueprints = data.get("blueprints", {})
		stockpiles = data.get("stockpiles", {})
		ground_items = data.get("ground_items", {})
		resources = data.get("resources", {"wood": 0, "food": 0, "stone": 0, "prepared_food": 0, "planks": 0, "blocks": 0})
		time_of_day = data.get("time_of_day", 6.0)
		day_count = data.get("day_count", 1)
		job_priorities = data.get("job_priorities", job_priorities.duplicate())
		# Migrate missing refined resources and tools
		for res in ["prepared_food", "planks", "blocks", "tools"]:
			if not resources.has(res):
				resources[res] = 0
		villagers = data.get("villagers", {})
		# Ensure old villagers have needs data
		for vid: String in villagers:
			if not villagers[vid].has("needs"):
				villagers[vid]["needs"] = {"hunger": 100.0, "energy": 100.0, "comfort": 80.0}
			else:
				# Clamp loaded needs so old saves don't start exhausted
				villagers[vid]["needs"]["hunger"] = clamp(villagers[vid]["needs"].get("hunger", 80.0), 50.0, 100.0)
				villagers[vid]["needs"]["energy"] = clamp(villagers[vid]["needs"].get("energy", 80.0), 50.0, 100.0)
				villagers[vid]["needs"]["comfort"] = clamp(villagers[vid]["needs"].get("comfort", 50.0), 30.0, 100.0)
			# Ensure workplace/target_blueprint are dictionaries, not null
			if not villagers[vid].has("workplace") or villagers[vid]["workplace"] == null:
				villagers[vid]["workplace"] = {}
			if not villagers[vid].has("target_blueprint") or villagers[vid]["target_blueprint"] == null:
				villagers[vid]["target_blueprint"] = ""
			if not villagers[vid].has("carrying") or villagers[vid]["carrying"] == null:
				villagers[vid]["carrying"] = {"resource": "", "amount": 0}
		# Ensure all stockpiles have refined-resource keys for newer saves
		for sid: String in stockpiles:
			for res in ["prepared_food", "planks", "blocks"]:
				if not stockpiles[sid]["resources"].has(res):
					stockpiles[sid]["resources"][res] = 0
		# Reset any stuck villagers to idle so the new job manager can reassign them
		for vid: String in villagers:
			villagers[vid]["state"] = "idle"
			villagers[vid]["to_pos"] = villagers[vid]["pos"].duplicate()
			villagers[vid]["from_pos"] = villagers[vid]["pos"].duplicate()
			villagers[vid]["move_progress"] = 0.0
		_recalc_total_resources()
		next_villager_id = data.get("next_villager_id", 1)
		print("Server: loaded planet with ", buildings.size(), " buildings, ", floors.size(), " floors, ", blueprints.size(), " blueprints, ", stockpiles.size(), " stockpiles, ", ground_items.size(), " ground piles, ", villagers.size(), " villagers")
	else:
		push_error("Failed to parse save file")

func create_default_stockpile() -> bool:
	ensure_world_generated()
	var half: int = PlanetGenerator.WORLD_SIZE / 2
	for radius in range(0, 30):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var pos := Vector2i(half + dx, half + dy)
				if can_build_at(pos) and add_stockpile(pos, Vector2i(1, 1)):
					return true
	return false

func save_world():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"seed": world_seed,
		"buildings": buildings,
		"floors": floors,
		"blueprints": blueprints,
		"stockpiles": stockpiles,
		"ground_items": ground_items,
		"resources": resources,
		"villagers": villagers,
		"next_villager_id": next_villager_id,
		"time_of_day": time_of_day,
		"day_count": day_count,
		"job_priorities": job_priorities
	}, "	"))
	file.close()
	print("Server: world saved")

func reset_world():
	buildings.clear()
	floors.clear()
	blueprints.clear()
	stockpiles.clear()
	ground_items.clear()
	rooms.clear()
	room_station_status.clear()
	villagers.clear()
	next_villager_id = 1
	time_of_day = 6.0
	day_count = 1
	resources = {
		"wood": 0,
		"food": 0,
		"stone": 0,
		"prepared_food": 0,
		"planks": 0,
		"blocks": 0,
		"tools": 0
	}
	job_priorities = {
		"builder": true,
		"lumberjack": true,
		"miner": true,
		"farmer": true,
		"cook": true,
		"carpenter": true,
		"mason": true,
		"toolsmith": true,
		"hauler": true
	}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	create_default_stockpile()
	print("Server: world reset, save cleared, default stockpile created")
