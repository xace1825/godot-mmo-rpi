extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var content_label: Label = $Panel/VBoxContainer/Content
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var target_type: String = ""  # "stockpile" or "villager"
var target_id: String = ""
var job_buttons_container: HBoxContainer

const JOB_NAMES := {
	"idle": "Без дела",
	"lumberjack": "Лесоруб",
	"miner": "Шахтер",
	"farmer": "Фермер",
	"cook": "Повар",
	"builder": "Строитель",
	"carpenter": "Столяр",
	"mason": "Каменщик",
	"toolsmith": "Кузнец",
	"hauler": "Носильщик"
}

func _ready():
	panel.visible = false
	close_button.pressed.connect(_on_close)
	
	job_buttons_container = HBoxContainer.new()
	job_buttons_container.visible = false
	var vbox: VBoxContainer = $Panel/VBoxContainer
	vbox.add_child(job_buttons_container)
	vbox.move_child(job_buttons_container, vbox.get_child_count() - 2)
	
	for job in JOB_NAMES:
		var btn := Button.new()
		btn.text = JOB_NAMES[job]
		btn.pressed.connect(_on_job_button_pressed.bind(job))
		job_buttons_container.add_child(btn)

func _on_job_button_pressed(job: String):
	if target_type == "villager" and target_id != "":
		print("Client: request set job ", target_id, " = ", job)
		Network.ask_set_job(target_id, job)

func _on_close():
	panel.visible = false
	target_type = ""
	target_id = ""
	job_buttons_container.visible = false

func show_stockpile(id: String, data: Dictionary):
	target_type = "stockpile"
	target_id = id
	job_buttons_container.visible = false
	title_label.text = "Склад %s" % id
	var res: Dictionary = data.get("resources", {"wood": 0, "stone": 0, "food": 0, "prepared_food": 0})
	var size: Dictionary = data.get("size", {"x": 1, "y": 1})
	var zone_count: int = data.get("zone", []).size()
	content_label.text = "Размер: %dx%d\nКлеток: %d\nДерево: %d\nКамень: %d\nЕда: %d\nГотовая еда: %d" % [
		size.get("x", 1), size.get("y", 1), zone_count,
		res.get("wood", 0), res.get("stone", 0), res.get("food", 0), res.get("prepared_food", 0)
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
	var needs: Dictionary = data.get("needs", {"hunger": 100, "energy": 100, "comfort": 100})
	var wp_str := "нет"
	if workplace.has("x") and workplace.has("y"):
		wp_str = "%d,%d" % [int(workplace["x"]), int(workplace["y"])]
	var eq: Dictionary = data.get("equipment", {})
	var tool: Dictionary = eq.get("tool", {})
	var tool_str := "нет"
	if tool.get("type", "") == "tool":
		var dur: int = int(tool.get("durability", 0))
		var max_dur: int = int(tool.get("max_durability", 0))
		tool_str = "инструмент %d/%d (%s)" % [dur, max_dur, tool.get("quality", "normal")]
	content_label.text = "Профессия: %s\nСостояние: %s\nПозиция: %d,%d\nРабочее место: %s\nГолод: %d\nЭнергия: %d\nКомфорт: %d\nЭкипировка: %s" % [
		job, state, int(pos.get("x", 0)), int(pos.get("y", 0)), wp_str,
		int(needs.get("hunger", 100)), int(needs.get("energy", 100)), int(needs.get("comfort", 100)),
		tool_str
	]
	
	job_buttons_container.visible = true
	for i in range(job_buttons_container.get_child_count()):
		var btn := job_buttons_container.get_child(i) as Button
		if btn == null:
			continue
		var btn_job := _get_job_from_button_name(btn.text)
		if btn_job == job:
			btn.modulate = Color(0.6, 1.0, 0.6)
		else:
			btn.modulate = Color(1, 1, 1)
	
	panel.visible = true

func _get_job_from_button_name(name: String) -> String:
	for job in JOB_NAMES:
		if JOB_NAMES[job] == name:
			return job
	return "idle"

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		# Do not close when clicking inside the panel
		var rect: Rect2 = panel.get_global_rect()
		if rect.has_point(get_viewport().get_mouse_position()):
			return
		# Left click outside closes the panel
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_close()
