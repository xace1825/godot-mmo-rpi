extends Node

const SAVE_PATH: String = "user://world_save.json"

var buildings: Dictionary = {}
var world_seed: int = 12345

func add_building(pos: Vector2i, type_id: int) -> bool:
    var key = "%d,%d" % [pos.x, pos.y]
    if buildings.has(key):
        print("Server: tile already occupied")
        return false
    buildings[key] = type_id
    print("Server: added building ", key, " type ", type_id)
    return true

func get_world_data() -> Dictionary:
    return {
        "seed": world_seed,
        "buildings": buildings.duplicate()
    }

func load_world():
    if not FileAccess.file_exists(SAVE_PATH):
        print("Server: no save file, starting fresh world")
        return
    var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
    var json = JSON.new()
    var err = json.parse(file.get_as_text())
    if err == OK:
        var data = json.get_data()
        world_seed = data.get("seed", world_seed)
        buildings = data.get("buildings", {})
        print("Server: loaded world with ", buildings.size(), " buildings")
    else:
        push_error("Failed to parse save file")

func save_world():
    var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify(get_world_data(), "\t"))
    file.close()
    print("Server: world saved")
