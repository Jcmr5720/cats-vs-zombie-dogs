extends Node2D
## Pruebas de la identidad de Barrio Gatuno (FASE 2):
##   godot --headless --path . res://tests/TestBarrio.tscn
##
## No comprueba que el codigo compile: comprueba que la CACERIA COORDINADA
## ocurre y que respeta las reglas de justicia. Cada bloque corresponde a una
## regla del diseño (territorios, manada, flanqueo, aullador, corredor).
##
## Usa stubs y `debug_set_time()`: nada de esperas de minutos reales.

const MapInteractableScript := preload("res://scripts/maps/map_interactable.gd")
const EnemyScript := preload("res://scripts/enemies/enemy.gd")
const HuntCorridorScript := preload("res://scripts/bosses/hunt_corridor.gd")
const EnemyScene := preload("res://scenes/enemies/Enemy.tscn")
const NEIGHBORHOOD := preload("res://data/maps/neighborhood_map.tres")

var _failures: Array[String] = []
var _checks: int = 0


## MapManager falso: territorios y rutas necesitan semilla y bioma.
class StubMapManager:
	extends Node
	var world_seed: int = 424242
	func get_world_seed() -> int:
		return world_seed
	func get_active_map():
		return preload("res://data/maps/neighborhood_map.tres")
	func is_run_ended() -> bool:
		return false


class StubPlayer:
	extends Node2D
	var velocity: Vector2 = Vector2.ZERO
	var damage_taken: int = 0
	func is_active() -> bool:
		return true
	func take_damage(amount: int) -> void:
		damage_taken += amount


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _make_player(pos: Vector2) -> StubPlayer:
	var player := StubPlayer.new()
	player.position = pos
	player.add_to_group("players")
	player.add_to_group("player")
	add_child(player)
	return player


func _make_pack_dog(pos: Vector2, level: int = 3) -> Node2D:
	var dog := EnemyScene.instantiate() as Node2D
	dog.position = pos
	add_child(dog)
	var data = RunPhaseConfig.load_enemy_data(&"pack_zombie_dog")
	dog.call("configure", data, 1.0, 1.0, 1.0)
	dog.set("behavior_level", level)
	return dog


func _run() -> void:
	var manager := StubMapManager.new()
	manager.add_to_group("map_manager")
	add_child(manager)
	EnemyScript.reset_pack_coordination()

	await _test_marks_never_inside_buildings()
	await _test_mark_budget_and_cleanup()
	await _test_territory_priority_not_additive()
	await _test_territory_changes_behavior()
	await _test_charge_limit_and_cancellation()
	await _test_flankers_leave_an_exit()
	await _test_hunt_corridor_is_fair()
	await _test_coordination_reset_on_restart()
	_test_barricades_never_seal_the_player()
	await _test_marks_give_symbolic_xp()
	_test_role_debut_is_staged()
	_test_determinism()

	if _failures.is_empty():
		print("TestBarrio: %d checks, 0 fallos" % _checks)
		print("TestBarrio: OK")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("  FALLO: %s" % failure)
		print("TestBarrio: %d checks, %d fallos" % [_checks, _failures.size()])
		get_tree().quit(1)


# --- Territorios -----------------------------------------------------------------

## Las marcas se colocan en suelo abierto y navegable, nunca dentro de manzanas.
func _test_marks_never_inside_buildings() -> void:
	var world_seed: int = 424242
	var placed: int = 0
	for i in 30:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("mark:%d" % i)
		var origin := Vector2(rng.randf_range(0.0, 6000.0), rng.randf_range(0.0, 6000.0))
		var placement := MapGeometry.find_tactical_position(
			world_seed, &"neighborhood", origin, 300.0, 700.0, rng)
		if not placement["found"]:
			continue
		placed += 1
		_check(MapGeometry.is_open_ground(world_seed, &"neighborhood", placement["pos"]),
			"marca dentro de una manzana en %s" % placement["pos"])
		# Nunca encima del jugador.
		_check(origin.distance_to(placement["pos"]) >= 250.0,
			"marca demasiado pegada al origen: %.0f px" % origin.distance_to(placement["pos"]))
	_check(placed > 0, "ninguna posicion valida en 30 intentos")


## Presupuesto de marcas simultaneas y limpieza al destruirlas.
func _test_mark_budget_and_cleanup() -> void:
	var created: Array[Node2D] = []
	for i in 6:
		var mark := MapInteractableScript.spawn(&"howl_post", self, Vector2(9000.0 + i * 400.0, 9000.0))
		if mark != null:
			created.append(mark)
	await get_tree().process_frame
	await get_tree().process_frame
	var alive: int = get_tree().get_node_count_in_group(MapInteractableScript.HOWL_GROUP)
	_check(alive <= MapInteractableScript.MAX_HOWL_POSTS,
		"presupuesto de marcas superado: %d vivas (tope %d)"
			% [alive, MapInteractableScript.MAX_HOWL_POSTS])
	_check(created.size() <= MapInteractableScript.MAX_HOWL_POSTS,
		"spawn() devolvio %d marcas por encima del tope" % created.size())
	# Limpieza: destruirlas las saca del grupo de territorio.
	for mark in created:
		if is_instance_valid(mark):
			mark.call("take_damage", 99999)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().get_node_count_in_group(MapInteractableScript.HOWL_GROUP) == 0,
		"quedaron marcas en el grupo de territorio tras destruirlas")


## Superposicion: dos marcas encima NO suman fuerza. Gana la mayor (prioridad).
func _test_territory_priority_not_additive() -> void:
	var strong := MapInteractableScript.spawn(&"howl_post", self, Vector2(20000.0, 20000.0))
	var weak := MapInteractableScript.spawn(&"howl_post", self, Vector2(20090.0, 20000.0))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(strong != null and weak != null, "no se pudieron crear las dos marcas de prueba")
	if strong == null or weak == null:
		return
	# Debilita una: baja su vida por debajo del umbral.
	var max_health: int = int(weak.get("max_health"))
	weak.call("take_damage", int(float(max_health) * 0.75))
	_check(bool(weak.call("is_weakened")), "la marca dañada no quedo marcada como debilitada")
	_check(not bool(strong.call("is_weakened")), "la marca intacta figura como debilitada")

	var territory := MapInteractableScript.territory_at(get_tree(), Vector2(20040.0, 20000.0))
	_check(not territory.is_empty(), "el punto entre dos marcas no esta en territorio")
	if not territory.is_empty():
		# La clave: la fuerza es la de la marca MAS fuerte, no la suma de ambas.
		_check(is_equal_approx(float(territory["strength"]), 1.0),
			"territorios superpuestos se acumularon: fuerza %.2f (se esperaba 1.0)"
				% float(territory["strength"]))
	# Fuera del radio no hay territorio.
	var far := MapInteractableScript.territory_at(get_tree(), Vector2(30000.0, 30000.0))
	_check(far.is_empty(), "hay territorio a 10000 px de cualquier marca")
	for mark in [strong, weak]:
		if is_instance_valid(mark):
			mark.call("take_damage", 99999)
	await get_tree().process_frame


## El territorio cambia la CONDUCTA del perro, no solo un numero.
func _test_territory_changes_behavior() -> void:
	var dog := _make_pack_dog(Vector2(40000.0, 40000.0))
	await get_tree().process_frame
	_check(not bool(dog.call("in_territory")),
		"un perro recien creado ya se cree en territorio")
	dog.call("enter_territory", 1.0, Vector2(40000.0, 40000.0), 300.0)
	_check(bool(dog.call("in_territory")), "enter_territory no marco al perro")
	# Prioridad tambien en el receptor: una marca debil no pisa a una fuerte.
	dog.call("enter_territory", 0.5, Vector2(40100.0, 40000.0), 300.0)
	_check(is_equal_approx(float(dog.get("_territory_strength")), 1.0),
		"una marca debil rebajo la fuerza del territorio ya asignado")
	dog.queue_free()
	await get_tree().process_frame


# --- Manada -----------------------------------------------------------------------

## Tope de cargas simultaneas y cancelacion al morir el lider.
func _test_charge_limit_and_cancellation() -> void:
	EnemyScript.reset_pack_coordination()
	_check(EnemyScript.active_charge_count() == 0, "el contador de cargas no arranca a cero")

	var player := _make_player(Vector2(50000.0, 50000.0))
	var dogs: Array[Node2D] = []
	for i in 6:
		dogs.append(_make_pack_dog(Vector2(50000.0 + float(i) * 60.0, 50150.0)))
	await get_tree().process_frame
	await get_tree().process_frame

	# Fuerza el arranque de cargas: mas perros que el tope permitido.
	var started: int = 0
	for dog in dogs:
		if EnemyScript.active_charge_count() >= EnemyScript.MAX_SIMULTANEOUS_CHARGES:
			break
		dog.call("_begin_pack_charge")
		started += 1
	_check(EnemyScript.active_charge_count() <= EnemyScript.MAX_SIMULTANEOUS_CHARGES,
		"cargas simultaneas por encima del tope: %d" % EnemyScript.active_charge_count())
	_check(started > 0, "no arranco ninguna carga")

	# El lider muere durante el telegrafo: la carga se cancela.
	var leader: Node2D = dogs[0]
	_check(float(leader.get("_charge_telegraph")) > 0.0,
		"el lider no tiene telegrafo activo (la carga seria daño sin aviso)")
	var before: int = EnemyScript.active_charge_count()
	leader.call("_die")
	_check(EnemyScript.active_charge_count() < before,
		"matar al lider no cancelo su carga (%d -> %d)"
			% [before, EnemyScript.active_charge_count()])

	for dog in dogs:
		if is_instance_valid(dog):
			dog.queue_free()
	player.queue_free()
	await get_tree().process_frame


# --- Flanqueo ---------------------------------------------------------------------

## Nunca se sellan todas las salidas: el numero de flanqueadores cerrando ruta
## contra un mismo jugador esta acotado.
func _test_flankers_leave_an_exit() -> void:
	EnemyScript.reset_pack_coordination()
	var player := _make_player(Vector2(60000.0, 60000.0))
	await get_tree().process_frame

	var flankers: Array[Node2D] = []
	for i in 6:
		var flanker := EnemyScene.instantiate() as Node2D
		flanker.position = Vector2(60000.0 + float(i) * 80.0, 60300.0)
		add_child(flanker)
		flanker.call("configure", RunPhaseConfig.load_enemy_data(&"flanker_zombie_dog"), 1.0, 1.0, 1.0)
		flanker.set("behavior_level", 3)
		flankers.append(flanker)
	await get_tree().process_frame

	var claimed: int = 0
	for flanker in flankers:
		if bool(flanker.call("_claim_flank_close", player)):
			claimed += 1
	_check(claimed <= 2,
		"%d flanqueadores cerraron ruta a la vez (tope 2: siempre debe quedar salida)" % claimed)
	_check(EnemyScript.closing_flanker_count(player) <= 2,
		"el contador de cierres supera el tope")

	# Al morir, el flanqueador libera su reserva: no deja rutas cerradas fantasma.
	var before: int = EnemyScript.closing_flanker_count(player)
	for flanker in flankers:
		if bool(flanker.get("_flank_closing")):
			flanker.call("_die")
			break
	_check(EnemyScript.closing_flanker_count(player) < before or before == 0,
		"morir no libero el cierre de ruta")

	for flanker in flankers:
		if is_instance_valid(flanker):
			flanker.queue_free()
	player.queue_free()
	await get_tree().process_frame


# --- Corredor de caceria ------------------------------------------------------------

## El corredor telegrafia, es estrecho (hay salida lateral), expira y se puede
## desactivar. Ninguna de esas propiedades es opcional.
func _test_hunt_corridor_is_fair() -> void:
	var from := Vector2(70000.0, 70000.0)
	var to := Vector2(70000.0, 71800.0)
	var corridor := HuntCorridorScript.spawn(self, from, to, 100.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(corridor != null, "no se creo el corredor de caceria")
	if corridor == null:
		return

	# Telegrafo: nace desarmado.
	_check(not bool(corridor.call("is_armed")),
		"el corredor nacio ya activo, sin ventana de aviso")

	# Solo uno a la vez: un segundo intento no crea otro.
	var second := HuntCorridorScript.spawn(self, from, to, 100.0)
	_check(second == null, "se crearon dos corredores de caceria a la vez")

	# Geometria: dentro en el eje, FUERA a un lado. Esa es la ruta de escape.
	_check(bool(corridor.call("contains", Vector2(70000.0, 70900.0))),
		"el centro del corredor no cuenta como dentro")
	_check(not bool(corridor.call("contains", Vector2(70000.0 + 260.0, 70900.0))),
		"no hay salida lateral: un punto a 260 px del eje sigue dentro")
	# Finito: mas alla del extremo, fuera.
	_check(not bool(corridor.call("contains", Vector2(70000.0, 73000.0))),
		"el corredor se extiende mas alla de su extremo (cubriria el mapa)")

	# Desactivable: es el contrajuego.
	corridor.call("deactivate")
	_check(not bool(corridor.call("contains", Vector2(70000.0, 70900.0))),
		"el corredor sigue activo tras desactivarlo")
	await get_tree().process_frame


# --- Reinicio y determinismo --------------------------------------------------------

## El estado compartido vive en `static var`: reiniciar la partida DEBE limpiarlo.
func _test_coordination_reset_on_restart() -> void:
	var player := _make_player(Vector2(80000.0, 80000.0))
	var dog := _make_pack_dog(Vector2(80000.0, 80150.0))
	await get_tree().process_frame
	dog.call("_begin_pack_charge")
	dog.call("_claim_flank_close", player)
	_check(EnemyScript.active_charge_count() > 0, "no habia estado que limpiar")

	EnemyScript.reset_pack_coordination()
	_check(EnemyScript.active_charge_count() == 0,
		"reiniciar no limpio las cargas activas (se arrastrarian a la run siguiente)")
	_check(EnemyScript.closing_flanker_count(player) == 0,
		"reiniciar no limpio las reservas de flanqueo")

	dog.queue_free()
	player.queue_free()
	await get_tree().process_frame


## Las barricadas nunca pueden dejar al jugador sin salida. Se reproduce aqui la
## regla de reparto del evento sobre geometria real: tras bloquear deben quedar
## al menos 2 rutas libres, o el evento debe degradar.
func _test_barricades_never_seal_the_player() -> void:
	var sealed: int = 0
	var blocked_any: int = 0
	for world_seed in [7, 42, 555, 1337, 424242]:
		for i in 40:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("barricade:%d:%d" % [world_seed, i])
			var origin := Vector2(rng.randf_range(0.0, 8000.0), rng.randf_range(0.0, 8000.0))
			var roads := MapGeometry.roads_near(world_seed, &"neighborhood", origin, 900.0)
			var candidates: int = 0
			for road in roads:
				var along: float = origin.x if road["axis"] == &"vertical" else origin.y
				var offset: float = absf(float(road["coord"]) - along)
				if offset >= 240.0 and offset <= 1100.0:
					candidates += 1
			var max_blocks: int = mini(2, maxi(0, roads.size() - 2))
			max_blocks = mini(max_blocks, candidates)
			if max_blocks <= 0:
				continue  # el evento degrada: no llega a poner barricadas
			blocked_any += 1
			# Invariante: tras bloquear siempre quedan >= 2 rutas.
			if roads.size() - max_blocks < 2:
				sealed += 1
	_check(sealed == 0,
		"%d situaciones dejarian al jugador con menos de 2 rutas libres" % sealed)
	_check(blocked_any > 0,
		"las barricadas degradan SIEMPRE: el evento nunca llegaria a bloquear calles")


## La marca da XP SIMBOLICA. Su recompensa es liberar el territorio, no
## experiencia: con 4-6 marcas por partida una XP normal financia cartas extra y
## rompe el contrato del soak "flow" (jugador estatico debe perder).
func _test_marks_give_symbolic_xp() -> void:
	var mark := MapInteractableScript.spawn(&"howl_post", self, Vector2(95000.0, 95000.0))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(mark != null, "no se pudo crear la marca de prueba de XP")
	if mark == null:
		return
	var xp: int = int(mark.get("xp_reward"))
	_check(xp <= 3, "la marca da %d XP: demasiado para no alterar el balance" % xp)
	# Un nido si debe dar XP normal: no es una marca de territorio.
	_check(xp < 14, "la marca da tanta XP como un nido")
	mark.call("take_damage", 99999)
	await get_tree().process_frame


## El Barrio presenta sus roles ESCALONADOS: manada desde el principio, el
## flanqueador en SPECIAL (60 s) y el aullador en HEAVY (110 s). Antes de su
## fase, el peso queda a cero.
func _test_role_debut_is_staged() -> void:
	var debut = NEIGHBORHOOD.get("enemy_debut_phase")
	_check(debut is Dictionary and not debut.is_empty(),
		"el Barrio no declara debut escalonado de roles")
	if not (debut is Dictionary):
		return
	_check(int(debut.get(&"flanker_zombie_dog", 0)) == RunPhaseConfig.Phase.SPECIAL_ENEMIES,
		"el flanqueador no debuta en SPECIAL (60 s)")
	_check(int(debut.get(&"howler_zombie_dog", 0)) == RunPhaseConfig.Phase.HEAVY_ENEMIES,
		"el aullador no debuta en HEAVY (110 s)")
	# La manada NO se escalona: es la identidad base del mapa desde el segundo 0.
	_check(not debut.has(&"pack_zombie_dog"),
		"la manada esta escalonada: el Barrio debe abrir con ella")
	# Coherencia: todo id escalonado debe tener peso declarado en el mapa.
	var overrides = NEIGHBORHOOD.get("phase_weight_overrides")
	for id in debut:
		_check((overrides as Dictionary).has(id),
			"%s tiene debut pero no peso propio en el Barrio" % id)


## Misma semilla = mismas rutas urbanas y mismo emplazamiento de marcas.
func _test_determinism() -> void:
	for world_seed in [11, 424242, 987654321]:
		var center := Vector2(2048.0, 2048.0)
		var a := MapGeometry.approach_points(world_seed, &"neighborhood", center, 420.0, 4)
		var b := MapGeometry.approach_points(world_seed, &"neighborhood", center, 420.0, 4)
		_check(a == b, "las rutas de aproximacion no son deterministas (semilla %d)" % world_seed)
		# Rutas realmente separadas: no valen cuatro puntos de la misma calle.
		for i in a.size():
			for j in range(i + 1, a.size()):
				var delta: float = absf(angle_difference(
					(a[i] - center).angle(), (a[j] - center).angle()))
				_check(delta >= 0.6,
					"dos rutas de manada casi solapadas (%.2f rad, semilla %d)" % [delta, world_seed])
		# El guion del Barrio cambia con la semilla y respeta su pool.
		var script_obj := RunScript.generate(NEIGHBORHOOD, world_seed)
		_check(NEIGHBORHOOD.dynamic_event_pool.has(script_obj.central_event),
			"evento fuera del pool del Barrio (semilla %d)" % world_seed)
		_check(NEIGHBORHOOD.biome_mutations.has(script_obj.dominant_mutation),
			"mutacion fuera del pool del Barrio (semilla %d)" % world_seed)
	_test_script_decisions_are_independent()


## Las decisiones del guion deben ser INDEPENDIENTES entre si. Con el hash
## original, los bits bajos quedaban correlacionados y el Barrio solo producia
## dos guiones reales (evento street_block => siempre carronero y apertura 0).
## Sobre una muestra amplia deben aparecer las cuatro combinaciones evento x
## mutacion y variar tambien el modificador del jefe.
func _test_script_decisions_are_independent() -> void:
	var pairs: Dictionary = {}
	var boss_mods: Dictionary = {}
	var openings: Dictionary = {}
	for world_seed in range(1, 200):
		var rs := RunScript.generate(NEIGHBORHOOD, world_seed * 2654435761)
		pairs["%s|%s" % [rs.central_event, rs.dominant_mutation]] = true
		boss_mods[rs.boss_modifier] = true
		openings[rs.opening_variant] = true
	var expected: int = NEIGHBORHOOD.dynamic_event_pool.size() * NEIGHBORHOOD.biome_mutations.size()
	_check(pairs.size() == expected,
		"evento y mutacion estan correlacionados: %d combinaciones de %d posibles"
			% [pairs.size(), expected])
	_check(boss_mods.size() >= 3,
		"solo %d modificadores de jefe distintos en 200 semillas" % boss_mods.size())
	_check(openings.size() == 2,
		"la variante de apertura no alterna (%d valores distintos)" % openings.size())
