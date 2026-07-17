class_name ChunkGroundRenderer
extends Node2D
## Suelo detallado de un chunk, dibujado UNA sola vez al crearse (Godot cachea el
## canvas item: cero coste por frame). Dibuja asfalto, aceras, lineas viales, pasos
## de cebra, senderos, lago, vias de tren... siguiendo el layout de BiomeLayoutGenerator,
## de modo que lo visible coincide exactamente con las zonas reservadas de la logica.
## Los colores derivan del MapData para mantener la identidad de cada bioma.

# CityPlan es clase global (class_name): se usa sin preload.
const CHUNK := Vector2(1024.0, 1024.0)

var _map: MapData
var _coord := Vector2i.ZERO
var _seed: int = 0
var _layout: Dictionary = {}


func setup(map_data: MapData, coord: Vector2i, world_seed: int, layout: Dictionary) -> void:
	_map = map_data
	_coord = coord
	_seed = world_seed
	_layout = layout
	# Mismo z que el WorldGrid (-1): el spawner va despues en el arbol, asi que el
	# suelo queda por encima del grid pero debajo de decoracion/props/obstaculos.
	z_index = -1
	queue_redraw()


func _h(tag: String) -> float:
	return CityPlan.hash01(_seed, "%s:%d:%d" % [tag, _coord.x, _coord.y])


func _draw() -> void:
	if _map == null or _layout.is_empty():
		return
	match _map.biome:
		&"park":
			_draw_park()
		&"industrial":
			_draw_industrial()
		_:
			_draw_neighborhood()


# =============================== BARRIO =======================================

func _draw_neighborhood() -> void:
	var plan: Dictionary = _layout.get("plan", {})
	if plan.is_empty():
		return
	var asphalt := Color(0.085, 0.09, 0.115)
	var sidewalk := Color(0.16, 0.17, 0.20)
	var curb := Color(0.30, 0.32, 0.38)

	_draw_lot_grounds()

	# Aceras (bandas a ambos lados de cada via).
	for r in plan["v_roads"]:
		var x: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		var sw: float = float(r["sidewalk"])
		if sw > 0.0:
			_rect(Rect2(x - hw - sw, 0, sw, CHUNK.y), sidewalk)
			_rect(Rect2(x + hw, 0, sw, CHUNK.y), sidewalk)
	for r in plan["h_roads"]:
		var y: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		var sw: float = float(r["sidewalk"])
		if sw > 0.0:
			_rect(Rect2(0, y - hw - sw, CHUNK.x, sw), sidewalk)
			_rect(Rect2(0, y + hw, CHUNK.x, sw), sidewalk)

	# Juntas de acera (losetas cada 64 px).
	var joint := Color(0.11, 0.12, 0.145)
	for r in plan["v_roads"]:
		var x: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		var sw: float = float(r["sidewalk"])
		if sw <= 0.0:
			continue
		var jy: float = 0.0
		while jy <= CHUNK.y:
			_line(Vector2(x - hw - sw, jy), Vector2(x - hw, jy), joint, 2.0)
			_line(Vector2(x + hw, jy), Vector2(x + hw + sw, jy), joint, 2.0)
			jy += 64.0
	for r in plan["h_roads"]:
		var y: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		var sw: float = float(r["sidewalk"])
		if sw <= 0.0:
			continue
		var jx: float = 0.0
		while jx <= CHUNK.x:
			_line(Vector2(jx, y - hw - sw), Vector2(jx, y - hw), joint, 2.0)
			_line(Vector2(jx, y + hw), Vector2(jx, y + hw + sw), joint, 2.0)
			jx += 64.0

	# Variacion tonal por loseta de acera: algunas losetas mas claras/oscuras.
	for r in plan["v_roads"]:
		var x: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		var sw: float = float(r["sidewalk"])
		if sw <= 0.0:
			continue
		for ti in int(CHUNK.y / 64.0):
			var th: float = CityPlan.hash01(_seed, "tile:v:%d:%d:%d:%d" % [int(r["index"]), _coord.x, _coord.y, ti])
			if th < 0.3:
				var tone := Color(1, 1, 1, 0.03) if th < 0.15 else Color(0, 0, 0, 0.05)
				_rect(Rect2(x - hw - sw, float(ti) * 64.0, sw, 64.0), tone)
				_rect(Rect2(x + hw, float(ti + 3 % 16) * 64.0, sw, 64.0), tone)
	for r in plan["h_roads"]:
		var y: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		var sw: float = float(r["sidewalk"])
		if sw <= 0.0:
			continue
		for ti in int(CHUNK.x / 64.0):
			var th: float = CityPlan.hash01(_seed, "tile:h:%d:%d:%d:%d" % [int(r["index"]), _coord.x, _coord.y, ti])
			if th < 0.3:
				var tone := Color(1, 1, 1, 0.03) if th < 0.15 else Color(0, 0, 0, 0.05)
				_rect(Rect2(float(ti) * 64.0, y - hw - sw, 64.0, sw), tone)
				_rect(Rect2(float(ti + 5 % 16) * 64.0, y + hw, 64.0, sw), tone)

	# Asfalto encima de las aceras (las tapa en las intersecciones, como en la realidad).
	for r in plan["v_roads"]:
		var x: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		_rect(Rect2(x - hw, 0, hw * 2.0, CHUNK.y), asphalt)
	for r in plan["h_roads"]:
		var y: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		_rect(Rect2(0, y - hw, CHUNK.x, hw * 2.0), asphalt)

	# Bandas de rodada: el trafico oscurece dos franjas paralelas por carril.
	var wear := Color(0.055, 0.06, 0.075, 0.35)
	for r in plan["v_roads"]:
		var x: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		for off in [-hw * 0.45, hw * 0.45]:
			_rect(Rect2(x + off - hw * 0.17, 0, hw * 0.34, CHUNK.y), wear)
	for r in plan["h_roads"]:
		var y: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		for off in [-hw * 0.45, hw * 0.45]:
			_rect(Rect2(0, y + off - hw * 0.17, CHUNK.x, hw * 0.34), wear)

	# Manchas y parches tonales del asfalto (deterministas).
	for i in 14:
		var sx: float = CityPlan.hash01(_seed, "stain_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var sy: float = CityPlan.hash01(_seed, "stain_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		if not _point_on_road(plan, Vector2(sx, sy)):
			continue
		var sr: float = 14.0 + CityPlan.hash01(_seed, "stain_r:%d:%d:%d" % [_coord.x, _coord.y, i]) * 22.0
		if i % 3 == 0:
			draw_circle(Vector2(sx, sy), sr, Color(0.06, 0.065, 0.08, 0.6))
		else:
			# Parche tonal: asfalto reparado, mas claro.
			draw_circle(Vector2(sx, sy), sr * 1.4, Color(0.12, 0.125, 0.15, 0.35))

	# Grietas del asfalto: polilineas cortas deterministas solo sobre via.
	for i in 8:
		var gx: float = CityPlan.hash01(_seed, "crack_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var gy: float = CityPlan.hash01(_seed, "crack_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		if not _point_on_road(plan, Vector2(gx, gy)):
			continue
		var p := Vector2(gx, gy)
		for k in 3:
			var ang: float = CityPlan.hash01(_seed, "crack_a:%d:%d:%d:%d" % [_coord.x, _coord.y, i, k]) * TAU
			var q := p + Vector2.RIGHT.rotated(ang) * (10.0 + CityPlan.hash01(_seed, "crack_l:%d:%d:%d:%d" % [_coord.x, _coord.y, i, k]) * 16.0)
			_line(p, q, Color(0.045, 0.05, 0.065, 0.8), 1.5)
			p = q

	# Bordillos en dos tonos: highlight del lado de la luz (NO) + linea oscura.
	var curb_dark := Color(0.05, 0.055, 0.07)
	for r in plan["v_roads"]:
		var x: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		_line(Vector2(x - hw - 1.5, 0), Vector2(x - hw - 1.5, CHUNK.y), curb.lightened(0.18), 2.0)
		_line(Vector2(x - hw + 1.0, 0), Vector2(x - hw + 1.0, CHUNK.y), curb_dark, 1.5)
		_line(Vector2(x + hw + 1.5, 0), Vector2(x + hw + 1.5, CHUNK.y), curb, 2.5)
		_line(Vector2(x + hw - 1.0, 0), Vector2(x + hw - 1.0, CHUNK.y), curb_dark, 1.5)
	for r in plan["h_roads"]:
		var y: float = float(r["local_pos"])
		var hw: float = float(r["half_width"])
		_line(Vector2(0, y - hw - 1.5), Vector2(CHUNK.x, y - hw - 1.5), curb.lightened(0.18), 2.0)
		_line(Vector2(0, y - hw + 1.0), Vector2(CHUNK.x, y - hw + 1.0), curb_dark, 1.5)
		_line(Vector2(0, y + hw + 1.5), Vector2(CHUNK.x, y + hw + 1.5), curb, 2.5)
		_line(Vector2(0, y + hw - 1.0), Vector2(CHUNK.x, y + hw - 1.0), curb_dark, 1.5)

	# Lineas viales: doble amarilla en avenidas, blanca discontinua en calles.
	for r in plan["v_roads"]:
		_draw_road_lines(float(r["local_pos"]), r["kind"], true, plan)
	for r in plan["h_roads"]:
		_draw_road_lines(float(r["local_pos"]), r["kind"], false, plan)

	# Intersecciones: parche de asfalto limpio + pasos de cebra + alcantarillas.
	for its in plan["intersections"]:
		_draw_intersection(its)

	# Hojas secas arrastradas a las esquinas (FASE VISUAL 1): pequenos grupos
	# ocres cerca de aceras; venden abandono sin ensuciar la lectura.
	for i in 10:
		var lx: float = CityPlan.hash01(_seed, "leaf_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var ly: float = CityPlan.hash01(_seed, "leaf_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		if _point_on_road(plan, Vector2(lx, ly)):
			continue
		for k in 3:
			var off := Vector2.RIGHT.rotated(CityPlan.hash01(_seed, "leaf_a:%d:%d:%d:%d" % [_coord.x, _coord.y, i, k]) * TAU) * (3.0 + float(k) * 4.0)
			var warm: float = CityPlan.hash01(_seed, "leaf_c:%d:%d:%d:%d" % [_coord.x, _coord.y, i, k])
			draw_circle(Vector2(lx, ly) + off, 2.2 + warm * 1.6, Color(0.45, 0.30, 0.12, 0.5).lerp(Color(0.55, 0.42, 0.18, 0.5), warm))

	# Marcas de garra felina en el pavimento: firma del Barrio Gatuno (3 aranazos
	# paralelos con el color de acento, muy tenues).
	for i in 3:
		if CityPlan.hash01(_seed, "claw:%d:%d:%d" % [_coord.x, _coord.y, i]) > 0.42:
			continue
		var cx: float = 90.0 + CityPlan.hash01(_seed, "claw_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * (CHUNK.x - 180.0)
		var cy: float = 90.0 + CityPlan.hash01(_seed, "claw_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * (CHUNK.y - 180.0)
		var ca: float = CityPlan.hash01(_seed, "claw_a:%d:%d:%d" % [_coord.x, _coord.y, i]) * TAU
		var dir := Vector2.RIGHT.rotated(ca)
		var side := Vector2(-dir.y, dir.x)
		for s in 3:
			var start := Vector2(cx, cy) + side * (float(s) - 1.0) * 7.0
			_line(start, start + dir * (26.0 + float(s % 2) * 8.0), Color(_map.accent_color.r, _map.accent_color.g, _map.accent_color.b, 0.16), 2.5)

	# Marcas de parada de bus.
	for anchor in _layout.get("anchors", []):
		if anchor.get("kind", &"") == &"bus_stop":
			var c: Vector2 = anchor.get("center", Vector2.ZERO)
			_rect(Rect2(c - Vector2(16, 52), Vector2(32, 104)), Color(_map.accent_color.r, _map.accent_color.g, _map.accent_color.b, 0.22))
			draw_rect(Rect2(c - Vector2(16, 52), Vector2(32, 104)), Color(_map.accent_color.r, _map.accent_color.g, _map.accent_color.b, 0.4), false, 2.0)


## Suelo de las manzanas segun su uso (plaza pavimentada, parque verde, parking
## rayado...). TODOS los lotes reciben un tono base propio: mata el fondo plano
## de cuadricula entre fachadas.
func _draw_lot_grounds() -> void:
	var lot_index: int = 0
	for anchor in _layout.get("anchors", []):
		var kind: StringName = anchor.get("kind", &"")
		var rect: Rect2 = anchor.get("rect", Rect2())
		lot_index += 1
		match kind:
			&"residential_block", &"commercial_block", &"trash_corner":
				# Tono propio por lote: hormigon claro / tierra / asfalto viejo.
				var lh: float = CityPlan.hash01(_seed, "lot_tone:%d:%d:%d" % [_coord.x, _coord.y, lot_index])
				var ground: Color
				if lh < 0.4:
					ground = Color(0.135, 0.14, 0.165)   # hormigon de patio
				elif lh < 0.7:
					ground = Color(0.125, 0.115, 0.10)   # tierra compactada
				else:
					ground = Color(0.10, 0.105, 0.125)   # asfalto viejo
				_rect(rect.grow(12.0), ground)
				# Textura tenue del patio.
				for i in 5:
					var tx: float = rect.position.x + CityPlan.hash01(_seed, "lg_x:%d:%d:%d:%d" % [_coord.x, _coord.y, lot_index, i]) * rect.size.x
					var ty: float = rect.position.y + CityPlan.hash01(_seed, "lg_y:%d:%d:%d:%d" % [_coord.x, _coord.y, lot_index, i]) * rect.size.y
					draw_circle(Vector2(tx, ty), 14.0 + CityPlan.hash01(_seed, "lg_r:%d:%d:%d:%d" % [_coord.x, _coord.y, lot_index, i]) * 18.0, Color(0, 0, 0, 0.07))
			&"pocket_park":
				var grass := Color(0.10, 0.145, 0.09)
				_rect(rect.grow(10.0), grass)
				for i in 6:
					var px: float = rect.position.x + CityPlan.hash01(_seed, "pp_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * rect.size.x
					var py: float = rect.position.y + CityPlan.hash01(_seed, "pp_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * rect.size.y
					draw_circle(Vector2(px, py), 22.0, Color(0.12, 0.17, 0.10, 0.8))
				# Matas de pasto (abanicos de trazos) y flores.
				for i in 8:
					var mx: float = rect.position.x + 20.0 + CityPlan.hash01(_seed, "tuft_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * (rect.size.x - 40.0)
					var my: float = rect.position.y + 20.0 + CityPlan.hash01(_seed, "tuft_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * (rect.size.y - 40.0)
					_grass_tuft(Vector2(mx, my), "pp_tuft:%d" % i)
				for i in 4:
					var fx: float = rect.position.x + 24.0 + CityPlan.hash01(_seed, "fl_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * (rect.size.x - 48.0)
					var fy: float = rect.position.y + 24.0 + CityPlan.hash01(_seed, "fl_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * (rect.size.y - 48.0)
					draw_circle(Vector2(fx, fy), 2.5, Color(0.85, 0.8, 0.45, 0.8))
			&"plaza":
				var paving := Color(0.15, 0.155, 0.185)
				_rect(rect.grow(10.0), paving)
				# Losetas de plaza.
				var tile: float = 52.0
				var tx: float = rect.position.x
				while tx <= rect.end.x:
					_line(Vector2(tx, rect.position.y), Vector2(tx, rect.end.y), Color(0.115, 0.12, 0.15), 1.5)
					tx += tile
				var ty: float = rect.position.y
				while ty <= rect.end.y:
					_line(Vector2(rect.position.x, ty), Vector2(rect.end.x, ty), Color(0.115, 0.12, 0.15), 1.5)
					ty += tile
				draw_circle(rect.get_center(), 34.0, Color(_map.accent_color.r, _map.accent_color.g, _map.accent_color.b, 0.14))
				draw_arc(rect.get_center(), 34.0, 0.0, TAU, 28, Color(_map.accent_color.r, _map.accent_color.g, _map.accent_color.b, 0.3), 2.0)
			&"parking_lot":
				var lot_asphalt := Color(0.10, 0.105, 0.13)
				_rect(rect.grow(6.0), lot_asphalt)
				# Rayas de aparcamiento en dos filas.
				for row in 2:
					var base_y: float = rect.position.y + rect.size.y * (0.35 if row == 0 else 0.65)
					var px: float = rect.position.x + 30.0
					while px < rect.end.x - 30.0:
						_line(Vector2(px, base_y - 34.0), Vector2(px, base_y + 34.0), Color(0.72, 0.72, 0.62, 0.28), 3.0)
						px += 76.0


func _draw_road_lines(pos: float, kind: StringName, vertical: bool, plan: Dictionary) -> void:
	var is_avenue: bool = kind == &"avenue"
	var line_color := Color(0.85, 0.72, 0.25, 0.55) if is_avenue else Color(0.8, 0.8, 0.72, 0.4)
	var dash: float = 44.0
	var gap: float = 34.0
	var offsets: Array[float] = []
	if is_avenue:
		offsets.assign([-5.0, 5.0])
	else:
		offsets.assign([0.0])
	for off in offsets:
		var t: float = 0.0
		while t < CHUNK.x:
			# No pintar linea dentro de las intersecciones.
			var mid: Vector2 = Vector2(pos + off, t + dash * 0.5) if vertical else Vector2(t + dash * 0.5, pos + off)
			if not _point_in_intersection(plan, mid):
				var a: Vector2 = Vector2(pos + off, t) if vertical else Vector2(t, pos + off)
				var b: Vector2 = Vector2(pos + off, minf(t + dash, CHUNK.y)) if vertical else Vector2(minf(t + dash, CHUNK.x), pos + off)
				_line(a, b, line_color, 4.0 if is_avenue else 3.0)
			t += dash + gap


func _draw_intersection(its: Dictionary) -> void:
	var pos: Vector2 = its["pos"]
	var v: Dictionary = its["v"]
	var h: Dictionary = its["h"]
	var v_hw: float = float(v["half_width"])
	var h_hw: float = float(h["half_width"])
	# Pasos de cebra en los 4 accesos.
	var zebra := Color(0.85, 0.85, 0.78, 0.5)
	var stripe_w: float = 8.0
	var stripe_gap: float = 9.0
	# Accesos norte y sur (cruzan la via vertical).
	for side_v in [-1.0, 1.0]:
		var base_y: float = pos.y + side_v * (h_hw + 16.0)
		var sx: float = pos.x - v_hw + 10.0
		while sx < pos.x + v_hw - 4.0:
			_line(Vector2(sx, base_y), Vector2(sx, base_y + side_v * 26.0), zebra, stripe_w)
			sx += stripe_w + stripe_gap
	# Accesos este y oeste (cruzan la via horizontal).
	for side_h in [-1.0, 1.0]:
		var base_x: float = pos.x + side_h * (v_hw + 16.0)
		var sy: float = pos.y - h_hw + 10.0
		while sy < pos.y + h_hw - 4.0:
			_line(Vector2(base_x, sy), Vector2(base_x + side_h * 26.0, sy), zebra, stripe_w)
			sy += stripe_w + stripe_gap
	# Stop lines: banda blanca gruesa antes de cada cebra (sentido de circulacion).
	var stop_line := Color(0.85, 0.85, 0.80, 0.55)
	for side_v in [-1.0, 1.0]:
		var sy2: float = pos.y + side_v * (h_hw + 50.0)
		_line(Vector2(pos.x + (2.0 if side_v > 0 else -v_hw + 2.0), sy2), Vector2(pos.x + (v_hw - 2.0 if side_v > 0 else -2.0), sy2), stop_line, 6.0)
	for side_h in [-1.0, 1.0]:
		var sx2: float = pos.x + side_h * (v_hw + 50.0)
		_line(Vector2(sx2, pos.y + (2.0 if side_h < 0 else -h_hw + 2.0)), Vector2(sx2, pos.y + (h_hw - 2.0 if side_h < 0 else -2.0)), stop_line, 6.0)
	# Alcantarilla en una esquina de la interseccion + rejilla de desague en otra.
	var corner := pos + Vector2(v_hw * 0.55, h_hw * 0.55)
	draw_circle(corner, 11.0, Color(0.05, 0.055, 0.07))
	draw_arc(corner, 11.0, 0.0, TAU, 16, Color(0.28, 0.3, 0.35, 0.8), 2.0)
	draw_arc(corner, 6.0, 0.0, TAU, 12, Color(0.28, 0.3, 0.35, 0.5), 1.5)
	var grate := pos + Vector2(-v_hw * 0.6, -h_hw + 8.0)
	_rect(Rect2(grate - Vector2(12.0, 5.0), Vector2(24.0, 10.0)), Color(0.05, 0.055, 0.07))
	for gi in 4:
		_line(grate + Vector2(-9.0 + float(gi) * 6.0, -4.0), grate + Vector2(-9.0 + float(gi) * 6.0, 4.0), Color(0.24, 0.26, 0.3, 0.8), 1.5)


func _point_on_road(plan: Dictionary, p: Vector2) -> bool:
	for r in plan["v_roads"]:
		if absf(p.x - float(r["local_pos"])) <= float(r["half_width"]):
			return true
	for r in plan["h_roads"]:
		if absf(p.y - float(r["local_pos"])) <= float(r["half_width"]):
			return true
	return false


func _point_in_intersection(plan: Dictionary, p: Vector2) -> bool:
	for its in plan["intersections"]:
		var pos: Vector2 = its["pos"]
		if absf(p.x - pos.x) <= float(its["v"]["half_width"]) + 30.0 and absf(p.y - pos.y) <= float(its["h"]["half_width"]) + 30.0:
			return true
	return false


# =============================== PARQUE =======================================

func _draw_park() -> void:
	# Pasto multitono determinista (parches suaves sobre el color base del fondo).
	for i in 16:
		var px: float = CityPlan.hash01(_seed, "grass_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var py: float = CityPlan.hash01(_seed, "grass_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		var pr: float = 60.0 + CityPlan.hash01(_seed, "grass_r:%d:%d:%d" % [_coord.x, _coord.y, i]) * 120.0
		var tone: float = CityPlan.hash01(_seed, "grass_t:%d:%d:%d" % [_coord.x, _coord.y, i])
		var grass := Color(0.10, 0.15, 0.085).lerp(Color(0.13, 0.19, 0.10), tone)
		draw_circle(Vector2(px, py), pr, Color(grass.r, grass.g, grass.b, 0.5))

	# Matas de pasto (abanicos de trazos) y flores silvestres deterministas.
	for i in 24:
		var tx: float = CityPlan.hash01(_seed, "ptuft_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var ty: float = CityPlan.hash01(_seed, "ptuft_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		_grass_tuft(Vector2(tx, ty), "ptuft:%d" % i)
	for i in 10:
		var fx: float = CityPlan.hash01(_seed, "pflor_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var fy: float = CityPlan.hash01(_seed, "pflor_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		var white: bool = CityPlan.hash01(_seed, "pflor_c:%d:%d:%d" % [_coord.x, _coord.y, i]) < 0.5
		draw_circle(Vector2(fx, fy), 2.4, Color(0.85, 0.85, 0.8, 0.8) if white else Color(0.85, 0.78, 0.4, 0.8))
		draw_circle(Vector2(fx, fy), 1.0, Color(0.8, 0.6, 0.2, 0.9) if white else Color(0.5, 0.3, 0.1, 0.9))

	# Charco ocasional con rim highlight.
	if CityPlan.hash01(_seed, "puddle:%d:%d" % [_coord.x, _coord.y]) < 0.3:
		var pux: float = 120.0 + CityPlan.hash01(_seed, "puddle_x:%d:%d" % [_coord.x, _coord.y]) * (CHUNK.x - 240.0)
		var puy: float = 120.0 + CityPlan.hash01(_seed, "puddle_y:%d:%d" % [_coord.x, _coord.y]) * (CHUNK.y - 240.0)
		var pur: float = 18.0 + CityPlan.hash01(_seed, "puddle_r:%d:%d" % [_coord.x, _coord.y]) * 20.0
		draw_circle(Vector2(pux, puy), pur, Color(0.09, 0.15, 0.18, 0.7))
		draw_arc(Vector2(pux, puy), pur * 0.8, PI * 0.95, PI * 1.55, 12, Color(0.6, 0.75, 0.8, 0.25), 2.0)

	# Claro de pradera.
	for anchor in _layout.get("anchors", []):
		if anchor.get("kind", &"") == &"clearing":
			var rect: Rect2 = anchor.get("rect", Rect2())
			draw_circle(rect.get_center(), rect.size.x * 0.55, Color(0.15, 0.21, 0.11, 0.55))
			draw_circle(rect.get_center(), rect.size.x * 0.42, Color(0.17, 0.235, 0.125, 0.5))

	# Senderos de tierra continuos (la misma curva global que reserva la logica).
	var dirt := Color(0.30, 0.25, 0.16)
	var dirt_edge := Color(0.22, 0.18, 0.12)
	for trail in _layout.get("trails", []):
		var points: Array = trail["points"]
		var hw: float = float(trail["half_width"])
		for i in points.size() - 1:
			_line(points[i], points[i + 1], dirt_edge, hw * 2.0 + 10.0)
		for i in points.size() - 1:
			_line(points[i], points[i + 1], dirt, hw * 2.0)
		# Huellas y piedritas del sendero.
		for i in range(0, points.size() - 1, 2):
			var mid: Vector2 = points[i].lerp(points[i + 1], 0.5)
			draw_circle(mid + Vector2(hw * 0.4, 0), 3.5, Color(0.38, 0.33, 0.22, 0.7))
			draw_circle(mid - Vector2(hw * 0.3, 6), 2.5, Color(0.38, 0.33, 0.22, 0.5))
		# Pasto invadiendo los bordes del sendero: semicirculos verdes irregulares.
		for i in range(0, points.size() - 1, 2):
			var mid2: Vector2 = points[i].lerp(points[i + 1], 0.5)
			var side: float = 1.0 if i % 4 == 0 else -1.0
			var edge := mid2 + Vector2(0, side * hw)
			draw_circle(edge, 7.0 + CityPlan.hash01(_seed, "pgrass:%d:%d:%d" % [_coord.x, _coord.y, i]) * 8.0, Color(0.11, 0.16, 0.09, 0.7))

	# Lago (misma geometria global en todos los chunks que toca: sin costuras).
	var lake: Dictionary = _layout.get("lake", {})
	if not lake.is_empty():
		var c: Vector2 = lake["center"]
		var r: float = float(lake["radius"])
		draw_circle(c, r + 26.0, Color(0.24, 0.21, 0.14))          # orilla de arena
		draw_circle(c, r + 8.0, Color(0.10, 0.20, 0.24))           # agua poco profunda
		draw_circle(c, r * 0.82, Color(0.08, 0.165, 0.21))         # agua profunda
		draw_arc(c + Vector2(-r * 0.25, -r * 0.3), r * 0.4, PI * 1.05, PI * 1.7, 20, Color(0.55, 0.75, 0.8, 0.30), 4.0)
		draw_arc(c + Vector2(r * 0.15, r * 0.1), r * 0.25, PI * 0.2, PI * 0.8, 14, Color(0.55, 0.75, 0.8, 0.18), 3.0)
		# Rim highlight NO en la orilla (luz global) + ondas concentricas tenues.
		draw_arc(c, r + 6.0, PI * 0.95, PI * 1.55, 24, Color(0.7, 0.85, 0.9, 0.22), 3.0)
		draw_arc(c, r * 0.55, 0.0, TAU, 28, Color(0.4, 0.6, 0.68, 0.10), 2.0)
		draw_arc(c, r * 0.35, 0.0, TAU, 22, Color(0.4, 0.6, 0.68, 0.08), 2.0)
		# Nenufares.
		for i in 3:
			var na: float = CityPlan.hash01(_seed, "lily:%d:%d:%d" % [_coord.x, _coord.y, i]) * TAU
			var nr: float = r * (0.3 + CityPlan.hash01(_seed, "lily_r:%d:%d:%d" % [_coord.x, _coord.y, i]) * 0.45)
			var np := c + Vector2.RIGHT.rotated(na) * nr
			draw_circle(np, 6.0, Color(0.20, 0.34, 0.18, 0.9))
			draw_line(np, np + Vector2(4.0, -2.0), Color(0.08, 0.165, 0.21), 2.5)
		# Juncos en la orilla.
		for i in 7:
			var a: float = CityPlan.hash01(_seed, "reed:%d:%d:%d" % [_coord.x, _coord.y, i]) * TAU
			var reed := c + Vector2.RIGHT.rotated(a) * (r + 18.0)
			_line(reed, reed + Vector2(-3, -14), Color(0.25, 0.38, 0.20, 0.8), 2.0)
			_line(reed, reed + Vector2(3, -16), Color(0.25, 0.38, 0.20, 0.8), 2.0)

	# Hojarasca (FASE VISUAL 1): manchas de hojas caidas en tonos otonales que
	# rompen el verde uniforme y refuerzan el abandono del parque.
	for i in 12:
		var hx: float = CityPlan.hash01(_seed, "hoja_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var hy: float = CityPlan.hash01(_seed, "hoja_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		var warm: float = CityPlan.hash01(_seed, "hoja_c:%d:%d:%d" % [_coord.x, _coord.y, i])
		var leaf_color := Color(0.42, 0.28, 0.10, 0.35).lerp(Color(0.52, 0.38, 0.14, 0.35), warm)
		draw_circle(Vector2(hx, hy), 16.0 + warm * 22.0, leaf_color)
		for k in 4:
			var off := Vector2.RIGHT.rotated(CityPlan.hash01(_seed, "hoja_a:%d:%d:%d:%d" % [_coord.x, _coord.y, i, k]) * TAU) * (10.0 + warm * 16.0)
			draw_circle(Vector2(hx, hy) + off, 2.4, Color(0.55, 0.40, 0.16, 0.55))

	# Setas al pie de la humedad: puntitos palidos con sombrero, en grupitos.
	for i in 5:
		if CityPlan.hash01(_seed, "seta:%d:%d:%d" % [_coord.x, _coord.y, i]) > 0.5:
			continue
		var sx: float = 60.0 + CityPlan.hash01(_seed, "seta_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * (CHUNK.x - 120.0)
		var sy: float = 60.0 + CityPlan.hash01(_seed, "seta_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * (CHUNK.y - 120.0)
		# FASE VISUAL 2: halo bioluminiscente bajo el grupo de setas (glow fake).
		draw_circle(Vector2(sx, sy - 3.0), 16.0, Color(0.35, 0.85, 0.55, 0.07))
		draw_circle(Vector2(sx, sy - 3.0), 9.0, Color(0.45, 0.95, 0.6, 0.10))
		for k in 3:
			var mp := Vector2(sx, sy) + Vector2(float(k) * 7.0 - 7.0, float(k % 2) * 5.0)
			_line(mp, mp + Vector2(0, -5), Color(0.75, 0.72, 0.62, 0.7), 2.0)
			draw_circle(mp + Vector2(0, -5.5), 3.2, Color(0.62, 0.45, 0.38, 0.85))
			draw_circle(mp + Vector2(0, -5.5), 1.2, Color(0.65, 1.0, 0.7, 0.7))

	# Zona de picnic: manta y cesta.
	for anchor in _layout.get("anchors", []):
		if anchor.get("kind", &"") == &"picnic_zone":
			var c: Vector2 = anchor.get("center", Vector2.ZERO)
			var blanket := Rect2(c - Vector2(42, 34), Vector2(84, 68))
			_rect(blanket, Color(0.55, 0.25, 0.22, 0.5))
			for k in 3:
				_line(Vector2(blanket.position.x, blanket.position.y + 17.0 * (k + 1)), Vector2(blanket.end.x, blanket.position.y + 17.0 * (k + 1)), Color(0.75, 0.68, 0.6, 0.3), 2.0)
			draw_circle(c + Vector2(52, -20), 9.0, Color(0.45, 0.33, 0.18, 0.8))


# ============================== INDUSTRIAL ====================================

func _draw_industrial() -> void:
	var plan: Dictionary = _layout.get("plan", {})
	var concrete := Color(0.115, 0.115, 0.10)
	var joint := Color(0.085, 0.085, 0.075)

	# Variacion tonal por placa: cada losa de 256 px con su propio matiz.
	var plate: float = 256.0
	for pi in 4:
		for pj in 4:
			var ph: float = CityPlan.hash01(_seed, "plate:%d:%d:%d:%d" % [_coord.x, _coord.y, pi, pj])
			if ph < 0.55:
				var tone := Color(1, 1, 1, 0.025) if ph < 0.28 else Color(0, 0, 0, 0.05)
				_rect(Rect2(float(pi) * plate, float(pj) * plate, plate, plate), tone)

	# Placas de hormigon con juntas de dilatacion.
	var px: float = 0.0
	while px <= CHUNK.x:
		_line(Vector2(px, 0), Vector2(px, CHUNK.y), joint, 3.0)
		px += plate
	var py: float = 0.0
	while py <= CHUNK.y:
		_line(Vector2(0, py), Vector2(CHUNK.x, py), joint, 3.0)
		py += plate

	# Grietas con parche de brea (mas oscuro, irregular).
	for i in 6:
		var cx: float = CityPlan.hash01(_seed, "icrack_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var cy: float = CityPlan.hash01(_seed, "icrack_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		var p := Vector2(cx, cy)
		for k in 3:
			var ang: float = CityPlan.hash01(_seed, "icrack_a:%d:%d:%d:%d" % [_coord.x, _coord.y, i, k]) * TAU
			var q := p + Vector2.RIGHT.rotated(ang) * (12.0 + CityPlan.hash01(_seed, "icrack_l:%d:%d:%d:%d" % [_coord.x, _coord.y, i, k]) * 18.0)
			_line(p, q, Color(0.045, 0.045, 0.04, 0.85), 3.0)
			p = q

	# Manchas de aceite deterministas.
	for i in 9:
		var ox: float = CityPlan.hash01(_seed, "oil_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var oy: float = CityPlan.hash01(_seed, "oil_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		var orr: float = 12.0 + CityPlan.hash01(_seed, "oil_r:%d:%d:%d" % [_coord.x, _coord.y, i]) * 26.0
		draw_circle(Vector2(ox, oy), orr, Color(0.05, 0.05, 0.06, 0.55))
		draw_circle(Vector2(ox + orr * 0.5, oy + orr * 0.3), orr * 0.45, Color(0.05, 0.05, 0.06, 0.4))

	if not plan.is_empty():
		# Corredores de carga: piso mas claro + franjas amarillas de seguridad.
		for r in plan["v_roads"]:
			var x: float = float(r["local_pos"])
			var hw: float = float(r["half_width"])
			_rect(Rect2(x - hw, 0, hw * 2.0, CHUNK.y), concrete.lightened(0.10))
			_dashed_line_v(x - hw + 6.0, Color(_map.hazard_color.r, _map.hazard_color.g, _map.hazard_color.b, 0.5))
			_dashed_line_v(x + hw - 6.0, Color(_map.hazard_color.r, _map.hazard_color.g, _map.hazard_color.b, 0.5))
		for r in plan["h_roads"]:
			if r["kind"] == &"rail":
				continue
			var y: float = float(r["local_pos"])
			var hw: float = float(r["half_width"])
			_rect(Rect2(0, y - hw, CHUNK.x, hw * 2.0), concrete.lightened(0.10))
			_dashed_line_h(y - hw + 6.0, Color(_map.hazard_color.r, _map.hazard_color.g, _map.hazard_color.b, 0.5))
			_dashed_line_h(y + hw - 6.0, Color(_map.hazard_color.r, _map.hazard_color.g, _map.hazard_color.b, 0.5))

	# Patios y naves: losa pintada.
	for anchor in _layout.get("anchors", []):
		var kind: StringName = anchor.get("kind", &"")
		var rect: Rect2 = anchor.get("rect", Rect2())
		match kind:
			&"loading_yard":
				_rect(rect, concrete.lightened(0.06))
				draw_rect(rect, Color(_map.hazard_color.r, _map.hazard_color.g, _map.hazard_color.b, 0.45), false, 4.0)
				# Esquinas pintadas.
				for corner_offset in [Vector2.ZERO, Vector2(rect.size.x, 0), rect.size, Vector2(0, rect.size.y)]:
					var cc: Vector2 = rect.position + corner_offset
					_line(cc, cc + (rect.get_center() - cc).normalized() * 26.0, Color(_map.hazard_color.r, _map.hazard_color.g, _map.hazard_color.b, 0.5), 5.0)
				# Franjas diagonales amarillo/negro en la entrada norte del patio.
				var stripe_x: float = rect.position.x + rect.size.x * 0.5 - 42.0
				for si in 6:
					var sx: float = stripe_x + float(si) * 14.0
					_line(Vector2(sx, rect.position.y + 2.0), Vector2(sx + 10.0, rect.position.y + 14.0),
						Color(_map.hazard_color.r, _map.hazard_color.g, _map.hazard_color.b, 0.55) if si % 2 == 0 else Color(0.05, 0.05, 0.05, 0.7), 5.0)
			&"warehouse":
				_rect(rect.grow(8.0), Color(0.095, 0.10, 0.09))
				draw_rect(rect.grow(8.0), Color(0.2, 0.21, 0.2, 0.7), false, 3.0)

	# Via de tren continua: balasto punteado, traviesas y dos railes con oxido.
	var rail: Dictionary = _layout.get("rail", {})
	if not rail.is_empty():
		var y: float = float(rail["local_y"])
		_rect(Rect2(0, y - 30.0, CHUNK.x, 60.0), Color(0.09, 0.088, 0.082))
		# Balasto: piedritas deterministas sobre la banda.
		for i in 26:
			var bx: float = CityPlan.hash01(_seed, "ballast_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
			var by: float = y - 26.0 + CityPlan.hash01(_seed, "ballast_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * 52.0
			draw_circle(Vector2(bx, by), 1.8, Color(0.14, 0.135, 0.125, 0.9))
		var tx: float = 8.0
		while tx < CHUNK.x:
			_rect(Rect2(tx, y - 22.0, 12.0, 44.0), Color(0.16, 0.13, 0.10))
			tx += 34.0
		# Railes con highlight NO y tramos de oxido.
		for ry in [y - 12.0, y + 12.0]:
			_line(Vector2(0, ry), Vector2(CHUNK.x, ry), Color(0.42, 0.44, 0.48), 4.0)
			_line(Vector2(0, ry - 1.5), Vector2(CHUNK.x, ry - 1.5), Color(0.58, 0.60, 0.65, 0.6), 1.5)
		for i in 4:
			var rx: float = CityPlan.hash01(_seed, "rust_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
			var rw: float = 26.0 + CityPlan.hash01(_seed, "rust_w:%d:%d:%d" % [_coord.x, _coord.y, i]) * 40.0
			var ry2: float = y - 12.0 if i % 2 == 0 else y + 12.0
			_line(Vector2(rx, ry2), Vector2(minf(rx + rw, CHUNK.x), ry2), Color(0.40, 0.24, 0.11, 0.7), 4.0)

	# Chatarra menuda (FASE VISUAL 1): tuercas, tornillos y esquirlas metalicas
	# dispersas; venden uso rudo del suelo sin geometria colisionable.
	for i in 12:
		var scx: float = CityPlan.hash01(_seed, "scrap_x:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.x
		var scy: float = CityPlan.hash01(_seed, "scrap_y:%d:%d:%d" % [_coord.x, _coord.y, i]) * CHUNK.y
		var kind: float = CityPlan.hash01(_seed, "scrap_k:%d:%d:%d" % [_coord.x, _coord.y, i])
		if kind < 0.5:
			draw_circle(Vector2(scx, scy), 2.6, Color(0.32, 0.33, 0.36, 0.8))
			draw_circle(Vector2(scx, scy), 1.1, Color(0.08, 0.08, 0.09, 0.9))
		else:
			var ang: float = CityPlan.hash01(_seed, "scrap_a:%d:%d:%d" % [_coord.x, _coord.y, i]) * TAU
			_line(Vector2(scx, scy), Vector2(scx, scy) + Vector2.RIGHT.rotated(ang) * 7.0, Color(0.38, 0.28, 0.16, 0.75), 2.0)

	# Flechas estarcidas de circulacion en los corredores (plantilla desgastada).
	if not plan.is_empty():
		for r in plan["v_roads"]:
			var ax: float = float(r["local_pos"])
			var ay: float = 140.0 + CityPlan.hash01(_seed, "arrow_v:%d:%d:%d" % [_coord.x, _coord.y, int(r["index"])]) * (CHUNK.y - 280.0)
			var arrow_c := Color(_map.hazard_color.r, _map.hazard_color.g, _map.hazard_color.b, 0.28)
			_line(Vector2(ax, ay + 22.0), Vector2(ax, ay - 14.0), arrow_c, 6.0)
			_line(Vector2(ax - 10.0, ay - 4.0), Vector2(ax, ay - 18.0), arrow_c, 6.0)
			_line(Vector2(ax + 10.0, ay - 4.0), Vector2(ax, ay - 18.0), arrow_c, 6.0)

	# Charco industrial con "sheen" frio.
	if CityPlan.hash01(_seed, "ipuddle:%d:%d" % [_coord.x, _coord.y]) < 0.35:
		var ipx: float = 120.0 + CityPlan.hash01(_seed, "ipuddle_x:%d:%d" % [_coord.x, _coord.y]) * (CHUNK.x - 240.0)
		var ipy: float = 120.0 + CityPlan.hash01(_seed, "ipuddle_y:%d:%d" % [_coord.x, _coord.y]) * (CHUNK.y - 240.0)
		var ipr: float = 16.0 + CityPlan.hash01(_seed, "ipuddle_r:%d:%d" % [_coord.x, _coord.y]) * 22.0
		draw_circle(Vector2(ipx, ipy), ipr, Color(0.06, 0.075, 0.09, 0.75))
		draw_arc(Vector2(ipx, ipy), ipr * 0.7, PI * 1.0, PI * 1.5, 12, Color(0.5, 0.65, 0.75, 0.22), 2.5)
		# FASE VISUAL 2: brillo toxico verdoso en el borde del charco quimico.
		draw_arc(Vector2(ipx, ipy), ipr + 3.0, 0.0, TAU, 20, Color(0.45, 0.9, 0.4, 0.13), 3.0)
		draw_circle(Vector2(ipx + ipr * 0.4, ipy - ipr * 0.2), ipr * 0.3, Color(0.5, 0.95, 0.45, 0.10))


func _dashed_line_v(x: float, color: Color) -> void:
	var t: float = 0.0
	while t < CHUNK.y:
		_line(Vector2(x, t), Vector2(x, minf(t + 30.0, CHUNK.y)), color, 4.0)
		t += 52.0


func _dashed_line_h(y: float, color: Color) -> void:
	var t: float = 0.0
	while t < CHUNK.x:
		_line(Vector2(t, y), Vector2(minf(t + 30.0, CHUNK.x), y), color, 4.0)
		t += 52.0


## Mata de pasto: abanico de 4-5 trazos cortos deterministas.
func _grass_tuft(pos: Vector2, tag: String) -> void:
	var blades: int = 4 + int(CityPlan.hash01(_seed, "%s:n:%d:%d" % [tag, _coord.x, _coord.y]) * 2.0)
	for b in blades:
		var spread: float = (float(b) / float(blades - 1) - 0.5) * 1.3
		var wobble: float = (CityPlan.hash01(_seed, "%s:w%d:%d:%d" % [tag, b, _coord.x, _coord.y]) - 0.5) * 0.4
		var tip := pos + Vector2(sin(spread + wobble) * 7.0, -6.0 - CityPlan.hash01(_seed, "%s:h%d:%d:%d" % [tag, b, _coord.x, _coord.y]) * 5.0)
		_line(pos, tip, Color(0.16, 0.24, 0.12, 0.85), 1.6)


# --- Primitivas recortadas al chunk (evitan doble alpha en fronteras) ----------

func _rect(rect: Rect2, color: Color) -> void:
	var clipped := rect.intersection(Rect2(Vector2.ZERO, CHUNK))
	if clipped.size.x > 0.0 and clipped.size.y > 0.0:
		draw_rect(clipped, color, true)


func _line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_line(a, b, color, width)
