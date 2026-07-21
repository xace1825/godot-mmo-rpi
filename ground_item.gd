extends Node2D

@onready var icon: Sprite2D = $Icon
@onready var amount_label: Label = $Amount

const RESOURCE_INDEX := {
	"wood": 0,
	"stone": 1,
	"food": 2,
	"prepared_food": 3,
	"planks": 4,
	"blocks": 5,
	"tools": 6,
}

func setup(resource: String, amount: int):
	var idx: int = RESOURCE_INDEX.get(resource, 0)
	icon.region_rect = Rect2(idx * 32, 0, 32, 32)
	amount_label.text = str(amount)

func set_amount(amount: int):
	amount_label.text = str(amount)
