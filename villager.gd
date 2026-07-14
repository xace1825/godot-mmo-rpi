extends Node2D

@onready var sprite: Sprite2D = $Sprite

func setup(job: String):
	match job:
		"lumberjack":
			sprite.modulate = Color(0.6, 0.4, 0.2)
		"miner":
			sprite.modulate = Color(0.5, 0.5, 0.55)
		"farmer":
			sprite.modulate = Color(0.2, 0.7, 0.3)
		_:
			sprite.modulate = Color(1, 1, 1)

func set_state(state: String):
	pass
