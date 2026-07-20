extends CanvasLayer

signal build_type_selected(type_id: int)
signal reset_requested()
signal spawn_requested()

@onready var main_panel: Panel = $MainPanel
@onready var main_container: HBoxContainer = $MainPanel/MainHBox
@onready var sub_panel: Panel = $SubPanel
@onready var sub_container: HBoxContainer = $SubPanel/SubHBox

var selected_type: int = -1
var current_category: int = -1

const CATEGORY_BUTTONS := {
	"StructuresButton": PlanetGenerator.BuildCategory.STRUCTURES,
	"ProductionButton": PlanetGenerator.BuildCategory.PRODUCTION,
	"LogisticsButton": PlanetGenerator.BuildCategory.LOGISTICS
}

const CATEGORY_NAMES := {
	PlanetGenerator.BuildCategory.STRUCTURES: "СТРУКТУРЫ",
	PlanetGenerator.BuildCategory.PRODUCTION: "ПРОИЗВОДСТВО",
	PlanetGenerator.BuildCategory.LOGISTICS: "ЛОГИСТИКА"
}

const CATEGORY_BUILDINGS := {
	PlanetGenerator.BuildCategory.STRUCTURES: [
		PlanetGenerator.BuildingType.WALL,
		PlanetGenerator.BuildingType.DOOR,
		PlanetGenerator.BuildingType.FLOOR,
		PlanetGenerator.BuildingType.BED,
		-1  # Room mode placeholder
	],
	PlanetGenerator.BuildCategory.PRODUCTION: [
		PlanetGenerator.BuildingType.SAWMILL,
		PlanetGenerator.BuildingType.FARM,
		PlanetGenerator.BuildingType.MINE,
		PlanetGenerator.BuildingType.KITCHEN,
		PlanetGenerator.BuildingType.CARPENTER,
		PlanetGenerator.BuildingType.MASON,
		PlanetGenerator.BuildingType.SMITHY
	],
	PlanetGenerator.BuildCategory.LOGISTICS: [
		PlanetGenerator.BuildingType.STOCKPILE
	]
}

const TYPE_ICONS := {
	PlanetGenerator.BuildingType.SAWMILL: "[Л]",
	PlanetGenerator.BuildingType.FARM: "[Ф]",
	PlanetGenerator.BuildingType.MINE: "[Ш]",
	PlanetGenerator.BuildingType.WALL: "[С]",
	PlanetGenerator.BuildingType.FLOOR: "[П]",
	PlanetGenerator.BuildingType.DOOR: "[Д]",
	PlanetGenerator.BuildingType.STOCKPILE: "[Ск]",
	PlanetGenerator.BuildingType.BED: "[Кр]",
	PlanetGenerator.BuildingType.KITCHEN: "[Кух]",
	PlanetGenerator.BuildingType.CARPENTER: "[Ст]",
	PlanetGenerator.BuildingType.MASON: "[Ка]",
	PlanetGenerator.BuildingType.SMITHY: "[Кз]",
	-1: "[Км]"
}

const RU_NAMES := {
	PlanetGenerator.BuildingType.SAWMILL: "Лесопилка",
	PlanetGenerator.BuildingType.FARM: "Ферма",
	PlanetGenerator.BuildingType.MINE: "Шахта",
	PlanetGenerator.BuildingType.WALL: "Стена",
	PlanetGenerator.BuildingType.FLOOR: "Пол",
	PlanetGenerator.BuildingType.DOOR: "Дверь",
	PlanetGenerator.BuildingType.STOCKPILE: "Склад",
	PlanetGenerator.BuildingType.BED: "Кровать",
	PlanetGenerator.BuildingType.KITCHEN: "Кухня",
	PlanetGenerator.BuildingType.CARPENTER: "Столярная",
	PlanetGenerator.BuildingType.MASON: "Каменотёсная",
	PlanetGenerator.BuildingType.SMITHY: "Кузница",
	-1: "Комната"
}

const TYPE_COLORS := {
	PlanetGenerator.BuildingType.SAWMILL: Color(0.7, 0.5, 0.3),
	PlanetGenerator.BuildingType.FARM: Color(0.3, 0.7, 0.3),
	PlanetGenerator.BuildingType.MINE: Color(0.55, 0.55, 0.6),
	PlanetGenerator.BuildingType.WALL: Color(0.6, 0.6, 0.65),
	PlanetGenerator.BuildingType.FLOOR: Color(0.7, 0.6, 0.45),
	PlanetGenerator.BuildingType.DOOR: Color(0.6, 0.4, 0.25),
	PlanetGenerator.BuildingType.STOCKPILE: Color(0.8, 0.7, 0.4),
	PlanetGenerator.BuildingType.BED: Color(0.9, 0.7, 0.7),
	PlanetGenerator.BuildingType.KITCHEN: Color(0.9, 0.4, 0.3),
	PlanetGenerator.BuildingType.CARPENTER: Color(0.75, 0.6, 0.35),
	PlanetGenerator.BuildingType.MASON: Color(0.6, 0.55, 0.55),
	PlanetGenerator.BuildingType.SMITHY: Color(0.5, 0.55, 0.65),
	-1: Color(0.5, 0.7, 0.9)
}

func _ready():
	main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	main_container.mouse_filter = Control.MOUSE_FILTER_STOP
	sub_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	sub_container.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in main_container.get_children():
		if child is Button:
			child.pressed.connect(_on_main_button_pressed.bind(child))
			child.add_theme_font_size_override("font_size", 16)
			child.mouse_filter = Control.MOUSE_FILTER_STOP
	_highlight_main_default()

func _on_main_button_pressed(button: Button):
	if button.name == "ResetButton":
		print("BuildUI: reset requested")
		reset_requested.emit()
		_close_sub_panel()
		button.accept_event()
		return
	if button.name == "SpawnButton":
		print("BuildUI: spawn requested")
		spawn_requested.emit()
		button.accept_event()
		return
	var category = CATEGORY_BUTTONS.get(button.name, -1)
	if category >= 0:
		_open_category(category, button)
	button.accept_event()

func _open_category(category: int, button: Button):
	current_category = category
	_clear_sub_buttons()
	for type_id in CATEGORY_BUILDINGS[category]:
		var sub := Button.new()
		sub.text = _building_button_text(type_id)
		sub.add_theme_font_size_override("font_size", 16)
		sub.mouse_filter = Control.MOUSE_FILTER_STOP
		sub.set_meta("type_id", type_id)
		var base: Color = TYPE_COLORS.get(type_id, Color(0.2, 0.2, 0.2))
		sub.add_theme_color_override("font_color", Color.WHITE)
		sub.add_theme_stylebox_override("normal", _make_stylebox(base, 0.9))
		sub.pressed.connect(_on_sub_button_pressed.bind(sub))
		sub_container.add_child(sub)
	sub_panel.visible = true
	_highlight_main_button(button)

func _clear_sub_buttons():
	for child in sub_container.get_children():
		child.queue_free()

func _close_sub_panel():
	sub_panel.visible = false
	_clear_sub_buttons()
	current_category = -1
	_highlight_main_default()

func _on_sub_button_pressed(button: Button):
	var type_id: int = button.get_meta("type_id", -1)
	selected_type = type_id
	build_type_selected.emit(type_id)
	print("BuildUI: selected ", button.text, " type ", type_id)
	_highlight_sub_button(button)
	button.accept_event()

func is_room_mode() -> bool:
	return selected_type == -1

func clear_selection():
	selected_type = -1
	_close_sub_panel()

func _building_button_text(type_id: int) -> String:
	var icon: String = TYPE_ICONS.get(type_id, "")
	var ru: String = RU_NAMES.get(type_id, "")
	return "%s
%s" % [icon, ru]

func _highlight_main_button(active: Button):
	for child in main_container.get_children():
		if child is Button:
			if child.name in CATEGORY_BUTTONS:
				child.add_theme_color_override("font_color", Color.WHITE)
				child.add_theme_stylebox_override("normal", _make_stylebox(Color(0.25, 0.25, 0.3), 0.9))
			else:
				child.add_theme_color_override("font_color", Color.WHITE)
				child.add_theme_stylebox_override("normal", _make_stylebox(Color(0.35, 0.2, 0.2), 0.9))
	active.add_theme_color_override("font_color", Color.YELLOW)
	active.add_theme_stylebox_override("normal", _make_stylebox(Color.YELLOW, 0.3))

func _highlight_main_default():
	for child in main_container.get_children():
		if child is Button:
			if child.name in CATEGORY_BUTTONS:
				child.add_theme_color_override("font_color", Color.WHITE)
				child.add_theme_stylebox_override("normal", _make_stylebox(Color(0.25, 0.25, 0.3), 0.9))
			else:
				child.add_theme_color_override("font_color", Color.WHITE)
				child.add_theme_stylebox_override("normal", _make_stylebox(Color(0.35, 0.2, 0.2), 0.9))

func _highlight_sub_button(active: Button):
	for child in sub_container.get_children():
		if child is Button:
			var tid: int = child.get_meta("type_id", -1)
			var base: Color = TYPE_COLORS.get(tid, Color(0.2, 0.2, 0.2))
			child.add_theme_color_override("font_color", Color.WHITE)
			child.add_theme_stylebox_override("normal", _make_stylebox(base, 0.9))
	active.add_theme_color_override("font_color", Color.YELLOW)
	active.add_theme_stylebox_override("normal", _make_stylebox(Color.YELLOW, 0.3))

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

func _input(event):
	# Close sub panel on Escape
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_sub_panel()
