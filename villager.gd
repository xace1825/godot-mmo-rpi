extends Node2D

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow
@onready var carrying_sprite: Sprite2D = $Carrying
@onready var click_area: Area2D = $ClickArea

var previous_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var move_speed: float = 2.0
var hop_phase: float = 0.0
var last_move_dir: String = "s"
var _shadow_base_scale: Vector2 = Vector2(0.8, 0.4)

const DIRECTION_FRAMES := {
	"n": 0,
	"s": 1,
	"e": 2,
	"w": 3,
}

const CARRY_FRAMES := {
	"wood": 0,
	"stone": 1,
	"food": 2,
	"prepared_food": 3,
	"planks": 4,
	"blocks": 5,
	"tools": 6,
}

func _ready():
	previous_position = position
	target_position = position
	_update_frame(false)

func setup(job: String):
	match job:
		"lumberjack":
			sprite.modulate = Color(0.7, 0.45, 0.25)
		"miner":
			sprite.modulate = Color(0.5, 0.5, 0.6)
		"farmer":
			sprite.modulate = Color(0.25, 0.7, 0.35)
		"builder":
			sprite.modulate = Color(1.0, 0.65, 0.0)
		"cook":
			sprite.modulate = Color(0.9, 0.4, 0.3)
		"carpenter":
			sprite.modulate = Color(0.75, 0.6, 0.35)
		"mason":
			sprite.modulate = Color(0.6, 0.55, 0.55)
		"hauler":
			sprite.modulate = Color(0.9, 0.75, 0.2)
		_:
			sprite.modulate = Color(0.8, 0.8, 0.8)

func _get_dir(delta: Vector2) -> String:
	if abs(delta.x) >= abs(delta.y):
		return "e" if delta.x >= 0 else "w"
	return "s" if delta.y >= 0 else "n"

func _update_frame(is_walking: bool):
	var row: int = 1 if is_walking else 0
	var col: int = DIRECTION_FRAMES.get(last_move_dir, 1)
	sprite.region_rect = Rect2(col * 32, row * 32, 32, 32)
	shadow.region_rect = Rect2(col * 32, row * 32, 32, 32)

func set_carrying(resource: String, amount: int):
	if carrying_sprite == null:
		return
	if resource == "" or amount <= 0:
		carrying_sprite.visible = false
	else:
		carrying_sprite.visible = true
		var idx: int = CARRY_FRAMES.get(resource, 0)
		carrying_sprite.region_rect = Rect2(idx * 32, 0, 32, 32)

func set_next_position(next_pos: Vector2):
	if target_position.is_equal_approx(next_pos):
		return
	previous_position = position
	target_position = next_pos
	move_progress = 0.0
	hop_phase = 0.0
	last_move_dir = _get_dir(target_position - previous_position)
	_update_frame(true)

func _process(delta):
	if target_position != previous_position:
		move_progress = min(move_progress + delta * move_speed, 1.0)
		position = previous_position.lerp(target_position, move_progress)
		hop_phase += delta * 8.0
		sprite.position.y = -abs(sin(hop_phase)) * 2.0
		if shadow:
			shadow.scale = _shadow_base_scale * (1.0 - abs(sin(hop_phase)) * 0.2)
		if move_progress >= 1.0:
			previous_position = target_position
			sprite.position.y = 0.0
			if shadow:
				shadow.scale = _shadow_base_scale
			_update_frame(false)
	else:
		sprite.position.y = lerp(sprite.position.y, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		if shadow:
			shadow.scale = shadow.scale.lerp(_shadow_base_scale, clampf(delta * 10.0, 0.0, 1.0))
