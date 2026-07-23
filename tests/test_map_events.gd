extends Node2D
## Valida el CABLEADO de la identidad de mapa (FASE 11) en ejecucion real:
##   godot --headless --path . res://tests/TestMapEvents.tscn
##
## El test que faltaba. `test_map_identity` comprueba que el guion ELIGE bien;
## este comprueba que lo elegido SE EJECUTA: que el evento central dispara una
## sola vez en su ventana con el id del guion, y que los interactables aparecen
## en su horario y en suelo abierto (nunca dentro de una manzana).
##
## Usa el `debug_set_time()` del director en vez de esperar 115 s de reloj.

const PhaseDirectorScript := preload("res://scripts/systems/phase_director.gd")
const NEIGHBORHOOD := preload("res://data/maps/neighborhood_map.tres")
const PARK := preload("res://data/maps/park_map.tres")

var _failures: Array[String] = []
var _checks: int = 0


class StubSpawner:
	extends Node
	var packs: Array = []
	var profiles: Array = []
	func set_phase_profile(p: Dictionary) -> void:
		profiles.append(p)
	func spawn_pack(id: StringName, count: int) -> int:
		packs.append([id, count])
		return count
	func start_horde(_d: float, _i: float) -> void:
		pass


class StubBossSpawner:
	extends Node2D
	signal boss_defeated(data)
	signal miniboss_defeated(data)
	func spawn_miniboss(_d = null) -> Node2D:
		return null
	func spawn_boss(_d = null) -> Node2D:
		return null


class StubHud:
	extends Node
	var messages: Array = []
	func set_phase_info(_t: String) -> void:
		pass
	func show_event_message(t: String, _d: float = 1.8) -> void:
		messages.append(t)
	func show_announcement(t: String, _d: float = 1.8) -> void:
		messages.append(t)
	func show_boss_bar(_n: String, _m: int) -> void:
		pass


## Registra los eventos centrales pedidos: es lo que queremos observar.
class StubWaveEvents:
	extends Node
	var triggered: Array = []
	func set_external_director(_a: bool) -> void:
		pass
	func trigger_map_event(id: StringName) -> void:
		triggered.append(id)


class StubMapManager:
	extends Node
	var map_data = null
	var world_seed: int = 0
	var script_obj: RunScript
	func is_run_ended() -> bool:
		return false
	func force_run_end(_v: bool) -> void:
		pass
	func get_active_map():
		return map_data
	func get_world_seed() -> int:
		return world_seed
	func get_run_script() -> RunScript:
		return script_obj


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _build_rig(suffix: String, map_data, world_seed: int) -> Dictionary:
	var spawner := StubSpawner.new()
	spawner.name = "Spawner" + suffix
	add_child(spawner)
	var boss_spawner := StubBossSpawner.new()
	boss_spawner.name = "BossSpawner" + suffix
	add_child(boss_spawner)
	var hud := StubHud.new()
	hud.name = "Hud" + suffix
	add_child(hud)
	var events := StubWaveEvents.new()
	events.name = "Events" + suffix
	add_child(events)
	var map_mgr := StubMapManager.new()
	map_mgr.name = "MapMgr" + suffix
	map_mgr.map_data = map_data
	map_mgr.world_seed = world_seed
	map_mgr.script_obj = RunScript.generate(map_data, world_seed)
	add_child(map_mgr)
	var director := Node.new()
	director.name = "Director" + suffix
	director.set_script(PhaseDirectorScript)
	director.set("hud_path", NodePath("../Hud" + suffix))
	director.set("enemy_spawner_path", NodePath("../Spawner" + suffix))
	director.set("boss_spawner_path", NodePath("../BossSpawner" + suffix))
	director.set("wave_event_manager_path", NodePath("../Events" + suffix))
	director.set("map_manager_path", NodePath("../MapMgr" + suffix))
	add_child(director)

	return {
		"spawner": spawner, "hud": hud, "events": events,
		"map": map_mgr, "director": director,
	}


## Jugador falso: el emplazamiento de interactables lo necesita como origen.
func _make_player(pos: Vector2) -> Node2D:
	var player := Node2D.new()
	player.add_to_group("player")
	player.global_position = pos
	add_child(player)
	return player


func _run() -> void:
	_test_central_event_fires_once()
	_test_central_event_matches_script()
	await _test_openings_differ_between_maps()
	# Coroutine: el emplazamiento usa add_child diferido y necesita pasar frames.
	await _test_interactables_land_on_open_ground()
	_test_same_seed_same_wiring()

	if _failures.is_empty():
		print("TestMapEvents: %d checks, 0 fallos" % _checks)
		print("TestMapEvents: OK")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("  FALLO: %s" % failure)
		print("TestMapEvents: %d checks, %d fallos" % [_checks, _failures.size()])
		get_tree().quit(1)


## Exactamente UN evento central por partida, y solo despues de su tiempo.
func _test_central_event_fires_once() -> void:
	var rig := _build_rig("A", NEIGHBORHOOD, 123456)
	var director: Node = rig["director"]
	var events: StubWaveEvents = rig["events"]

	director.debug_set_time(RunPhaseConfig.CENTRAL_EVENT_TIME - 5.0)
	director._process(0.1)
	_check(events.triggered.is_empty(),
		"el evento central disparo ANTES de su ventana (%s)" % str(events.triggered))

	director.debug_set_time(RunPhaseConfig.CENTRAL_EVENT_TIME + 1.0)
	director._process(0.1)
	_check(events.triggered.size() == 1,
		"tras la ventana se esperaba 1 evento, hubo %d" % events.triggered.size())

	# Muchos frames despues: sigue siendo uno solo (no se repite por frame).
	for i in 30:
		director.debug_set_time(RunPhaseConfig.CENTRAL_EVENT_TIME + 2.0 + float(i))
		director._process(0.1)
	_check(events.triggered.size() == 1,
		"el evento central se repitio: %d disparos" % events.triggered.size())


## El id disparado es EL DEL GUION, y pertenece al pool del mapa.
func _test_central_event_matches_script() -> void:
	for world_seed in [11, 2024, 987654321]:
		for map_data in [NEIGHBORHOOD, PARK]:
			var rig := _build_rig("M%d_%s" % [world_seed, map_data.id], map_data, world_seed)
			var director: Node = rig["director"]
			var events: StubWaveEvents = rig["events"]
			director.debug_set_time(RunPhaseConfig.CENTRAL_EVENT_TIME + 1.0)
			director._process(0.1)
			var expected: StringName = RunScript.generate(map_data, world_seed).central_event
			_check(events.triggered.size() == 1 and events.triggered[0] == expected,
				"%s/%d: disparo %s, el guion decia %s"
					% [map_data.id, world_seed, str(events.triggered), expected])
			_check(map_data.dynamic_event_pool.has(expected),
				"%s: el evento %s no pertenece al pool del mapa" % [map_data.id, expected])


## Barrio y Parque no abren igual: la apertura sale del MapData, no del director.
func _test_openings_differ_between_maps() -> void:
	var seeds := [7, 99, 12345]
	var rigs: Array = []
	for world_seed in seeds:
		rigs.append([
			_build_rig("ON%d" % world_seed, NEIGHBORHOOD, world_seed),
			_build_rig("OP%d" % world_seed, PARK, world_seed),
		])
	# `_start_run` (y con el la manada de apertura) va diferido desde `_ready`:
	# sin dejar pasar el frame, los spawners aun estarian vacios.
	await get_tree().process_frame
	await get_tree().process_frame
	var neighborhood_openings: Array = []
	var park_openings: Array = []
	for pair in rigs:
		neighborhood_openings.append(pair[0]["spawner"].packs.duplicate())
		park_openings.append(pair[1]["spawner"].packs.duplicate())
	for i in seeds.size():
		_check(not neighborhood_openings[i].is_empty(), "el Barrio no abrio con manada")
		_check(not park_openings[i].is_empty(), "el Parque no abrio con manada")
	# Al menos una semilla debe distinguir los dos mapas en la apertura.
	var differ: bool = false
	for i in seeds.size():
		if str(neighborhood_openings[i]) != str(park_openings[i]):
			differ = true
	_check(differ, "Barrio y Parque abrieron identico en todas las semillas")


## Contrato central del emplazamiento: los interactables nunca nacen dentro de
## una manzana. Es el bug que hacia aparecer marcas de aullido sobre las casas.
func _test_interactables_land_on_open_ground() -> void:
	var world_seed: int = 424242
	var player := _make_player(Vector2(2048.0, 2048.0))
	var rig := _build_rig("I", NEIGHBORHOOD, world_seed)
	var director: Node = rig["director"]
	var times: PackedFloat32Array = NEIGHBORHOOD.interactable_times
	_check(times.size() > 0, "el Barrio no programa interactables")

	for t in times:
		director.debug_set_time(float(t) + 1.0)
		director._process(0.1)
	# add_child es diferido: hay que dejar pasar el frame.
	await get_tree().process_frame
	await get_tree().process_frame

	var spawned: Array = []
	for child in get_children():
		if child.is_in_group("map_interactables"):
			spawned.append(child)
	_check(not spawned.is_empty(), "no aparecio ningun interactable en sus tiempos")
	for node in spawned:
		var pos: Vector2 = (node as Node2D).global_position
		_check(MapGeometry.is_open_ground(world_seed, NEIGHBORHOOD.biome, pos),
			"interactable dentro de una manzana en %s" % pos)
		_check(pos.distance_to(player.global_position) <= 800.0,
			"interactable demasiado lejos del jugador: %.0f px"
				% pos.distance_to(player.global_position))
	for node in spawned:
		node.queue_free()
	player.queue_free()


## Misma semilla = mismo cableado (evento y apertura), sin depender del azar global.
func _test_same_seed_same_wiring() -> void:
	var first := _build_rig("S1", NEIGHBORHOOD, 555)
	var second := _build_rig("S2", NEIGHBORHOOD, 555)
	for rig in [first, second]:
		rig["director"].debug_set_time(RunPhaseConfig.CENTRAL_EVENT_TIME + 1.0)
		rig["director"]._process(0.1)
	_check(str(first["events"].triggered) == str(second["events"].triggered),
		"la misma semilla disparo eventos distintos: %s vs %s"
			% [str(first["events"].triggered), str(second["events"].triggered)])
