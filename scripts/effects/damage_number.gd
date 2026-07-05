extends Node2D
## Número de daño flotante. Aparece sobre el enemigo golpeado, sube un poco y se
## desvanece. Se libera solo. Es liviano: solo un Label + un tween corto.

@onready var _label: Label = $Label


func _ready() -> void:
	add_to_group("vfx")


## Lo llama FeedbackManager justo después de instanciarlo.
func setup(amount: int, color: Color = Color(1, 1, 1, 1)) -> void:
	# Si aún no entró al árbol, _label no existe: guardamos y aplicamos en _ready.
	if not is_node_ready():
		await ready
	_label.text = str(amount)
	_label.add_theme_color_override("font_color", color)
	# Pequeña dispersión horizontal para que números seguidos no se solapen.
	position.x += randf_range(-8.0, 8.0)
	_animate()


func _animate() -> void:
	var rise: float = randf_range(28.0, 40.0)
	scale = Vector2(0.6, 0.6)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", position.y - rise, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.55).set_delay(0.18)
	tween.chain().tween_callback(queue_free)
