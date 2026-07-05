extends Node2D
## Genera perros zombis alrededor del jugador y escala la dificultad de forma
## CONTINUA mediante un difficulty_score que combina tiempo, nivel del jugador
## y enemigos eliminados. Todos los efectos tienen límites para que la curva
## sea exigente pero nunca imposible demasiado pronto.
##
## difficulty_score = minutos_sobrevividos * time_weight
##                  + nivel_jugador * level_weight
##                  + enemigos_eliminados / kills_divisor
##                  + upgrades_elegidos * upgrade_weight
##                  + companions * companion_weight

const EnemyData = preload("res://scripts/enemies/enemy_data.gd")

signal stats_updated(kills: int, difficulty: float)

@export var enemy_scene: PackedScene
@export var enemy_types: Array[EnemyData] = []

@export_group("Fórmula de dificultad")
## Peso de los minutos sobrevividos en el score.
@export var time_weight: float = 1.2
## Peso del nivel del jugador en el score.
@export var level_weight: float = 0.9
## Cada cuántos kills se suma 1 punto de dificultad.
@export var kills_divisor: float = 35.0
## Peso de cada mejora elegida (premia builds avanzadas con más presión).
@export var upgrade_weight: float = 0.35
## Peso de cada gato rescatado en la dificultad. Suavizado en Fase 04: con armas
## y compañeros la presión ya crece por otros lados, 1.1 castigaba demasiado.
@export var companion_weight: float = 0.7
## Ligera compensacion si varios companeros estan derribados.
@export var downed_companion_weight: float = -0.25
## Peso de cada arma activa (Fase 04.5): mas armas = mas presion.
@export var weapon_weight: float = 0.7
## Peso de cada nivel de arma acumulado (builds muy subidas = mas presion).
@export var weapon_level_weight: float = 0.18

@export_group("Aparición")
## Bajado de 1.2 a 0.95: el primer minuto tiene mas accion (critica de "poco
## divertido" por arranque lento). La dificultad lo sigue acortando sola.
@export var base_spawn_interval: float = 0.95
@export var min_spawn_interval: float = 0.30
## Cuánto baja el intervalo por punto de dificultad.
@export var interval_per_point: float = 0.05
@export var base_max_enemies: int = 22
## Enemigos vivos extra permitidos por punto de dificultad.
@export var enemies_per_point: float = 3.0
@export var min_radius: float = 520.0
@export var max_radius: float = 760.0

@export_group("Escalado de enemigos")
@export var health_per_point: float = 0.06
@export var max_health_multiplier: float = 2.6
@export var speed_per_point: float = 0.025
@export var max_speed_multiplier: float = 1.7
@export var damage_per_point: float = 0.04
@export var max_damage_multiplier: float = 2.2

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
## Presion extra por mejoras permanentes (Fase 07). Se lee una vez al iniciar.
var _permanent_power: float = 0.0
## Presion extra por el poder del Refugio (Fase 10): objetos colocados.
var _shelter_power: float = 0.0


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_perf = get_node_or_null("/root/Performance")
	# Las mejoras permanentes suben un poco la presion (Fase 07).
	var mp: Node = get_node_or_null("/root/MetaProgression")
	if mp != null and mp.has_method("get_permanent_power_score"):
		_permanent_power = float(mp.get_permanent_power_score())
	# El Refugio tambien (Fase 10): solo los objetos COLOCADOS cuentan.
	var shelter: Node = get_node_or_null("/root/Shelter")
	if shelter != null and shelter.has_method("get_power_score"):
		_shelter_power = float(shelter.get_power_score())

	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = base_spawn_interval
	_spawn_timer.autostart = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)


func _process(delta: float) -> void:
	_elapsed_time += delta
	if _emergency_cooldown > 0.0:
		_emergency_cooldown -= delta
	_update_event_timers(delta)
	_update_backpressure(delta)
	_maybe_emergency_cleanup()
	_recalculate_difficulty()


## Numero real de enemigos vivos (incluye jefes/mini-jefes, que tambien presionan).
## Se lee del grupo para no desincronizarse con spawns externos ni con muertes que
## no pasan por la señal del spawner.
func _alive_enemies() -> int:
	return get_tree().get_node_count_in_group("enemies")


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
	var candidates: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.is_in_group("boss") or e.is_in_group("miniboss"):
			continue
		var d: float = (e as Node2D).global_position.distance_to(_player.global_position)
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


## Recalcula el score y ajusta el ritmo de aparición en vivo.
func _recalculate_difficulty() -> void:
	var minutes: float = _elapsed_time / 60.0
	var player_level: int = _get_player_level()
	_difficulty_score = minutes * time_weight \
		+ player_level * level_weight \
		+ _kills / kills_divisor \
		+ _get_player_upgrades() * upgrade_weight \
		+ _get_companion_count() * companion_weight \
		+ _get_downed_companion_count() * downed_companion_weight \
		+ _get_weapon_count() * weapon_weight \
		+ _get_total_weapon_levels() * weapon_level_weight

	# Modificador del mapa activo (Fase 06): escala la presion global.
	_difficulty_score *= _map_difficulty_mult
	# Mejoras permanentes (Fase 07.5): presion extra suave segun el poder acumulado.
	_difficulty_score += _permanent_power * 0.12
	# Poder del Refugio (Fase 10): mas equipo colocado = algo mas de presion.
	_difficulty_score += _shelter_power * 0.10

	# La horda acorta el intervalo (mas spawns); el backpressure lo alarga si hay
	# saturacion. rate>1 = mas rapido, rate<1 = mas lento.
	var interval: float = base_spawn_interval - _difficulty_score * interval_per_point
	var rate: float = max(0.05, _horde_intensity * _spawn_multiplier)
	interval /= rate
	_spawn_timer.wait_time = max(min_spawn_interval, interval)

	stats_updated.emit(_kills, _difficulty_score)


func _get_player_level() -> int:
	if not is_instance_valid(_player):
		return 1
	var level_value = _player.get("level")
	if level_value == null:
		return 1
	return int(level_value)


func _get_player_upgrades() -> int:
	if not is_instance_valid(_player):
		return 0
	var value = _player.get("upgrades_chosen")
	if value == null:
		return 0
	return int(value)


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


func _get_weapon_count() -> int:
	var manager: Node = _get_weapon_manager()
	if not is_instance_valid(manager) or not manager.has_method("get_weapon_count"):
		return 0
	return int(manager.get_weapon_count())


func _get_total_weapon_levels() -> int:
	var manager: Node = _get_weapon_manager()
	if not is_instance_valid(manager) or not manager.has_method("get_total_weapon_levels"):
		return 0
	return int(manager.get_total_weapon_levels())


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
	var dynamic: float = base_max_enemies + _difficulty_score * enemies_per_point + extra
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
	# Se suprime bajo backpressure fuerte para no castigar cuando ya hay saturacion.
	if _spawn_multiplier < 0.5:
		return
	var wave_chance: float = min(max_wave_chance, base_wave_chance + _difficulty_score * wave_chance_per_point)
	if randf() < wave_chance:
		for _i in wave_extra_enemies:
			if not _can_spawn_more():
				break
			_spawn_enemy()


func _spawn_enemy() -> void:
	var enemy := enemy_scene.instantiate() as Node2D
	if enemy == null:
		return

	var enemy_type: EnemyData = _pick_enemy_type()
	if enemy.has_method("configure"):
		enemy.call("configure", enemy_type, _health_multiplier(), _speed_multiplier(), _damage_multiplier())

	# Elites: raros al principio (1.5%), hasta 10% con la dificultad alta. Dan XP x4.
	var elite_chance: float = clampf(0.015 + _difficulty_score * 0.004, 0.0, 0.10)
	if randf() < elite_chance and enemy.has_method("make_elite"):
		enemy.call("make_elite", ([&"veloz", &"blindado", &"gigante"] as Array[StringName]).pick_random())

	enemy.global_position = _resolve_spawn_position(_player.global_position + _spawn_offset())
	if enemy.has_signal("died"):
		enemy.connect("died", Callable(self, "_on_enemy_died"))

	# Los enemigos cuelgan del nivel para vivir aparte del spawner.
	get_parent().add_child(enemy)
	_alive_count += 1


func _health_multiplier() -> float:
	return min(max_health_multiplier, 1.0 + _difficulty_score * health_per_point) * _map_health_mult


func _speed_multiplier() -> float:
	return min(max_speed_multiplier, 1.0 + _difficulty_score * speed_per_point) * _map_speed_mult


func _damage_multiplier() -> float:
	# El mult del mapa/dificultad de historia se aplica FUERA del tope: la
	# dificultad elegida debe sentirse siempre, incluso con el score saturado.
	return min(max_damage_multiplier, 1.0 + _difficulty_score * damage_per_point) * _map_damage_mult


## Decide dónde aparece el enemigo: en el borde visible de la cámara (presión
## alta) o en el anillo lejano. La probabilidad de borde sube con la dificultad.
func _spawn_offset() -> Vector2:
	var edge_chance: float = min(max_edge_chance, base_edge_chance + _difficulty_score * edge_chance_per_point)
	if randf() < edge_chance:
		return _camera_edge_offset(randf() * TAU)
	return _random_ring_offset()


## Calcula un punto justo fuera del rectángulo visible de la cámara en una
## dirección dada, para que el enemigo "entre en escena" cerca del jugador.
func _camera_edge_offset(angle: float) -> Vector2:
	var direction: Vector2 = Vector2.RIGHT.rotated(angle)
	var half_extent: Vector2 = Vector2(960, 540)
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
	var obstacles := get_tree().get_nodes_in_group("obstacles")
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
