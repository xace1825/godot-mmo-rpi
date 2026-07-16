extends CanvasLayer

signal build_type_selected(type_id: int)
signal reset_requested()
signal spawn_requested()

@onready var panel: Panel = $Panel
@onready var container: HBoxContainer = $Panel/HBoxContainer

var selected_type: int = -1

const TYPE_MAP := {
	"SawmillButton": PlanetGenerator.BuildingType.SAWMILL,
	"FarmButton": PlanetGenerator.BuildingType.FARM,
	"MineButton": PlanetGenerator.BuildingType.MINE,
	"WallButton": PlanetGenerator.BuildingType.WALL,
	"FloorButton": PlanetGenerator.BuildingType.FLOOR,
	"DoorButton": PlanetGenerator.BuildingType.DOOR,
	"StockpileButton": PlanetGenerator.BuildingType.STOCKPILE
}

const TYPE_ICONS := {
	PlanetGenerator.BuildingType.SAWMILL: "[S]",
	PlanetGenerator.BuildingType.FARM: "[F]",
	PlanetGenerator.BuildingType.MINE: "[M]",
	PlanetGenerator.BuildingType.WALL: "[W]",
	PlanetGenerator.BuildingType.FLOOR: "[Fl]",
	PlanetGenerator.BuildingType.DOOR: "[D]",
	PlanetGenerator.BuildingType.STOCKPILE: "[St]"
}

const TYPE_COLORS := {
	PlanetGenerator.BuildingType.SAWMILL: Color(0.7, 0.5, 0.3),
	PlanetGenerator.BuildingType.FARM: Color(0.3, 0.7, 0.3),
	PlanetGenerator.BuildingType.MINE: Color(0.55, 0.55, 0.6),
	PlanetGenerator.BuildingType.WALL: Color(0.6, 0.6, 0.65),
	PlanetGenerator.BuildingType.FLOOR: Color(0.7, 0.6, 0.45),
	PlanetGenerator.BuildingType.DOOR: Color(0.6, 0.4, 0.25),
	PlanetGenerator.BuildingType.STOCKPILE: Color(0.8, 0.7, 0.4)
}

func _ready():
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in container.get_children():
		if child is Button:
			child.pressed.connect(_on_button_pressed.bind(child))
			child.text = _button_text(child)
			child.add_theme_font_size_override("font_size", 16)
			child.set_meta("type_id", TYPE_MAP.get(child.name, -1))
			child.mouse_filter = Control.MOUSE_FILTER_STOP
	_highlight_default()

func _button_text(button: Button) -> String:
	var type_id: int = TYPE_MAP.get(button.name, -1)
	var icon: String = TYPE_ICONS.get(type_id, "")
	return "%s\n%s" % [icon, button.name.replace("Button", "")]

func _on_button_pressed(button: Button):
	if button.name == "ResetButton":
		print("BuildUI: reset requested")
		reset_requested.emit()
		button.accept_event()
		return
	if button.name == "SpawnButton":
		print("BuildUI: spawn requested")
		spawn_requested.emit()
		button.accept_event()
		return
	var type_id = TYPE_MAP.get(button.name, -1)
	selected_type = type_id
	build_type_selected.emit(type_id)
	print("BuildUI: selected ", button.name, " type ", type_id)
	_highlight_button(button)
	button.accept_event()

func _highlight_button(active: Button):
	for child in container.get_children():
		if child is Button:
			var tid: int = child.get_meta("type_id", -1)
			var base: Color = TYPE_COLORS.get(tid, Color(0.2, 0.2, 0.2))
			child.add_theme_color_override("font_color", Color.WHITE)
			child.add_theme_stylebox_override("normal", _make_stylebox(base, 0.9))
	active.add_theme_color_override("font_color", Color.YELLOW)
	active.add_theme_stylebox_override("normal", _make_stylebox(Color.YELLOW, 0.3))

func _highlight_default():
	for child in container.get_children():
		if child is Button:
			var tid: int = child.get_meta("type_id", -1)
			var base: Color = TYPE_COLORS.get(tid, Color(0.2, 0.2, 0.2))
			child.add_theme_color_override("font_color", Color.WHITE)
			child.add_theme_stylebox_override("normal", _make_stylebox(base, 0.9))

func _make_stylebox(color: Color, alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, alpha)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb
