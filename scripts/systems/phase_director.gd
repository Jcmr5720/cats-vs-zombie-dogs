extends Node
## Director de fases (Partidas rapidas): convierte cada mapa en una partida
## corta e intensa de ~5 minutos con progresion por fases:
##   INTRO -> COMMON -> SPECIAL -> HEAVY -> MINIBOSS -> BOSS -> ELITE_BOSS
## y cierre garantizado: furia final a los 5:00 y derrota al limite absoluto
## (~5:30) si el jefe sigue vivo. Los tiempos por defecto y las composiciones
## viven CENTRALIZADOS en RunPhaseConfig; aqui solo esta la orquestacion.
##
## Reutiliza los sistemas existentes: EnemySpawner (spawn + presupuesto),
## BossSpawner (jefes + barra del HUD + musica) y MapManager (victoria/derrota y
## recompensas). El calendario clasico del WaveEventManager queda suspendido
## (set_external_director).
##
## FASE 12: tambien planta las cajas de botin (armas y suministros) en TODOS los
## mapas, en paralelo a los interactables de identidad. Las recompensas de jefe ya
## no pasan por aqui: las suelta el propio jefe a traves del LootDirector.
##
## El reloj se detiene solo con la pausa del arbol (menu), igual que el
## WaveEventManager clasico: process_mode heredado.

signal phase_changed(phase: int)

@export var hud_path: NodePath
@export var enemy_spawner_path: NodePath
@export var boss_spawner_path: NodePath
@export var wave_event_manager_path: NodePath
@export var map_manager_path: NodePath
@export var loot_director_path: NodePath

@export_group("Tiempos de fase (segundos; defaults en RunPhaseConfig)")
@export var common_start: float = RunPhaseConfig.COMMON_START
@export var special_start: float = RunPhaseConfig.SPECIAL_START
@export var heavy_start: float = RunPhaseConfig.HEAVY_START
@export var miniboss_start: float = RunPhaseConfig.MINIBOSS_START
@export var boss_start: float = RunPhaseConfig.BOSS_START
@export var elite_start: float = RunPhaseConfig.ELITE_START
@export var final_fury_start: float = RunPhaseConfig.FINAL_FURY_START
@export var absolute_limit: float = RunPhaseConfig.ABSOLUTE_LIMIT

var _hud: Node
var _spawner: Node
var _boss_spawner: Node
var _wave_events: Node
var _map_manager: Node
var _loot_director: Node

var _elapsed: float = 0.0
var _phase: int = RunPhaseConfig.Phase.INTRO
var _run_over: bool = false
var _opening_runners_done: bool = false
var _fury_started: bool = false
var _hud_tick: float = 0.0
## Jefe activo (para la transformacion elite y la furia final).
var _boss_node: Node2D
## FASE 11: evento central del guion (uno por partida) e interactables del mapa.
var _central_event_done: bool = false
var _interactable_index: int = 0
## Espera antes de reintentar un emplazamiento que no encontro suelo valido.
var _interactable_retry: float = 0.0
## FASE 12: cajas de botin. Dos listas independientes (armas y suministros) que se
## resuelven en una sola linea temporal, con su propia espera de reintento.
var _weapon_crate_index: int = 0
var _supply_crate_index: int = 0
var _crate_retry: float = 0.0
## Cadencia del volcado de telemetria (solo con RUN_TELEMETRY=1).
var _telemetry_dump: float = 30.0

const MapInteractable = preload("res://scripts/maps/map_interactable.gd")
## Solo para el reinicio de su estado estatico de coordinacion (enemy.gd no
## declara class_name, asi que se referencia por script).
const EnemyScript = preload("res://scripts/enemies/enemy.gd")


func _ready() -> void:
	add_to_group("phase_director")
	_hud = get_node_or_null(hud_path)
	_spawner = get_node_or_null(enemy_spawner_path)
	_boss_spawner = get_node_or_null(boss_spawner_path)
	_wave_events = get_node_or_null(wave_event_manager_path)
	_map_manager = get_node_or_null(map_manager_path)
	_loot_director = get_node_or_null(loot_director_path)

	# El director asume el calendario completo: sin hordas/jefes del sistema clasico.
	if is_instance_valid(_wave_events) and _wave_events.has_method("set_external_director"):
		_wave_events.set_external_director(true)

	if is_instance_valid(_boss_spawner):
		if _boss_spawner.has_signal("boss_defeated"):
			_boss_spawner.connect("boss_defeated", Callable(self, "_on_boss_defeated"))

	# Diferido: todos los sistemas (incluido MapManager con el mapa activo) deben
	# haber corrido su _ready antes de aplicar el primer perfil y la manada inicial.
	call_deferred("_start_run")


func _start_run() -> void:
	# El estado compartido de coordinacion vive en `static var` (no en nodos):
	# sobrevive a un cambio de escena. Sin este reinicio, reiniciar la partida
	# arrastraria lideres muertos, cargas fantasma y reservas de flanqueo de la
	# run anterior.
	EnemyScript.reset_pack_coordination()
	MapInteractable.reset_pending()
	# El cache de geometria es estatico: se vacia al arrancar por si cambio el
	# mapa o la semilla respecto a la partida anterior.
	MapGeometry.clear_cache()
	_apply_phase(RunPhaseConfig.Phase.INTRO)
	# Segundo 0: manada inicial fuera de camara, con ruta de escape. FASE 11: el
	# TIPO de la manada es la apertura caracteristica del mapa (la variante la
	# elige la semilla via RunScript).
	if is_instance_valid(_spawner) and _spawner.has_method("spawn_pack"):
		var count: int = randi_range(RunPhaseConfig.OPENING_PACK_MIN, RunPhaseConfig.OPENING_PACK_MAX)
		_spawner.spawn_pack(_opening_id(true), count)
	_announce("¡La horda llega! Resiste hasta el jefe")


## Id de apertura del mapa activo (pack=true: manada inicial; false: variedad del
## segundo ~8). La variante alternativa la decide el guion de la semilla.
func _opening_id(pack: bool) -> StringName:
	var fallback: StringName = &"zombie_dog" if pack else &"runner_zombie_dog"
	var map = _active_map()
	if map == null:
		return fallback
	var base: StringName = map.get("opening_pack_id") if pack else map.get("opening_variety_id")
	var alt: StringName = map.get("opening_pack_alt_id") if pack else map.get("opening_variety_alt_id")
	var rs = _run_script()
	if rs != null and int(rs.opening_variant) == 1 and alt != &"":
		return alt
	return base if base != &"" else fallback


func _active_map():
	if is_instance_valid(_map_manager) and _map_manager.has_method("get_active_map"):
		return _map_manager.get_active_map()
	return null


func _run_script():
	if is_instance_valid(_map_manager) and _map_manager.has_method("get_run_script"):
		return _map_manager.get_run_script()
	return null


## Semilla del mundo activo (la misma que usa la geometria del renderer).
func _world_seed() -> int:
	if is_instance_valid(_map_manager) and _map_manager.has_method("get_world_seed"):
		return _map_manager.get_world_seed()
	return 0


## Bioma del mapa activo: decide que geometria se consulta (calles vs senderos).
func _biome() -> StringName:
	var map = _active_map()
	return map.biome if map != null else &"neighborhood"


func _process(delta: float) -> void:
	if _run_over:
		return
	if is_instance_valid(_map_manager) and _map_manager.has_method("is_run_ended") \
			and _map_manager.is_run_ended():
		_run_over = true
		return
	_elapsed += delta

	# Segundo ~8: entra una variedad rapida (la horda no es homogenea). FASE 11:
	# el tipo lo define la apertura del mapa.
	if not _opening_runners_done and _elapsed >= RunPhaseConfig.OPENING_RUNNERS_TIME:
		_opening_runners_done = true
		# FASE 2: la variedad rapida entra por un ACCESO URBANO valido (calle o
		# interseccion fuera de camara), no por un arco aleatorio. En mapas sin
		# calles `spawn_pack_urban` cae solo al reparto clasico.
		if is_instance_valid(_spawner) and _spawner.has_method("spawn_pack_urban"):
			_spawner.spawn_pack_urban(_opening_id(false), RunPhaseConfig.OPENING_RUNNERS_COUNT, 1)
		elif is_instance_valid(_spawner) and _spawner.has_method("spawn_pack"):
			_spawner.spawn_pack(_opening_id(false), RunPhaseConfig.OPENING_RUNNERS_COUNT)

	var target: int = _phase_for_time(_elapsed)
	if target != _phase:
		_apply_phase(target)

	# FASE 11: evento central del guion (uno por partida, elegido por semilla).
	if not _central_event_done and _elapsed >= RunPhaseConfig.CENTRAL_EVENT_TIME:
		_central_event_done = true
		var rs = _run_script()
		if rs != null and rs.central_event != &"" and is_instance_valid(_wave_events) \
				and _wave_events.has_method("trigger_map_event"):
			_wave_events.trigger_map_event(rs.central_event)
			RunTelemetry.count(&"central_event_fired")
			if RunTelemetry.enabled:
				print("TELEMETRY t=%.0f central_event=%s" % [_elapsed, rs.central_event])

	# FASE 11: interactables caracteristicos del mapa (marcas de aullido, nidos,
	# lineas de produccion) en sus tiempos programados.
	_spawn_due_interactables(delta)

	# FASE 12: cajas de botin (armas y suministros). Salen en todos los mapas.
	_spawn_due_crates(delta)

	# Volcado periodico de telemetria (solo con RUN_TELEMETRY=1): un soak que se
	# interrumpe antes del final sigue dejando datos utiles.
	if RunTelemetry.enabled:
		_telemetry_dump -= delta
		if _telemetry_dump <= 0.0:
			_telemetry_dump = 30.0
			print("TELEMETRY t=%.0f %s" % [_elapsed, RunTelemetry.report_line()])

	# 5:00 — se detienen los spawns comunes y arranca la furia final.
	if not _fury_started and _elapsed >= final_fury_start:
		_start_final_fury()

	# Limite absoluto (~5:30): si el jefe sigue vivo, derrota. Sin partidas infinitas.
	if _elapsed >= absolute_limit:
		_time_out_defeat()
		return

	_hud_tick -= delta
	if _hud_tick <= 0.0:
		_hud_tick = 0.25
		_update_hud_phase()


## Fase que corresponde al reloj usando los tiempos CONFIGURADOS del nodo.
func _phase_for_time(seconds: float) -> int:
	if seconds < common_start:
		return RunPhaseConfig.Phase.INTRO
	if seconds < special_start:
		return RunPhaseConfig.Phase.COMMON_ENEMIES
	if seconds < heavy_start:
		return RunPhaseConfig.Phase.SPECIAL_ENEMIES
	if seconds < miniboss_start:
		return RunPhaseConfig.Phase.HEAVY_ENEMIES
	if seconds < boss_start:
		return RunPhaseConfig.Phase.MINIBOSS
	if seconds < elite_start:
		return RunPhaseConfig.Phase.BOSS
	return RunPhaseConfig.Phase.ELITE_BOSS


## Genera los interactables del mapa cuyo tiempo ya llego (uno por _process como
## mucho: sin rafagas). Aparecen a media distancia del jugador.
func _spawn_due_interactables(delta: float) -> void:
	if _interactable_retry > 0.0:
		_interactable_retry -= delta
		return
	var map = _active_map()
	if map == null:
		return
	var kind: StringName = map.get("interactable_kind")
	if kind == &"" or kind == null:
		return
	var times: PackedFloat32Array = map.get("interactable_times")
	if _interactable_index >= times.size():
		return
	if _elapsed < float(times[_interactable_index]):
		return
	var slot: int = _interactable_index
	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not (player is Node2D):
		# Sin jugador (respawn, todos abatidos en coop): NO se consume el slot.
		# Consumirlo aqui perdia el interactable de esa fase para toda la partida.
		_interactable_retry = 1.0
		return
	_interactable_index += 1
	var origin: Vector2 = (player as Node2D).global_position
	# FASE 11: el emplazamiento consulta la GEOMETRIA del mapa. Antes era
	# `origin + angulo aleatorio`, que plantaba marcas dentro de los edificios y
	# nidos en mitad del lago. Ahora se prefiere un punto tactico (interseccion
	# en el Barrio, cruce de sendero en el Parque) y se exige suelo abierto y
	# libre de obstaculos. El rng deriva de la semilla + el indice del slot: la
	# distribucion de interactables forma parte del guion de la partida.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("interactable:%d:%d" % [_world_seed(), slot])
	var placement := MapGeometry.find_tactical_position(
		_world_seed(), _biome(), origin, 480.0, 760.0, rng, player as Node2D)
	if not placement["found"]:
		# Sin sitio valido cerca (el jugador esta metido en una manzana cerrada):
		# se reintenta en unos segundos en vez de plantar la estructura dentro de
		# una casa. El cooldown evita repetir la busqueda cada frame.
		_interactable_index = slot
		_interactable_retry = 2.0
		return
	MapInteractable.spawn(kind, get_parent(), placement["pos"], rng)
	RunTelemetry.count(&"interactables_spawned")
	if bool(placement.get("tactical", false)):
		RunTelemetry.count(&"interactables_on_tactical_spot")
	if RunTelemetry.enabled:
		print("TELEMETRY t=%.0f interactable=%s pos=%s tactical=%s"
			% [_elapsed, kind, placement["pos"], placement.get("tactical", false)])
	match kind:
		&"howl_post":
			_announce("¡Marca de aullido! Destruyela para romper el territorio")
		&"nest":
			_announce("¡Un nido despierta!")
		&"production_line":
			_announce("¡Linea de produccion activa! Sabotea la maquina")


## Planta las cajas de botin cuyo tiempo ya llego (FASE 12). Scheduler PARALELO al
## de interactables a proposito: aquel depende de `MapData.interactable_kind` (que
## es identidad de mapa), y las cajas deben salir en TODOS los mapas.
func _spawn_due_crates(delta: float) -> void:
	if _crate_retry > 0.0:
		_crate_retry -= delta
		return
	# Se mezclan las dos listas en una sola linea temporal para no plantar dos
	# cajas a la vez ni partir el codigo en dos copias.
	var next: Dictionary = _next_crate()
	if next.is_empty() or _elapsed < float(next["time"]):
		return

	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not (player is Node2D):
		# Sin jugador (respawn, todos abatidos en coop): NO se consume el slot.
		_crate_retry = 1.0
		return

	var kind: StringName = next["kind"]
	var slot: int = int(next["slot"])
	# Semilla con SALT PROPIO ("crate:"), distinto del de los interactables: asi
	# anadir o quitar cajas no desplaza las demas decisiones de la semilla. El
	# mismo rng sortea la posicion Y el contenido, de modo que una semilla da
	# siempre las mismas armas en las mismas cajas.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("crate:%d:%s:%d" % [_world_seed(), kind, slot])
	var placement := MapGeometry.find_tactical_position(
		_world_seed(), _biome(), (player as Node2D).global_position,
		RunPhaseConfig.CRATE_MIN_DISTANCE, RunPhaseConfig.CRATE_MAX_DISTANCE,
		rng, player as Node2D)
	if not placement["found"]:
		_crate_retry = 2.0
		return

	if kind == &"weapon_crate":
		_weapon_crate_index += 1
		_announce("¡Caja de armas! Rompela para conseguir un arma")
	else:
		_supply_crate_index += 1
		_announce("¡Caja de suministros!")
	MapInteractable.spawn(kind, get_parent(), placement["pos"], rng)
	RunTelemetry.count(StringName("%ss_spawned" % kind))
	if RunTelemetry.enabled:
		print("TELEMETRY t=%.0f crate=%s pos=%s" % [_elapsed, kind, placement["pos"]])


## Siguiente caja pendiente de las dos listas, la que toque antes. {} si no queda.
func _next_crate() -> Dictionary:
	var weapon_times := RunPhaseConfig.WEAPON_CRATE_TIMES
	var supply_times := RunPhaseConfig.SUPPLY_CRATE_TIMES
	var has_weapon: bool = _weapon_crate_index < weapon_times.size()
	var has_supply: bool = _supply_crate_index < supply_times.size()
	if not has_weapon and not has_supply:
		return {}
	if has_weapon and (not has_supply
			or float(weapon_times[_weapon_crate_index]) <= float(supply_times[_supply_crate_index])):
		return {"kind": &"weapon_crate", "slot": _weapon_crate_index,
			"time": weapon_times[_weapon_crate_index]}
	return {"kind": &"supply_crate", "slot": _supply_crate_index,
		"time": supply_times[_supply_crate_index]}


func _apply_phase(phase: int) -> void:
	_phase = phase
	# Perfil de spawn de la fase, con la identidad del mapa mezclada encima.
	var profile: Dictionary = RunPhaseConfig.phase_profile(phase).duplicate(true)
	_merge_map_weights(profile)
	# FASE 11: nivel de comportamiento de la fase (1 basico, 2 tactico, 3
	# coordinado). Viaja en el mismo perfil hacia el spawner.
	profile["behavior_level"] = RunPhaseConfig.behavior_level_for_phase(phase)
	if is_instance_valid(_spawner) and _spawner.has_method("set_phase_profile"):
		_spawner.set_phase_profile(profile)

	match phase:
		RunPhaseConfig.Phase.COMMON_ENEMIES:
			_announce("La horda crece...")
		RunPhaseConfig.Phase.SPECIAL_ENEMIES:
			_announce("¡Enemigos especiales detectados!")
		RunPhaseConfig.Phase.HEAVY_ENEMIES:
			_announce("¡Amenazas pesadas en camino!")
		RunPhaseConfig.Phase.MINIBOSS:
			# El BossSpawner ya anuncia con nombre, barra propia, shake y sfx.
			if is_instance_valid(_boss_spawner) and _boss_spawner.has_method("spawn_miniboss"):
				_boss_spawner.spawn_miniboss()
		RunPhaseConfig.Phase.BOSS:
			# Anuncio, barra del HUD y musica de jefe los pone el BossSpawner.
			if is_instance_valid(_boss_spawner) and _boss_spawner.has_method("spawn_boss"):
				_boss_node = _boss_spawner.spawn_boss()
		RunPhaseConfig.Phase.ELITE_BOSS:
			_transform_boss_elite()
	phase_changed.emit(phase)


## 4:15 — el jefe actual SE TRANSFORMA en su version elite (no se crea otro).
## El propio jefe decide CUANDO es seguro (espera a que acabe el ataque activo) y
## abre su SEGUNDA barra via senal; aqui solo se pide la transformacion. Si el
## jefe ya se auto-transformo al 35%, la peticion es idempotente.
func _transform_boss_elite() -> void:
	if not is_instance_valid(_boss_node):
		# Si el jugador ya mato al jefe, la victoria la gestiono MapManager.
		return
	if _boss_node.has_method("request_elite_transform"):
		_boss_node.request_elite_transform()
		_announce("¡¡El jefe se transforma!!")


## 5:00 — furia final: paran los spawns comunes y el jefe se acelera (evitable).
func _start_final_fury() -> void:
	_fury_started = true
	if is_instance_valid(_spawner) and _spawner.has_method("set_phase_profile"):
		var empty: Dictionary = RunPhaseConfig.phase_profile(RunPhaseConfig.Phase.VICTORY)
		_spawner.set_phase_profile(empty)
	if is_instance_valid(_boss_node) and _boss_node.has_method("enrage"):
		_boss_node.enrage()
	_announce("¡¡FURIA FINAL!! Derrota al jefe YA")
	Feedback.shake(0.3)


## Limite absoluto alcanzado con el jefe vivo: derrota (via flujo unificado).
func _time_out_defeat() -> void:
	if _run_over:
		return
	_run_over = true
	_phase = RunPhaseConfig.Phase.DEFEAT
	phase_changed.emit(_phase)
	_announce("El jefe sigue en pie... la colonia cae")
	if is_instance_valid(_map_manager) and _map_manager.has_method("force_run_end"):
		_map_manager.force_run_end(false)


func _on_boss_defeated(_data) -> void:
	# La victoria (recompensas, panel, guardado) la orquesta MapManager con sus
	# objetivos; aqui solo se refleja el estado para HUD/tests.
	_run_over = true
	_phase = RunPhaseConfig.Phase.VICTORY
	phase_changed.emit(_phase)


## Mezcla la identidad del mapa: multiplica pesos de la fase por los overrides
## del MapData (phase_weight_overrides: id -> multiplicador).
func _merge_map_weights(profile: Dictionary) -> void:
	if not is_instance_valid(_map_manager) or not _map_manager.has_method("get_active_map"):
		return
	var map = _map_manager.get_active_map()
	if map == null:
		return
	var overrides = map.get("phase_weight_overrides")
	if not (overrides is Dictionary) or overrides.is_empty():
		return
	var weights: Dictionary = profile.get("weights", {})
	for id in overrides:
		if weights.has(id):
			weights[id] = float(weights[id]) * float(overrides[id])
	# Debut escalonado: un rol que aun no le toca entrar se pone a peso 0. Es lo
	# que hace que el Barrio se LEA (manada -> flanqueador -> aullador) en vez de
	# soltar los tres roles a la vez desde el principio.
	var debut = map.get("enemy_debut_phase")
	if debut is Dictionary:
		for id in debut:
			if weights.has(id) and _phase < int(debut[id]):
				weights[id] = 0.0


func _update_hud_phase() -> void:
	if not is_instance_valid(_hud) or not _hud.has_method("set_phase_info"):
		return
	var label: String
	var remaining: float
	if _fury_started:
		label = "Furia final"
		remaining = maxf(0.0, absolute_limit - _elapsed)
	else:
		label = RunPhaseConfig.phase_name(_phase)
		remaining = maxf(0.0, final_fury_start - _elapsed)
	var total: int = int(ceil(remaining))
	@warning_ignore("integer_division")
	_hud.set_phase_info("%s · %d:%02d" % [label, total / 60, total % 60])


## Avisos de fase (FURIA FINAL, transformación élite): impacto en Lilita One si
## el HUD lo soporta; si no, mensaje de evento clásico.
func _announce(text: String) -> void:
	if not is_instance_valid(_hud):
		return
	if _hud.has_method("show_announcement"):
		_hud.show_announcement(text, 2.4)
	elif _hud.has_method("show_event_message"):
		_hud.show_event_message(text, 2.4)


# --- API de consulta / tests ----------------------------------------------------

func get_phase() -> int:
	return _phase


func get_elapsed() -> float:
	return _elapsed


func is_final_fury() -> bool:
	return _fury_started


## Salta el reloj (tests/debug). Las transiciones se aplican en el proximo frame.
func debug_set_time(seconds: float) -> void:
	_elapsed = seconds
