extends Node2D

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow
@onready var carrying_rect: ColorRect = $Carrying
@onready var click_area: Area2D = $ClickArea

var previous_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var move_speed: float = 2.0
var hop_phase: float = 0.0

const CARRY_COLORS := {
	"wood": Color(0.55, 0.35, 0.2),
	"stone": Color(0.55, 0.55, 0.6),
	"food": Color(0.3, 0.65, 0.25)
}

func _ready():
	previous_position = position
	target_position = position

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
		_:
			sprite.modulate = Color(0.9, 0.9, 0.9)
	if shadow:
		shadow.modulate = Color(0, 0, 0, 0.35)

func set_carrying(resource: String, amount: int):
	if carrying_rect == null:
		return
	if resource == "" or amount <= 0:
		carrying_rect.visible = false
	else:
		carrying_rect.visible = true
		carrying_rect.color = CARRY_COLORS.get(resource, Color(0.9, 0.9, 0.9))

func set_next_position(next_pos: Vector2):
	if target_position.is_equal_approx(next_pos):
		return
	previous_position = position
	target_position = next_pos
	move_progress = 0.0
	hop_phase = 0.0

func _process(delta):
	if target_position != previous_position:
		move_progress = min(move_progress + delta * move_speed, 1.0)
		position = previous_position.lerp(target_position, move_progress)
		hop_phase += delta * 8.0
		sprite.position.y = -abs(sin(hop_phase)) * 2.0
		if shadow:
			shadow.scale = Vector2(1.0 - abs(sin(hop_phase)) * 0.2, 1.0 - abs(sin(hop_phase)) * 0.2)
		if move_progress >= 1.0:
			previous_position = target_position
			sprite.position.y = 0.0
			if shadow:
				shadow.scale = Vector2.ONE
	else:
		sprite.position.y = lerp(sprite.position.y, 0.0, delta * 10.0)
		if shadow:
			shadow.scale = shadow.scale.lerp(Vector2.ONE, delta * 10.0)
