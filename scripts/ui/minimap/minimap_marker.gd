extends Control
## Marcador reutilizable del minimapa (Sistema Minimapa). Un icono vectorial
## pequeno dibujado por codigo (sin texturas), reciclado mediante object pooling
## por el MinimapController: NUNCA se crea/destruye un marcador por frame.
##
## Tipos: &"player" (triangulo con orientacion), &"companion" (punto celeste),
## &"rescue" (rombo amarillo), &"miniboss" (rombo rojo), &"boss" (icono rojo
## grande). Si la entidad queda fuera del area visible del radar, off_map=true
## y el marcador se dibuja como flecha de borde apuntando hacia ella.

var kind: StringName = &"companion"
var color: Color = Color.WHITE
## Orientacion (radianes): mirada del jugador o direccion hacia la entidad
## cuando esta fuera del radar (flecha de borde).
var heading: float = 0.0
## true = la entidad esta fuera del radar; se dibuja como flecha en el borde.
var off_map: bool = false
## true = entidad debilitada (companero/jugador derribado): se apaga el color.
var dimmed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Configura el marcador y solo redibuja si algo visual cambio (position se
## mueve aparte, sin costo de redraw).
func setup(new_kind: StringName, new_color: Color, new_heading: float = 0.0,
		new_off_map: bool = false, new_dimmed: bool = false) -> void:
	if kind == new_kind and color == new_color and off_map == new_off_map \
			and dimmed == new_dimmed and is_equal_approx(heading, new_heading):
		return
	kind = new_kind
	color = new_color
	heading = new_heading
	off_map = new_off_map
	dimmed = new_dimmed
	queue_redraw()


func _draw() -> void:
	var base: Color = color
	if dimmed:
		base = Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, 0.8)
	if off_map:
		_draw_edge_arrow(base)
		return
	match kind:
		&"player":
			_draw_player(base)
		&"companion":
			_draw_dot(base, 3.5)
		&"rescue":
			_draw_diamond(base, 6.0)
		&"miniboss":
			_draw_diamond(base, 7.5)
		&"boss":
			_draw_boss(base)
		# --- Botin (FASE 13): una FORMA distinta por tipo, no solo un color ---
		&"crate_weapon":
			_draw_crate(base)
		&"crate_supply":
			_draw_supply(base)
		&"crate_special":
			_draw_faceted_diamond(base)
		&"loot_weapon":
			_draw_hollow_square(base)
		&"loot_powerup":
			_draw_triangle(base)
		&"loot_mutation":
			_draw_star(base, 5.5)
		&"loot_core":
			_draw_core(base)
		_:
			_draw_dot(base, 3.0)


## Triangulo orientado hacia la mirada del jugador, con borde oscuro.
func _draw_player(base: Color) -> void:
	draw_set_transform(Vector2.ZERO, heading, Vector2.ONE)
	var pts := PackedVector2Array([Vector2(7, 0), Vector2(-5, -5), Vector2(-5, 5)])
	draw_colored_polygon(pts, base)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.8), 1.4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dot(base: Color, radius: float) -> void:
	draw_circle(Vector2.ZERO, radius + 1.2, Color(0, 0, 0, 0.55))
	draw_circle(Vector2.ZERO, radius, base)


func _draw_diamond(base: Color, half: float) -> void:
	var pts := PackedVector2Array([
		Vector2(0, -half), Vector2(half, 0), Vector2(0, half), Vector2(-half, 0)])
	draw_colored_polygon(pts, base)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.8), 1.4)


## Jefe: circulo rojo grande con anillo y "colmillos" para leerse al instante.
func _draw_boss(base: Color) -> void:
	draw_circle(Vector2.ZERO, 10.5, Color(0, 0, 0, 0.6))
	draw_circle(Vector2.ZERO, 9.0, base)
	draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 20, Color(1, 1, 1, 0.85), 1.6)
	# Cruz interior oscura (calavera abstracta, legible a 9 px).
	draw_line(Vector2(-3.5, -3.5), Vector2(3.5, 3.5), Color(0.1, 0, 0, 0.9), 2.0)
	draw_line(Vector2(3.5, -3.5), Vector2(-3.5, 3.5), Color(0.1, 0, 0, 0.9), 2.0)


## --- Formas de botin (FASE 13) -------------------------------------------------

## Caja de armas: cuadrado relleno con cruz de tablones.
func _draw_crate(base: Color) -> void:
	var h: float = 4.5
	draw_rect(Rect2(-h - 1.2, -h - 1.2, (h + 1.2) * 2.0, (h + 1.2) * 2.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(-h, -h, h * 2.0, h * 2.0), base)
	draw_line(Vector2(-h, -h), Vector2(h, h), Color(0, 0, 0, 0.6), 1.2)
	draw_line(Vector2(h, -h), Vector2(-h, h), Color(0, 0, 0, 0.6), 1.2)


## Caja de suministros: circulo con cruz de botiquin.
func _draw_supply(base: Color) -> void:
	draw_circle(Vector2.ZERO, 5.6, Color(0, 0, 0, 0.55))
	draw_circle(Vector2.ZERO, 4.5, base)
	draw_line(Vector2(0, -2.6), Vector2(0, 2.6), Color(0, 0, 0, 0.7), 1.4)
	draw_line(Vector2(-2.6, 0), Vector2(2.6, 0), Color(0, 0, 0, 0.7), 1.4)


## Caja especial: rombo con facetas.
func _draw_faceted_diamond(base: Color) -> void:
	_draw_diamond(base, 6.0)
	draw_line(Vector2(0, -6), Vector2(0, 6), Color(0, 0, 0, 0.6), 1.0)


## Arma en el suelo: cuadrado HUECO (silueta de caja vacia, se distingue del
## cuadrado relleno de la caja de armas).
func _draw_hollow_square(base: Color) -> void:
	var h: float = 4.5
	draw_rect(Rect2(-h, -h, h * 2.0, h * 2.0), Color(0, 0, 0, 0.6), false, 3.2)
	draw_rect(Rect2(-h, -h, h * 2.0, h * 2.0), base, false, 1.8)


## Mejora comun: triangulo pequeno hacia arriba.
func _draw_triangle(base: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -4.5), Vector2(4.0, 3.2), Vector2(-4.0, 3.2)])
	draw_colored_polygon(pts, base)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.7), 1.2)


## Mutacion: estrella de 5 puntas.
func _draw_star(base: Color, radius: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a: float = -PI * 0.5 + PI * float(i) / 5.0
		var r: float = radius if i % 2 == 0 else radius * 0.45
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, base)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.7), 1.0)


## Nucleo de evolucion: anillo con punto central (orbita).
func _draw_core(base: Color) -> void:
	draw_circle(Vector2.ZERO, 6.2, Color(0, 0, 0, 0.55))
	draw_arc(Vector2.ZERO, 4.8, 0.0, TAU, 16, base, 1.8)
	draw_circle(Vector2.ZERO, 2.0, base)


## Flecha de borde: la entidad esta fuera del radar; apunta hacia su direccion.
## El jefe usa una flecha mayor (prioridad de lectura).
func _draw_edge_arrow(base: Color) -> void:
	var s: float = 9.0 if kind == &"boss" else 6.5
	draw_set_transform(Vector2.ZERO, heading, Vector2.ONE)
	var pts := PackedVector2Array([Vector2(s, 0), Vector2(-s * 0.6, -s * 0.62), Vector2(-s * 0.6, s * 0.62)])
	draw_colored_polygon(pts, base)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.8), 1.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
