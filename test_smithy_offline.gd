extends Node

func _ready():
	Engine.time_scale = 10.0
	print("TEST: offline smithy production test starting")
	
	# Singleplayer offline setup
	var offline := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = offline
	
	GameState.reset_world()
	GameState.ensure_world_generated()
	# Clear the default stockpile created by reset_world so totals reflect only our test stockpile
	for sid in GameState.stockpiles.keys():
		GameState.stockpiles[sid]["resources"] = {"wood": 0, "stone": 0, "food": 0, "prepared_food": 0, "planks": 0, "blocks": 0, "tools": 0}
	
	# Place a stockpile next to a buildable tile
	var base_pos := Vector2i(70, 70)
	if not GameState.can_build_at(base_pos):
		base_pos = GameState.random_walkable_tile()
	var stock_pos := base_pos
	var stock_id: bool = GameState.add_stockpile(stock_pos, Vector2i(2, 2))
	if stock_id:
		var last_key: String = GameState.stockpiles.keys()[GameState.stockpiles.size() - 1]
		GameState.stockpiles[last_key]["resources"] = {"wood": 500, "stone": 500, "food": 500, "prepared_food": 100, "planks": 100, "blocks": 100, "tools": 20}
	GameState._recalc_total_resources()
	
	# Place smithy blueprint on an adjacent buildable tile
	var smithy_pos := Vector2i(stock_pos.x + 2, stock_pos.y)
	if not GameState.can_build_at(smithy_pos):
		smithy_pos = GameState.random_walkable_tile()
	GameState.add_blueprint(smithy_pos, PlanetGenerator.BuildingType.SMITHY)
	
	# Complete the smithy instantly (test only)
	GameState.complete_blueprint(smithy_pos)
	if not GameState.buildings.has("%d,%d" % [smithy_pos.x, smithy_pos.y]):
		_fail("smithy could not be completed")
		return
	print("TEST: smithy completed at ", smithy_pos)
	
	# Spawn villager right next to smithy
	var spawn_pos := Vector2i(smithy_pos.x + 1, smithy_pos.y)
	var vid := GameState.spawn_villager(spawn_pos, "idle")
	var sid := str(vid)
	
	# Assign toolsmith manually
	GameState.set_villager_job(sid, "toolsmith")
	
	# Job manager should pick up the manual assignment next tick
	# Wait for production (real time under time_scale)
	await get_tree().create_timer(8.0).timeout
	
	var res := GameState.resources.duplicate()
	print("TEST: resources after 8s = ", res)
	
	if res.get("tools", 0) < 20:
		_fail("tools count dropped (tools=" + str(res.get("tools", 0)) + ")")
		return
	if res.get("planks", 0) >= 100:
		_fail("planks were not consumed (planks=" + str(res.get("planks", 0)) + ")")
		return
	if res.get("blocks", 0) >= 100:
		_fail("blocks were not consumed (blocks=" + str(res.get("blocks", 0)) + ")")
		return
	
	print("TEST PASS: toolsmith produces tools from planks and blocks")
	get_tree().quit()

func _fail(msg: String):
	print("TEST FAIL: ", msg)
	get_tree().quit(1)
