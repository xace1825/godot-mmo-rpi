extends Node2D

@onready var icon: ColorRect = $Icon
@onready var amount_label: Label = $Amount

const COLORS := {
	"wood": Color(0.55, 0.35, 0.2),
	"stone": Color(0.55, 0.55, 0.6),
	"food": Color(0.3, 0.65, 0.25)
}

func setup(resource: String, amount: int):
	icon.color = COLORS.get(resource, Color(0.9, 0.9, 0.9))
	amount_label.text = str(amount)

func set_amount(amount: int):
	amount_label.text = str(amount)
