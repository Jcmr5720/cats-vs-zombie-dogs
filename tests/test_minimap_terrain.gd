extends Node2D
## Pruebas del TERRENO del minimapa (Fase correccion).
##   godot --headless --path . res://tests/TestMinimapTerrain.tscn
## Valida, por mapa (barrio, parque, industrial):
## - El terreno se resuelve desde el generador REAL (misma seed) y dibuja vias.
## - Las calles se ALINEAN con la reticula global de CityPlan (lineas cada 512 px
##   con via confirmada por road_at_line) — no es geometria inventada.
## - El parque dibuja senderos (polilineas) y el industrial via de tren.
## - Los obstaculos grandes aparecen como SILUETAS en su posicion correcta.
## - El terreno queda DEBAJO de puntos y marcadores (no tapa entidades).
## - Compacto vs ampliado: el ampliado cubre mas mundo y muestra mas detalle.
## - La cache de layouts no crece de forma continua con el jugador quieto.
## - En coop hay dos capas de terreno (una por radar).

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"
const MAPS: Array = [
	["res://data/maps/neighborhood_map.tres", "barrio"],
	["res://data/maps/park_map.tres", "parque"],
	["res://data/maps/industrial_alley_map.tres", "industrial"],
]

var _failures: Array[String] = []
var _checks: int = 0
var _map_index: int = -1
var _level: Node
var _phase: String = "next_map"
var _wait_seconds: float = 0.0
var _next_phase: String = ""
var _done: bool = false
var _cache_size_before: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _done:
		return
	if _wait_seconds > 0.0:
		_wait_seconds -= delta
		if _wait_seconds <= 0.0:
			_phase = _next_phase
		return
	match _phase:
		"next_map":
			_load_next_map()
		"check_terrain":
			_check_terrain()
		"check_expand":
			_check_expand()
		"check_stable":
			_check_stable()
		"coop_boot":
			_boot_coop()
		"coop_check":
			_check_coop()


func _wait(seconds: float, next_phase: String) -> void:
	_wait_seconds = seconds
	_next_phase = next_phase
	_phase = "waiting"


func _controller(id: int) -> Control:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	return hud.get_node_or_null("Minimap%d" % id) as Control if hud != null else null


func _terrain(ctrl: Control) -> Control:
	return ctrl.get_node_or_null("Terrain") as Control if ctrl != null else null


func _spawner() -> Node:
	var mm: Node = get_tree().get_first_node_in_group("map_manager")
	return mm.get("_obstacle_spawner") if mm != null else null


func _load_next_map() -> void:
	_map_index += 1
	if _map_index >= MAPS.size():
		_phase = "coop_boot"
		return
	if is_instance_valid(_level):
		_level.queue_free()
	var gf: Node = get_node_or_null("/root/GameFlow")
	gf.set("game_mode", "solo")
	gf.set("selected_map", load(MAPS[_map_index][0]))
	_level = (load(MAIN_LEVEL) as PackedScene).instantiate()
	call_deferred("add_child", _level)
	_wait(1.6, "check_terrain")


func _check_terrain() -> void:
	var label: String = MAPS[_map_index][1]
	var c1 := _controller(1)
	var terrain := _terrain(c1)
	_expect(terrain != null, "%s: existe la capa de terreno" % label)
	if terrain == null:
		_phase = "next_map"
		return
	var source = terrain.get("source")
	_expect(source != null and bool(source.call("is_resolved")), "%s: la fuente resolvio mapa+seed del generador real" % label)
	var stats: Dictionary = terrain.call("get_draw_stats")
	var biome: StringName = source.call("biome") if source != null else &""

	match biome:
		&"park":
			_expect(int(stats["paths"]) > 0, "%s: dibuja senderos (%d)" % [label, int(stats["paths"])])
		&"industrial":
			_expect(int(stats["roads"]) > 0, "%s: dibuja corredores (%d)" % [label, int(stats["roads"])])
		_:
			_expect(int(stats["roads"]) > 0, "%s: dibuja calles (%d)" % [label, int(stats["roads"])])

	# Alineacion con el mapa real: cada via recta debe estar centrada en una linea
	# de la reticula global (multiplo de 512) y CityPlan debe confirmar esa via.
	var sp: Node = _spawner()
	if sp != null and biome != &"park":
		var world_seed: int = int(sp.call("get_resolved_seed"))
		var rects: Array = terrain.call("get_world_road_rects")
		var aligned: int = 0
		var confirmed: int = 0
		for r in rects:
			var rect := r as Rect2
			var vertical: bool = rect.size.y > rect.size.x
			var line_pos: float = rect.get_center().x if vertical else rect.get_center().y
			var index: int = int(round(line_pos / 512.0))
			if absf(line_pos - float(index) * 512.0) < 1.0:
				aligned += 1
				var road: Dictionary = CityPlan.road_at_line(world_seed, biome, &"v" if vertical else &"h", index)
				if not road.is_empty():
					confirmed += 1
		_expect(rects.size() > 0 and aligned == rects.size(),
			"%s: TODAS las vias en la reticula global (%d/%d)" % [label, aligned, rects.size()])
		_expect(confirmed == rects.size(),
			"%s: CityPlan confirma cada via dibujada (%d/%d)" % [label, confirmed, rects.size()])

	# Siluetas de obstaculos grandes en su sitio.
	var dots: Control = c1.get_node_or_null("Dots") as Control
	var polys: Array = dots.get("struct_polys")
	var circles = dots.get("struct_circles")
	_expect(polys.size() + (circles as PackedVector2Array).size() > 0,
		"%s: hay siluetas de estructuras (%d polys, %d circulos)" % [label, polys.size(), (circles as PackedVector2Array).size()])
	_check_silhouette_position(label, c1, dots)

	# Orden de capas: terreno por debajo de puntos y marcadores.
	var markers: Control = c1.get_node_or_null("Markers") as Control
	_expect(terrain.get_index() < dots.get_index() and dots.get_index() < markers.get_index(),
		"%s: terreno < puntos < marcadores (orden de dibujo)" % label)

	if _map_index == 0:
		_phase = "check_expand"
	else:
		_phase = "next_map"


## Busca un obstaculo grande cercano y verifica que su silueta esta donde toca.
func _check_silhouette_position(label: String, c1: Control, dots: Control) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var best: Node2D = null
	for o in get_tree().get_nodes_in_group("obstacles"):
		if not is_instance_valid(o) or not o.has_method("get_footprint_size"):
			continue
		var fsize: Vector2 = o.get_footprint_size()
		if maxf(fsize.x, fsize.y) < 64.0:
			continue
		if (o as Node2D).global_position.distance_to(player.global_position) < 900.0:
			best = o
			break
	if best == null:
		print("  (sin obstaculo grande cercano en %s: silueta posicional no comprobada)" % label)
		return
	var scale_v = c1.call("_map_scale")
	var expected: Vector2 = c1.size * 0.5 + (best.global_position - player.global_position) * float(scale_v)
	var found: bool = false
	for poly in dots.get("struct_polys"):
		var centroid := Vector2.ZERO
		for p in (poly as PackedVector2Array):
			centroid += p
		centroid /= float((poly as PackedVector2Array).size())
		if centroid.distance_to(expected) < 6.0:
			found = true
			break
	if not found:
		for i in (dots.get("struct_circles") as PackedVector2Array).size():
			if (dots.get("struct_circles") as PackedVector2Array)[i].distance_to(expected) < 6.0:
				found = true
				break
	_expect(found, "%s: la silueta del obstaculo grande esta en su posicion (%.0f px de radar)" % [label, expected.x])


func _check_expand() -> void:
	var c1 := _controller(1)
	var terrain := _terrain(c1)
	var roads_compact: int = int((terrain.call("get_draw_stats") as Dictionary)["roads"])
	var detailed_compact: bool = bool(terrain.get("_detailed"))
	c1.call("set_expanded", true)
	set_meta("roads_compact", roads_compact)
	_expect(not detailed_compact, "compacto: sin capa de detalle de manzanas")
	_wait(1.2, "check_stable")


func _check_stable() -> void:
	var c1 := _controller(1)
	var terrain := _terrain(c1)
	var stats: Dictionary = terrain.call("get_draw_stats")
	var roads_expanded: int = int(stats["roads"])
	_expect(bool(terrain.get("_detailed")), "ampliado: capa de detalle activa")
	_expect(roads_expanded > int(get_meta("roads_compact")),
		"ampliado: cubre mas mundo (%d vias vs %d)" % [roads_expanded, int(get_meta("roads_compact"))])
	c1.call("set_expanded", false)

	# Estabilidad: con el jugador quieto, la cache de layouts no debe crecer.
	var source = terrain.get("source")
	_cache_size_before = (source.get("_layouts") as Dictionary).size()
	_wait(1.5, "cache_verify")
	_next_phase = "cache_verify"
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		# El jugador puede derivar un poco por knockback de la horda: se tolera
		# la generacion puntual de algun chunk de borde, no un crecimiento continuo.
		var after: int = (source.get("_layouts") as Dictionary).size()
		_expect(after - _cache_size_before <= 2,
			"cache de terreno acotada en reposo (%d -> %d)" % [_cache_size_before, after])
		_phase = "next_map"
		_wait_seconds = 0.0)


func _boot_coop() -> void:
	if is_instance_valid(_level):
		_level.queue_free()
	var gf: Node = get_node_or_null("/root/GameFlow")
	gf.set("game_mode", "local_coop")
	gf.set("selected_map", load(MAPS[0][0]))
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		_level = (load(MAIN_LEVEL) as PackedScene).instantiate()
		add_child(_level)
		_wait(1.6, "coop_check"))
	_phase = "waiting"
	_wait_seconds = 999.0  # la espera real la corta el timer de arriba


func _check_coop() -> void:
	var t1 := _terrain(_controller(1))
	var t2 := _terrain(_controller(2))
	_expect(t1 != null and t2 != null, "coop: cada radar tiene su capa de terreno")
	if t1 != null and t2 != null:
		_expect(t1.get("source") == t2.get("source"), "coop: ambos comparten la MISMA cache de layouts")
		var s1: Dictionary = t1.call("get_draw_stats")
		_expect(int(s1["roads"]) > 0, "coop: el radar del J1 dibuja calles (%d)" % int(s1["roads"]))
	_finish()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", message)
	else:
		_failures.append(message)
		printerr("  FALLO  ", message)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("")
	print("TestMinimapTerrain: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().paused = false
	get_tree().quit(0 if _failures.is_empty() else 1)
