extends Node2D
## Genera perros zombis alrededor del jugador y escala la dificultad de forma
## CONTINUA mediante un difficulty_score. Fase correccion de balance: TODA la
## curva (pesos, techos, etapas) vive CENTRALIZADA en GameBalance
## (scripts/systems/game_balance.gd); aqui solo queda la mecanica de spawn.
##
## difficulty_score = minutos * TIME_WEIGHT            (eje principal: tiempo)
##                  + potencia_del_jugador SUAVIZADA   (ajuste moderado, EMA)
##                  + kills / KILLS_DIVISOR
##                  + bono coop plano
##   ... multiplicado por el mapa y ACOTADO por SCORE_CAP.

const EnemyData = preload("res://scripts/enemies/enemy_data.gd")

signal stats_updated(kills: int, difficulty: float)

@export var enemy_scene: PackedScene
@export var enemy_types: Array[EnemyData] = []

@export_group("Aparición")
@export var min_radius: float = 520.0
@export var max_radius: float = 760.0

@export_group("Presión")
## Probabilidad base de que un enemigo aparezca justo en el borde visible de
## la cámara (más cerca = más peligro). Crece con la dificultad.
@export var base_edge_chance: float = 0.07
@export var edge_chance_per_point: float = 0.03
@export var max_edge_chance: float = 0.70
## Margen extra fuera de la pantalla al aparecer en el borde.
@export var edge_margin: float = 60.0
## Probabilidad (creciente con la dificultad) de que un spawn se convierta en una
## mini-oleada de varios enemigos a la vez.
@export var base_wave_chance: float = 0.05
@export var wave_chance_per_point: float = 0.02
@export var max_wave_chance: float = 0.45
@export var wave_extra_enemies: int = 3

@export_group("Control de hordas (Fase 08.75)")
## Por encima de este numero de enemigos vivos se reduce la presion (backpressure).
@export var soft_enemy_cap: int = 120
## Tope duro: no se generan enemigos normales ni eventos por encima de esto.
@export var hard_enemy_cap: int = 180
## Tope absoluto: dispara la limpieza de emergencia.
@export var absolute_enemy_cap: int = 220
## Kills/min de referencia. Si el jugador mata menos y hay saturacion, baja el spawn.
@export var expected_kill_rate: float = 40.0
## Piso del multiplicador de spawn bajo backpressure (0.25 = un cuarto del ritmo).
@export_range(0.05, 1.0, 0.05) var backpressure_min_multiplier: float = 0.25
## Limpieza de emergencia: elimina enemigos lejanos si el juego esta critico.
@export var enable_emergency_cleanup: bool = true
## Solo se eliminan enemigos mas lejos que esta distancia del jugador.
@export var emergency_cleanup_distance: float = 1500.0
## Sesgo direccional de horda: fraccion de spawns que llegan desde un mismo lado.
@export_range(0.0, 1.0, 0.05) var horde_bias_strength: float = 0.6

@export_group("Balance coop (Fase Coop 1.5)")
## Enemigos vivos extra permitidos en coop (base y topes). El bono de score coop
## vive en GameBalance.COOP_SCORE_BONUS (fuente unica).
@export var coop_max_enemies_bonus: int = 25
@export var coop_cap_bonus: int = 30

var _alive_count: int = 0
## Backpressure suavizado (1.0 = ritmo pleno; <1 = reducido por saturacion/FPS).
var _spawn_multiplier: float = 1.0
## Timestamps (segundos de partida) de kills recientes, para estimar kills/min.
var _kill_times: Array[float] = []
var _emergency_cooldown: float = 0.0
## Direccion preferente de una horda dirigida (Vector2.ZERO = sin sesgo).
var _horde_bias_dir: Vector2 = Vector2.ZERO
var _perf: Node
var _kills: int = 0
var _elapsed_time: float = 0.0
var _difficulty_score: float = 0.0
var _player: Node2D
var _spawn_timer: Timer

# --- Eventos de oleada (Fase 05): los activa WaveEventManager y decaen solos. ---
## Multiplicador de ritmo de spawn durante una horda (1.0 = sin horda).
var _horde_intensity: float = 1.0
var _horde_timer: float = 0.0
## Peso extra a los runners durante una manada (0.0 = sin manada).
var _runner_boost: float = 0.0
var _runner_timer: float = 0.0
## Tope de enemigos extra que una horda permite por encima del maximo normal.
@export var horde_max_enemies_bonus: int = 18

# --- Modificadores de mapa (Fase 06): los fija MapManager.set_map_modifiers. ---
var _map_difficulty_mult: float = 1.0
var _map_runner_mult: float = 1.0
var _map_health_mult: float = 1.0
var _map_speed_mult: float = 1.0
var _map_damage_mult: float = 1.0
## Bono de dificultad por jugadores extra en coop (Fase Coop, seccion 13). Suma
## presion constante al score para compensar el doble de dano/coberturua del equipo.
var _coop_bonus: float = 0.0
## Enemigos vivos extra permitidos en coop (antes se sumaba al export base).
var _coop_extra_enemies: int = 0
## Potencia del jugador SUAVIZADA (Fase correccion): los datos caros se muestrean
## cada POWER_POLL_SECONDS y el valor efectivo persigue al real con una media
## movil exponencial — elegir una carta no dispara la dificultad al instante.
var _raw_power: float = 0.0
var _power_smoothed: float = 0.0
var _power_poll_timer: float = 0.0
## Presion extra por mejoras permanentes (Fase 07). Se lee una vez al iniciar.
var _permanent_power: float = 0.0
## Presion extra por el poder del Refugio (Fase 10): objetos colocados.
var _shelter_power: float = 0.0
var _obstacle_cache: Array = []
var _obstacle_cache_timer: float = 0.0

# --- Partidas rapidas por fases (lo dirige PhaseDirector) -----------------------
## Perfil de la fase activa (RunPhaseConfig.phase_profile + overrides del mapa).
## Vacio = modo clasico (curva continua por score). Claves: weights, interval,
## budget, max_alive, tier_caps, type_caps, behavior_level.
var _phase_profile: Dictionary = {}
## FASE 11: mutaciones elite del bioma (se SUMAN a las genericas) y la mutacion
## dominante del guion de la semilla (pesa doble). Las fija MapManager.
var _mutation_pool: Array[StringName] = []
var _dominant_mutation: StringName = &""
## Nivel de comportamiento de la fase activa (1..3); lo reciben los enemigos.
var _behavior_level: int = 1
## Suma de threat_cost de los enemigos VIVOS generados por este spawner.
var _threat_active: float = 0.0
## Conteos de vivos por id y por categoria (para limites por tipo/categoria).
var _alive_by_id: Dictionary = {}
var _alive_by_tier: Dictionary = {}


func _ready() -> void:
	add_to_group("enemy_spawner")
	_player = get_tree().get_first_node_in_group("player")
	_perf = get_node_or_null("/root/Performance")
	# Mejoras permanentes / Refugio solo cuentan en Historia. En Partida libre no hay
	# bonos, asi que tampoco su presion compensatoria (_permanent_power/_shelter_power=0).
	if _is_story_run():
		# Las mejoras permanentes suben un poco la presion (Fase 07).
		var mp: Node = get_node_or_null("/root/MetaProgression")
		if mp != null and mp.has_method("get_permanent_power_score"):
			_permanent_power = float(mp.get_permanent_power_score())
		# El Refugio tambien (Fase 10): solo los objetos COLOCADOS cuentan.
		var shelter: Node = get_node_or_null("/root/Shelter")
		if shelter != null and shelter.has_method("get_power_score"):
			_shelter_power = float(shelter.get_power_score())

	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = GameBalance.BASE_SPAWN_INTERVAL
	_spawn_timer.autostart = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)


func _process(delta: float) -> void:
	_elapsed_time += delta
	if _emergency_cooldown > 0.0:
		_emergency_cooldown -= delta
	_obstacle_cache_timer = maxf(0.0, _obstacle_cache_timer - delta)
	_update_event_timers(delta)
	_update_backpressure(delta)
	_maybe_emergency_cleanup()
	_update_smoothed_power(delta)
	_recalculate_difficulty()


## Muestrea la potencia real del jugador por intervalos y la suaviza con una
## media movil exponencial. La potencia solo puede BAJAR igual de despacio que
## sube: perder companeros/derribarse no abarata la dificultad al instante
## (anti-exploit) y elegir una carta no la encarece de golpe.
func _update_smoothed_power(delta: float) -> void:
	_power_poll_timer -= delta
	if _power_poll_timer <= 0.0:
		_power_poll_timer = GameBalance.POWER_POLL_SECONDS
		_raw_power = _compute_raw_power()
	var blend: float = 1.0 - exp(-delta / GameBalance.POWER_SMOOTH_SECONDS)
	_power_smoothed = lerpf(_power_smoothed, _raw_power, blend)


## Potencia CRUDA del equipo. Cada beneficio cuenta UNA sola vez (la formula
## anterior sumaba nivel + mejoras elegidas + niveles de arma: el mismo poder
## puntuaba tres veces por carta). Componentes: nivel maximo del equipo, armas
## activas, niveles de arma acumulados y companeros (con leve descuento por
## companero derribado).
func _compute_raw_power() -> float:
	return _get_player_level() * GameBalance.LEVEL_WEIGHT \
		+ _get_weapon_count() * GameBalance.WEAPON_WEIGHT \
		+ _get_total_weapon_levels() * GameBalance.WEAPON_LEVEL_WEIGHT \
		+ _get_companion_count() * GameBalance.COMPANION_WEIGHT \
		+ _get_downed_companion_count() * GameBalance.DOWNED_COMPANION_WEIGHT


## Numero real de enemigos vivos (incluye jefes/mini-jefes, que tambien presionan).
## Se lee del grupo para no desincronizarse con spawns externos ni con muertes que
## no pasan por la señal del spawner.
##
## FASE 11: los interactables de mapa (marcas de aullido, nidos, lineas) viven en
## el grupo "enemies" para que las armas puedan dañarlos, pero son ESTRUCTURAS
## estaticas, no presion. Si contaran aqui, cada marca viva robaria un slot de
## perro real y el Barrio (hasta 5 marcas con las del Alfa) spawnearia menos
## enemigos justo cuando mas presion deberia haber.
func _alive_enemies() -> int:
	var tree := get_tree()
	return maxi(0, tree.get_node_count_in_group("enemies")
		- tree.get_node_count_in_group(&"map_interactables"))


## Kills en los ultimos 60 s (aprox. kills/min).
func _recent_kill_rate() -> float:
	var cutoff: float = _elapsed_time - 60.0
	while not _kill_times.is_empty() and _kill_times[0] < cutoff:
		_kill_times.pop_front()
	# Si llevamos menos de 1 min, extrapola sobre el tiempo transcurrido.
	var window: float = min(_elapsed_time, 60.0)
	if window <= 0.5:
		return expected_kill_rate
	return _kill_times.size() * (60.0 / window)


## Backpressure: si hay saturacion y el jugador mata poco (o el FPS sufre), se
## reduce el ritmo de spawn de forma suave. Nunca sube la dificultad hasta crashear.
func _update_backpressure(delta: float) -> void:
	var alive: int = _alive_enemies()
	var target: float = 1.0
	if alive >= soft_enemy_cap:
		# Cuanto peor sea el kill-rate frente al esperado, mas se frena el spawn.
		if _recent_kill_rate() < expected_kill_rate:
			target = backpressure_min_multiplier
		else:
			target = 0.6
	if _perf != null:
		if _perf.is_critical():
			target = min(target, backpressure_min_multiplier)
		elif _perf.is_warning():
			target = min(target, 0.6)
	_spawn_multiplier = move_toward(_spawn_multiplier, target, delta * 1.5)
	if _perf != null:
		_perf.spawn_multiplier = _spawn_multiplier


## Limpieza de emergencia (ultimo recurso): elimina enemigos MUY lejanos si se pasa
## el tope absoluto o el FPS lleva segundos por el suelo. Nunca toca jefes, mini-jefes,
## enemigos cercanos, compañeros ni rescates.
func _maybe_emergency_cleanup() -> void:
	if not enable_emergency_cleanup or _emergency_cooldown > 0.0:
		return
	var alive: int = _alive_enemies()
	var fps_bad: bool = _perf != null and _perf.has_method("fps_sustained_critical") and _perf.fps_sustained_critical()
	if alive <= absolute_enemy_cap and not (fps_bad and alive > soft_enemy_cap):
		return
	if not is_instance_valid(_player):
		return
	var team: Array = _team_players()
	var candidates: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.is_in_group("boss") or e.is_in_group("miniboss"):
			continue
		# Los interactables de mapa (marcas, nidos) no son perros: nunca se limpian.
		if e.is_in_group("map_interactables"):
			continue
		# Coop: la distancia que cuenta es al jugador MAS CERCANO. Nunca se borra
		# un enemigo que este presionando al P2 aunque quede lejos del P1.
		var d: float = INF
		for p in team:
			d = minf(d, (e as Node2D).global_position.distance_to((p as Node2D).global_position))
		if d >= emergency_cleanup_distance:
			candidates.append([d, e])
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	var to_remove: int = max(0, alive - soft_enemy_cap)
	var removed: int = 0
	for pair in candidates:
		if removed >= to_remove:
			break
		var e: Node = pair[1]
		if is_instance_valid(e):
			e.queue_free()
			_alive_count = max(0, _alive_count - 1)
			removed += 1
	_emergency_cooldown = 2.0


## Decae los efectos temporales de eventos de oleada.
func _update_event_timers(delta: float) -> void:
	if _horde_timer > 0.0:
		_horde_timer -= delta
		if _horde_timer <= 0.0:
			_horde_intensity = 1.0
			_horde_bias_dir = Vector2.ZERO
	if _runner_timer > 0.0:
		_runner_timer -= delta
		if _runner_timer <= 0.0:
			_runner_boost = 0.0


# --- API de eventos de oleada (la llama WaveEventManager) --------------------

## Activa una horda: durante `duration` s el ritmo de spawn se multiplica por
## `intensity` y se permite mas enemigos vivos.
func start_horde(duration: float, intensity: float) -> void:
	_horde_intensity = max(1.0, intensity)
	_horde_timer = max(0.0, duration)
	# Horda dirigida: los enemigos llegan mayormente desde un lado (lectura de mapa).
	_horde_bias_dir = Vector2.RIGHT.rotated(randf() * TAU)


## Activa una manada de runners: durante `duration` s los runners pesan mucho mas
## en la seleccion de tipo de enemigo.
func start_runner_pack(duration: float, weight_bonus: float = 3.0) -> void:
	_runner_boost = max(0.0, weight_bonus)
	_runner_timer = max(0.0, duration)


## True solo en Modo Historia (donde aplican mejoras permanentes y Refugio).
func _is_story_run() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_story_run") and gf.is_story_run()


## Activa el escalado cooperativo (Fase Coop, seccion 13): bono de presion constante
## y mas techo de enemigos, porque el equipo cubre mas terreno y hace mas dano.
## Fase correccion: la presion coop entra UNA sola vez (este bono plano); ya no se
## multiplica ademas todo el score (map_manager) ni se duplica en los caps.
func set_coop_players(count: int) -> void:
	if count >= 2:
		_coop_bonus = GameBalance.COOP_SCORE_BONUS
		_coop_extra_enemies = coop_max_enemies_bonus
		soft_enemy_cap += coop_cap_bonus
		hard_enemy_cap += coop_cap_bonus
		absolute_enemy_cap += coop_cap_bonus
	else:
		_coop_bonus = 0.0
		_coop_extra_enemies = 0


# --- API de fases (la llama PhaseDirector) --------------------------------------

## Fija el perfil de spawn de la fase activa. Un Dictionary vacio devuelve el
## spawner al modo clasico. El presupuesto de amenaza y los limites por tipo y
## categoria se aplican EN CADA spawn: nunca se generan combinaciones por encima
## del presupuesto, y el presupuesto se recupera solo al morir enemigos.
func set_phase_profile(profile: Dictionary) -> void:
	_phase_profile = profile if profile != null else {}
	if not _phase_profile.is_empty():
		_spawn_timer.wait_time = maxf(0.2, float(_phase_profile.get("interval", GameBalance.BASE_SPAWN_INTERVAL)))
		_behavior_level = clampi(int(_phase_profile.get("behavior_level", 1)), 1, 3)


## FASE 11: mutaciones elite del mapa activo (las fija MapManager al cargar).
func set_mutation_pool(pool: Array, dominant: StringName = &"") -> void:
	_mutation_pool.clear()
	for m in pool:
		_mutation_pool.append(StringName(m))
	_dominant_mutation = dominant


## Sorteo de mutacion elite: genericas + las del bioma; la dominante del guion
## pesa el doble (dos papeletas extra).
func _pick_elite_kind() -> StringName:
	var pool: Array[StringName] = [&"veloz", &"blindado", &"gigante"]
	pool.append_array(_mutation_pool)
	if _dominant_mutation != &"":
		pool.append(_dominant_mutation)
		pool.append(_dominant_mutation)
	return pool.pick_random()


func get_phase_profile() -> Dictionary:
	return _phase_profile


func get_active_threat() -> float:
	return _threat_active


func get_alive_count_for(id: StringName) -> int:
	return int(_alive_by_id.get(id, 0))


## Genera una manada inmediata de `count` enemigos de un tipo, entrando desde un
## arco de ~200 grados fuera de la camara: presion inmediata pero SIEMPRE queda
## al menos una ruta de escape despejada.
func spawn_pack(enemy_id: StringName, count: int) -> int:
	var data: EnemyData = RunPhaseConfig.load_enemy_data(enemy_id)
	if data == null or enemy_scene == null:
		return 0
	var base_angle: float = randf() * TAU
	var spawned: int = 0
	for _i in count:
		if not _can_spawn_more():
			break
		if not _phase_profile.is_empty() and not _phase_slot_available(data):
			break
		var angle: float = base_angle + randf_range(-1.75, 1.75)
		var anchor: Node2D = _spawn_anchor()
		if anchor == null:
			break
		var offset: Vector2 = _camera_edge_offset(angle)
		_spawn_enemy_of(data, anchor.global_position + offset)
		spawned += 1
	return spawned


## Distancia minima a CUALQUIER jugador para un spawn urbano: nunca encima.
const URBAN_SPAWN_MIN_DISTANCE: float = 520.0


## Accesos urbanos validos alrededor del ancla: puntos sobre calles/intersecciones
## reales, en suelo abierto, libres de obstaculos y lejos de todos los jugadores.
## Es la base de "los corredores entran por la calle, no encima del jugador".
func _urban_access_points(center: Vector2, wanted: int) -> Array[Vector2]:
	var valid: Array[Vector2] = []
	var manager: Node = get_tree().get_first_node_in_group("map_manager")
	if not is_instance_valid(manager) or not manager.has_method("get_world_seed"):
		return valid
	var map = manager.get_active_map() if manager.has_method("get_active_map") else null
	if map == null:
		return valid
	var world_seed: int = manager.get_world_seed()
	# Radio de entrada: fuera de camara con margen, pero no al otro lado del mapa.
	for radius in [760.0, 940.0, 620.0]:
		for point in MapGeometry.approach_points(world_seed, map.biome, center, radius, 4):
			if valid.size() >= wanted:
				return valid
			if not _far_from_all_players(point, URBAN_SPAWN_MIN_DISTANCE):
				continue
			if not MapGeometry.is_open_ground(world_seed, map.biome, point):
				continue
			if not MapGeometry.is_clear(self, point, 34.0):
				continue
			valid.append(point)
	return valid


## Manada que entra por ACCESOS URBANOS distintos (FASE 2, identidad del Barrio).
## `access_count` = por cuantas bocas de calle distintas se reparte la entrada.
## Si el mapa no tiene calles utiles, cae al `spawn_pack` clasico: nunca deja de
## spawnear por no encontrar geometria.
func spawn_pack_urban(enemy_id: StringName, count: int, access_count: int = 2) -> int:
	var data: EnemyData = RunPhaseConfig.load_enemy_data(enemy_id)
	if data == null or enemy_scene == null:
		return 0
	var anchor: Node2D = _spawn_anchor()
	if not is_instance_valid(anchor):
		return 0
	var accesses := _urban_access_points(anchor.global_position, maxi(1, access_count))
	if accesses.is_empty():
		return spawn_pack(enemy_id, count)
	var spawned: int = 0
	for i in count:
		if not _can_spawn_more():
			break
		if not _phase_profile.is_empty() and not _phase_slot_available(data):
			break
		# Reparto por bocas: los que entran juntos salen del mismo acceso, con
		# dispersion corta para que se lea como "vienen por esa calle".
		var access: Vector2 = accesses[i % accesses.size()]
		var jitter: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, 70.0)
		_spawn_enemy_of(data, access + jitter)
		spawned += 1
	if spawned > 0:
		RunTelemetry.count(&"urban_spawns", spawned)
		RunTelemetry.count(&"urban_accesses_used", accesses.size())
	return spawned


## Llamada dirigida a UN acceso concreto (la usa el Aullador para abrir un
## segundo frente por una calle distinta de la suya).
func spawn_pack_from_street(enemy_id: StringName, count: int, near_point: Vector2,
		_access_count: int = 1) -> int:
	var data: EnemyData = RunPhaseConfig.load_enemy_data(enemy_id)
	if data == null or enemy_scene == null:
		return 0
	if not _far_from_all_players(near_point, URBAN_SPAWN_MIN_DISTANCE):
		return 0
	var spawned: int = 0
	for _i in count:
		if not _can_spawn_more():
			break
		if not _phase_profile.is_empty() and not _phase_slot_available(data):
			break
		var jitter: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, 60.0)
		_spawn_enemy_of(data, near_point + jitter)
		spawned += 1
	return spawned


func get_difficulty_score() -> float:
	return _difficulty_score


func get_kills() -> int:
	return _kills


## Modificadores del mapa activo (Fase 06). El MapManager los aplica al cargar.
## damage_mult (Fase 09): dificultad del Modo Historia; opcional para no romper
## a los llamadores existentes de 4 argumentos.
func set_map_modifiers(difficulty_mult: float, runner_mult: float, health_mult: float, speed_mult: float, damage_mult: float = 1.0) -> void:
	_map_difficulty_mult = max(0.1, difficulty_mult)
	_map_runner_mult = max(0.0, runner_mult)
	_map_health_mult = max(0.1, health_mult)
	_map_speed_mult = max(0.1, speed_mult)
	_map_damage_mult = max(0.1, damage_mult)


## Recalcula el score y ajusta el ritmo de aparición en vivo. La curva completa
## (pesos, techos y etapas) vive en GameBalance: fuente unica de verdad.
func _recalculate_difficulty() -> void:
	var minutes: float = _elapsed_time / 60.0
	# El bono coop entra en RAMPA durante la etapa inicial: dos jugadores no
	# empiezan con toda la presion extra encima antes de su primera build.
	_difficulty_score = minutes * GameBalance.TIME_WEIGHT \
		+ _power_smoothed \
		+ _kills / GameBalance.KILLS_DIVISOR \
		+ _coop_bonus * GameBalance.early_ramp(minutes)

	# Modificador del mapa activo (Fase 06): escala la presion global.
	_difficulty_score *= _map_difficulty_mult
	# Mejoras permanentes (Fase 07.5) y Refugio (Fase 10): presion extra SUAVE.
	# Bajadas en la Fase correccion (0.12/0.10 -> 0.10/0.08) para que ser mas
	# fuerte por meta-progresion no castigue de inmediato.
	_difficulty_score += _permanent_power * 0.10
	_difficulty_score += _shelter_power * 0.08
	# Techo absoluto del score (antes no existia: superaba 120).
	_difficulty_score = minf(_difficulty_score, GameBalance.SCORE_CAP)

	# MODO FASES: la fase es la fuente principal de dificultad; el score solo
	# ajusta SUAVE dentro de ella (tope 25% mas rapido). El backpressure por
	# saturacion/FPS sigue mandando por encima de todo.
	if not _phase_profile.is_empty():
		var base_interval: float = float(_phase_profile.get("interval", GameBalance.BASE_SPAWN_INTERVAL))
		var tune: float = clampf(1.0 - _difficulty_score * 0.004, 0.75, 1.0)
		var phase_interval: float = base_interval * tune / maxf(0.05, _spawn_multiplier)
		_spawn_timer.wait_time = maxf(0.25, phase_interval)
		stats_updated.emit(_kills, _difficulty_score)
		return

	# La horda acorta el intervalo (mas spawns); el backpressure lo alarga si hay
	# saturacion. rate>1 = mas rapido, rate<1 = mas lento. El SUELO del intervalo
	# depende del minuto: alto al inicio, baja hacia el final (GameBalance).
	var interval: float = GameBalance.BASE_SPAWN_INTERVAL - _difficulty_score * GameBalance.INTERVAL_PER_POINT
	var rate: float = max(0.05, _horde_intensity * _spawn_multiplier)
	interval /= rate
	_spawn_timer.wait_time = maxf(GameBalance.spawn_floor(minutes), interval)

	stats_updated.emit(_kills, _difficulty_score)


## Jugadores del equipo (coop: ambos; solo: el clasico). Para dificultad y anclas.
func _team_players() -> Array:
	var players: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and p is Node2D:
			players.append(p)
	if players.is_empty() and is_instance_valid(_player):
		players.append(_player)
	return players


## Ancla del spawn: un jugador ACTIVO al azar (en coop reparte la presion entre
## las dos mitades). Cae a P1 si nadie esta activo.
func _spawn_anchor() -> Node2D:
	var active: Array = []
	for p in _team_players():
		if p.has_method("is_active") and not p.is_active():
			continue
		active.append(p)
	if active.is_empty():
		return _player
	return active.pick_random()


func _far_from_all_players(pos: Vector2, min_distance: float) -> bool:
	for p in _team_players():
		if pos.distance_to((p as Node2D).global_position) < min_distance:
			return false
	return true


## Nivel del equipo: el MAXIMO de los jugadores (coop: niveles independientes).
func _get_player_level() -> int:
	var best: int = 1
	for p in _team_players():
		var level_value = p.get("level")
		if level_value != null:
			best = maxi(best, int(level_value))
	return best


func _get_companion_count() -> int:
	var manager: Node = get_tree().get_first_node_in_group("companion_manager")
	if not is_instance_valid(manager):
		return 0
	if not manager.has_method("get_companion_count"):
		return 0
	return int(manager.get_companion_count())


func _get_downed_companion_count() -> int:
	var manager: Node = get_tree().get_first_node_in_group("companion_manager")
	if not is_instance_valid(manager):
		return 0
	if not manager.has_method("get_downed_companion_count"):
		return 0
	return int(manager.get_downed_companion_count())


func _get_weapon_manager() -> Node:
	if is_instance_valid(_player) and _player.has_method("get_weapon_manager"):
		return _player.get_weapon_manager()
	return get_tree().get_first_node_in_group("weapon_manager")


## Armas del EQUIPO (coop: suma de los arsenales independientes de P1 y P2).
func _get_weapon_count() -> int:
	var total: int = 0
	for manager in _team_weapon_managers():
		if manager.has_method("get_weapon_count"):
			total += int(manager.get_weapon_count())
	return total


func _get_total_weapon_levels() -> int:
	var total: int = 0
	for manager in _team_weapon_managers():
		if manager.has_method("get_total_weapon_levels"):
			total += int(manager.get_total_weapon_levels())
	return total


func _team_weapon_managers() -> Array:
	var managers: Array = []
	for p in _team_players():
		if p.has_method("get_weapon_manager"):
			var wm: Node = p.get_weapon_manager()
			if is_instance_valid(wm):
				managers.append(wm)
	if managers.is_empty():
		var fallback: Node = _get_weapon_manager()
		if is_instance_valid(fallback):
			managers.append(fallback)
	return managers


func _current_max_enemies() -> int:
	var extra: float = 0.0
	var companions: int = _get_companion_count()
	if companions >= 2:
		extra += 4.0
	if companions >= 4:
		extra += 3.0
	# El techo por defecto es el soft cap; una horda permite subir hacia el hard cap.
	var cap: int = soft_enemy_cap
	if _horde_timer > 0.0:
		cap = hard_enemy_cap
	# Bajo estado critico se recorta el techo para recuperar FPS.
	if _perf != null and _perf.is_critical():
		cap = int(cap * 0.6)
	# MODO FASES: el tope de vivos lo define la fase (mas el margen coop).
	if not _phase_profile.is_empty():
		return mini(cap, int(_phase_profile.get("max_alive", 20)) + _coop_extra_enemies)
	var dynamic: float = GameBalance.BASE_MAX_ENEMIES + _difficulty_score * GameBalance.ENEMIES_PER_POINT \
		+ extra + float(_coop_extra_enemies)
	return int(min(cap, dynamic))


## Puede generar un enemigo mas? Respeta el techo dinamico y el hard cap absoluto.
func _can_spawn_more() -> bool:
	var alive: int = _alive_enemies()
	if alive >= hard_enemy_cap:
		return false
	return alive < _current_max_enemies()


func _on_spawn_timer_timeout() -> void:
	if enemy_scene == null:
		return
	if not _can_spawn_more():
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(_player):
			return

	_spawn_enemy()

	# Mini-oleada: a veces aparecen varios de golpe (más probable con la presión).
	# Se suprime bajo backpressure fuerte y durante la ETAPA INICIAL (el arranque
	# no castiga con oleadas antes de la primera build).
	if _spawn_multiplier < 0.5:
		return
	var wave_chance: float = min(max_wave_chance, base_wave_chance + _difficulty_score * wave_chance_per_point)
	wave_chance *= GameBalance.early_ramp(_elapsed_time / 60.0)
	if randf() < wave_chance:
		for _i in wave_extra_enemies:
			if not _can_spawn_more():
				break
			_spawn_enemy()


func _spawn_enemy() -> void:
	var enemy_type: EnemyData
	if _phase_profile.is_empty():
		enemy_type = _pick_enemy_type()
	else:
		enemy_type = _pick_phase_enemy_type()
		if enemy_type == null:
			return  # sin hueco en presupuesto/limites: ventana de respiro natural
	var anchor: Node2D = _spawn_anchor()
	if not is_instance_valid(anchor):
		return
	_spawn_enemy_of(enemy_type, anchor.global_position + _spawn_offset())


## Instancia y coloca un enemigo de un tipo concreto (comun a ambos modos).
func _spawn_enemy_of(enemy_type: EnemyData, desired_pos: Vector2) -> void:
	var enemy := enemy_scene.instantiate() as Node2D
	if enemy == null:
		return

	if enemy.has_method("configure"):
		enemy.call("configure", enemy_type, _health_multiplier(), _speed_multiplier(), _damage_multiplier())

	# Elites por ESCALONES de minutos (GameBalance): 0% en la etapa inicial y
	# subiendo por intervalos hasta el techo. Dan XP x4. Solo entre enemigos
	# COMUNES: especiales y pesados ya son variantes con identidad propia.
	var is_common: bool = enemy_type == null or enemy_type.tier == &"common"
	var elite_chance: float = GameBalance.elite_chance(_elapsed_time / 60.0, _difficulty_score)
	if is_common and randf() < elite_chance and enemy.has_method("make_elite"):
		enemy.call("make_elite", _pick_elite_kind())

	# FASE 11: nivel de comportamiento de la fase (la dificultad crece por
	# conducta). Se fija antes de entrar al arbol.
	enemy.set("behavior_level", _behavior_level)

	# Rework Coop: el spawn se ancla a un jugador activo al azar (no siempre P1),
	# y se reintenta si el punto quedaria a la vista de CUALQUIER mitad (en split
	# cada jugador ve su propia zona del mundo).
	var spawn_pos: Vector2 = _resolve_spawn_position(desired_pos)
	if _coop_bonus > 0.0:
		for _attempt in 5:
			if _far_from_all_players(spawn_pos, 420.0):
				break
			var anchor: Node2D = _spawn_anchor()
			if not is_instance_valid(anchor):
				break
			spawn_pos = _resolve_spawn_position(anchor.global_position + _spawn_offset())
	enemy.global_position = spawn_pos
	if enemy.has_signal("died"):
		enemy.connect("died", Callable(self, "_on_enemy_died"))

	# Registro de amenaza y limites: el coste se libera al SALIR del arbol
	# (cubre tanto muertes como la limpieza de emergencia).
	if enemy_type != null:
		_register_tracked_spawn(enemy, enemy_type)

	# Los enemigos cuelgan del nivel para vivir aparte del spawner.
	get_parent().add_child(enemy)
	_alive_count += 1


func _register_tracked_spawn(enemy: Node2D, enemy_type: EnemyData) -> void:
	_threat_active += enemy_type.threat_cost
	_alive_by_id[enemy_type.id] = int(_alive_by_id.get(enemy_type.id, 0)) + 1
	_alive_by_tier[enemy_type.tier] = int(_alive_by_tier.get(enemy_type.tier, 0)) + 1
	enemy.tree_exited.connect(_on_tracked_enemy_gone.bind(enemy_type.id, enemy_type.tier, enemy_type.threat_cost))


func _on_tracked_enemy_gone(id: StringName, tier: StringName, cost: float) -> void:
	_threat_active = maxf(0.0, _threat_active - cost)
	_alive_by_id[id] = maxi(0, int(_alive_by_id.get(id, 0)) - 1)
	_alive_by_tier[tier] = maxi(0, int(_alive_by_tier.get(tier, 0)) - 1)


## Seleccion de tipo del MODO FASES: pondera los pesos de la fase (con la
## identidad del mapa ya mezclada por el PhaseDirector) y descarta candidatos
## sin hueco en el presupuesto de amenaza o en los limites por tipo/categoria.
func _pick_phase_enemy_type() -> EnemyData:
	var weights: Dictionary = _phase_profile.get("weights", {})
	var candidates: Array = []
	var total: float = 0.0
	for id in weights:
		var w: float = float(weights[id])
		if w <= 0.0:
			continue
		var data: EnemyData = RunPhaseConfig.load_enemy_data(id)
		if data == null or not _phase_slot_available(data):
			continue
		candidates.append([data, w])
		total += w
	if candidates.is_empty() or total <= 0.0:
		return null
	var roll: float = randf() * total
	for pair in candidates:
		roll -= pair[1]
		if roll <= 0.0:
			return pair[0]
	return candidates[candidates.size() - 1][0]


## Hay hueco para este tipo? Presupuesto de amenaza + limite por tipo + limite
## por categoria. En coop el presupuesto sube UNA sola vez (RunPhaseConfig).
func _phase_slot_available(data: EnemyData) -> bool:
	if _phase_profile.is_empty():
		return true
	var budget: float = float(_phase_profile.get("budget", 0.0))
	if budget <= 0.0:
		return false
	var budget_max: float = budget * (RunPhaseConfig.BUDGET_COOP_MULT if _coop_bonus > 0.0 else 1.0)
	if _threat_active + data.threat_cost > budget_max:
		return false
	var type_caps: Dictionary = _phase_profile.get("type_caps", {})
	if type_caps.has(data.id) and int(_alive_by_id.get(data.id, 0)) >= int(type_caps[data.id]):
		return false
	var tier_caps: Dictionary = _phase_profile.get("tier_caps", {})
	if tier_caps.has(data.tier) and int(_alive_by_tier.get(data.tier, 0)) >= int(tier_caps[data.tier]):
		return false
	return true


## Multiplicadores FINALES de enemigo, con TECHO TOTAL en GameBalance: la parte
## por score esta acotada Y el producto con los multiplicadores externos
## (mapa x plaga x dificultad x coop) tambien. Antes el producto externo era
## ilimitado (vida x4.7 medida en coop dificil al minuto 3).
func _health_multiplier() -> float:
	return GameBalance.health_multiplier(_difficulty_score, _map_health_mult)


func _speed_multiplier() -> float:
	return GameBalance.speed_multiplier(_difficulty_score, _map_speed_mult)


func _damage_multiplier() -> float:
	return GameBalance.damage_multiplier(_difficulty_score, _map_damage_mult)


## Decide dónde aparece el enemigo: en el borde visible de la cámara (presión
## alta) o en el anillo lejano. La probabilidad de borde sube con la dificultad.
func _spawn_offset() -> Vector2:
	var edge_chance: float = min(max_edge_chance, base_edge_chance + _difficulty_score * edge_chance_per_point)
	# Etapa inicial: sin spawns pegados a camara (presion de borde gradual).
	edge_chance *= GameBalance.early_ramp(_elapsed_time / 60.0)
	if randf() < edge_chance:
		return _camera_edge_offset(randf() * TAU)
	return _random_ring_offset()


## Calcula un punto justo fuera del rectángulo visible de la cámara en una
## dirección dada, para que el enemigo "entre en escena" cerca del jugador.
func _camera_edge_offset(angle: float) -> Vector2:
	var direction: Vector2 = Vector2.RIGHT.rotated(angle)
	var half_extent: Vector2 = Vector2(960, 540)
	if _coop_bonus > 0.0:
		# Coop split: la camara del viewport raiz esta "aparcada" (zoom extremo) y
		# NO representa lo visible. Cota conservadora: media ventana completa con
		# el zoom real de las mitades — fuera de la vista de cualquier mitad.
		half_extent = get_viewport_rect().size * 0.5 / CoopConfig.SPLIT_BASE_ZOOM
	else:
		var camera := get_viewport().get_camera_2d()
		if camera != null:
			half_extent = get_viewport_rect().size * 0.5 / camera.zoom

	# Proyecta la dirección al borde del rectángulo visible.
	var scale_x: float = INF if is_zero_approx(direction.x) else half_extent.x / absf(direction.x)
	var scale_y: float = INF if is_zero_approx(direction.y) else half_extent.y / absf(direction.y)
	var border_distance: float = min(scale_x, scale_y) + edge_margin
	return direction * border_distance


## Devuelve un offset aleatorio dentro del anillo [min_radius, max_radius]. Durante
## una horda dirigida, el angulo se sesga hacia `_horde_bias_dir` (lectura de lado).
func _random_ring_offset() -> Vector2:
	var angle: float = randf() * TAU
	if _horde_timer > 0.0 and _horde_bias_dir != Vector2.ZERO and randf() < horde_bias_strength:
		angle = _horde_bias_dir.angle() + randf_range(-0.7, 0.7)
	var distance: float = randf_range(min_radius, max_radius)
	return Vector2.RIGHT.rotated(angle) * distance


## Empuja el punto de aparicion fuera de cualquier obstaculo cercano para que los
## enemigos no nazcan dentro de un muro/carro. Barato: pocos obstaculos colisionables.
func _resolve_spawn_position(pos: Vector2) -> Vector2:
	var obstacles := _cached_obstacles()
	if obstacles.is_empty():
		return pos
	for _attempt in 4:
		var blocked: bool = false
		for o in obstacles:
			if not is_instance_valid(o) or not (o is Node2D):
				continue
			var radius: float = 40.0
			if o.has_method("get_block_radius"):
				radius = float(o.get_block_radius())
			var offset: Vector2 = pos - (o as Node2D).global_position
			if offset.length() < radius + 20.0:
				# Empuja hacia afuera del obstaculo.
				var dir: Vector2 = offset.normalized() if offset.length() > 0.01 else Vector2.RIGHT.rotated(randf() * TAU)
				pos = (o as Node2D).global_position + dir * (radius + 24.0)
				blocked = true
				break
		if not blocked:
			break
	return pos


func _cached_obstacles() -> Array:
	if _obstacle_cache_timer <= 0.0:
		_obstacle_cache = get_tree().get_nodes_in_group("obstacles")
		_obstacle_cache_timer = 0.5
	return _obstacle_cache


func _on_enemy_died(_position: Vector2, _xp_value: int) -> void:
	_alive_count = max(_alive_count - 1, 0)
	_kills += 1
	_kill_times.append(_elapsed_time)


## Selección ponderada con pesos que crecen según la dificultad, de modo que
## ciertos tipos (p.ej. runners) aparezcan más a medida que sube la presión.
func _pick_enemy_type() -> EnemyData:
	if enemy_types.is_empty():
		return null

	var total_weight: float = 0.0
	for enemy_type in enemy_types:
		if enemy_type != null:
			total_weight += _effective_weight(enemy_type)

	if total_weight <= 0.0:
		return enemy_types[0]

	var roll: float = randf() * total_weight
	for enemy_type in enemy_types:
		if enemy_type == null:
			continue
		roll -= _effective_weight(enemy_type)
		if roll <= 0.0:
			return enemy_type

	return enemy_types[0]


func _effective_weight(enemy_type: EnemyData) -> float:
	var weight: float = enemy_type.spawn_weight + enemy_type.weight_growth * _difficulty_score
	if enemy_type != null and enemy_type.id == &"runner_zombie_dog":
		if _get_companion_count() >= 3:
			weight += 0.55
		# Manada de runners activa: los runners dominan la seleccion.
		weight += _runner_boost
		# Modificador de mapa (Fase 06): biomas con mas/menos runners.
		weight *= _map_runner_mult
	return max(0.0, weight)
