extends SceneTree
## Test headless de la capa de geometria de gameplay (FASE 11):
##   godot --headless -s tests/test_map_geometry.gd
##
## Todo aqui es puro (sin autoloads ni arbol): MapGeometry solo traduce CityPlan
## a coordenadas globales. Lo que se valida es justamente lo que faltaba antes:
## que el emplazamiento sea COHERENTE CON EL MAPA y determinista por semilla.

const SEEDS := [1337, 424242, 987654321, 55, 7919]

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	_test_roads_are_global()
	_test_open_ground_excludes_blocks()
	_test_approach_points_use_streets()
	_test_approach_points_are_distinct_routes()
	_test_park_has_no_streets_but_has_trails()
	_test_lake_is_global_and_stable()
	_test_placement_never_inside_a_building()
	_test_determinism()
	_test_rail_follows_the_track()
	print("test_map_geometry: %d checks, %d fallos" % [_checks, _failures])
	if _failures > 0:
		push_error("test_map_geometry: FALLO")
		quit(1)
	else:
		print("test_map_geometry: OK")
		quit(0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("  FALLO: %s" % message)


## Las vias devueltas viven en la reticula GLOBAL (x = index * GRID), que es lo
## que permite que gameplay y renderer hablen del mismo sitio.
func _test_roads_are_global() -> void:
	for world_seed in SEEDS:
		var origin := Vector2(4096.0, -2048.0)
		var roads := MapGeometry.roads_near(world_seed, &"neighborhood", origin, 1024.0)
		_check(not roads.is_empty(), "semilla %d: no hay calles cerca del origen" % world_seed)
		for road in roads:
			var coord: float = float(road["coord"])
			_check(is_equal_approx(fmod(absf(coord), CityPlan.GRID), 0.0)
					or is_equal_approx(fmod(absf(coord), CityPlan.GRID), CityPlan.GRID),
				"via fuera de la reticula global: %f" % coord)
			var along: float = origin.x if road["axis"] == &"vertical" else origin.y
			_check(absf(coord - along) <= 1024.0 + CityPlan.GRID,
				"via devuelta fuera del span pedido")


## El interior de las manzanas NO es suelo abierto: ahi es donde hay edificios.
## Es el bug que hacia aparecer marcas de aullido encima de las casas.
func _test_open_ground_excludes_blocks() -> void:
	for world_seed in SEEDS:
		var found_block: bool = false
		var found_road: bool = false
		# Barrido de una zona amplia: debe haber de los dos tipos de suelo.
		for x in range(0, 4096, 128):
			for y in range(0, 4096, 128):
				var pos := Vector2(float(x), float(y))
				var open: bool = MapGeometry.is_open_ground(world_seed, &"neighborhood", pos)
				var lot := MapGeometry.lot_at(world_seed, &"neighborhood", pos)
				_check(open != (not lot.is_empty()),
					"is_open_ground y lot_at se contradicen en %s" % pos)
				if lot.is_empty():
					found_road = true
				else:
					found_block = true
		_check(found_block, "semilla %d: no se encontro ninguna manzana" % world_seed)
		_check(found_road, "semilla %d: no se encontro ningun suelo abierto" % world_seed)


## Los puntos de aproximacion caen SOBRE el corredor de una calle: la manada
## llega por la calle, no atravesando el salon de una casa.
func _test_approach_points_use_streets() -> void:
	for world_seed in SEEDS:
		var center := Vector2(2048.0, 2048.0)
		var points := MapGeometry.approach_points(world_seed, &"neighborhood", center, 900.0, 4)
		_check(not points.is_empty(),
			"semilla %d: sin rutas de aproximacion en el Barrio" % world_seed)
		for point in points:
			var corridor := MapGeometry.road_corridor_at(world_seed, &"neighborhood", point)
			_check(not corridor.is_empty(),
				"punto de aproximacion %s fuera de calle (semilla %d)" % [point, world_seed])
			_check(absf(center.distance_to(point) - 900.0) < 2.0,
				"punto de aproximacion fuera del anillo pedido")


## Rutas DISTINTAS: el reparto angular evita cuatro puntos de la misma avenida.
func _test_approach_points_are_distinct_routes() -> void:
	for world_seed in SEEDS:
		var center := Vector2(2048.0, 2048.0)
		var points := MapGeometry.approach_points(world_seed, &"neighborhood", center, 900.0, 4)
		for i in points.size():
			for j in range(i + 1, points.size()):
				var delta: float = absf(angle_difference(
					(points[i] - center).angle(), (points[j] - center).angle()))
				_check(delta >= 0.6,
					"dos rutas separadas solo %.2f rad (semilla %d)" % [delta, world_seed])


## El Parque no tiene calles por diseño: sus rutas salen de los senderos.
func _test_park_has_no_streets_but_has_trails() -> void:
	for world_seed in SEEDS:
		_check(MapGeometry.roads_near(world_seed, &"park", Vector2(1000, 1000), 2048.0).is_empty(),
			"el Parque devolvio calles")
		_check(MapGeometry.lot_at(world_seed, &"park", Vector2(1000, 1000)).is_empty(),
			"el Parque devolvio manzanas")
		var trail := MapGeometry.nearest_trail_point(world_seed, Vector2(1500.0, 1500.0))
		_check(not trail.is_empty(), "semilla %d: el Parque no tiene senderos" % world_seed)
		if not trail.is_empty():
			_check((trail["dir"] as Vector2).is_normalized(),
				"la direccion del sendero no esta normalizada")


## El lago se devuelve en coordenadas globales y coincide con lo que dice
## CityPlan para su chunk: el evento del lago puede anclarse a el.
func _test_lake_is_global_and_stable() -> void:
	var lakes_found: int = 0
	for world_seed in SEEDS:
		for cx in range(0, 4):
			for cy in range(0, 4):
				var probe := Vector2(cx * CityPlan.CHUNK.x + 512.0, cy * CityPlan.CHUNK.y + 512.0)
				var lake := MapGeometry.lake_near(world_seed, probe)
				if lake.is_empty():
					continue
				lakes_found += 1
				_check(float(lake["radius"]) > 0.0, "lago con radio no positivo")
				# Consultado desde su propio centro debe devolver el mismo lago.
				var again := MapGeometry.lake_near(world_seed, lake["center"])
				_check(not again.is_empty() and (again["center"] as Vector2).is_equal_approx(lake["center"]),
					"el lago no es estable al consultarlo desde su centro")
	_check(lakes_found > 0, "ninguna semilla genero lago en la region barrida")


## Contrato central: si find_open_position dice que encontro sitio, ese sitio
## NUNCA esta dentro de un edificio.
func _test_placement_never_inside_a_building() -> void:
	for world_seed in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed
		for i in 40:
			var origin := Vector2(rng.randf_range(0.0, 8192.0), rng.randf_range(0.0, 8192.0))
			var result := MapGeometry.find_open_position(
				world_seed, &"neighborhood", origin, 480.0, 640.0, rng)
			if not result["found"]:
				continue
			var pos: Vector2 = result["pos"]
			_check(MapGeometry.is_open_ground(world_seed, &"neighborhood", pos),
				"find_open_position devolvio un punto dentro de una manzana: %s" % pos)
			var distance: float = origin.distance_to(pos)
			_check(distance >= 479.0 and distance <= 641.0,
				"find_open_position devolvio %f, fuera del anillo [480,640]" % distance)


## Misma semilla = misma geometria; semillas distintas = geometria distinta.
func _test_determinism() -> void:
	var center := Vector2(3000.0, 3000.0)
	for world_seed in SEEDS:
		var a := MapGeometry.approach_points(world_seed, &"neighborhood", center, 900.0, 4)
		var b := MapGeometry.approach_points(world_seed, &"neighborhood", center, 900.0, 4)
		_check(a == b, "approach_points no es determinista (semilla %d)" % world_seed)
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = 99
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = 99
		var pa := MapGeometry.find_open_position(world_seed, &"neighborhood", center, 400.0, 600.0, rng_a)
		var pb := MapGeometry.find_open_position(world_seed, &"neighborhood", center, 400.0, 600.0, rng_b)
		_check(pa["pos"].is_equal_approx(pb["pos"]),
			"find_open_position no es determinista con el mismo rng")
	# Semillas distintas deben dar plantas urbanas distintas.
	var signatures: Dictionary = {}
	for world_seed in SEEDS:
		signatures[str(MapGeometry.approach_points(world_seed, &"neighborhood", center, 900.0, 4))] = true
	_check(signatures.size() >= 2,
		"todas las semillas dieron las mismas rutas (%d unicas)" % signatures.size())


## La via de tren existe en una de cada 3 filas de chunks y es constante en la fila.
func _test_rail_follows_the_track() -> void:
	for world_seed in SEEDS:
		var rows_with_rail: int = 0
		for row in range(0, 9):
			var probe := Vector2(1234.0, float(row) * CityPlan.CHUNK.y + 100.0)
			var y: float = MapGeometry.rail_y_near(world_seed, probe)
			if is_nan(y):
				continue
			rows_with_rail += 1
			# Misma fila consultada desde otra X: misma via.
			var other := MapGeometry.rail_y_near(world_seed, Vector2(9999.0, probe.y))
			_check(not is_nan(other) and is_equal_approx(other, y),
				"la via de tren cambia de Y dentro de la misma fila")
		_check(rows_with_rail > 0, "semilla %d: ninguna fila tiene via de tren" % world_seed)
