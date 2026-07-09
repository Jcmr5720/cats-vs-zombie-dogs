class_name IconDrawer
extends Control
## Iconos geometricos simples para HUD/cartas. No usa fuentes ni imagenes externas.

@export var icon_type: StringName = &"cat":
	set(value):
		icon_type = value
		queue_redraw()
@export var accent: Color = Color(1.0, 0.8, 0.35, 1.0):
	set(value):
		accent = value
		queue_redraw()
@export var detail: Color = Color(0.08, 0.10, 0.14, 1.0):
	set(value):
		detail = value
		queue_redraw()
@export var level: int = 0:
	set(value):
		level = value
		queue_redraw()
@export var dimmed: bool = false:
	set(value):
		dimmed = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(38, 38)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(size.x, size.y) * 0.44
	var col: Color = accent.darkened(0.48) if dimmed else accent
	# Los iconos de interfaz (flechas, candados, engranajes...) no llevan la sombra
	# de disco que usan los iconos "ficha" del HUD; se dibujan limpios sobre el fondo.
	if not _is_ui_glyph(icon_type):
		draw_circle(c + Vector2(0, r * 0.18), r * 0.86, Color(0, 0, 0, 0.28))
	match icon_type:
		&"health":
			_draw_health(c, r, col)
		&"xp":
			_draw_diamond(c, r, col)
		&"sardine":
			_draw_sardine(c, r, col)
		&"weapon_projectile":
			_draw_projectile(c, r, col)
		&"weapon_explosive":
			_draw_burst(c, r, col)
		&"weapon_boomerang":
			_draw_boomerang(c, r, col)
		&"weapon_laser":
			_draw_laser(c, r, col)
		&"weapon_orbital":
			_draw_orbital(c, r, col)
		&"weapon_area":
			_draw_cloud(c, r, col)
		&"boss":
			_draw_boss(c, r, col)
		&"map":
			_draw_map(c, r, col)
		&"upgrade":
			_draw_upgrade(c, r, col)
		&"companion":
			_draw_cat(c, r, col, true)
		# --- Glifos de interfaz (rediseño UI) ---
		&"back":
			_draw_back(c, r, col)
		&"close":
			_draw_close(c, r, col)
		&"lock":
			_draw_lock(c, r, col)
		&"star":
			_draw_star(c, r, col)
		&"check":
			_draw_check(c, r, col)
		&"clock":
			_draw_clock(c, r, col)
		&"gear":
			_draw_gear(c, r, col)
		&"shield":
			_draw_shield(c, r, col)
		&"paw":
			_draw_paw(c, r, col)
		&"shelter":
			_draw_shelter(c, r, col)
		&"plus":
			_draw_plus(c, r, col)
		&"play":
			_draw_play(c, r, col)
		_:
			_draw_cat(c, r, col, false)

	if level > 0:
		var font := get_theme_default_font()
		var font_size := 12
		var text := str(level)
		var badge := Vector2(size.x - 11, size.y - 10)
		draw_circle(badge, 9.0, Color(0.04, 0.05, 0.07, 0.92))
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, badge + Vector2(-text_size.x * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _draw_cat(c: Vector2, r: float, col: Color, badge: bool) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.62, -r * 0.22), c + Vector2(-r * 0.24, -r * 0.88), c + Vector2(-r * 0.08, -r * 0.24)]), col.darkened(0.08))
	draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.62, -r * 0.22), c + Vector2(r * 0.24, -r * 0.88), c + Vector2(r * 0.08, -r * 0.24)]), col.darkened(0.08))
	draw_circle(c, r * 0.72, col)
	draw_circle(c + Vector2(-r * 0.26, -r * 0.08), r * 0.10, detail)
	draw_circle(c + Vector2(r * 0.26, -r * 0.08), r * 0.10, detail)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.11, r * 0.12), c + Vector2(r * 0.11, r * 0.12), c + Vector2(0, r * 0.25)]), Color(1, 0.56, 0.58))
	if badge:
		draw_circle(c + Vector2(r * 0.46, r * 0.40), r * 0.22, detail)
		draw_circle(c + Vector2(r * 0.46, r * 0.40), r * 0.13, col.lightened(0.25))


func _draw_health(c: Vector2, r: float, col: Color) -> void:
	draw_rect(Rect2(c + Vector2(-r * 0.18, -r * 0.62), Vector2(r * 0.36, r * 1.24)), col, true)
	draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.18), Vector2(r * 1.24, r * 0.36)), col, true)


func _draw_diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.72, 0), c + Vector2(0, r), c + Vector2(-r * 0.72, 0)]), col)
	draw_line(c + Vector2(-r * 0.42, 0), c + Vector2(r * 0.42, 0), col.lightened(0.35), 2.0)


func _draw_sardine(c: Vector2, r: float, col: Color) -> void:
	var body := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		body.append(c + Vector2(cos(a) * r * 0.66 - r * 0.18, sin(a) * r * 0.34))
	draw_colored_polygon(body, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.42, 0), c + Vector2(r * 0.92, -r * 0.42), c + Vector2(r * 0.92, r * 0.42)]), col.darkened(0.08))
	draw_circle(c + Vector2(-r * 0.46, -r * 0.05), r * 0.08, detail)
	draw_line(c + Vector2(-r * 0.12, -r * 0.22), c + Vector2(r * 0.28, r * 0.20), col.lightened(0.32), 2.0)


func _draw_projectile(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r, -r * 0.24), c + Vector2(r * 0.55, -r * 0.24), c + Vector2(r, 0), c + Vector2(r * 0.55, r * 0.24), c + Vector2(-r, r * 0.24)]), col)
	draw_line(c + Vector2(-r * 0.8, 0), c + Vector2(-r * 0.2, 0), col.lightened(0.35), 2.0)


func _draw_burst(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 12:
		pts.append(c + Vector2.RIGHT.rotated(TAU * float(i) / 12.0) * (r if i % 2 == 0 else r * 0.48))
	draw_colored_polygon(pts, col)
	draw_circle(c, r * 0.32, col.lightened(0.35))


func _draw_boomerang(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.85, -r * 0.42), c + Vector2(r * 0.85, -r * 0.05), c + Vector2(-r * 0.78, r * 0.48), c + Vector2(-r * 0.35, 0)]), col)


func _draw_laser(c: Vector2, r: float, col: Color) -> void:
	draw_line(c + Vector2(-r, r * 0.44), c + Vector2(r, -r * 0.44), Color(col.r, col.g, col.b, 0.32), 8.0)
	draw_line(c + Vector2(-r, r * 0.44), c + Vector2(r, -r * 0.44), col, 3.0)
	draw_circle(c + Vector2(r * 0.56, -r * 0.25), r * 0.16, col.lightened(0.42))


func _draw_orbital(c: Vector2, r: float, col: Color) -> void:
	draw_arc(c, r * 0.78, 0.2, TAU - 0.55, 28, col, 3.0)
	draw_circle(c + Vector2.RIGHT.rotated(-0.55) * r * 0.78, r * 0.22, col.lightened(0.2))
	draw_circle(c, r * 0.25, detail)


func _draw_cloud(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(-r * 0.32, r * 0.10), r * 0.38, Color(col.r, col.g, col.b, 0.72))
	draw_circle(c + Vector2(r * 0.05, -r * 0.06), r * 0.46, Color(col.r, col.g, col.b, 0.62))
	draw_circle(c + Vector2(r * 0.42, r * 0.16), r * 0.32, Color(col.r, col.g, col.b, 0.66))


func _draw_boss(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r * 0.78, col.darkened(0.16))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.64, -r * 0.26), c + Vector2(-r * 0.34, -r * 0.96), c + Vector2(-r * 0.10, -r * 0.20)]), col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.64, -r * 0.26), c + Vector2(r * 0.34, -r * 0.96), c + Vector2(r * 0.10, -r * 0.20)]), col)
	draw_circle(c + Vector2(-r * 0.26, -r * 0.08), r * 0.12, Color(1.0, 0.92, 0.28))
	draw_circle(c + Vector2(r * 0.26, -r * 0.08), r * 0.12, Color(1.0, 0.92, 0.28))
	draw_rect(Rect2(c + Vector2(-r * 0.42, r * 0.28), Vector2(r * 0.84, r * 0.16)), detail, true)


func _draw_map(c: Vector2, r: float, col: Color) -> void:
	draw_rect(Rect2(c - Vector2(r * 0.78, r * 0.58), Vector2(r * 1.56, r * 1.16)), col, true)
	draw_line(c + Vector2(-r * 0.28, -r * 0.58), c + Vector2(-r * 0.08, r * 0.58), detail, 2.0)
	draw_line(c + Vector2(r * 0.32, -r * 0.58), c + Vector2(r * 0.14, r * 0.58), detail, 2.0)


func _draw_upgrade(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.34, -r * 0.16), c + Vector2(r, -r * 0.10), c + Vector2(r * 0.48, r * 0.32), c + Vector2(r * 0.62, r), c + Vector2(0, r * 0.58), c + Vector2(-r * 0.62, r), c + Vector2(-r * 0.48, r * 0.32), c + Vector2(-r, -r * 0.10), c + Vector2(-r * 0.34, -r * 0.16)]), col)


# --- Glifos de interfaz -------------------------------------------------------
## Iconos limpios y coloreables para navegación y estados (rediseño UI). Se dibujan
## con trazo grueso para leerse bien a tamaños pequeños; sin sombra de disco.

func _is_ui_glyph(t: StringName) -> bool:
	return t in [&"back", &"close", &"lock", &"star", &"check", &"clock",
		&"gear", &"shield", &"paw", &"shelter", &"plus", &"play"]


func _draw_back(c: Vector2, r: float, col: Color) -> void:
	var w: float = maxf(3.0, r * 0.34)
	draw_line(c + Vector2(r * 0.5, -r * 0.62), c + Vector2(-r * 0.42, 0), col, w)
	draw_line(c + Vector2(-r * 0.42, 0), c + Vector2(r * 0.5, r * 0.62), col, w)


func _draw_close(c: Vector2, r: float, col: Color) -> void:
	var w: float = maxf(3.0, r * 0.30)
	draw_line(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, r * 0.6), col, w)
	draw_line(c + Vector2(r * 0.6, -r * 0.6), c + Vector2(-r * 0.6, r * 0.6), col, w)


func _draw_lock(c: Vector2, r: float, col: Color) -> void:
	draw_arc(c + Vector2(0, -r * 0.12), r * 0.5, PI, TAU, 18, col, maxf(2.5, r * 0.22))
	var body := Rect2(c + Vector2(-r * 0.62, -r * 0.14), Vector2(r * 1.24, r * 0.92))
	_round_rect(body, r * 0.16, col)
	draw_circle(c + Vector2(0, r * 0.28), r * 0.12, detail)


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a: float = -PI * 0.5 + PI * float(i) / 5.0
		var rad: float = r if i % 2 == 0 else r * 0.44
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	if dimmed:
		# Estrella vacía: solo contorno.
		for i in pts.size():
			draw_line(pts[i], pts[(i + 1) % pts.size()], col, maxf(1.5, r * 0.12))
	else:
		draw_colored_polygon(pts, col)


func _draw_check(c: Vector2, r: float, col: Color) -> void:
	var w: float = maxf(3.0, r * 0.30)
	draw_line(c + Vector2(-r * 0.6, 0), c + Vector2(-r * 0.14, r * 0.5), col, w)
	draw_line(c + Vector2(-r * 0.14, r * 0.5), c + Vector2(r * 0.66, -r * 0.5), col, w)


func _draw_clock(c: Vector2, r: float, col: Color) -> void:
	draw_arc(c, r * 0.82, 0.0, TAU, 28, col, maxf(2.5, r * 0.18))
	draw_line(c, c + Vector2(0, -r * 0.52), col, maxf(2.0, r * 0.16))
	draw_line(c, c + Vector2(r * 0.42, r * 0.06), col, maxf(2.0, r * 0.16))


func _draw_gear(c: Vector2, r: float, col: Color) -> void:
	var teeth := PackedVector2Array()
	var count: int = 8
	for i in count * 2:
		var a: float = TAU * float(i) / float(count * 2)
		var rad: float = r if i % 2 == 0 else r * 0.68
		teeth.append(c + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(teeth, col)
	draw_circle(c, r * 0.34, detail)


func _draw_shield(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0, -r * 0.9), c + Vector2(r * 0.78, -r * 0.5),
		c + Vector2(r * 0.62, r * 0.42), c + Vector2(0, r * 0.95),
		c + Vector2(-r * 0.62, r * 0.42), c + Vector2(-r * 0.78, -r * 0.5),
	])
	draw_colored_polygon(pts, col)


func _draw_paw(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(0, r * 0.28), r * 0.5, col)
	draw_circle(c + Vector2(-r * 0.5, -r * 0.16), r * 0.2, col)
	draw_circle(c + Vector2(-r * 0.16, -r * 0.5), r * 0.2, col)
	draw_circle(c + Vector2(r * 0.16, -r * 0.5), r * 0.2, col)
	draw_circle(c + Vector2(r * 0.5, -r * 0.16), r * 0.2, col)


func _draw_shelter(c: Vector2, r: float, col: Color) -> void:
	# Casita con oreja de gato en el tejado.
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 0.8, -r * 0.1), c + Vector2(0, -r * 0.85), c + Vector2(r * 0.8, -r * 0.1),
	]), col)
	_round_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.1), Vector2(r * 1.2, r * 0.95)), r * 0.12, col)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(r * 0.28, -r * 0.62), c + Vector2(r * 0.52, -r * 0.98), c + Vector2(r * 0.6, -r * 0.5),
	]), col)


func _draw_plus(c: Vector2, r: float, col: Color) -> void:
	var w: float = maxf(3.0, r * 0.30)
	draw_line(c + Vector2(0, -r * 0.62), c + Vector2(0, r * 0.62), col, w)
	draw_line(c + Vector2(-r * 0.62, 0), c + Vector2(r * 0.62, 0), col, w)


func _draw_play(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 0.45, -r * 0.62), c + Vector2(r * 0.62, 0), c + Vector2(-r * 0.45, r * 0.62),
	]), col)


## Rectángulo con esquinas redondeadas rellenas (para candado/casita).
func _round_rect(rect: Rect2, radius: float, col: Color) -> void:
	radius = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	draw_rect(Rect2(rect.position + Vector2(radius, 0), rect.size - Vector2(radius * 2.0, 0)), col, true)
	draw_rect(Rect2(rect.position + Vector2(0, radius), rect.size - Vector2(0, radius * 2.0)), col, true)
	for corner in [Vector2(radius, radius), Vector2(rect.size.x - radius, radius),
			Vector2(radius, rect.size.y - radius), Vector2(rect.size.x - radius, rect.size.y - radius)]:
		draw_circle(rect.position + corner, radius, col)
