class_name MapGeometry
extends RefCounted
## Capa de CONSULTA de geometria para gameplay (FASE 11).
##
## `CityPlan` ya decide calles, manzanas, distritos, senderos y lagos de forma
## pura y determinista, pero hasta ahora solo lo leian el renderer de chunks y el
## minimapa: TODO el emplazamiento de gameplay era "posicion del jugador + angulo
## aleatorio". Por eso las marcas de aullido caian encima de las casas y la
## niebla del lago aparecia donde no habia lago.
##
## Este modulo no decide geometria nueva: traduce la de CityPlan a coordenadas
## GLOBALES y responde las preguntas que el juego necesita hacer:
##   - "por que rutas distintas puede llegarme una manada"   -> approach_points()
##   - "donde puedo plantar esto sin que quede dentro de un edificio" -> find_open_position()
##   - "que sector cubre el lago que tengo cerca"            -> lake_near()
##
## Todo es estatico y puro (misma semilla = misma respuesta) salvo `is_clear()`,
## que consulta el espacio fisico para descartar obstaculos ya instanciados.

## Capa 5: obstaculos solidos (ver obstacle.gd).
const OBSTACLE_LAYER: int = 1 << 4
## Cuantas lineas de reticula se exploran alrededor del punto consultado.
const SEARCH_LINES: int = 4


# --- Red vial (global) ---------------------------------------------------------

## Vias que cruzan la vecindad de `pos`, en coordenadas GLOBALES. Cada entrada:
## {axis: &"vertical"/&"horizontal", coord: float (x de la vertical / y de la
## horizontal), kind, half_width, sidewalk, width: half_width + sidewalk}.
## Los biomas sin calles (parque) devuelven [].
static func roads_near(world_seed: int, biome: StringName, pos: Vector2, span: float = 1200.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if biome == &"park":
		return out
	var first_v: int = floori((pos.x - span) / CityPlan.GRID)
	var last_v: int = ceili((pos.x + span) / CityPlan.GRID)
	for index in range(first_v, last_v + 1):
		var road := CityPlan.road_at_line(world_seed, biome, &"v", index)
		if road.is_empty():
			continue
		out.append(_road_entry(road, &"vertical", float(index) * CityPlan.GRID))
	var first_h: int = floori((pos.y - span) / CityPlan.GRID)
	var last_h: int = ceili((pos.y + span) / CityPlan.GRID)
	for index in range(first_h, last_h + 1):
		var road := CityPlan.road_at_line(world_seed, biome, &"h", index)
		if road.is_empty():
			continue
		out.append(_road_entry(road, &"horizontal", float(index) * CityPlan.GRID))
	return out


static func _road_entry(road: Dictionary, axis: StringName, coord: float) -> Dictionary:
	var half: float = float(road["half_width"])
	var sidewalk: float = float(road["sidewalk"])
	return {
		"axis": axis,
		"coord": coord,
		"kind": road["kind"],
		"half_width": half,
		"sidewalk": sidewalk,
		"width": half + sidewalk,
	}


## Via cuyo corredor (calzada + acera) contiene `pos`, o {} si esta en manzana.
static func road_corridor_at(world_seed: int, biome: StringName, pos: Vector2) -> Dictionary:
	for road in roads_near(world_seed, biome, pos, CityPlan.GRID * 2.0):
		var along: float = pos.x if road["axis"] == &"vertical" else pos.y
		if absf(along - float(road["coord"])) <= float(road["width"]):
			return road
	return {}


## Intersecciones (cruces de dos vias) en coordenadas GLOBALES cerca de `pos`.
## Son los puntos tacticos del Barrio: mandan sobre varias rutas a la vez.
static func intersections_near(world_seed: int, biome: StringName, pos: Vector2, span: float = 1200.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var roads := roads_near(world_seed, biome, pos, span)
	for v in roads:
		if v["axis"] != &"vertical":
			continue
		for h in roads:
			if h["axis"] != &"horizontal":
				continue
			out.append(Vector2(float(v["coord"]), float(h["coord"])))
	return out


# --- Rutas de aproximacion -----------------------------------------------------

## Puntos a ~`radius` de `center` desde los que se puede llegar POR CALLE, lo mas
## repartidos angularmente posible. Es la consulta que convierte "la manada entra
## por un arco aleatorio" en "la manada baja por calles distintas".
##
## Devuelve como mucho `count` puntos globales. Si el bioma no tiene calles
## (parque) usa los senderos; si tampoco hay, devuelve [] y el llamador conserva
## su comportamiento anterior.
static func approach_points(world_seed: int, biome: StringName, center: Vector2,
		radius: float, count: int) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	if biome == &"park":
		candidates = _trail_ring_points(world_seed, center, radius)
	else:
		candidates = _road_ring_points(world_seed, biome, center, radius)
	return _spread_by_angle(candidates, center, count)


## Cortes de las calles con el circulo de radio `radius` alrededor de `center`.
static func _road_ring_points(world_seed: int, biome: StringName, center: Vector2, radius: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for road in roads_near(world_seed, biome, center, radius + CityPlan.GRID):
		var coord: float = float(road["coord"])
		if road["axis"] == &"vertical":
			var dx: float = coord - center.x
			if absf(dx) > radius:
				continue
			var dy: float = sqrt(maxf(0.0, radius * radius - dx * dx))
			out.append(Vector2(coord, center.y - dy))
			out.append(Vector2(coord, center.y + dy))
		else:
			var dy2: float = coord - center.y
			if absf(dy2) > radius:
				continue
			var dx2: float = sqrt(maxf(0.0, radius * radius - dy2 * dy2))
			out.append(Vector2(center.x - dx2, coord))
			out.append(Vector2(center.x + dx2, coord))
	return out


## Cortes de los senderos del parque con el circulo (el equivalente organico).
static func _trail_ring_points(world_seed: int, center: Vector2, radius: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var row: int = floori(center.y / CityPlan.CHUNK.y)
	var col: int = floori(center.x / CityPlan.CHUNK.x)
	for r in [row - 1, row, row + 1]:
		if not CityPlan.park_has_row_trail(world_seed, r):
			continue
		for side in [-1.0, 1.0]:
			var wx: float = center.x + side * radius
			var wy: float = CityPlan.park_trail_y(world_seed, r, wx)
			if absf(wy - center.y) <= radius * 1.25:
				out.append(Vector2(wx, wy))
	for c in [col - 1, col, col + 1]:
		if not CityPlan.park_has_col_trail(world_seed, c):
			continue
		for side in [-1.0, 1.0]:
			var wy2: float = center.y + side * radius
			var wx2: float = CityPlan.park_trail_x(world_seed, c, wy2)
			if absf(wx2 - center.x) <= radius * 1.25:
				out.append(Vector2(wx2, wy2))
	return out


## Selecciona hasta `count` puntos maximizando la separacion angular (rutas
## DISTINTAS, no cuatro puntos de la misma calle).
static func _spread_by_angle(candidates: Array[Vector2], center: Vector2, count: int) -> Array[Vector2]:
	var picked: Array[Vector2] = []
	if candidates.is_empty() or count <= 0:
		return picked
	# Determinista: ordenar por angulo antes de repartir.
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return (a - center).angle() < (b - center).angle())
	picked.append(sorted[0])
	while picked.size() < count:
		var best: Vector2 = Vector2.ZERO
		var best_gap: float = -1.0
		for candidate in sorted:
			var gap: float = TAU
			for chosen in picked:
				var delta: float = absf(angle_difference((candidate - center).angle(), (chosen - center).angle()))
				gap = minf(gap, delta)
			if gap > best_gap:
				best_gap = gap
				best = candidate
		# Rutas demasiado juntas no cuentan como rutas distintas.
		if best_gap < 0.6:
			break
		picked.append(best)
	return picked


# --- Terreno abierto y emplazamiento -------------------------------------------

## Manzana (lote) que contiene `pos`, o {} si el punto esta en calle/hueco.
## Los lotes son el interior de las manzanas: ahi es donde estan los edificios.
## Cache de manzanas por chunk. `CityPlan.lots_for_chunk` recalcula las vias del
## chunk y reserva arrays cada llamada; el emplazamiento la invoca decenas de
## veces por rafaga (14 candidatos por interactable, 12 por spawn urbano) y eso
## producia picos de frame visibles en los soaks. La planta urbana es PURA y no
## cambia durante la partida, asi que cachearla es seguro.
static var _lots_cache: Dictionary = {}
## Tope del cache: el jugador solo recorre unos pocos chunks por partida.
const LOTS_CACHE_MAX: int = 64


## Vacia el cache de manzanas (cambio de mapa o de semilla).
static func clear_cache() -> void:
	_lots_cache.clear()


static func lot_at(world_seed: int, biome: StringName, pos: Vector2) -> Dictionary:
	if biome == &"park":
		return {}
	var coord := Vector2i(floori(pos.x / CityPlan.CHUNK.x), floori(pos.y / CityPlan.CHUNK.y))
	var local: Vector2 = pos - Vector2(coord) * CityPlan.CHUNK
	var key: String = "%d:%s:%d:%d" % [world_seed, biome, coord.x, coord.y]
	var lots: Array = _lots_cache.get(key, [])
	if lots.is_empty():
		lots = CityPlan.lots_for_chunk(world_seed, biome, coord)
		if _lots_cache.size() >= LOTS_CACHE_MAX:
			_lots_cache.clear()
		_lots_cache[key] = lots
	for lot in lots:
		if (lot["rect"] as Rect2).has_point(local):
			return lot
	return {}


## Suelo transitable segun el PLAN del mapa: fuera del interior de las manzanas y
## fuera del lago. No mira obstaculos instanciados (para eso, `is_clear`).
static func is_open_ground(world_seed: int, biome: StringName, pos: Vector2) -> bool:
	if biome == &"park":
		var lake := lake_near(world_seed, pos)
		if not lake.is_empty():
			var center: Vector2 = lake["center"]
			if pos.distance_to(center) <= float(lake["radius"]) * 0.95:
				return false
		return true
	return lot_at(world_seed, biome, pos).is_empty()


## Libre de obstaculos REALES ya instanciados (consulta al espacio fisico).
## `world` es cualquier nodo dentro del arbol (se usa su world_2d).
static func is_clear(world: Node2D, pos: Vector2, radius: float = 40.0) -> bool:
	if world == null or not world.is_inside_tree():
		return true
	var space := world.get_world_2d().direct_space_state
	if space == null:
		return true
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, pos)
	params.collision_mask = OBSTACLE_LAYER
	params.collide_with_areas = false
	return space.intersect_shape(params, 1).is_empty()


## Busca un punto valido en el anillo [min_r, max_r] alrededor de `origin`.
## Determinista si el `rng` lo es. Prueba candidatos repartidos y devuelve el
## primero que este en suelo abierto y libre de obstaculos.
##
## Devuelve {found: bool, pos: Vector2}: `found = false` significa que ningun
## candidato paso los filtros y `pos` es el mejor esfuerzo (el llamador decide si
## lo usa o se salta el spawn). Nunca devuelve un punto dentro de un edificio si
## habia alternativa.
static func find_open_position(world_seed: int, biome: StringName, origin: Vector2,
		min_r: float, max_r: float, rng: RandomNumberGenerator,
		world: Node2D = null, attempts: int = 14) -> Dictionary:
	var fallback: Vector2 = origin + Vector2.RIGHT.rotated(rng.randf() * TAU) * maxf(min_r, 1.0)
	for i in attempts:
		var angle: float = rng.randf() * TAU
		var distance: float = rng.randf_range(min_r, max_r)
		var candidate: Vector2 = origin + Vector2.RIGHT.rotated(angle) * distance
		if not is_open_ground(world_seed, biome, candidate):
			continue
		if not is_clear(world, candidate):
			continue
		return {"found": true, "pos": candidate}
	return {"found": false, "pos": fallback}


## Como `find_open_position`, pero prefiere puntos TACTICOS: intersecciones en el
## Barrio/Industrial y cruces de sendero en el Parque. Es lo que convierte una
## marca de aullido de "adorno aleatorio" en "domina este cruce".
static func find_tactical_position(world_seed: int, biome: StringName, origin: Vector2,
		min_r: float, max_r: float, rng: RandomNumberGenerator,
		world: Node2D = null) -> Dictionary:
	var tactical: Array[Vector2] = []
	if biome == &"park":
		tactical = _trail_ring_points(world_seed, origin, (min_r + max_r) * 0.5)
	else:
		for point in intersections_near(world_seed, biome, origin, max_r + CityPlan.GRID):
			var distance: float = origin.distance_to(point)
			if distance >= min_r and distance <= max_r:
				tactical.append(point)
	# Orden determinista y barajado por semilla: no siempre la misma esquina.
	tactical.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return (a - origin).angle() < (b - origin).angle())
	if not tactical.is_empty():
		var start: int = rng.randi() % tactical.size()
		for i in tactical.size():
			var point: Vector2 = tactical[(start + i) % tactical.size()]
			if is_clear(world, point):
				return {"found": true, "pos": point, "tactical": true}
	var open := find_open_position(world_seed, biome, origin, min_r, max_r, rng, world)
	open["tactical"] = false
	return open


# --- Parque: lago y senderos ---------------------------------------------------

## Lago cuya region toca `pos`, en coordenadas GLOBALES: {center, radius}.
## {} si no hay lago cerca. Es la geometria a la que debe anclarse el evento del
## lago en vez de sembrar niebla alrededor del jugador.
static func lake_near(world_seed: int, pos: Vector2, span_chunks: int = 1) -> Dictionary:
	var base := Vector2i(floori(pos.x / CityPlan.CHUNK.x), floori(pos.y / CityPlan.CHUNK.y))
	var best: Dictionary = {}
	var best_distance: float = INF
	for dx in range(-span_chunks, span_chunks + 1):
		for dy in range(-span_chunks, span_chunks + 1):
			var coord := base + Vector2i(dx, dy)
			var lake := CityPlan.park_lake_for_chunk(world_seed, coord)
			if lake.is_empty():
				continue
			var center: Vector2 = (lake["center"] as Vector2) + Vector2(coord) * CityPlan.CHUNK
			var distance: float = pos.distance_to(center)
			if distance < best_distance:
				best_distance = distance
				best = {"center": center, "radius": float(lake["radius"])}
	return best


## Punto del sendero mas cercano a `pos` (con su direccion de avance), o {} si el
## bioma no tiene senderos. Los claros del Parque se definen respecto a esto.
static func nearest_trail_point(world_seed: int, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	var row: int = floori(pos.y / CityPlan.CHUNK.y)
	for r in [row - 1, row, row + 1]:
		if not CityPlan.park_has_row_trail(world_seed, r):
			continue
		var y: float = CityPlan.park_trail_y(world_seed, r, pos.x)
		var distance: float = absf(y - pos.y)
		if distance < best_distance:
			best_distance = distance
			var ahead: float = CityPlan.park_trail_y(world_seed, r, pos.x + 64.0)
			best = {"pos": Vector2(pos.x, y), "dir": Vector2(64.0, ahead - y).normalized()}
	var col: int = floori(pos.x / CityPlan.CHUNK.x)
	for c in [col - 1, col, col + 1]:
		if not CityPlan.park_has_col_trail(world_seed, c):
			continue
		var x: float = CityPlan.park_trail_x(world_seed, c, pos.y)
		var distance2: float = absf(x - pos.x)
		if distance2 < best_distance:
			best_distance = distance2
			var ahead2: float = CityPlan.park_trail_x(world_seed, c, pos.y + 64.0)
			best = {"pos": Vector2(x, pos.y), "dir": Vector2(ahead2 - x, 64.0).normalized()}
	return best


# --- Industrial: via de tren ---------------------------------------------------

## Y GLOBAL de la via de tren que cruza la fila de chunks de `pos`, o NAN si esa
## fila no tiene via. El tren debe correr por la via, no por donde este el jugador.
static func rail_y_near(world_seed: int, pos: Vector2) -> float:
	var row: int = floori(pos.y / CityPlan.CHUNK.y)
	for r in [row, row - 1, row + 1]:
		var rail := CityPlan.rail_for_chunk(world_seed, Vector2i(0, r))
		if rail.is_empty():
			continue
		return float(r) * CityPlan.CHUNK.y + float(rail["local_y"])
	return NAN
