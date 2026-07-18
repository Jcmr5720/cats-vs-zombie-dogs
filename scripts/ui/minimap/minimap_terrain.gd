extends Control
## Capa de terreno del minimapa: dibuja el trazado del mundo (calles claras =
## transitable, lago = bloqueado, via de tren, y en modo ampliado manzanas y
## zonas) en UN solo canvas item, a partir de los layouts cacheados de
## MinimapTerrainSource.
##
## Modelo de scroll suave sin redibujar: el contenido se dibuja en coordenadas
## de MUNDO * escala; el controller mueve `position` cada frame (barato) y solo
## se redibuja cuando cambia el conjunto de chunks visibles, la escala/detalle o
## aparecen layouts nuevos.

const MinimapConfig = preload("res://scripts/ui/minimap/minimap_config.gd")
const CHUNK_SIZE := Vector2(1024.0, 1024.0)

## Fuente compartida (la inyecta MinimapSystem via el controller).
var source: RefCounted

var _map_scale: float = 0.1
var _detailed: bool = false
var _region: Rect2
var _chunk_from := Vector2i(99999, 99999)
var _chunk_to := Vector2i(99999, 99999)
## Rects de via en coordenadas de MUNDO del ultimo redibujado (para tests de
## alineacion contra CityPlan).
var _world_road_rects: Array[Rect2] = []
## Conteo de elementos del ultimo redibujado (para tests: parque usa senderos,
## industrial tren, etc.).
var _draw_stats: Dictionary = {"roads": 0, "paths": 0, "lakes": 0, "rails": 0, "zones": 0}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Tick del controller (throttled): asegura layouts y redibuja solo si hace falta.
func update_region(focus_world: Vector2, world_radius: float, map_scale: float, detailed: bool) -> void:
	if source == null or not source.call("resolve", get_tree()):
		return
	var half := Vector2.ONE * (world_radius * 1.15)
	_region = Rect2(focus_world - half, half * 2.0)
	var generated: bool = bool(source.call("ensure_region", _region, MinimapConfig.TERRAIN_CHUNK_BUDGET))
	var from := Vector2i(floori(_region.position.x / CHUNK_SIZE.x), floori(_region.position.y / CHUNK_SIZE.y))
	var to := Vector2i(floori(_region.end.x / CHUNK_SIZE.x), floori(_region.end.y / CHUNK_SIZE.y))
	var dirty: bool = generated or from != _chunk_from or to != _chunk_to \
		or not is_equal_approx(map_scale, _map_scale) or detailed != _detailed
	_chunk_from = from
	_chunk_to = to
	_map_scale = map_scale
	_detailed = detailed
	if dirty:
		queue_redraw()


func get_world_road_rects() -> Array[Rect2]:
	return _world_road_rects


func get_draw_stats() -> Dictionary:
	return _draw_stats


func _draw() -> void:
	if source == null or not bool(source.call("is_resolved")):
		return
	_world_road_rects.clear()
	_draw_stats = {"roads": 0, "paths": 0, "lakes": 0, "rails": 0, "zones": 0}
	# Claves ya dibujadas en ESTE redibujado: las vias de frontera y los senderos/
	# lagos que tocan varios chunks vienen duplicados en layouts vecinos con la
	# misma geometria global; sin dedupe, el alfa se doblaria en esos tramos.
	var drawn: Dictionary = {}
	for y in range(_chunk_from.y, _chunk_to.y + 1):
		for x in range(_chunk_from.x, _chunk_to.x + 1):
			var coord := Vector2i(x, y)
			var layout: Dictionary = source.call("layout_for", coord)
			if layout.is_empty():
				continue
			_draw_chunk(coord, layout, drawn)


func _draw_chunk(coord: Vector2i, layout: Dictionary, drawn: Dictionary) -> void:
	var origin := Vector2(coord) * CHUNK_SIZE

	# --- Zonas y estructuras de manzana (solo en modo ampliado: mas detalle) ---
	if _detailed:
		for anchor in layout.get("anchors", []):
			var kind: StringName = anchor.get("kind", &"")
			var rect: Rect2 = anchor.get("rect", Rect2())
			match kind:
				&"plaza", &"pocket_park", &"clearing", &"picnic_zone":
					_rect(origin, rect, MinimapConfig.ZONE_COLOR)
					_draw_stats["zones"] = int(_draw_stats["zones"]) + 1
				&"parking_lot", &"loading_yard":
					_rect(origin, rect, MinimapConfig.YARD_COLOR)
				&"warehouse":
					# Nave: bloque cerrado relevante (silueta de perimetro).
					_rect_outline(origin, rect, MinimapConfig.STRUCT_COLOR)
				&"container_lane":
					_rect(origin, rect, Color(MinimapConfig.STRUCT_COLOR.r, MinimapConfig.STRUCT_COLOR.g, MinimapConfig.STRUCT_COLOR.b, 0.16))

	# --- Vias (rectas: calles/avenidas/corredores/tren) ---
	for road in layout.get("roads", []):
		var kind: StringName = road.get("kind", &"")
		if road.has("rect"):
			var rect: Rect2 = road["rect"]
			var center := origin + rect.get_center()
			var key := "%s:%d:%d" % [road.get("axis", &""), int(round(center.x)), int(round(center.y))]
			if drawn.has(key):
				continue
			drawn[key] = true
			var color: Color = MinimapConfig.ROAD_STREET_COLOR
			match kind:
				&"avenue", &"cargo_corridor":
					color = MinimapConfig.ROAD_AVENUE_COLOR
				&"rail":
					color = MinimapConfig.RAIL_COLOR
			_rect(origin, rect, color)
			if kind == &"rail":
				_draw_stats["rails"] = int(_draw_stats["rails"]) + 1
			else:
				_draw_stats["roads"] = int(_draw_stats["roads"]) + 1
				_world_road_rects.append(Rect2(origin + rect.position, rect.size))
		elif road.has("points"):
			# Senderos del parque (polilineas transitables).
			var points: Array = road["points"]
			if points.size() < 2:
				continue
			var key_p := "path:%d:%d" % [int(round(origin.x + (points[0] as Vector2).x)), int(round(origin.y + (points[0] as Vector2).y))]
			if drawn.has(key_p):
				continue
			drawn[key_p] = true
			var width: float = maxf(1.5, float(road.get("half_width", 40.0)) * 2.0 * _map_scale)
			var scaled := PackedVector2Array()
			for p in points:
				scaled.append((origin + (p as Vector2)) * _map_scale)
			draw_polyline(scaled, MinimapConfig.PATH_COLOR, width)
			_draw_stats["paths"] = int(_draw_stats["paths"]) + 1

	# --- Lago (area NO transitable relevante) ---
	var lake: Dictionary = layout.get("lake", {})
	if not lake.is_empty():
		var center_w: Vector2 = origin + (lake.get("center", Vector2.ZERO) as Vector2)
		var key_l := "lake:%d:%d" % [int(round(center_w.x)), int(round(center_w.y))]
		if not drawn.has(key_l):
			drawn[key_l] = true
			draw_circle(center_w * _map_scale, float(lake.get("radius", 100.0)) * _map_scale, MinimapConfig.WATER_COLOR)
			_draw_stats["lakes"] = int(_draw_stats["lakes"]) + 1


func _rect(origin: Vector2, rect: Rect2, color: Color) -> void:
	draw_rect(Rect2((origin + rect.position) * _map_scale, rect.size * _map_scale), color)


func _rect_outline(origin: Vector2, rect: Rect2, color: Color) -> void:
	var r := Rect2((origin + rect.position) * _map_scale, rect.size * _map_scale)
	draw_rect(r, Color(color.r, color.g, color.b, color.a * 0.35))
	draw_rect(r, color, false, 1.5)
