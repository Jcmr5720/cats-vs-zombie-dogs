class_name BiomeLayoutGenerator
extends RefCounted
## Genera capas logicas por chunk: vias, zonas/anchors y areas reservadas. No
## instancia nodos; solo describe donde tiene sentido colocar cosas. La estructura
## (calles, senderos, lagos, vias de tren) viene de CityPlan, que decide con
## funciones puras sobre coordenadas GLOBALES: los chunks vecinos comparten las
## mismas lineas y todo continua sin costuras en las fronteras.

# WorldSeedManager y CityPlan son clases globales (class_name): sin preload.
const CHUNK_SIZE := Vector2(1024.0, 1024.0)


static func generate(map_data: MapData, coord: Vector2i, world_seed: int) -> Dictionary:
	var biome: StringName = map_data.biome if map_data != null else &"neighborhood"
	match biome:
		&"park":
			return _park(coord, world_seed, biome)
		&"industrial":
			return _industrial(coord, world_seed, biome)
		_:
			return _neighborhood(coord, world_seed, biome)


static func _base(coord: Vector2i, biome: StringName) -> Dictionary:
	return {
		"coord": coord,
		"biome": biome,
		"roads": [],
		"reserved_rects": [],
		"reserved_circles": [],
		"anchors": [],
		"debug_lines": [],
	}


# --- Barrio (ciudad) -----------------------------------------------------------

static func _neighborhood(coord: Vector2i, world_seed: int, biome: StringName) -> Dictionary:
	var out := _base(coord, biome)
	var plan: Dictionary = CityPlan.roads_for_chunk(world_seed, biome, coord)
	out["plan"] = plan
	var district: Dictionary = CityPlan.district(world_seed, biome, coord)
	out["district"] = district

	for r in plan["v_roads"]:
		_add_vertical_corridor(out, float(r["local_pos"]), float(r["half_width"]) + float(r["sidewalk"]), r["kind"])
	for r in plan["h_roads"]:
		_add_horizontal_corridor(out, float(r["local_pos"]), float(r["half_width"]) + float(r["sidewalk"]), r["kind"])

	# Intersecciones: paso de cebra siempre; semaforo cuando cruza una avenida.
	for its in plan["intersections"]:
		var pos: Vector2 = its["pos"]
		_add_anchor(out, &"crosswalk", pos, Rect2(pos - Vector2(110, 110), Vector2(220, 220)), 1.0, {"v": its["v"], "h": its["h"]})
		if bool(its["has_avenue"]):
			_add_anchor(out, &"traffic_light", pos, Rect2(pos - Vector2(150, 150), Vector2(300, 300)), 1.0, {"v": its["v"], "h": its["h"]})

	# Manzanas entre calles: el distrito decide la mezcla de usos.
	var lots: Array[Dictionary] = CityPlan.lots_for_chunk(world_seed, biome, coord)
	for li in lots.size():
		var lot: Dictionary = lots[li]
		var rect: Rect2 = (lot["rect"] as Rect2).grow(-26.0)
		if rect.size.x < 110.0 or rect.size.y < 110.0:
			continue
		var kind := _lot_kind(world_seed, coord, li, district)
		var extra := {"facing": lot["facing"]}
		_add_anchor(out, kind, rect.get_center(), rect, 1.0, extra)
		if kind == &"plaza":
			out["reserved_rects"].append(rect.grow(-40.0))

	# Coches aparcados pegados al bordillo de las avenidas y paradas de bus.
	for r in plan["v_roads"]:
		if r["kind"] != &"avenue":
			continue
		var x: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		for side in [-1.0, 1.0]:
			if CityPlan.hash01(world_seed, "parked:v:%d:%d:%d" % [int(r["index"]), coord.y, int(side)]) < 0.62:
				var band := Rect2(Vector2(x + side * (hw - 30.0) - 24.0, 90.0), Vector2(48.0, CHUNK_SIZE.y - 180.0))
				_add_anchor(out, &"parked_cars", band.get_center(), band, 0.9, {"axis": &"vertical", "side": side})
		if CityPlan.hash01(world_seed, "bus:v:%d:%d" % [int(r["index"]), coord.y]) < 0.35:
			var bus_y: float = 200.0 + CityPlan.hash01(world_seed, "bus_y:%d:%d" % [coord.x, coord.y]) * (CHUNK_SIZE.y - 400.0)
			var bus_pos := Vector2(x + hw + float(r["sidewalk"]) * 0.5, bus_y)
			_add_anchor(out, &"bus_stop", bus_pos, Rect2(bus_pos - Vector2(40, 70), Vector2(80, 140)), 0.8, {"axis": &"vertical"})
	for r in plan["h_roads"]:
		if r["kind"] != &"avenue":
			continue
		var y: float = float(r["local_pos"])
		var hw2: float = float(r["half_width"])
		for side in [-1.0, 1.0]:
			if CityPlan.hash01(world_seed, "parked:h:%d:%d:%d" % [int(r["index"]), coord.x, int(side)]) < 0.62:
				var band := Rect2(Vector2(90.0, y + side * (hw2 - 26.0) - 20.0), Vector2(CHUNK_SIZE.x - 180.0, 40.0))
				_add_anchor(out, &"parked_cars", band.get_center(), band, 0.9, {"axis": &"horizontal", "side": side})
	return out


## Uso de una manzana segun distrito + hash del lote (determinista).
static func _lot_kind(world_seed: int, coord: Vector2i, lot_index: int, district: Dictionary) -> StringName:
	var h: float = CityPlan.hash01(world_seed, "lot:%d:%d:%d" % [coord.x, coord.y, lot_index])
	match district.get("kind", &"residential"):
		&"commercial":
			if h < 0.42:
				return &"commercial_block"
			elif h < 0.66:
				return &"parking_lot"
			elif h < 0.80:
				return &"plaza"
			return &"residential_block"
		&"plaza":
			if h < 0.30:
				return &"plaza"
			elif h < 0.55:
				return &"pocket_park"
			return &"residential_block"
		&"pocket_park":
			if h < 0.45:
				return &"pocket_park"
			elif h < 0.60:
				return &"parking_lot"
			return &"residential_block"
		_:
			if h < 0.68:
				return &"residential_block"
			elif h < 0.82:
				return &"parking_lot"
			elif h < 0.92:
				return &"pocket_park"
			return &"trash_corner"


# --- Parque --------------------------------------------------------------------

static func _park(coord: Vector2i, world_seed: int, biome: StringName) -> Dictionary:
	var out := _base(coord, biome)
	var trails: Array[Dictionary] = CityPlan.park_trails_for_chunk(world_seed, coord)
	out["trails"] = trails
	for trail in trails:
		_add_path_band(out, trail["points"], float(trail["half_width"]) + 22.0, trail["kind"])

	# Lago continuo por region (puede cruzar varios chunks sin costura).
	var lake: Dictionary = CityPlan.park_lake_for_chunk(world_seed, coord)
	out["lake"] = lake
	if not lake.is_empty():
		var lake_center: Vector2 = lake["center"]
		var lake_radius: float = float(lake["radius"])
		out["reserved_circles"].append({"center": lake_center, "radius": lake_radius + 30.0})
		_add_anchor(out, &"pond", lake_center, Rect2(lake_center - Vector2.ONE * lake_radius, Vector2.ONE * lake_radius * 2.0), 0.95, {"radius": lake_radius})

	# Claro de pradera en algunos chunks (zona abierta jugable).
	if CityPlan.hash01(world_seed, "clearing:%d:%d" % [coord.x, coord.y]) < 0.40:
		_add_anchor(out, &"clearing", CHUNK_SIZE * 0.5, Rect2(Vector2(330, 340), Vector2(360, 330)), 1.0)

	# Arboledas en las esquinas (los bosquecillos dan estructura y cobertura).
	var corners: Array[Vector2] = [Vector2(190, 190), Vector2(830, 190), Vector2(190, 830), Vector2(830, 830)]
	for i in 4:
		var weight: float = 0.7 + WorldSeedManager.rand01(world_seed, biome, coord, 40 + i) * 0.3
		_add_anchor(out, &"tree_grove", corners[i], Rect2(corners[i] - Vector2(175, 155), Vector2(350, 310)), weight)

	# Bancos, picnic y kiosko a lo largo del sendero principal de la fila.
	if CityPlan.park_has_row_trail(world_seed, coord.y):
		var origin := Vector2(coord) * CHUNK_SIZE
		for i in 3:
			var wx: float = origin.x + 200.0 + float(i) * 300.0
			var trail_y: float = CityPlan.park_trail_y(world_seed, coord.y, wx) - origin.y
			if trail_y < 60.0 or trail_y > CHUNK_SIZE.y - 60.0:
				continue
			var side: float = 1.0 if i % 2 == 0 else -1.0
			var pos := Vector2(wx - origin.x, trail_y + side * 115.0)
			_add_anchor(out, &"bench_zone", pos, Rect2(pos - Vector2(100, 80), Vector2(200, 160)), 0.8)
		var kiosk_h: float = CityPlan.hash01(world_seed, "kiosk:%d:%d" % [coord.x, coord.y])
		if kiosk_h < 0.24:
			var kx: float = origin.x + 512.0
			var ky: float = CityPlan.park_trail_y(world_seed, coord.y, kx) - origin.y - 150.0
			if ky > 90.0 and ky < CHUNK_SIZE.y - 90.0:
				_add_anchor(out, &"kiosk", Vector2(512.0, ky), Rect2(Vector2(512.0 - 90.0, ky - 80.0), Vector2(180, 160)), 0.85)
	if CityPlan.hash01(world_seed, "picnic:%d:%d" % [coord.x, coord.y]) < 0.30:
		var px: float = 250.0 + CityPlan.hash01(world_seed, "picnic_x:%d:%d" % [coord.x, coord.y]) * 520.0
		var py: float = 250.0 + CityPlan.hash01(world_seed, "picnic_y:%d:%d" % [coord.x, coord.y]) * 520.0
		_add_anchor(out, &"picnic_zone", Vector2(px, py), Rect2(Vector2(px - 130.0, py - 110.0), Vector2(260, 220)), 0.8)

	_add_anchor(out, &"broken_fence", Vector2(55, CHUNK_SIZE.y * 0.5), Rect2(Vector2(20, 260), Vector2(80, 500)), 0.45)
	_add_anchor(out, &"broken_fence", Vector2(970, CHUNK_SIZE.y * 0.5), Rect2(Vector2(925, 260), Vector2(80, 500)), 0.45)
	return out


# --- Industrial ----------------------------------------------------------------

static func _industrial(coord: Vector2i, world_seed: int, biome: StringName) -> Dictionary:
	var out := _base(coord, biome)
	var plan: Dictionary = CityPlan.roads_for_chunk(world_seed, biome, coord)
	out["plan"] = plan
	var district: Dictionary = CityPlan.district(world_seed, biome, coord)
	out["district"] = district

	for r in plan["v_roads"]:
		_add_vertical_corridor(out, float(r["local_pos"]), float(r["half_width"]) + float(r["sidewalk"]), r["kind"])
	for r in plan["h_roads"]:
		_add_horizontal_corridor(out, float(r["local_pos"]), float(r["half_width"]) + float(r["sidewalk"]), r["kind"])

	# Via de tren continua (una cada 3 filas de chunks, misma Y en toda la fila).
	var rail: Dictionary = CityPlan.rail_for_chunk(world_seed, coord)
	out["rail"] = rail
	if not rail.is_empty():
		_add_horizontal_corridor(out, float(rail["local_y"]), 36.0, &"rail")

	# Filas de contenedores pegadas a los corredores de carga.
	for r in plan["v_roads"]:
		if r["kind"] != &"cargo_corridor":
			continue
		var x: float = float(r["local_pos"])
		var hw: float = float(r["half_width"]) + float(r["sidewalk"])
		for side in [-1.0, 1.0]:
			if CityPlan.hash01(world_seed, "lane:%d:%d:%d" % [int(r["index"]), coord.y, int(side)]) < 0.72:
				var lane_x: float = x + side * (hw + 66.0)
				if lane_x < 70.0 or lane_x > CHUNK_SIZE.x - 70.0:
					continue
				var band := Rect2(Vector2(lane_x - 60.0, 110.0), Vector2(120.0, CHUNK_SIZE.y - 220.0))
				_add_anchor(out, &"container_lane", band.get_center(), band, 0.95, {"axis": &"vertical"})

	# Manzanas: naves, patios de carga, zonas de barriles y maquinaria.
	var lots: Array[Dictionary] = CityPlan.lots_for_chunk(world_seed, biome, coord)
	for li in lots.size():
		var lot: Dictionary = lots[li]
		var rect: Rect2 = (lot["rect"] as Rect2).grow(-30.0)
		if rect.size.x < 130.0 or rect.size.y < 130.0:
			continue
		var h: float = CityPlan.hash01(world_seed, "yard:%d:%d:%d" % [coord.x, coord.y, li])
		if h < 0.34 and rect.size.x > 260.0 and rect.size.y > 220.0:
			_add_anchor(out, &"warehouse", rect.get_center(), rect, 1.0, {"facing": lot["facing"]})
		elif h < 0.56:
			_add_anchor(out, &"loading_yard", rect.get_center(), rect, 1.0)
			if CityPlan.hash01(world_seed, "crane:%d:%d:%d" % [coord.x, coord.y, li]) < 0.4:
				_add_anchor(out, &"crane", rect.get_center() + Vector2(rect.size.x * 0.3, 0), Rect2(rect.get_center() - Vector2(40, 40), Vector2(80, 80)), 0.9)
		elif h < 0.78:
			_add_anchor(out, &"barrel_zone", rect.get_center(), rect.grow(-20.0), 0.7)
		else:
			_add_anchor(out, &"machinery", rect.get_center(), rect.grow(-20.0), 0.6)

	_add_anchor(out, &"pipe_wall", Vector2(250, 65), Rect2(Vector2(120, 35), Vector2(300, 90)), 0.6)
	_add_anchor(out, &"pipe_wall", Vector2(770, 960), Rect2(Vector2(610, 895), Vector2(300, 90)), 0.6)
	return out


# --- Utilidades ----------------------------------------------------------------

static func _add_anchor(out: Dictionary, kind: StringName, center: Vector2, rect: Rect2, weight: float, extra: Dictionary = {}) -> void:
	var anchor := {"kind": kind, "center": center, "rect": rect, "weight": weight}
	for key in extra.keys():
		anchor[key] = extra[key]
	out["anchors"].append(anchor)
	if kind in [&"clearing", &"loading_yard"]:
		out["reserved_rects"].append(rect.grow(18.0))


static func _add_vertical_corridor(out: Dictionary, x: float, half_width: float, kind: StringName) -> void:
	var rect := Rect2(Vector2(x - half_width, 0), Vector2(half_width * 2.0, CHUNK_SIZE.y))
	out["roads"].append({"kind": kind, "rect": rect, "axis": &"vertical"})
	out["reserved_rects"].append(rect)
	out["debug_lines"].append([Vector2(x, 0), Vector2(x, CHUNK_SIZE.y)])


static func _add_horizontal_corridor(out: Dictionary, y: float, half_width: float, kind: StringName) -> void:
	var rect := Rect2(Vector2(0, y - half_width), Vector2(CHUNK_SIZE.x, half_width * 2.0))
	out["roads"].append({"kind": kind, "rect": rect, "axis": &"horizontal"})
	out["reserved_rects"].append(rect)
	out["debug_lines"].append([Vector2(0, y), Vector2(CHUNK_SIZE.x, y)])


static func _add_path_band(out: Dictionary, points: Array, half_width: float, kind: StringName) -> void:
	out["roads"].append({"kind": kind, "points": points, "half_width": half_width})
	for p in points:
		out["reserved_circles"].append({"center": p, "radius": half_width})
	out["debug_lines"].append(points)
