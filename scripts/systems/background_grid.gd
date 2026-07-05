extends Node2D
## Fondo de cuadrícula urbana sutil dibujado por código (sin texturas externas).
## Sigue el centro de la cámara y se redibuja cada frame, de modo que al moverse
## el jugador la rejilla se desplaza y aporta sensación de velocidad. Mantiene
## buena legibilidad usando líneas tenues sobre un color base oscuro.

## Semilla del mundo de la run (la fija el MapManager); varia los detalles del patron.
@export var world_seed: int = 0
@export var grid_size: float = 64.0
@export var base_color: Color = Color(0.12, 0.13, 0.17)
@export var line_color: Color = Color(0.17, 0.19, 0.25)
@export var major_line_color: Color = Color(0.24, 0.27, 0.35)
@export var dot_color: Color = Color(0.30, 0.34, 0.44)
@export var secondary_color: Color = Color(0.09, 0.10, 0.13)
@export var accent_color: Color = Color(0.5, 0.5, 0.55)
@export var hazard_color: Color = Color(0.9, 0.65, 0.18)
@export var pattern_type: StringName = &"streets"
@export_range(0.0, 1.0, 0.01) var pattern_strength: float = 0.45
@export var road_line_enabled: bool = true
@export var hazard_line_enabled: bool = false
## Cada cuántas celdas se dibuja una línea reforzada (calle principal).
@export var major_every: int = 4

const CHUNK_SIZE := Vector2(1024.0, 1024.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_2d()
	var view_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = global_position
	if camera != null:
		view_size = get_viewport_rect().size / camera.zoom
		center = camera.get_screen_center_position()

	var half: Vector2 = view_size * 0.5
	var top_left: Vector2 = center - half - Vector2(grid_size, grid_size)
	var bottom_right: Vector2 = center + half + Vector2(grid_size, grid_size)

	# Color base que cubre toda la zona visible.
	draw_rect(Rect2(top_left, bottom_right - top_left), base_color, true)
	_draw_biome_pattern(top_left, bottom_right)

	var start_x: float = floor(top_left.x / grid_size) * grid_size
	var start_y: float = floor(top_left.y / grid_size) * grid_size

	# Líneas verticales.
	var x: float = start_x
	while x <= bottom_right.x:
		var cell_x: int = int(round(x / grid_size))
		var is_major: bool = cell_x % major_every == 0
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y),
			major_line_color if is_major else line_color, 2.0 if is_major else 1.0)
		x += grid_size

	# Líneas horizontales.
	var y: float = start_y
	while y <= bottom_right.y:
		var cell_y: int = int(round(y / grid_size))
		var is_major: bool = cell_y % major_every == 0
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y),
			major_line_color if is_major else line_color, 2.0 if is_major else 1.0)
		y += grid_size

	# Puntos en los cruces principales: textura de "piso urbano" sutil.
	x = start_x
	while x <= bottom_right.x:
		if int(round(x / grid_size)) % major_every == 0:
			y = start_y
			while y <= bottom_right.y:
				if int(round(y / grid_size)) % major_every == 0:
					draw_circle(Vector2(x, y), 2.0, dot_color)
				y += grid_size
		x += grid_size


func _draw_biome_pattern(top_left: Vector2, bottom_right: Vector2) -> void:
	var alpha: float = clampf(pattern_strength, 0.0, 1.0)
	if alpha <= 0.01:
		return
	# Las calles, senderos, lagos y vias de tren reales viven en ChunkGroundRenderer
	# por chunk. El fondo global queda como textura ambiental tenue para no duplicar
	# geometria ni contradecir el CityPlan.
	var cell: float = grid_size * 3.0
	var start_x: float = floor(top_left.x / cell) * cell
	var start_y: float = floor(top_left.y / cell) * cell
	var x: float = start_x
	while x <= bottom_right.x:
		var y: float = start_y
		while y <= bottom_right.y:
			var h: float = _cell_noise(x, y, 3)
			if h < 0.34:
				var pos := Vector2(
					x + 22.0 + _cell_noise(x, y, 4) * (cell - 44.0),
					y + 22.0 + _cell_noise(x, y, 5) * (cell - 44.0)
				)
				var color := secondary_color.lerp(accent_color, 0.18 + h * 0.22)
				draw_circle(pos, 1.8 + h * 2.4, Color(color.r, color.g, color.b, 0.10 * alpha))
			y += cell
		x += cell


func _cell_noise(x: float, y: float, salt: int) -> float:
	return fposmod(sin((x + float(world_seed % 997)) * 12.9898 + (y - float(salt)) * 78.233) * 43758.5453, 1.0)


func _draw_chunk_layouts(top_left: Vector2, bottom_right: Vector2, biome: StringName, alpha: float) -> void:
	var min_cx: int = floori(top_left.x / CHUNK_SIZE.x) - 1
	var max_cx: int = floori(bottom_right.x / CHUNK_SIZE.x) + 1
	var min_cy: int = floori(top_left.y / CHUNK_SIZE.y) - 1
	var max_cy: int = floori(bottom_right.y / CHUNK_SIZE.y) + 1
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var origin := Vector2(cx, cy) * CHUNK_SIZE
			match biome:
				&"park":
					_draw_park_chunk_floor(origin, Vector2i(cx, cy), alpha)
				&"industrial":
					_draw_industrial_chunk_floor(origin, alpha)
				_:
					_draw_neighborhood_chunk_floor(origin, alpha)


func _draw_neighborhood_chunk_floor(origin: Vector2, alpha: float) -> void:
	var road := Color(0.075, 0.082, 0.105, 0.62 * alpha)
	var curb := Color(0.48, 0.50, 0.56, 0.24 * alpha)
	var walk := Color(0.13, 0.14, 0.17, 0.34 * alpha)
	var center := origin + CHUNK_SIZE * 0.5
	draw_rect(Rect2(Vector2(center.x - 120.0, origin.y), Vector2(240.0, CHUNK_SIZE.y)), road, true)
	draw_rect(Rect2(Vector2(origin.x, center.y - 120.0), Vector2(CHUNK_SIZE.x, 240.0)), road, true)
	draw_rect(Rect2(Vector2(center.x - 172.0, origin.y), Vector2(52.0, CHUNK_SIZE.y)), walk, true)
	draw_rect(Rect2(Vector2(center.x + 120.0, origin.y), Vector2(52.0, CHUNK_SIZE.y)), walk, true)
	draw_rect(Rect2(Vector2(origin.x, center.y - 172.0), Vector2(CHUNK_SIZE.x, 52.0)), walk, true)
	draw_rect(Rect2(Vector2(origin.x, center.y + 120.0), Vector2(CHUNK_SIZE.x, 52.0)), walk, true)
	for x in [center.x - 120.0, center.x + 120.0, center.x - 172.0, center.x + 172.0]:
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + CHUNK_SIZE.y), curb, 2.0)
	for y in [center.y - 120.0, center.y + 120.0, center.y - 172.0, center.y + 172.0]:
		draw_line(Vector2(origin.x, y), Vector2(origin.x + CHUNK_SIZE.x, y), curb, 2.0)
	for rect in [
		Rect2(origin + Vector2(95, 95), Vector2(255, 255)),
		Rect2(origin + Vector2(674, 95), Vector2(255, 255)),
		Rect2(origin + Vector2(95, 674), Vector2(255, 255)),
		Rect2(origin + Vector2(674, 674), Vector2(255, 255)),
	]:
		draw_rect(rect, Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.22 * alpha), true)
		draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.08 * alpha), false, 2.0)


func _draw_park_chunk_floor(origin: Vector2, coord: Vector2i, alpha: float) -> void:
	var path := Color(0.42, 0.34, 0.2, 0.38 * alpha)
	var path_y: float = origin.y + CHUNK_SIZE.y * 0.5 + sin(float(coord.x) * 0.9) * 120.0
	var next_y: float = origin.y + CHUNK_SIZE.y * 0.5 + sin(float(coord.x + 1) * 0.9) * 120.0
	_draw_poly_path([
		Vector2(origin.x, path_y),
		Vector2(origin.x + CHUNK_SIZE.x * 0.5, lerpf(path_y, next_y, 0.5)),
		Vector2(origin.x + CHUNK_SIZE.x, next_y),
	], path, 34.0)
	draw_circle(origin + CHUNK_SIZE * 0.5, 170.0, Color(0.16, 0.23, 0.14, 0.22 * alpha))
	if _chunk_hash(Vector2i(coord.x, coord.y), 7) < 0.28:
		var pond := origin + CHUNK_SIZE * 0.5 + Vector2(_chunk_hash(coord, 8) * 300.0 - 150.0, _chunk_hash(coord, 9) * 240.0 - 120.0)
		draw_circle(pond, 70.0, Color(0.13, 0.29, 0.34, 0.44 * alpha))
		draw_circle(pond + Vector2(48, 10), 45.0, Color(0.13, 0.29, 0.34, 0.38 * alpha))
	for p in [origin + Vector2(70, 70), origin + Vector2(954, 70), origin + Vector2(70, 954), origin + Vector2(954, 954)]:
		draw_line(p, p + Vector2(0, 95), Color(0.42, 0.35, 0.22, 0.18 * alpha), 3.0)


func _draw_industrial_chunk_floor(origin: Vector2, alpha: float) -> void:
	var concrete := Color(0.12, 0.12, 0.105, 0.38 * alpha)
	var lane := Color(hazard_color.r, hazard_color.g, hazard_color.b, 0.20 * alpha)
	var center := origin + CHUNK_SIZE * 0.5
	draw_rect(Rect2(Vector2(center.x - 150.0, origin.y), Vector2(300.0, CHUNK_SIZE.y)), concrete, true)
	draw_rect(Rect2(Vector2(origin.x, center.y - 115.0), Vector2(CHUNK_SIZE.x, 230.0)), concrete, true)
	draw_rect(Rect2(center - Vector2(280, 210), Vector2(560, 420)), Color(0.14, 0.14, 0.12, 0.38 * alpha), true)
	draw_rect(Rect2(center - Vector2(280, 210), Vector2(560, 420)), lane, false, 3.0)
	for x in [origin.x + 185.0, origin.x + 839.0]:
		draw_rect(Rect2(Vector2(x - 72.0, origin.y + 120.0), Vector2(144.0, 260.0)), Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.34 * alpha), true)
		draw_rect(Rect2(Vector2(x - 72.0, origin.y + 644.0), Vector2(144.0, 260.0)), Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.34 * alpha), true)
	for x in [center.x - 150.0, center.x + 150.0]:
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + CHUNK_SIZE.y), lane, 2.5)
	for y in [center.y - 115.0, center.y + 115.0]:
		draw_line(Vector2(origin.x, y), Vector2(origin.x + CHUNK_SIZE.x, y), lane, 2.5)


func _chunk_hash(coord: Vector2i, salt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("%d:%d_%d_%d" % [world_seed, coord.x, coord.y, salt]))
	return rng.randf()


func _draw_neighborhood_layout(top_left: Vector2, bottom_right: Vector2, alpha: float) -> void:
	var road := Color(0.075, 0.082, 0.105, 0.9 * alpha)
	var curb := Color(0.46, 0.48, 0.54, 0.34 * alpha)
	var walk := Color(0.13, 0.14, 0.17, 0.55 * alpha)
	draw_rect(Rect2(Vector2(-190.0, top_left.y), Vector2(380.0, bottom_right.y - top_left.y)), road, true)
	draw_rect(Rect2(Vector2(top_left.x, -170.0), Vector2(bottom_right.x - top_left.x, 340.0)), road, true)
	draw_rect(Rect2(Vector2(-250.0, top_left.y), Vector2(60.0, bottom_right.y - top_left.y)), walk, true)
	draw_rect(Rect2(Vector2(190.0, top_left.y), Vector2(60.0, bottom_right.y - top_left.y)), walk, true)
	draw_rect(Rect2(Vector2(top_left.x, -230.0), Vector2(bottom_right.x - top_left.x, 60.0)), walk, true)
	draw_rect(Rect2(Vector2(top_left.x, 170.0), Vector2(bottom_right.x - top_left.x, 60.0)), walk, true)
	for x in [-190.0, 190.0, -250.0, 250.0]:
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), curb, 2.0)
	for y in [-170.0, 170.0, -230.0, 230.0]:
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), curb, 2.0)
	for y in [-640.0, 640.0]:
		draw_rect(Rect2(Vector2(top_left.x, y - 80.0), Vector2(bottom_right.x - top_left.x, 160.0)), Color(0.08, 0.087, 0.11, 0.46 * alpha), true)
	for x in [-650.0, 650.0]:
		draw_rect(Rect2(Vector2(x - 80.0, top_left.y), Vector2(160.0, bottom_right.y - top_left.y)), Color(0.08, 0.087, 0.11, 0.42 * alpha), true)
	for i in 7:
		var stripe_x: float = -105.0 + float(i) * 35.0
		draw_line(Vector2(stripe_x, -235.0), Vector2(stripe_x, -175.0), Color(0.9, 0.88, 0.78, 0.24 * alpha), 5.0)
		draw_line(Vector2(stripe_x, 175.0), Vector2(stripe_x, 235.0), Color(0.9, 0.88, 0.78, 0.24 * alpha), 5.0)
	for rect in [
		Rect2(Vector2(-980, -900), Vector2(420, 430)),
		Rect2(Vector2(540, -880), Vector2(440, 410)),
		Rect2(Vector2(-940, 430), Vector2(390, 430)),
		Rect2(Vector2(560, 420), Vector2(430, 450)),
	]:
		draw_rect(rect, Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.32 * alpha), true)
		draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.12 * alpha), false, 2.0)


func _draw_park_layout(top_left: Vector2, bottom_right: Vector2, alpha: float) -> void:
	var path := Color(0.42, 0.34, 0.2, 0.52 * alpha)
	var edge := Color(0.24, 0.18, 0.11, 0.34 * alpha)
	_draw_poly_path(_ellipse_points(Vector2.ZERO, Vector2(650, 430), 56), path, 34.0)
	_draw_poly_path(_ellipse_points(Vector2.ZERO, Vector2(650, 430), 56), edge, 3.0)
	draw_circle(Vector2.ZERO, 250.0, Color(0.16, 0.23, 0.14, 0.48 * alpha))
	draw_arc(Vector2.ZERO, 250.0, 0.0, TAU, 48, Color(accent_color.r, accent_color.g, accent_color.b, 0.16 * alpha), 4.0)
	_draw_poly_path([
		Vector2(top_left.x, -90.0),
		Vector2(-560.0, -20.0),
		Vector2(-120.0, 90.0),
		Vector2(380.0, 35.0),
		Vector2(bottom_right.x, 120.0),
	], path, 26.0)
	draw_circle(Vector2(640, 20), 96.0, Color(0.13, 0.29, 0.34, 0.62 * alpha))
	draw_circle(Vector2(715, 35), 68.0, Color(0.13, 0.29, 0.34, 0.62 * alpha))
	draw_arc(Vector2(610, -8), 48.0, PI * 1.1, PI * 1.65, 16, Color(0.72, 0.9, 0.92, 0.22 * alpha), 4.0)
	var fence_color := Color(0.42, 0.35, 0.22, 0.24 * alpha)
	var e: float = 1450.0
	draw_rect(Rect2(Vector2(-e, -e), Vector2(e * 2.0, e * 2.0)), fence_color, false, 4.0)


func _draw_industrial_layout(top_left: Vector2, bottom_right: Vector2, alpha: float) -> void:
	var concrete := Color(0.12, 0.12, 0.105, 0.68 * alpha)
	var lane := Color(hazard_color.r, hazard_color.g, hazard_color.b, 0.24 * alpha)
	var yard := Rect2(Vector2(-420, -280), Vector2(840, 560))
	draw_rect(yard, concrete.lightened(0.08), true)
	draw_rect(yard, lane, false, 3.0)
	draw_rect(Rect2(Vector2(-160.0, top_left.y), Vector2(320.0, bottom_right.y - top_left.y)), Color(0.09, 0.095, 0.09, 0.42 * alpha), true)
	draw_rect(Rect2(Vector2(top_left.x, -120.0), Vector2(bottom_right.x - top_left.x, 240.0)), Color(0.09, 0.095, 0.09, 0.38 * alpha), true)
	for x in [-960.0, -720.0, 720.0, 960.0]:
		draw_rect(Rect2(Vector2(x - 72.0, -860.0), Vector2(144.0, 520.0)), Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.42 * alpha), true)
		draw_rect(Rect2(Vector2(x - 72.0, 340.0), Vector2(144.0, 520.0)), Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.42 * alpha), true)
	for x in [-420.0, 420.0]:
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), lane, 3.0)
	for y in [-360.0, 360.0]:
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), lane, 3.0)


func _ellipse_points(center: Vector2, radius: Vector2, segments: int) -> Array:
	var points: Array = []
	for i in segments + 1:
		var a: float = TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	return points


func _draw_poly_path(points: Array, color: Color, width: float) -> void:
	for i in max(0, points.size() - 1):
		draw_line(points[i], points[i + 1], color, width)


func _draw_street_marks(top_left: Vector2, bottom_right: Vector2, alpha: float) -> void:
	if road_line_enabled:
		var y: float = floor(top_left.y / (grid_size * 5.0)) * grid_size * 5.0
		while y <= bottom_right.y:
			draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y),
				Color(accent_color.r, accent_color.g, accent_color.b, 0.28 * alpha), 3.0)
			var dash_x: float = floor(top_left.x / 120.0) * 120.0
			while dash_x <= bottom_right.x:
				draw_line(Vector2(dash_x, y + grid_size * 0.55), Vector2(dash_x + 52.0, y + grid_size * 0.55),
					Color(0.88, 0.88, 0.78, 0.16 * alpha), 4.0)
				dash_x += 120.0
			# Cruces peatonales (cebra) periodicos: hacen que la calle se lea como calle.
			var cross_x: float = floor(top_left.x / 520.0) * 520.0
			while cross_x <= bottom_right.x:
				for k in 5:
					var sx: float = cross_x + float(k) * 9.0
					draw_line(Vector2(sx, y - 10.0), Vector2(sx, y + grid_size * 0.78),
						Color(0.9, 0.9, 0.82, 0.14 * alpha), 5.0)
				cross_x += 520.0
			# Bordes de acera a ambos lados de la calle: la banda se lee como via.
			draw_line(Vector2(top_left.x, y - 16.0), Vector2(bottom_right.x, y - 16.0),
				Color(0.55, 0.57, 0.62, 0.14 * alpha), 2.0)
			draw_line(Vector2(top_left.x, y + grid_size * 0.85), Vector2(bottom_right.x, y + grid_size * 0.85),
				Color(0.55, 0.57, 0.62, 0.14 * alpha), 2.0)
			y += grid_size * 5.0

	# Plazas/estacionamientos: manzanas grandes con borde, cada ~12 celdas. Dan
	# variacion de "ciudad" a gran escala en vez de textura uniforme.
	var plaza_step: float = grid_size * 12.0
	var zx: float = floor(top_left.x / plaza_step) * plaza_step
	while zx <= bottom_right.x:
		var zy: float = floor(top_left.y / plaza_step) * plaza_step
		while zy <= bottom_right.y:
			var zh: float = fposmod(sin(zx * 0.013 + zy * 0.027) * 43758.5453, 1.0)
			if zh < 0.55:
				var rect := Rect2(Vector2(zx + 70, zy + 90), Vector2(230, 150))
				draw_rect(rect, Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.35 * alpha), true)
				draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.14 * alpha), false, 2.0)
				# Rayas de estacionamiento.
				for p in 4:
					var px2: float = rect.position.x + 30.0 + float(p) * 46.0
					draw_line(Vector2(px2, rect.position.y + 16), Vector2(px2, rect.position.y + 62),
						Color(0.85, 0.85, 0.75, 0.12 * alpha), 3.0)
			zy += plaza_step
		zx += plaza_step

	var block: float = grid_size * 6.0
	var sx: float = floor(top_left.x / block) * block
	while sx <= bottom_right.x:
		var sy: float = floor(top_left.y / block) * block
		while sy <= bottom_right.y:
			var rect := Rect2(Vector2(sx + 18, sy + 18), Vector2(72, 28))
			draw_rect(rect, Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.28 * alpha), true)
			draw_rect(rect.grow(-8), Color(accent_color.r, accent_color.g, accent_color.b, 0.10 * alpha), true)
			sy += block
		sx += block


func _draw_park_paths(top_left: Vector2, bottom_right: Vector2, alpha: float) -> void:
	var path_color := Color(0.43, 0.35, 0.20, 0.30 * alpha)
	var y: float = floor(top_left.y / (grid_size * 4.0)) * grid_size * 4.0
	while y <= bottom_right.y:
		var a := Vector2(top_left.x, y + sin(y * 0.01) * 30.0)
		var b := Vector2(bottom_right.x, y + 60.0 + sin(y * 0.013) * 30.0)
		draw_line(a, b, path_color, 22.0)
		draw_line(a, b, Color(accent_color.r, accent_color.g, accent_color.b, 0.08 * alpha), 3.0)
		y += grid_size * 4.0

	var puddle_step: float = grid_size * 5.0
	var px: float = floor(top_left.x / puddle_step) * puddle_step
	while px <= bottom_right.x:
		var py: float = floor(top_left.y / puddle_step) * puddle_step
		while py <= bottom_right.y:
			draw_circle(Vector2(px + 42, py + 88), 18.0, Color(0.18, 0.29, 0.25, 0.18 * alpha))
			py += puddle_step
		px += puddle_step

	# Estanques: laguna de dos tonos con brillo, cada ~9 celdas. Anclan el bioma
	# de parque con puntos de interes grandes en vez de solo textura.
	var pond_step: float = grid_size * 9.0
	var qx: float = floor(top_left.x / pond_step) * pond_step
	while qx <= bottom_right.x:
		var qy: float = floor(top_left.y / pond_step) * pond_step
		while qy <= bottom_right.y:
			var ph: float = fposmod(sin(qx * 0.017 + qy * 0.031) * 43758.5453, 1.0)
			if ph < 0.4:
				var c := Vector2(qx + 120.0 + ph * 200.0, qy + 140.0)
				# Orilla, agua y reflejo.
				draw_circle(c, 46.0, Color(0.30, 0.26, 0.18, 0.5 * alpha))
				draw_circle(c + Vector2(24, 4), 34.0, Color(0.30, 0.26, 0.18, 0.5 * alpha))
				draw_circle(c, 40.0, Color(0.16, 0.30, 0.34, 0.55 * alpha))
				draw_circle(c + Vector2(22, 4), 28.0, Color(0.16, 0.30, 0.34, 0.55 * alpha))
				draw_arc(c + Vector2(-6, -8), 20.0, PI * 1.1, PI * 1.6, 10, Color(0.65, 0.85, 0.9, 0.22 * alpha), 3.0)
			qy += pond_step
		qx += pond_step

	# Matas de pasto y florecitas deterministas: el parque se siente vivo sin RNG.
	var tuft_step: float = grid_size * 3.0
	var tx: float = floor(top_left.x / tuft_step) * tuft_step
	while tx <= bottom_right.x:
		var ty: float = floor(top_left.y / tuft_step) * tuft_step
		while ty <= bottom_right.y:
			var h: float = fposmod(sin(tx * 12.9898 + ty * 78.233) * 43758.5453, 1.0)
			var base := Vector2(tx + h * tuft_step * 0.7 + 20.0, ty + fposmod(h * 7.31, 1.0) * tuft_step * 0.7 + 20.0)
			if h < 0.62:
				var grass := Color(0.36, 0.52, 0.30, 0.30 * alpha)
				draw_line(base, base + Vector2(-4, -9), grass, 2.0)
				draw_line(base, base + Vector2(0, -11), grass, 2.0)
				draw_line(base, base + Vector2(4, -8), grass, 2.0)
			elif h < 0.74:
				# Flor: punto claro con centro calido.
				draw_circle(base, 3.4, Color(0.92, 0.88, 0.96, 0.30 * alpha))
				draw_circle(base, 1.5, Color(0.95, 0.78, 0.35, 0.4 * alpha))
			ty += tuft_step
		tx += tuft_step


func _draw_industrial_floor(top_left: Vector2, bottom_right: Vector2, alpha: float) -> void:
	var plate: float = grid_size * 2.0
	var x: float = floor(top_left.x / plate) * plate
	while x <= bottom_right.x:
		var y: float = floor(top_left.y / plate) * plate
		while y <= bottom_right.y:
			var rect := Rect2(Vector2(x + 6, y + 6), Vector2(plate - 12, plate - 12))
			draw_rect(rect, Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.22 * alpha), true)
			draw_rect(rect, Color(major_line_color.r, major_line_color.g, major_line_color.b, 0.18 * alpha), false, 1.0)
			y += plate
		x += plate

	# Pasarelas de seguridad: carriles amarillos verticales cada ~8 columnas, como
	# los pasillos pintados de una nave industrial.
	var lane_step: float = grid_size * 8.0
	var lx: float = floor(top_left.x / lane_step) * lane_step
	while lx <= bottom_right.x:
		draw_line(Vector2(lx, top_left.y), Vector2(lx, bottom_right.y),
			Color(hazard_color.r, hazard_color.g, hazard_color.b, 0.14 * alpha), 3.0)
		draw_line(Vector2(lx + 46.0, top_left.y), Vector2(lx + 46.0, bottom_right.y),
			Color(hazard_color.r, hazard_color.g, hazard_color.b, 0.14 * alpha), 3.0)
		lx += lane_step

	if hazard_line_enabled:
		var hy: float = floor(top_left.y / (grid_size * 5.0)) * grid_size * 5.0
		while hy <= bottom_right.y:
			# Cinta de peligro: franjas diagonales alternadas (look industrial clasico).
			var hx: float = floor(top_left.x / 28.0) * 28.0
			while hx <= bottom_right.x:
				draw_line(Vector2(hx, hy + 7.0), Vector2(hx + 14.0, hy - 7.0),
					Color(hazard_color.r, hazard_color.g, hazard_color.b, 0.34 * alpha), 5.0)
				hx += 28.0
			draw_line(Vector2(top_left.x, hy + 8.5), Vector2(bottom_right.x, hy + 8.5),
				Color(0.08, 0.08, 0.09, 0.4 * alpha), 2.0)
			draw_line(Vector2(top_left.x, hy - 8.5), Vector2(bottom_right.x, hy - 8.5),
				Color(0.08, 0.08, 0.09, 0.4 * alpha), 2.0)
			hy += grid_size * 5.0
