extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var content_label: Label = $Panel/VBoxContainer/Content
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var target_type: String = ""  # "stockpile" or "villager"
var target_id: String = ""

func _ready():
	panel.visible = false
	close_button.pressed.connect(_on_close)

func _on_close():
	panel.visible = false
	target_type = ""
	target_id = ""

func show_stockpile(id: String, data: Dictionary):
	target_type = "stockpile"
	target_id = id
	title_label.text = "Склад %s" % id
	var res: Dictionary = data.get("resources", {"wood": 0, "stone": 0, "food": 0})
	var size: Dictionary = data.get("size", {"x": 1, "y": 1})
	var zone_count: int = data.get("zone", []).size()
	content_label.text = "Размер: %dx%d\nКлеток: %d\nДерево: %d\nКамень: %d\nЕда: %d" % [
		size.get("x", 1), size.get("y", 1), zone_count,
		res.get("wood", 0), res.get("stone", 0), res.get("food", 0)
	]
	panel.visible = true

func show_villager(id: String, data: Dictionary):
	target_type = "villager"
	target_id = id
	title_label.text = data.get("name", "Житель %s" % id)
	var job: String = data.get("job", "idle")
	var state: String = data.get("state", "idle")
	var pos: Dictionary = data.get("pos", {"x": 0, "y": 0})
	var workplace: Dictionary = data.get("workplace", {})
	var wp_str := "нет"
	if workplace.has("x") and workplace.has("y"):
		wp_str = "%d,%d" % [int(workplace["x"]), int(workplace["y"])]
	content_label.text = "Профессия: %s\nСостояние: %s\nПозиция: %d,%d\nРабочее место: %s" % [
		job, state, int(pos.get("x", 0)), int(pos.get("y", 0)), wp_str
	]
	panel.visible = true

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		# Do not close when clicking inside the panel
		var rect: Rect2 = panel.get_global_rect()
		if rect.has_point(get_viewport().get_mouse_position()):
			return
		# Left click outside closes the panel
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_close()
