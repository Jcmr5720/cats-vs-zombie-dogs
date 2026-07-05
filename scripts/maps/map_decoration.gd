extends Node2D
## Marcas de suelo por bioma dibujadas por codigo (sin assets externos). Recorre las
## celdas visibles alrededor de la camara y dibuja SOLO detalle plano de bajo alfa
## (hojas, papeles, manchas, marcas) determinista por celda: nunca dibuja pseudo-
## edificios ni props que puedan chocar visualmente con los obstaculos reales del
## MapChunkManager. El estilo lo fija MapData.biome. No bloquea el movimiento.

const CELL: float = 240.0

## Semilla del mundo de la run (la fija el MapManager). Se mezcla en el hash por
## celda para que cada partida tenga una decoracion distinta pero estable.
var world_seed: int = 0

var _biome: StringName = &"neighborhood"
var _grid_color: Color = Color(0.2, 0.22, 0.28, 1.0)
var _accent_color: Color = Color(0.6, 0.6, 0.65, 1.0)
var _hazard_color: Color = Color(0.9, 0.65, 0.18, 1.0)
var _density: float = 0.36
var _scale_min: float = 0.7
var _scale_max: float = 1.35
var _ambient_detail_count: int = 2


func _process(_delta: float) -> void:
	queue_redraw()


## La llama el MapManager al cargar/cambiar de mapa.
func configure(map_data) -> void:
	_biome = map_data.biome
	_grid_color = map_data.grid_color
	_accent_color = map_data.decoration_accent_color if map_data.decoration_accent_color != Color(0.5, 0.5, 0.55, 1.0) else map_data.accent_color
	_hazard_color = map_data.hazard_color
	_density = clampf(map_data.decoration_density, 0.0, 1.0)
	_scale_min = max(0.1, map_data.decoration_scale_min)
	_scale_max = max(_scale_min, map_data.decoration_scale_max)
	_ambient_detail_count = max(0, map_data.ambient_detail_count)
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_2d()
	var view_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = global_position
	if camera != null:
		view_size = get_viewport_rect().size / camera.zoom
		center = camera.get_screen_center_position()

	var half: Vector2 = view_size * 0.5
	var min_cx: int = int(floor((center.x - half.x) / CELL)) - 1
	var max_cx: int = int(floor((center.x + half.x) / CELL)) + 1
	var min_cy: int = int(floor((center.y - half.y) / CELL)) - 1
	var max_cy: int = int(floor((center.y + half.y) / CELL)) + 1

	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			_draw_cell(cx, cy)


func _draw_cell(cx: int, cy: int) -> void:
	# Presencia y parametros deterministas por celda.
	if _cell_rand(cx, cy, 1) > _density:
		return
	var origin: Vector2 = Vector2(cx, cy) * CELL
	# Solo detalle plano de suelo: los props/edificios reales los pone el chunk manager.
	for i in maxi(2, _ambient_detail_count + 1):
		_draw_floor_detail(cx, cy, i, origin)


## Marcas planas de bajo alfa: nunca compiten con obstaculos ni con el suelo del chunk.
func _draw_floor_detail(cx: int, cy: int, index: int, origin: Vector2) -> void:
	var salt: int = 20 + index * 4
	var pos := origin + Vector2(_cell_rand(cx, cy, salt), _cell_rand(cx, cy, salt + 1)) * CELL
	var variant: float = _cell_rand(cx, cy, salt + 2)
	match _biome:
		&"park":
			if variant < 0.45:
				# Hojas caidas: 3 puntitos calidos.
				for k in 3:
					var leaf := pos + Vector2(_cell_rand(cx, cy, salt + 3 + k) * 26.0 - 13.0, _cell_rand(cx, cy, salt + 6 + k) * 26.0 - 13.0)
					draw_circle(leaf, 3.0, Color(0.42, 0.30, 0.14, 0.30))
			elif variant < 0.8:
				# Mancha de pasto pisado.
				draw_circle(pos, lerpf(6.0, 14.0, _cell_rand(cx, cy, salt + 3)), Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.10))
			else:
				# Huellas de pata: dos pares.
				for k in 4:
					var paw := pos + Vector2(float(k) * 9.0, sin(float(k) * 2.2) * 5.0)
					draw_circle(paw, 2.2, Color(0.1, 0.1, 0.1, 0.25))
		&"industrial":
			if variant < 0.5:
				# Rayadura de neumatico.
				var dir := Vector2(28.0, 0.0).rotated(_cell_rand(cx, cy, salt + 3) * TAU)
				draw_line(pos, pos + dir, Color(0.04, 0.04, 0.05, 0.35), 3.0)
				draw_line(pos + Vector2(0, 5), pos + dir + Vector2(0, 5), Color(0.04, 0.04, 0.05, 0.25), 3.0)
			else:
				# Salpicadura de oxido/quimicos.
				draw_circle(pos, lerpf(5.0, 12.0, _cell_rand(cx, cy, salt + 3)), Color(_hazard_color.r, _hazard_color.g, _hazard_color.b, 0.10))
		_:
			if variant < 0.4:
				# Papel/basura en el suelo.
				var paper := Rect2(pos, Vector2(9.0, 6.0))
				draw_rect(paper, Color(0.7, 0.7, 0.65, 0.20), true)
			elif variant < 0.75:
				# Grieta corta en la banqueta.
				var b := pos + Vector2(16, 0).rotated(_cell_rand(cx, cy, salt + 3) * TAU)
				draw_line(pos, b, Color(0.05, 0.05, 0.06, 0.30), 2.0)
			else:
				# Mancha oscura difusa.
				draw_circle(pos, lerpf(6.0, 13.0, _cell_rand(cx, cy, salt + 3)), Color(0.03, 0.035, 0.045, 0.22))


# --- Hash determinista por celda --------------------------------------------

func _cell_rand(cx: int, cy: int, salt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d_%d_%d" % [world_seed, cx, cy, salt])
	return rng.randf()
