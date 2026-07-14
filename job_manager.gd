extends Node

const TICK_RATE: float = 1.0
const WORK_UNITS_PER_TICK: float = 0.33
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
	for id in GameState.villagers:
		var v = GameState.villagers[id] as Dictionary
		if v["state"] == "idle" or v["state"] == "working":
			v["progress"] += WORK_UNITS_PER_TICK
			v["state"] = "working"
			if v["progress"] >= 1.0:
				v["progress"] = 0.0
				v["carrying"] += PRODUCTION_AMOUNT
				var res := PlanetGenerator.get_resource_for_job(v["job"])
				if res != "" and GameState.resources.has(res):
					GameState.resources[res] += PRODUCTION_AMOUNT
					print("Server: villager ", id, " produced ", res, "=", GameState.resources[res])
				v["state"] = "returning"
		elif v["state"] == "returning":
			# In future: walk to storage. For now instant drop.
			v["carrying"] = 0
			v["state"] = "idle"
	# Sync to all clients periodically handled by Network
