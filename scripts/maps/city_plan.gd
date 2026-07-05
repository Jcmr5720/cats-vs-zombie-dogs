class_name CityPlan
extends RefCounted
## Plan urbano global determinista. Todas las decisiones estructurales del mundo
## (calles, manzanas, distritos, senderos, lagos, vias de tren) derivan de
## world_seed + coordenadas GLOBALES mediante funciones puras. Los chunks vecinos
## calculan exactamente lo mismo, asi que calles y senderos continuan sin costuras
## en las fronteras de chunk sin necesidad de comunicacion entre chunks.
##
## Reticula vial: lineas globales cada GRID px. La linea vertical i vive en
## x = i * GRID; la horizontal j en y = j * GRID. Cada indice multiplo de 4 es
## avenida garantizada (malla conexa); el resto se decide por hash.

const GRID: float = 512.0
const CHUNK := Vector2(1024.0, 1024.0)
## Cada cuantos indices hay avenida garantizada (i % 4 == 0 -> cada 2048 px).
const AVENUE_EVERY: int = 4
## Tamano de distrito en chunks (celdas de 4x4 chunks).
const DISTRICT_CHUNKS: int = 4
## Tamano de region de lago del parque en chunks.
const LAKE_REGION_CHUNKS: int = 3


# --- Hash puro -----------------------------------------------------------------

static func hash01(world_seed: int, tag: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("%d|%s" % [world_seed, tag]))
	return rng.randf()


# --- Red vial ------------------------------------------------------------------

## Decide si hay via en la linea global `index` del eje dado. {} si no hay.
## La decision depende SOLO de world_seed + eje + indice: continuidad garantizada.
static func road_at_line(world_seed: int, biome: StringName, axis: StringName, index: int) -> Dictionary:
	if biome == &"park":
		return {}
	if posmod(index, AVENUE_EVERY) == 0:
		if biome == &"industrial":
			return {"kind": &"cargo_corridor", "half_width": 118.0, "sidewalk": 24.0}
		return {"kind": &"avenue", "half_width": 104.0, "sidewalk": 34.0}
	var h: float = hash01(world_seed, "road:%s:%d" % [axis, index])
	if biome == &"industrial":
		if h < 0.40:
			return {"kind": &"service_corridor", "half_width": 70.0, "sidewalk": 0.0}
		return {}
	if h < 0.48:
		return {"kind": &"street", "half_width": 58.0, "sidewalk": 26.0}
	return {}


## Vias que tocan un chunk, en coordenadas locales del chunk. Incluye las lineas
## de frontera (local 0 y 1024): ambos vecinos las calculan igual y dibujan su mitad.
## Devuelve {v_roads, h_roads, intersections}. Cada via: {index, local_pos, kind,
## half_width, sidewalk, axis}. Cada interseccion: {pos, v, h, has_avenue}.
static func roads_for_chunk(world_seed: int, biome: StringName, coord: Vector2i) -> Dictionary:
	var v_roads: Array[Dictionary] = []
	var h_roads: Array[Dictionary] = []
	var lines_per_chunk: int = int(CHUNK.x / GRID)
	for k in lines_per_chunk + 1:
		var vi: int = coord.x * lines_per_chunk + k
		var v := road_at_line(world_seed, biome, &"v", vi)
		if not v.is_empty():
			v = v.duplicate()
			v["index"] = vi
			v["local_pos"] = float(k) * GRID
			v["axis"] = &"vertical"
			v_roads.append(v)
		var hi: int = coord.y * lines_per_chunk + k
		var h := road_at_line(world_seed, biome, &"h", hi)
		if not h.is_empty():
			h = h.duplicate()
			h["index"] = hi
			h["local_pos"] = float(k) * GRID
			h["axis"] = &"horizontal"
			h_roads.append(h)

	var intersections: Array[Dictionary] = []
	for v in v_roads:
		for h in h_roads:
			intersections.append({
				"pos": Vector2(v["local_pos"], h["local_pos"]),
				"v": v,
				"h": h,
				"has_avenue": v["kind"] in [&"avenue", &"cargo_corridor"] or h["kind"] in [&"avenue", &"cargo_corridor"],
			})
	return {"v_roads": v_roads, "h_roads": h_roads, "intersections": intersections}


## Manzanas (lotes) del chunk: rectangulos locales entre vias, con margen de acera.
## Cada lote sabe que bordes dan a calle: facing = Array[StringName] con &"n"/&"s"/&"e"/&"w".
static func lots_for_chunk(world_seed: int, biome: StringName, coord: Vector2i) -> Array[Dictionary]:
	var plan := roads_for_chunk(world_seed, biome, coord)
	var x_segments := _free_segments(plan["v_roads"], CHUNK.x)
	var y_segments := _free_segments(plan["h_roads"], CHUNK.y)
	var lots: Array[Dictionary] = []
	for xs in x_segments:
		for ys in y_segments:
			var rect := Rect2(Vector2(xs.x, ys.x), Vector2(xs.y - xs.x, ys.y - ys.x))
			if rect.size.x < 150.0 or rect.size.y < 150.0:
				continue
			var facing: Array[StringName] = []
			if _road_at_edge(plan["v_roads"], xs.x):
				facing.append(&"w")
			if _road_at_edge(plan["v_roads"], xs.y):
				facing.append(&"e")
			if _road_at_edge(plan["h_roads"], ys.x):
				facing.append(&"n")
			if _road_at_edge(plan["h_roads"], ys.y):
				facing.append(&"s")
			lots.append({"rect": rect, "facing": facing})
	return lots


## Tramos libres [inicio, fin] de un eje del chunk una vez descontadas las vias.
static func _free_segments(roads: Array, length: float) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	for r in roads:
		var half: float = float(r["half_width"]) + float(r["sidewalk"])
		cuts.append(Vector2(float(r["local_pos"]) - half, float(r["local_pos"]) + half))
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var segments: Array[Vector2] = []
	var cursor: float = 0.0
	for c in cuts:
		if c.x > cursor:
			segments.append(Vector2(cursor, minf(c.x, length)))
		cursor = maxf(cursor, c.y)
	if cursor < length:
		segments.append(Vector2(cursor, length))
	return segments


static func _road_at_edge(roads: Array, edge: float) -> bool:
	for r in roads:
		var half: float = float(r["half_width"]) + float(r["sidewalk"])
		if absf(float(r["local_pos"]) - half - edge) < 1.0 or absf(float(r["local_pos"]) + half - edge) < 1.0:
			return true
	return false


# --- Distritos -----------------------------------------------------------------

## Distrito de un chunk (celdas de 4x4 chunks). Modula el contenido de las manzanas
## sin tocar las calles, asi no rompe la continuidad de fronteras.
static func district(world_seed: int, biome: StringName, chunk_coord: Vector2i) -> Dictionary:
	var cell := Vector2i(floori(float(chunk_coord.x) / DISTRICT_CHUNKS), floori(float(chunk_coord.y) / DISTRICT_CHUNKS))
	var h: float = hash01(world_seed, "district:%s:%d:%d" % [biome, cell.x, cell.y])
	var kind: StringName = &"residential"
	if h < 0.22:
		kind = &"commercial"
	elif h < 0.34:
		kind = &"plaza"
	elif h < 0.46:
		kind = &"pocket_park"
	return {
		"kind": kind,
		"cell": cell,
		"density": 0.85 + hash01(world_seed, "district_density:%d:%d" % [cell.x, cell.y]) * 0.3,
	}


# --- Parque: senderos y lago ---------------------------------------------------

## Y global del sendero principal de la fila de chunks `row` en funcion del X global.
## Funcion continua de x: los chunks vecinos obtienen exactamente la misma curva.
static func park_trail_y(world_seed: int, row: int, world_x: float) -> float:
	var p1: float = hash01(world_seed, "trail_ph1:%d" % row) * TAU
	var p2: float = hash01(world_seed, "trail_ph2:%d" % row) * TAU
	var base_y: float = float(row) * CHUNK.y + CHUNK.y * 0.5
	return base_y + sin(world_x * 0.0011 + p1) * 225.0 + sin(world_x * 0.0037 + p2) * 70.0


## X global del sendero vertical de la columna `col` en funcion del Y global.
static func park_trail_x(world_seed: int, col: int, world_y: float) -> float:
	var p1: float = hash01(world_seed, "vtrail_ph1:%d" % col) * TAU
	var base_x: float = float(col) * CHUNK.x + CHUNK.x * 0.5
	return base_x + sin(world_y * 0.0014 + p1) * 180.0


static func park_has_row_trail(world_seed: int, row: int) -> bool:
	return posmod(row, 2) == 0 or hash01(world_seed, "trail_row:%d" % row) < 0.45


static func park_has_col_trail(world_seed: int, col: int) -> bool:
	return posmod(col, 2) == 0 or hash01(world_seed, "trail_col:%d" % col) < 0.35


## Senderos del parque que cruzan el chunk, como polilineas en coords locales.
## Cada sendero: {points: Array[Vector2], half_width, kind}.
static func park_trails_for_chunk(world_seed: int, coord: Vector2i) -> Array[Dictionary]:
	var trails: Array[Dictionary] = []
	var origin := Vector2(coord) * CHUNK
	const STEP: float = 128.0
	# Senderos horizontales: el de esta fila y los de filas vecinas (pueden invadir).
	for row in [coord.y - 1, coord.y, coord.y + 1]:
		if not park_has_row_trail(world_seed, row):
			continue
		var points: Array[Vector2] = []
		var touches: bool = false
		for k in int(CHUNK.x / STEP) + 1:
			var wx: float = origin.x + float(k) * STEP
			var wy: float = park_trail_y(world_seed, row, wx)
			var local := Vector2(wx, wy) - origin
			points.append(local)
			if local.y > -140.0 and local.y < CHUNK.y + 140.0:
				touches = true
		if touches:
			trails.append({"points": points, "half_width": 58.0, "kind": &"main_path"})
	# Senderos verticales (conectores mas estrechos).
	for col in [coord.x - 1, coord.x, coord.x + 1]:
		if not park_has_col_trail(world_seed, col):
			continue
		var points: Array[Vector2] = []
		var touches: bool = false
		for k in int(CHUNK.y / STEP) + 1:
			var wy: float = origin.y + float(k) * STEP
			var wx: float = park_trail_x(world_seed, col, wy)
			var local := Vector2(wx, wy) - origin
			points.append(local)
			if local.x > -140.0 and local.x < CHUNK.x + 140.0:
				touches = true
		if touches:
			trails.append({"points": points, "half_width": 44.0, "kind": &"side_path"})
	return trails


## Lago del parque por region de 3x3 chunks, decidido en coordenadas GLOBALES.
## Devuelve {center: Vector2 (local al chunk), radius} si el lago toca el chunk; {} si no.
static func park_lake_for_chunk(world_seed: int, coord: Vector2i) -> Dictionary:
	var region := Vector2i(floori(float(coord.x) / LAKE_REGION_CHUNKS), floori(float(coord.y) / LAKE_REGION_CHUNKS))
	if hash01(world_seed, "lake:%d:%d" % [region.x, region.y]) > 0.55:
		return {}
	var region_origin := Vector2(region) * CHUNK * float(LAKE_REGION_CHUNKS)
	var span: float = CHUNK.x * LAKE_REGION_CHUNKS
	var center_global := region_origin + Vector2(
		span * (0.28 + hash01(world_seed, "lake_x:%d:%d" % [region.x, region.y]) * 0.44),
		span * (0.28 + hash01(world_seed, "lake_y:%d:%d" % [region.x, region.y]) * 0.44)
	)
	var radius: float = 190.0 + hash01(world_seed, "lake_r:%d:%d" % [region.x, region.y]) * 110.0
	var local := center_global - Vector2(coord) * CHUNK
	# Solo interesa si el circulo toca este chunk (con margen de orilla).
	var chunk_rect := Rect2(Vector2.ZERO, CHUNK).grow(radius + 60.0)
	if not chunk_rect.has_point(local):
		return {}
	return {"center": local, "radius": radius}


# --- Industrial: via de tren ---------------------------------------------------

## Via de tren horizontal: una cada 3 filas de chunks, con Y constante en toda la
## fila (funcion de coord.y). Devuelve {local_y} si pasa por el chunk; {} si no.
static func rail_for_chunk(world_seed: int, coord: Vector2i) -> Dictionary:
	var offset: int = int(hash01(world_seed, "rail_offset") * 3.0)
	if posmod(coord.y - offset, 3) != 0:
		return {}
	var local_y: float = 190.0 + hash01(world_seed, "rail_y:%d" % coord.y) * 220.0
	return {"local_y": local_y}
