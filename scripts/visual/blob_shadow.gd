class_name BlobShadow
extends Node2D
## Sombra blob reutilizable (FASE VISUAL 2). Dibuja dos elipses concentricas
## (halo suave + nucleo denso) UNA sola vez (canvas item cacheado; cero coste
## por frame). Sigue al padre automaticamente por ser hijo. Respeta el ajuste
## global de sombras (Feedback.shadows_enabled) al entrar al arbol.

@export var radius: float = 22.0
## Aplastamiento vertical (1 = circulo, 0.4 = elipse tipica top-down).
@export var squash: float = 0.42
@export var opacity: float = 0.26
@export var soft_opacity_ratio: float = 0.45
@export var shadow_offset: Vector2 = Vector2(0, 16)
@export var color: Color = Color(0, 0, 0)


func _ready() -> void:
	z_index = -1
	# Grupo para que Feedback aplique el toggle de sombras EN VIVO.
	add_to_group("blob_shadows")
	var fb: Node = get_node_or_null("/root/Feedback")
	if fb != null and not bool(fb.get("shadows_enabled")):
		visible = false
	queue_redraw()


## Reconfigura en runtime (p.ej. si el dueno crece de fase).
func configure(new_radius: float, new_opacity: float = -1.0, new_offset: Vector2 = Vector2.INF) -> void:
	radius = new_radius
	if new_opacity >= 0.0:
		opacity = new_opacity
	if new_offset != Vector2.INF:
		shadow_offset = new_offset
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = shadow_offset
	# Halo suave exterior + nucleo denso: mismo doble nivel que las sombras de
	# personajes de FASE VISUAL 1, en un solo nodo reutilizable.
	_ellipse(center, radius * 1.45, Color(color.r, color.g, color.b, opacity * soft_opacity_ratio))
	_ellipse(center, radius, Color(color.r, color.g, color.b, opacity))


func _ellipse(center: Vector2, r: float, c: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		points.append(center + Vector2(cos(a) * r, sin(a) * r * squash))
	draw_colored_polygon(points, c)
