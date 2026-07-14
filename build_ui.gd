extends CanvasLayer

signal build_type_selected(type_id: int)

@onready var panel: Panel = $Panel
@onready var container: HBoxContainer = $Panel/HBoxContainer

var selected_type: int = -1

const TYPE_MAP := {
	"SawmillButton": PlanetGenerator.BuildingType.SAWMILL,
	"FarmButton": PlanetGenerator.BuildingType.FARM,
	"MineButton": PlanetGenerator.BuildingType.MINE,
	"WallButton": PlanetGenerator.BuildingType.WALL,
	"FloorButton": PlanetGenerator.BuildingType.FLOOR,
	"DoorButton": PlanetGenerator.BuildingType.DOOR
}

func _ready():
	for child in container.get_children():
		if child is Button:
			child.pressed.connect(_on_button_pressed.bind(child))

func _on_button_pressed(button: Button):
	var type_id = TYPE_MAP.get(button.name, -1)
	selected_type = type_id
	build_type_selected.emit(type_id)
	print("BuildUI: selected ", button.name, " type ", type_id)
	_highlight_button(button)

func _highlight_button(active: Button):
	for child in container.get_children():
		if child is Button:
			child.modulate = Color.WHITE
	active.modulate = Color.YELLOW
