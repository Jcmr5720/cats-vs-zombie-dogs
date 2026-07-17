class_name MapChunkManager
extends Node2D
## Genera el mundo por chunks alrededor del jugador/camara. Cada chunk usa una seed
## derivada del mapa y de sus coordenadas, asi que al descargarse y volver a entrar
## se reconstruye igual. El nodo reemplaza al viejo "generador unico inicial".

# ObstacleData, WorldSeedManager, BiomeLayoutGenerator, CityPlan,
# ChunkGroundRenderer y AnimatedProp son clases globales (class_name): se usan
# directamente sin preload (evita el warning de constante que sombrea la clase).

const CHUNK_SIZE := Vector2(1024.0, 1024.0)
const ACTIVE_RADIUS: int = 2
const NO_FIXED_ROTATION: float = 999999.0

@export var obstacle_scene: PackedScene
@export var max_active_obstacles: int = 380
@export var world_seed: int = 0
@export var debug_draw_enabled: bool = false

var _chunks: Dictionary = {} # Vector2i -> Node2D
var _layouts: Dictionary = {} # Vector2i -> Dictionary
var _rng := RandomNumberGenerator.new()
var _map: MapData
var _resolved_seed: int = 0
var _player: Node2D
var _last_center_chunk := Vector2i(999999, 999999)
var _fallback_origin := Vector2.ZERO
var _generating_coord := Vector2i.ZERO


func generate(map_data: MapData, player_position: Vector2 = Vector2.ZERO) -> void:
	clear()
	if obstacle_scene == null or map_data == null or map_data.obstacle_types.is_empty():
		return
	_map = map_data
	_resolved_seed = WorldSeedManager.resolve_seed(_map, world_seed)
	_fallback_origin = player_position
	_player = _find_player()
	_update_chunks(true)
	queue_redraw()


func clear() -> void:
	_last_center_chunk = Vector2i(999999, 999999)
	for chunk in _chunks.values():
		if is_instance_valid(chunk):
			chunk.queue_free()
	_chunks.clear()
	_layouts.clear()
	queue_redraw()


func _process(_delta: float) -> void:
	if _map == null or obstacle_scene == null:
		return
	if not is_instance_valid(_player):
		_player = _find_player()
	_update_chunks(false)


func _update_chunks(force: bool) -> void:
	var center_pos: Vector2 = _player.global_position if is_instance_valid(_player) else _fallback_origin
	var center_chunk := _world_to_chunk(center_pos)
	if not force and center_chunk == _last_center_chunk:
		return
	_last_center_chunk = center_chunk

	var wanted: Dictionary = {}
	for y in range(center_chunk.y - ACTIVE_RADIUS, center_chunk.y + ACTIVE_RADIUS + 1):
		for x in range(center_chunk.x - ACTIVE_RADIUS, center_chunk.x + ACTIVE_RADIUS + 1):
			var coord := Vector2i(x, y)
			wanted[coord] = true

	for coord in _chunks.keys():
		if not wanted.has(coord):
			var old_chunk: Node2D = _chunks[coord]
			if is_instance_valid(old_chunk):
				old_chunk.queue_free()
			_chunks.erase(coord)
			_layouts.erase(coord)

	for coord in wanted.keys():
		if not _chunks.has(coord):
			_create_chunk(coord)
	queue_redraw()


func _create_chunk(coord: Vector2i) -> void:
	var chunk := Node2D.new()
	chunk.name = "MapChunk_%d_%d" % [coord.x, coord.y]
	chunk.position = Vector2(coord) * CHUNK_SIZE
	add_child(chunk)
	_chunks[coord] = chunk

	var types := _valid_types(_map)
	if types.is_empty():
		return
	var layout: Dictionary = BiomeLayoutGenerator.generate(_map, coord, _resolved_seed)
	_layouts[coord] = layout
	_rng.seed = WorldSeedManager.chunk_seed(_resolved_seed, _map.biome, coord)
	_generating_coord = coord

	# Sub-nodos: suelo cacheado (detras), props decorativos y obstaculos con colision.
	var ground := ChunkGroundRenderer.new()
	ground.name = "Ground"
	chunk.add_child(ground)
	ground.setup(_map, coord, _resolved_seed, layout)
	var props := Node2D.new()
	props.name = "Props"
	chunk.add_child(props)
	var obstacles := Node2D.new()
	obstacles.name = "Obstacles"
	chunk.add_child(obstacles)
	_place_visual_props(props, layout, coord)

	var target: int = _chunk_obstacle_budget()
	var placed: Array[Rect2] = []
	match _map.biome:
		&"park":
			_generate_park_chunk(obstacles, layout, types, target, placed)
		&"industrial":
			_generate_industrial_chunk(obstacles, layout, types, target, placed)
		_:
			_generate_neighborhood_chunk(obstacles, layout, types, target, placed)


func _place_visual_props(props: Node2D, layout: Dictionary, coord: Vector2i) -> void:
	for anchor in layout.get("anchors", []):
		var kind: StringName = anchor.get("kind", &"")
		match kind:
			&"traffic_light":
				_add_prop(props, &"traffic_light", anchor.get("center", Vector2.ZERO) + Vector2(38, -38), coord, str(anchor.get("center", Vector2.ZERO)))
			&"bus_stop":
				_add_prop(props, &"bus_stop", anchor.get("center", Vector2.ZERO), coord, str(anchor.get("center", Vector2.ZERO)))
			&"crane":
				_add_prop(props, &"crane", anchor.get("center", Vector2.ZERO), coord, str(anchor.get("center", Vector2.ZERO)), _map.hazard_color)
	for road in layout.get("roads", []):
		if road.get("kind", &"") not in [&"avenue", &"cargo_corridor"]:
			continue
		var axis: StringName = road.get("axis", &"")
		if axis == &"vertical":
			var x: float = (road.get("rect", Rect2()) as Rect2).get_center().x
			for y in [220.0, 760.0]:
				if CityPlan.hash01(_resolved_seed, "lamp:%d:%d:v:%d" % [coord.x, coord.y, int(y)]) < 0.72:
					_add_prop(props, &"street_lamp", Vector2(x + 142.0, y), coord, "v:%d" % int(y))
		elif axis == &"horizontal":
			var y2: float = (road.get("rect", Rect2()) as Rect2).get_center().y
			for x2 in [220.0, 760.0]:
				if CityPlan.hash01(_resolved_seed, "lamp:%d:%d:h:%d" % [coord.x, coord.y, int(x2)]) < 0.72:
					_add_prop(props, &"street_lamp", Vector2(x2, y2 + 142.0), coord, "h:%d" % int(x2))


func _add_prop(props: Node2D, kind: StringName, local_pos: Vector2, coord: Vector2i, key: String, accent: Color = Color(0.95, 0.75, 0.28)) -> void:
	if local_pos.x < -80.0 or local_pos.x > CHUNK_SIZE.x + 80.0 or local_pos.y < -80.0 or local_pos.y > CHUNK_SIZE.y + 80.0:
		return
	var prop := AnimatedProp.new()
	prop.name = "%s_%d" % [kind, props.get_child_count()]
	props.add_child(prop)
	prop.position = local_pos
	prop.configure(kind, _resolved_seed, "%d:%d:%s" % [coord.x, coord.y, key], accent)


func _generate_neighborhood_chunk(chunk: Node2D, layout: Dictionary, types: Array, target: int, placed: Array[Rect2]) -> void:
	var house := _first_type(types, [&"house", &"wall"])
	var wall := _first_type(types, [&"wall", &"house"])
	var car := _first_type(types, [&"car"])
	var dumpster := _first_type(types, [&"container", &"crate"])
	var crate := _first_type(types, [&"crate", &"fence"])
	var tree := _first_type(types, [&"tree", &"bush"])
	var bush := _first_type(types, [&"bush", &"crate"])

	for anchor in layout.get("anchors", []):
		var kind: StringName = anchor.get("kind", &"")
		var rect: Rect2 = anchor.get("rect", Rect2())
		var facing: Array = anchor.get("facing", [])
		match kind:
			&"residential_block":
				_place_lot_buildings(chunk, layout, house, wall, rect, facing, placed)
			&"commercial_block":
				_place_lot_buildings(chunk, layout, house, house, rect, facing, placed)
				_try_place(chunk, layout, dumpster, rect.get_center() + Vector2(rect.size.x * 0.22, rect.size.y * 0.2), placed, 0.55)
				_try_place(chunk, layout, crate, rect.get_center() - Vector2(rect.size.x * 0.2, rect.size.y * 0.22), placed, 0.5)
			&"parking_lot":
				_place_parking_rows(chunk, layout, car, rect, placed)
				_try_place(chunk, layout, crate, rect.position + Vector2(rect.size.x * 0.78, rect.size.y * 0.76), placed, 0.58)
			&"pocket_park":
				_place_radial_group(chunk, layout, tree, rect.get_center(), placed, 3, 55.0, minf(rect.size.x, rect.size.y) * 0.38, 0.55)
				_place_radial_group(chunk, layout, bush, rect.get_center(), placed, 2, 40.0, minf(rect.size.x, rect.size.y) * 0.3, 0.5)
			&"trash_corner":
				_place_cluster_in_rect(chunk, layout, dumpster, rect.grow(-rect.size.x * 0.3), placed, 2, 0.58)
				_place_cluster_in_rect(chunk, layout, crate, rect.grow(-rect.size.x * 0.34), placed, 2, 0.55)
			&"parked_cars":
				_place_parked_cars(chunk, layout, car, rect, anchor.get("axis", &"vertical"), placed)
		if placed.size() >= target:
			return


func _generate_park_chunk(chunk: Node2D, layout: Dictionary, types: Array, target: int, placed: Array[Rect2]) -> void:
	var tree := _first_type(types, [&"tree"])
	var bush := _first_type(types, [&"bush"])
	var bench := _first_type(types, [&"bench"])
	var rock := _first_type(types, [&"rock"])
	var fence := _first_type(types, [&"fence"])

	for anchor in layout.get("anchors", []):
		var kind: StringName = anchor.get("kind", &"")
		var rect: Rect2 = anchor.get("rect", Rect2())
		var center: Vector2 = anchor.get("center", rect.position + rect.size * 0.5)
		match kind:
			&"tree_grove":
				_place_radial_group(chunk, layout, tree, center, placed, 4, 55.0, 145.0, 0.58)
				_place_radial_group(chunk, layout, bush, center, placed, 3, 85.0, 185.0, 0.52)
			&"bench_zone":
				_try_place(chunk, layout, bench, center, placed, 0.55, _rng.randf_range(-0.25, 0.25))
				_try_place(chunk, layout, bush, center + Vector2(_rng.randf_range(-80, 80), _rng.randf_range(-40, 40)), placed, 0.5)
			&"pond":
				var ring: float = float(anchor.get("radius", 130.0)) + 55.0
				for i in 8:
					var pos: Vector2 = center + Vector2.RIGHT.rotated(TAU * float(i) / 8.0 + _rng.randf_range(-0.2, 0.2)) * (ring + _rng.randf_range(-15.0, 35.0))
					_try_place(chunk, layout, rock if i % 2 == 0 else bush, pos, placed, 0.52)
			&"picnic_zone":
				_try_place(chunk, layout, bench, center + Vector2(-55, 0), placed, 0.5, 0.0)
				_try_place(chunk, layout, bench, center + Vector2(55, 20), placed, 0.5, 0.0)
				_try_place(chunk, layout, bush, center + Vector2(0, -85), placed, 0.5)
			&"kiosk":
				_try_place(chunk, layout, fence, center + Vector2(0, -60), placed, 0.5, 0.0)
				_try_place(chunk, layout, fence, center + Vector2(-70, 0), placed, 0.5, PI * 0.5)
				_try_place(chunk, layout, fence, center + Vector2(70, 0), placed, 0.5, PI * 0.5)
				_try_place(chunk, layout, bench, center + Vector2(0, 62), placed, 0.5, 0.0)
			&"broken_fence":
				if _rng.randf() < float(anchor.get("weight", 0.5)):
					_try_place(chunk, layout, fence, center + Vector2(0, -120), placed, 0.55, PI * 0.5)
					_try_place(chunk, layout, fence, center + Vector2(0, 120), placed, 0.55, PI * 0.5)
		if placed.size() >= target:
			return


func _generate_industrial_chunk(chunk: Node2D, layout: Dictionary, types: Array, target: int, placed: Array[Rect2]) -> void:
	var container := _first_type(types, [&"container"])
	var barrel := _first_type(types, [&"barrel"])
	var pipe := _first_type(types, [&"pipe"])
	var wall := _first_type(types, [&"wall", &"rock"])
	var block := _first_type(types, [&"rock", &"wall"])

	for anchor in layout.get("anchors", []):
		var kind: StringName = anchor.get("kind", &"")
		var rect: Rect2 = anchor.get("rect", Rect2())
		var center: Vector2 = anchor.get("center", rect.position + rect.size * 0.5)
		match kind:
			&"container_lane":
				# Fila ordenada de contenedores a lo largo de la banda (eje vertical).
				var count: int = maxi(2, int(rect.size.y / 190.0))
				for i in count:
					var y: float = rect.position.y + 70.0 + float(i) * ((rect.size.y - 140.0) / maxf(1.0, float(count - 1)))
					_try_place(chunk, layout, container, Vector2(center.x, y), placed, 0.5, PI * 0.5)
					if _rng.randf() < 0.4:
						_try_place(chunk, layout, barrel, Vector2(center.x + _random_sign() * 78.0, y + 52.0), placed, 0.46)
			&"warehouse":
				_place_warehouse(chunk, layout, wall, container, rect, placed)
			&"barrel_zone":
				_place_cluster_in_rect(chunk, layout, barrel, rect, placed, 4, 0.48)
			&"pipe_wall":
				_try_place(chunk, layout, pipe, center, placed, 0.5, 0.0)
				_try_place(chunk, layout, wall, center + Vector2(_rng.randf_range(-95, 95), 46), placed, 0.55, 0.0)
			&"machinery":
				_try_place(chunk, layout, block, center, placed, 0.55)
				_try_place(chunk, layout, pipe, center + Vector2(70, -70), placed, 0.48, PI * 0.5)
			&"concrete_blocks":
				_place_cluster_in_rect(chunk, layout, block, rect, placed, 3, 0.5)
		if placed.size() >= target:
			return


## Coloca un obstaculo validando su FOOTPRINT real (AABB con tamaño y rotacion
## sorteados ANTES de instanciar), no solo la distancia entre centros. Rechaza si
## el footprint sale del chunk (evita solapes entre chunks vecinos), pisa un area
## reservada o interseca otro footprint ya colocado. allow_on_road (solo coches
## aparcados) salta UNICAMENTE los rects reservados de vias, nunca el resto.
func _try_place(chunk: Node2D, layout: Dictionary, type: ObstacleData, local_pos: Vector2, placed: Array[Rect2], gap_mult: float, fixed_rotation: float = NO_FIXED_ROTATION, allow_on_road: bool = false, preset_size: Vector2 = Vector2.ZERO) -> bool:
	if type == null or placed.size() >= _chunk_obstacle_budget():
		return false
	var size: Vector2 = preset_size if preset_size != Vector2.ZERO else _roll_size(type)
	var rot: float = fixed_rotation if fixed_rotation != NO_FIXED_ROTATION else _roll_rotation(type)
	var he: Vector2 = _rotated_half_extents(size, rot)
	var pad: float = 8.0 * gap_mult
	var footprint := Rect2(local_pos - he - Vector2.ONE * pad, (he + Vector2.ONE * pad) * 2.0)
	# Contenido integro en el chunk: dos obstaculos de chunks vecinos no pueden solaparse.
	if not Rect2(Vector2(6.0, 6.0), CHUNK_SIZE - Vector2(12.0, 12.0)).encloses(footprint):
		return false
	var world_pos: Vector2 = chunk.global_position + local_pos
	if _player != null and world_pos.distance_to(_player.global_position) < _map.safe_radius_around_player:
		return false
	if _footprint_reserved(footprint, layout, allow_on_road):
		return false
	for other in placed:
		if footprint.intersects(other):
			return false
	if _count_active_obstacles() >= max_active_obstacles:
		return false

	var obstacle := obstacle_scene.instantiate() as Node2D
	if obstacle == null:
		return false
	chunk.add_child(obstacle)
	obstacle.position = local_pos
	if obstacle.has_method("configure"):
		obstacle.configure(type, _rng, size, rot)
	placed.append(footprint)
	return true


## Sortea el tamaño con el rng del chunk (misma formula que usaba obstacle.configure).
func _roll_size(type: ObstacleData) -> Vector2:
	return Vector2(
		lerpf(type.min_size.x, type.max_size.x, _rng.randf()),
		lerpf(type.min_size.y, type.max_size.y, _rng.randf())
	)


func _roll_rotation(type: ObstacleData) -> float:
	return _rng.randf_range(-type.max_rotation, type.max_rotation) if type.max_rotation > 0.0 else 0.0


## Semiextensiones del AABB de un rect size rotado rot (exacto a 0/90 grados;
## sobre-cubre los jitters pequeños, que es lo conservador correcto).
func _rotated_half_extents(size: Vector2, rot: float) -> Vector2:
	var c: float = absf(cos(rot))
	var s: float = absf(sin(rot))
	return Vector2(c * size.x + s * size.y, s * size.x + c * size.y) * 0.5


## Edificios de una manzana alineados a las calles: empaqueta las fachadas por
## cursor usando el ANCHO REAL de cada edificio (nada de paso fijo), con la
## profundidad justa para no invadir la acera y sin salirse del lote. Las manzanas
## sin calle solo llevan esquinas.
func _place_lot_buildings(chunk: Node2D, layout: Dictionary, house: ObstacleData, wall: ObstacleData, rect: Rect2, facing: Array, placed: Array[Rect2]) -> void:
	if facing.is_empty():
		_place_rect_corners(chunk, layout, house, rect.grow(-30.0), placed, 0.7)
		return
	for dir in facing:
		var horizontal: bool = dir == &"n" or dir == &"s"
		var edge_start: float = (rect.position.x if horizontal else rect.position.y) + 20.0
		var edge_end: float = (rect.end.x if horizontal else rect.end.y) - 20.0
		var cursor: float = edge_start
		while cursor < edge_end:
			var type: ObstacleData = house if _rng.randf() < 0.72 else wall
			if type == null:
				return
			var size := _roll_size(type)
			# En bordes oeste/este se transpone el tamaño en vez de rotar el nodo:
			# el dibujo pseudo-3D (techo + fachada sur) siempre mira al sur.
			if not horizontal:
				size = Vector2(size.y, size.x)
			var he := size * 0.5
			var along_w: float = size.x if horizontal else size.y
			var depth_he: float = he.y if horizontal else he.x
			if cursor + along_w > edge_end:
				break
			var along_c: float = cursor + along_w * 0.5
			var pos: Vector2
			match dir:
				&"n":
					pos = Vector2(along_c, rect.position.y + depth_he + 14.0)
				&"s":
					pos = Vector2(along_c, rect.end.y - depth_he - 14.0)
				&"w":
					pos = Vector2(rect.position.x + depth_he + 14.0, along_c)
				_:
					pos = Vector2(rect.end.x - depth_he - 14.0, along_c)
			# El footprint completo debe caber dentro del lote (no invade la acera).
			var footprint := Rect2(pos - he, he * 2.0)
			if rect.encloses(footprint):
				_try_place(chunk, layout, type, pos, placed, 0.55, 0.0, false, size)
			cursor += along_w + _rng.randf_range(16.0, 42.0)
	# Patio interior: algun muro o esquina suelta para dar profundidad.
	if _rng.randf() < 0.4:
		_try_place(chunk, layout, wall, rect.get_center() + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40)), placed, 0.6)


## Coches aparcados en fila pegados al bordillo: cursor a lo largo de la banda con
## el LARGO REAL de cada coche + hueco aleatorio, saltando los tramos cercanos a
## intersecciones (donde estan las cebras). allow_on_road permite pisar el asfalto
## reservado de la via, pero el footprint sigue valido contra todo lo demas.
func _place_parked_cars(chunk: Node2D, layout: Dictionary, car: ObstacleData, band: Rect2, axis: StringName, placed: Array[Rect2]) -> void:
	if car == null:
		return
	var vertical: bool = axis == &"vertical"
	var start: float = band.position.y if vertical else band.position.x
	var stop: float = band.end.y if vertical else band.end.x
	var lane: float = band.get_center().x if vertical else band.get_center().y
	var intersections: Array = (layout.get("plan", {}) as Dictionary).get("intersections", [])
	var cursor: float = start + _rng.randf_range(0.0, 40.0)
	while cursor < stop:
		var size := _roll_size(car)
		var slot_center: float = cursor + size.x * 0.5
		if slot_center + size.x * 0.5 > stop:
			break
		var near_cross: bool = false
		for its in intersections:
			var its_pos: Vector2 = its["pos"]
			var along: float = its_pos.y if vertical else its_pos.x
			var cross_hw: float = float((its["h"] if vertical else its["v"])["half_width"])
			if absf(slot_center - along) < cross_hw + 110.0:
				near_cross = true
				break
		if not near_cross and _rng.randf() < 0.62:
			var pos: Vector2 = Vector2(lane, slot_center) if vertical else Vector2(slot_center, lane)
			var rot: float = (PI * 0.5 if vertical else 0.0) + _rng.randf_range(-0.05, 0.05)
			_try_place(chunk, layout, car, pos, placed, 0.5, rot, true, size)
		cursor += size.x + _rng.randf_range(22.0, 55.0)


## Nave industrial: perimetro de muros alineados con hueco de entrada + contenedores dentro.
func _place_warehouse(chunk: Node2D, layout: Dictionary, wall: ObstacleData, container: ObstacleData, rect: Rect2, placed: Array[Rect2]) -> void:
	var door_side: int = _rng.randi_range(0, 3)
	var sides := [
		{"a": rect.position, "b": Vector2(rect.end.x, rect.position.y), "rot": 0.0},
		{"a": Vector2(rect.end.x, rect.position.y), "b": rect.end, "rot": PI * 0.5},
		{"a": rect.end, "b": Vector2(rect.position.x, rect.end.y), "rot": 0.0},
		{"a": Vector2(rect.position.x, rect.end.y), "b": rect.position, "rot": PI * 0.5},
	]
	# Paso segun el largo medio real del muro: perimetro continuo sin solapes.
	var wall_avg: float = (wall.min_size.x + wall.max_size.x) * 0.5 if wall != null else 150.0
	for s in sides.size():
		var side: Dictionary = sides[s]
		var a: Vector2 = side["a"]
		var b: Vector2 = side["b"]
		var count: int = maxi(1, int(a.distance_to(b) / (wall_avg + 10.0)))
		@warning_ignore("integer_division")
		var door_index: int = count / 2  # hueco de entrada en el punto medio
		for i in count:
			if s == door_side and i == door_index:
				continue  # hueco de entrada
			var pos: Vector2 = a.lerp(b, (float(i) + 0.5) / float(count))
			# Lados verticales: tamaño transpuesto en vez de rotar (extrusion al sur).
			var size := _roll_size(wall)
			if float(side["rot"]) > 0.1:
				size = Vector2(size.y, size.x)
			_try_place(chunk, layout, wall, pos, placed, 0.3, 0.0, false, size)
	# Mercancia dentro de la nave.
	_try_place(chunk, layout, container, rect.get_center() + Vector2(-40, -20), placed, 0.5, 0.0)
	if _rng.randf() < 0.6:
		_try_place(chunk, layout, container, rect.get_center() + Vector2(55, 45), placed, 0.5, 0.0)


func _place_rect_corners(chunk: Node2D, layout: Dictionary, type: ObstacleData, rect: Rect2, placed: Array[Rect2], min_mult: float) -> void:
	for p in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, rect.position + Vector2(0, rect.size.y)]:
		_try_place(chunk, layout, type, p, placed, min_mult)


func _place_rect_edges(chunk: Node2D, layout: Dictionary, type: ObstacleData, rect: Rect2, placed: Array[Rect2], min_mult: float) -> void:
	var center := rect.position + rect.size * 0.5
	_try_place(chunk, layout, type, Vector2(center.x, rect.position.y), placed, min_mult, 0.0)
	_try_place(chunk, layout, type, Vector2(center.x, rect.position.y + rect.size.y), placed, min_mult, 0.0)
	_try_place(chunk, layout, type, Vector2(rect.position.x, center.y), placed, min_mult, PI * 0.5)
	_try_place(chunk, layout, type, Vector2(rect.position.x + rect.size.x, center.y), placed, min_mult, PI * 0.5)


## Coches en los huecos que pinta el renderer (rayas verticales cada 76 px desde
## rect.x+30): centrados entre rayas y girados 90 grados, como en un parking real.
func _place_parking_rows(chunk: Node2D, layout: Dictionary, type: ObstacleData, rect: Rect2, placed: Array[Rect2]) -> void:
	if type == null:
		return
	var rows := [rect.position.y + rect.size.y * 0.35, rect.position.y + rect.size.y * 0.65]
	for row_y in rows:
		var i: int = 0
		while true:
			var x: float = rect.position.x + 30.0 + 76.0 * (float(i) + 0.5)
			if x > rect.end.x - 30.0:
				break
			if _rng.randf() < 0.6:
				_try_place(chunk, layout, type, Vector2(x, row_y), placed, 0.4, PI * 0.5)
			i += 1


func _place_cluster_in_rect(chunk: Node2D, layout: Dictionary, type: ObstacleData, rect: Rect2, placed: Array[Rect2], count: int, min_mult: float) -> void:
	for _i in count:
		var pos := rect.position + Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y)
		_try_place(chunk, layout, type, pos, placed, min_mult, _rng.randf_range(-0.25, 0.25))


func _place_radial_group(chunk: Node2D, layout: Dictionary, type: ObstacleData, center: Vector2, placed: Array[Rect2], count: int, min_radius: float, max_radius: float, min_mult: float) -> void:
	for i in count:
		var pos := center + Vector2.RIGHT.rotated((TAU * float(i) / float(max(1, count))) + _rng.randf_range(-0.35, 0.35)) * _rng.randf_range(min_radius, max_radius)
		_try_place(chunk, layout, type, pos, placed, min_mult)


## True si el footprint pisa un area reservada. Con allow_on_road se ignoran solo
## los rects que provienen de corredores viales (layout["roads"]), nunca los demas
## (plazas, claros, patios de carga) ni los circulos (senderos, lago).
func _footprint_reserved(footprint: Rect2, layout: Dictionary, allow_on_road: bool) -> bool:
	var road_rects: Array[Rect2] = []
	if allow_on_road:
		for road in layout.get("roads", []):
			if road.has("rect"):
				road_rects.append(road["rect"] as Rect2)
	for rect in layout.get("reserved_rects", []):
		var r := rect as Rect2
		if allow_on_road and r in road_rects:
			continue
		if footprint.intersects(r):
			return true
	for circle in layout.get("reserved_circles", []):
		var c: Vector2 = circle.get("center", Vector2.ZERO)
		var radius: float = float(circle.get("radius", 0.0))
		# Circulo vs rect: distancia del centro al punto mas cercano del rect.
		var closest := Vector2(
			clampf(c.x, footprint.position.x, footprint.end.x),
			clampf(c.y, footprint.position.y, footprint.end.y)
		)
		if c.distance_to(closest) <= radius:
			return true
	return false


func _chunk_obstacle_budget() -> int:
	# Presupuesto mayor que antes: el footprint check rechaza mas intentos y las
	# fachadas empaquetadas necesitan margen para completarse.
	var base: int = int(round(lerpf(12.0, 19.0, clampf(_map.obstacle_density, 0.0, 1.0))))
	if _map.biome == &"industrial":
		base += 2
	elif _map.biome == &"park":
		base += 1
	return base


func _park_path_y(chunk_x: int) -> float:
	return CHUNK_SIZE.y * 0.5 + sin(float(chunk_x) * 0.9) * 120.0


func _world_to_chunk(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CHUNK_SIZE.x), floori(pos.y / CHUNK_SIZE.y))


func _random_sign() -> float:
	return 1.0 if _rng.randf() < 0.5 else -1.0


func _find_player() -> Node2D:
	var by_name := get_parent().get_node_or_null("Player") if get_parent() != null else null
	if by_name is Node2D:
		return by_name
	if not is_inside_tree():
		return null
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node2D:
		return players[0]
	return null


func _count_active_obstacles() -> int:
	var total: int = 0
	for chunk in _chunks.values():
		if is_instance_valid(chunk):
			var obstacles: Node = chunk.get_node_or_null("Obstacles")
			total += obstacles.get_child_count() if obstacles != null else 0
	return total


func _valid_types(map_data: MapData) -> Array:
	var out: Array = []
	for t in map_data.obstacle_types:
		if t == null:
			continue
		if not map_data.allow_large_blocks and (t.category == &"house" or t.category == &"wall"):
			continue
		out.append(t)
	return out


func _first_type(types: Array, cats: Array) -> ObstacleData:
	for cat in cats:
		for t in types:
			if t.category == cat:
				return t
	return types[0] if not types.is_empty() else null


func is_point_clear(pos: Vector2, radius: float) -> bool:
	for chunk in _chunks.values():
		if not is_instance_valid(chunk):
			continue
		var obstacles: Node = chunk.get_node_or_null("Obstacles")
		if obstacles == null:
			continue
		for child in obstacles.get_children():
			if not is_instance_valid(child) or not (child is Node2D):
				continue
			var block: float = 40.0
			if child.has_method("get_block_radius"):
				block = float(child.get_block_radius())
			if pos.distance_to((child as Node2D).global_position) < block + radius:
				return false
	return true


func get_active_chunk_count() -> int:
	return _chunks.size()


func get_active_obstacle_count() -> int:
	return _count_active_obstacles()


func get_resolved_seed() -> int:
	return _resolved_seed


## MapData activo (lo usa el minimapa para reconstruir el trazado del terreno
## con las MISMAS funciones puras de CityPlan/BiomeLayoutGenerator).
func get_map_data() -> MapData:
	return _map


func set_debug_draw(enabled: bool) -> void:
	debug_draw_enabled = enabled
	queue_redraw()


func _draw() -> void:
	if not debug_draw_enabled:
		return
	for coord in _layouts.keys():
		var layout: Dictionary = _layouts[coord]
		var origin := Vector2(coord) * CHUNK_SIZE
		draw_rect(Rect2(origin, CHUNK_SIZE), Color(0.25, 0.8, 1.0, 0.08), false, 2.0)
		for rect in layout.get("reserved_rects", []):
			draw_rect(Rect2(origin + (rect as Rect2).position, (rect as Rect2).size), Color(0.2, 0.8, 0.4, 0.10), true)
		for anchor in layout.get("anchors", []):
			var center: Vector2 = origin + anchor.get("center", Vector2.ZERO)
			draw_circle(center, 10.0, Color(1.0, 0.8, 0.2, 0.75))
		for line in layout.get("debug_lines", []):
			if line is Array and line.size() >= 2:
				for i in range(line.size() - 1):
					draw_line(origin + line[i], origin + line[i + 1], Color(1.0, 1.0, 1.0, 0.3), 3.0)
