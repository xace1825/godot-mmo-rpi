extends Node

const TICK_RATE: float = 1.0
const WORK_UNITS_PER_TICK: float = 0.33
const BUILD_UNITS_PER_TICK: float = 0.25
const PRODUCTION_AMOUNT: int = 1

var tick_timer: float = 0.0

func _ready():
	if not (OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless"):
		set_physics_process(false)

func _physics_process(delta):
	if not (OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless"):
		return
	tick_timer += delta
	if tick_timer >= TICK_RATE:
		tick_timer -= TICK_RATE
		_tick()

func _tick():
	_process_builders()
	_process_workers()

func _process_builders():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		if v["job"] != "builder":
			continue
		var bp_key: String = v.get("target_blueprint", "")
		if bp_key == "" or not GameState.blueprints.has(bp_key):
			bp_key = _find_blueprint()
			if bp_key == "":
				v["state"] = "idle"
				continue
			v["target_blueprint"] = bp_key
		
		var bp = GameState.blueprints[bp_key] as Dictionary
		var pos = Vector2i(int(bp["pos"]["x"]), int(bp["pos"]["y"]))
		v["pos"] = {"x": pos.x, "y": pos.y}
		v["state"] = "building"
		bp["progress"] += BUILD_UNITS_PER_TICK
		if bp["progress"] >= 1.0:
			if GameState.complete_blueprint(pos):
				# For production stations, builder becomes worker
				if bp["type"] < PlanetGenerator.BuildingType.WALL:
					v["job"] = PlanetGenerator.get_job_type(bp["type"])
					v["workplace"] = {"x": pos.x, "y": pos.y}
					v["home"] = {"x": pos.x, "y": pos.y}
					v["building_type"] = bp["type"]
				print("Server: builder ", id, " became ", v["job"], " at ", pos)
				v["target_blueprint"] = ""
				v["state"] = "idle"
			else:
				bp["progress"] = 0.99
				v["state"] = "waiting_resources"

func _find_blueprint() -> String:
	for key in GameState.blueprints:
		return key
	return ""

func _process_workers():
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		var res := PlanetGenerator.get_resource_for_job(v["job"])
		if res == "":
			continue
		if v["state"] == "idle" or v["state"] == "working":
			v["progress"] += WORK_UNITS_PER_TICK
			v["state"] = "working"
			if v["progress"] >= 1.0:
				v["progress"] = 0.0
				v["carrying"] += PRODUCTION_AMOUNT
				if GameState.resources.has(res):
					GameState.resources[res] += PRODUCTION_AMOUNT
					print("Server: villager ", id, " produced ", res, "=", GameState.resources[res])
				v["state"] = "returning"
		elif v["state"] == "returning":
			v["carrying"] = 0
			v["state"] = "idle"
