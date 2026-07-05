extends Node2D
## Destello de impacto / muerte. Anillo que se expande y se desvanece, con un
## flash central brillante; en efectos grandes (muertes, explosiones) además
## salen chispas radiales. Sin partículas (más barato y predecible).
## Se libera solo al terminar.

@onready var _ring: Polygon2D = $Ring
@onready var _flash: Polygon2D = $Flash
@onready var _sparks: Node2D = $Sparks


func _ready() -> void:
	add_to_group("vfx")


func setup(color: Color = Color(1, 1, 1, 1), start_scale: float = 0.4, end_scale: float = 1.6) -> void:
	if not is_node_ready():
		await ready
	_ring.color = color
	_flash.color = color.lightened(0.45)
	scale = Vector2(start_scale, start_scale)
	rotation = randf() * TAU

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(end_scale, end_scale), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.22)
	# El flash central se apaga más rápido que el anillo (golpe de luz breve).
	tween.tween_property(_flash, "scale", Vector2(0.2, 0.2), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Chispas radiales solo en efectos grandes, para no cargar los impactos comunes.
	if end_scale >= 1.4:
		var count: int = _sparks.get_child_count()
		for i in count:
			var spark := _sparks.get_child(i) as Polygon2D
			if spark == null:
				continue
			spark.color = color.lightened(0.25)
			var dir: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(count) + randf_range(-0.35, 0.35))
			spark.rotation = dir.angle()
			tween.tween_property(spark, "position", dir * randf_range(16.0, 26.0), 0.22) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_sparks.visible = false

	tween.chain().tween_callback(queue_free)
