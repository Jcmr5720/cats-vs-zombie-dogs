extends CharacterBody2D
## Perro zombi. Persigue al jugador con un leve zigzag para no amontonarse,
## recibe daño (con flash de impacto), muere con una desaparición animada y
## suelta un orbe de experiencia. Se configura con un EnemyData y multiplicadores
## de dificultad para reutilizar la misma escena con muchas variantes.

signal died(position: Vector2, xp_value: int)

const EnemyData = preload("res://scripts/enemies/enemy_data.gd")
const CompanionBalance = preload("res://scripts/companions/companion_balance.gd")

@export var max_health: int = 20
@export var speed: float = 90.0
@export var contact_damage: int = 10
@export var xp_value: int = 3
## Distancia a la que el perro daña al gato por contacto.
@export var contact_range: float = 36.0
## Escena del orbe de experiencia que se suelta al morir.
@export var xp_orb_scene: PackedScene
@export var enemy_data: EnemyData

var current_health: int
var _player: Node2D
var _chase_target: Node2D
var _is_dead: bool = false
var _health_multiplier: float = 1.0
var _speed_multiplier: float = 1.0
var _damage_multiplier: float = 1.0

# Variación de movimiento para que no se muevan todos idénticos.
var _speed_jitter: float = 1.0
var _wobble_phase: float = 0.0
var _wobble_strength: float = 0.0
var _wobble_speed: float = 0.0
var _time: float = 0.0

var _base_scale: Vector2 = Vector2.ONE
var _flash_tween: Tween

## Elite: variante rara con modificador (&"veloz"/&"blindado"/&"gigante"), aura
## de color y XP x4. Se marca antes de entrar al arbol y se aplica tras
## _apply_config para que los multiplicadores no se pisen.
var _elite_kind: StringName = &""
var _elite_aura: Polygon2D

# --- Partidas rapidas por fases: comportamiento por tipo (EnemyData.behavior) ---
## Rama de comportamiento activa (&"" = persecucion clasica).
var _behavior: StringName = &""
## Nivel de comportamiento (FASE 11): 1 = basico, 2 = tactico, 3 = coordinado.
## Lo fija el spawner segun la fase del PhaseDirector; los enemigos ganan
## conducta nueva con el tiempo, no solo estadisticas.
var behavior_level: int = 1
## Estado generico de la mutacion elite activa (sobrecargado, carga de manada...).
var _mutation_timer: float = 0.0
var _mutation_state: int = 0
var _mutation_state_timer: float = 0.0
## Multiplicador de velocidad de la mutacion (sobrecargado alterna con el).
var _mutation_speed_mult: float = 1.0
## Placas de la mutacion "chatarra": reducen daño y se rompen por etapas.
var _scrap_plates: int = 0
## Perro de manada nivel 3: temporizador de la carga coordinada.
var _pack_charge_timer: float = 9.0
## Cooldown general del comportamiento (embestida, salto, aullido, escupitajo).
var _behavior_timer: float = 0.0
## Sub-estado (embestidor/cazador/explosivo/sanador) y su temporizador.
var _behavior_state: int = 0
var _behavior_state_timer: float = 0.0
## Direccion fijada durante una embestida o salto.
var _behavior_dir: Vector2 = Vector2.ZERO
var _behavior_hit_done: bool = false
## Flanqueador: lado elegido al nacer (no cambia de lado constantemente).
var _flank_side: float = 1.0
## Flanqueador N2/N3: punto de ruta lateral que intenta ocupar, y su vigencia.
## Se recalcula con cadencia baja: cambiar de destino cada frame produce el
## movimiento erratico que el diseño prohibe expresamente.
var _flank_route: Vector2 = Vector2.ZERO
var _flank_route_timer: float = 0.0
var _flank_closing: bool = false
## true cuando el flanqueador ya llego a la ruta que eligio (flanqueo completado).
var _flank_arrived: bool = false
## Territorio de manada: fuerza (0 = fuera), centro y radio de la marca que lo
## cubre. Lo refresca la marca por tick; caduca solo si el perro sale de ella.
var _territory_strength: float = 0.0
var _territory_center: Vector2 = Vector2.ZERO
var _territory_radius: float = 0.0
var _territory_timer: float = 0.0
## Manada N2: ruta de aproximacion asignada a ESTE perro (indice en _pack_routes).
var _pack_route_index: int = -1
## Manada N3: telegrafo de la carga en curso (>0 = avisando, aun sin cargar).
var _charge_telegraph: float = 0.0
var _charge_is_leader: bool = false
## Aullador: cooldown de la LLAMADA de refuerzos (independiente del aullido).
var _howler_call_timer: float = 0.0
## Orden recibida de un Aullador (&"press"/&"flank"/&"regroup"/&"charge") y su TTL.
var _order: StringName = &""
var _order_timer: float = 0.0
var _order_point: Vector2 = Vector2.ZERO
## Perro de manada: bonus activo (0..PACK_BONUS_CAP) y anillo visual.
var _pack_bonus: float = 0.0
var _pack_scan_timer: float = 0.0
var _pack_ring: Polygon2D
## Potenciacion temporal del Aullador (no se apila: gana la mayor).
var _buff_mult: float = 1.0
var _buff_timer: float = 0.0
## Cazador: objetivo mantenido un tiempo minimo.
var _hunter_target: Node2D
var _hunter_target_timer: float = 0.0
## Esbirros del jefe: jefe vinculado y curacion restante del sanador.
var _boss: Node2D
var _heal_left: int = 0
var _heal_tick_timer: float = 0.0
## Telegrafo del embestidor (linea) y del vinculo del sanador.
var _charge_line: Line2D
var _healer_link: Line2D

const PACK_BONUS_PER_DOG: float = 0.07
const PACK_BONUS_CAP: float = 0.21
const PACK_RADIUS: float = 200.0

# --- Coordinacion de manada del Barrio (FASE 2) --------------------------------
# Estado de GRUPO, no de instancia: vive en `static var` en vez de en un nodo
# coordinador aparte (el proyecto no quiere otra capa de IA paralela). Todo lo
# que hay aqui es un puñado de contadores y una lista de rutas cacheada.
#
# IMPORTANTE: las `static var` sobreviven a un cambio de escena. `reset_pack_coordination()`
# lo llama el PhaseDirector al arrancar la partida; sin eso, reiniciar arrastraria
# lideres muertos y cargas fantasma de la run anterior.

## Cargas coordinadas simultaneas permitidas. Con mas, el jugador recibe
## embestidas desde todas partes y deja de poder leerlas una por una.
const MAX_SIMULTANEOUS_CHARGES: int = 2
## Cada cuanto se recalculan las rutas urbanas de aproximacion (caro: consulta
## geometria). Muy por encima del frame: la manada no necesita replanear a 60 Hz.
const ROUTE_REFRESH_INTERVAL: float = 2.5
## Anticipacion de la carga coordinada: el jugador DEBE poder reaccionar.
const CHARGE_TELEGRAPH: float = 0.9

## Rutas de aproximacion vigentes (puntos urbanos alrededor del objetivo).
static var _pack_routes: Array[Vector2] = []
static var _pack_routes_time: float = -999.0
static var _pack_routes_center: Vector2 = Vector2.ZERO
## Cargas coordinadas activas (lideres vivos preparando o ejecutando carga).
static var _active_charge_leaders: Array = []
## Flanqueadores que estan cerrando una ruta ahora mismo, por jugador objetivo.
## Sirve para la regla "nunca sellar todas las salidas a la vez".
static var _closing_flankers: Dictionary = {}


## Reinicio del estado compartido. Lo llama el arranque de partida: las static
## vars no se limpian solas al recargar la escena.
static func reset_pack_coordination() -> void:
	_pack_routes.clear()
	_pack_routes_time = -999.0
	_pack_routes_center = Vector2.ZERO
	_active_charge_leaders.clear()
	_closing_flankers.clear()


## Cargas coordinadas vivas ahora mismo (purga lideres muertos de paso).
static func active_charge_count() -> int:
	for i in range(_active_charge_leaders.size() - 1, -1, -1):
		var leader = _active_charge_leaders[i]
		if not is_instance_valid(leader) or leader.get("_is_dead"):
			_active_charge_leaders.remove_at(i)
	return _active_charge_leaders.size()


## Flanqueadores cerrando ruta contra `target` (purga los que ya no son validos).
static func closing_flanker_count(target: Node) -> int:
	var key: int = target.get_instance_id() if target != null else 0
	var list: Array = _closing_flankers.get(key, [])
	for i in range(list.size() - 1, -1, -1):
		if not is_instance_valid(list[i]) or list[i].get("_is_dead"):
			list.remove_at(i)
	_closing_flankers[key] = list
	return list.size()
const CHARGER_TRIGGER_RANGE: float = 340.0
const HUNTER_LEAP_RANGE: float = 300.0
const HEALER_TOTAL_HEAL: int = 150
const ENEMY_PROJECTILE_SCRIPT := preload("res://scripts/enemies/enemy_projectile.gd")
const HAZARD_ZONE_SCRIPT := preload("res://scripts/enemies/hazard_zone.gd")
const PUP_DATA_PATH := "res://data/enemies/pup_zombie_dog.tres"

# Steering lateral para rodear obstaculos cuando move_and_slide choca contra uno.
var _avoid: Vector2 = Vector2.ZERO
var _subtarget: Vector2 = Vector2.ZERO
var _has_subtarget: bool = false
var _last_position: Vector2 = Vector2.ZERO
var _stuck_time: float = 0.0
var _stuck_check_timer: float = 0.0
var _recovery_timer: float = 0.0
var _avoidance_skill: float = 1.0
var _lookahead_distance: float = 48.0
## Atasco DURO: en layouts de semilla estrechos un enemigo puede quedar acuñado
## entre obstaculos donde el rodeo lateral no basta. Se mide el tiempo acumulado
## realmente atascado; superado un umbral, entra en modo "fantasma": atraviesa
## los obstaculos brevemente y avanza recto hacia el objetivo para desatascarse.
var _hard_stuck_time: float = 0.0
var _ghost_timer: float = 0.0
const HARD_STUCK_LIMIT: float = 2.4
const GHOST_DURATION: float = 0.7
## Umbral de atasco duro como VARIABLE: la mutacion "sabueso" lo baja (atraviesa
## obstaculos antes: sigue el rastro del jugador).
var _hard_stuck_limit: float = HARD_STUCK_LIMIT

# Knockback: impulso que decae y se suma a la velocidad de persecución.
var _knockback: Vector2 = Vector2.ZERO
## Cuánto empuja un impacto (px/s). Los runners, más ligeros, se mueven más.
@export var knockback_strength: float = 150.0
@export var knockback_decay: float = 9.0

# Separación simple para que no se apilen todos en el mismo punto.
@export var separation_radius: float = 26.0
@export var separation_strength: float = 36.0
@export var separation_update_interval: float = 0.10
@export var separation_neighbor_limit: int = 10
var _separation_cache: Vector2 = Vector2.ZERO
var _separation_timer: float = 0.0

## Ralentizacion externa (barricada del policia, empujon). Multiplica la
## velocidad mientras dura; no se apila: gana la mas fuerte.
var _slow_mult: float = 1.0
var _slow_timer: float = 0.0

## Cache del compañero objetivo/en contacto: el escaneo del grupo "companions"
## se hace en ticks (0.25 s), no cada frame por enemigo (rendimiento en hordas).
var _companion_scan_timer: float = 0.0
var _cached_companion: Node2D
## Cache del jugador objetivo: mismo criterio (el grupo "players" se recorria
## cada frame de fisica POR ENEMIGO; con hordas grandes era coste puro).
var _target_scan_timer: float = 0.0

## Controlador visual de sprites (ETAPA ARTISTICA 2/3). Puede no existir.
@onready var _sprite_visual: Node = get_node_or_null("SpriteVisual")
## Cadencia de la ANIMACION de mordisco (solo visual; el dano sigue siendo el
## contacto continuo regulado por la invulnerabilidad del objetivo).
var _attack_anim_timer: float = 0.0
@onready var _visual: Node2D = $Visual
@onready var _body: Polygon2D = $Visual/Body
@onready var _snout: Polygon2D = $Visual/Snout
@onready var _eye_left: Polygon2D = $Visual/EyeLeft
@onready var _eye_right: Polygon2D = $Visual/EyeRight
@onready var _outline: Polygon2D = $Visual/Outline
@onready var _ears: Polygon2D = $Visual/Ears
@onready var _legs: Polygon2D = $Visual/Legs
@onready var _tail: Polygon2D = $Visual/Tail
@onready var _jaw: Polygon2D = $Visual/Jaw
@onready var _scar: Polygon2D = $Visual/Scar
@onready var _collar: Polygon2D = $Visual/Collar
@onready var _stud: Polygon2D = $Visual/Stud
@onready var _drool: Polygon2D = $Visual/Drool
@onready var _spikes: Polygon2D = $Visual/Spikes
@onready var _pupil_left: Polygon2D = $Visual/PupilLeft
@onready var _pupil_right: Polygon2D = $Visual/PupilRight

# Orientación del cuerpo: se rota solo el nodo Visual y se voltea verticalmente
# al mirar a la izquierda, para que el perro nunca quede boca abajo. La sombra
# y la colisión no rotan. El pop de spawn escala el Visual desde pequeño.
var _face_angle: float = 0.0
var _spawn_scale: float = 1.0


func _ready() -> void:
	add_to_group("enemies")
	# Colisiona con los obstaculos de mapa (capa 5, Fase 08.75) para rodearlos.
	set_collision_mask_value(5, true)
	_randomize_movement()
	_apply_config()
	_last_position = global_position
	# El jugador objetivo se localiza por grupo. En coop hay 2 jugadores: se elige
	# el vivo mas cercano; en solo devuelve al unico jugador (comportamiento igual).
	_player = _resolve_target_player()
	# Pop de aparición: el cuerpo crece desde pequeño (la colisión no se toca).
	_spawn_scale = 0.25
	var pop := create_tween()
	pop.tween_property(self, "_spawn_scale", 1.0, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	# Reevalua el jugador objetivo (coop: el vivo mas cercano puede cambiar) en
	# ticks de 0.2 s, no cada frame: con 50+ enemigos el escaneo continuo pesaba.
	_target_scan_timer -= delta
	if _target_scan_timer <= 0.0 or not is_instance_valid(_player):
		_target_scan_timer = 0.2
		_player = _resolve_target_player()
	if not is_instance_valid(_player):
		velocity = Vector2.ZERO
		return

	_time += delta

	# Modo fantasma para salir de un acuñamiento duro: mientras dura, no colisiona
	# con obstaculos (se restaura la mascara al expirar).
	if _ghost_timer > 0.0:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			set_collision_mask_value(5, true)

	# Potenciacion del Aullador: decae sola (no se apila).
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_buff_mult = 1.0

	# Efectos continuos de la mutacion elite (lider, carroñero, sobrecargado).
	if _elite_kind != &"":
		_mutation_tick(delta)

	# Comportamientos por fase: efectos periodicos (aullido, escupitajo, manada)
	# y estados con control TOTAL del movimiento (embestida, salto, mecha, canal).
	if _behavior != &"":
		_behavior_tick(delta)
		if _behavior_full_control(delta):
			if _attack_anim_timer > 0.0:
				_attack_anim_timer -= delta
			_animate_visual()
			return

	_nearest_companion_cached(delta)
	_chase_target = _pick_chase_target()
	var target_position: Vector2 = _player.global_position
	if is_instance_valid(_chase_target):
		target_position = _chase_target.global_position
	if _behavior != &"":
		target_position = _behavior_target_position(target_position)
	var direction: Vector2 = _steered_direction(target_position, delta)
	# Zigzag suave: cada enemigo serpentea con fase y fuerza propias.
	var wobble: float = sin(_time * _wobble_speed + _wobble_phase) * _wobble_strength
	if not _has_subtarget:
		direction = direction.rotated(wobble)
	# Ralentizacion externa (zonas de control de los compañeros).
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_mult = 1.0
	velocity = direction * speed * _speed_jitter * _slow_mult * _buff_mult * _mutation_speed_mult * (1.0 + _pack_bonus) \
		+ _separation(delta) + _knockback + _avoid
	move_and_slide()
	if velocity.length_squared() > 1.0:
		_face_angle = lerp_angle(_face_angle, velocity.angle(), 0.16)

	# Si chocamos con un obstaculo, generamos un empuje lateral para rodearlo.
	_avoid = _avoid.move_toward(Vector2.ZERO, speed * 4.0 * delta)
	if get_slide_collision_count() > 0:
		var col := get_last_slide_collision()
		if col != null:
			var normal: Vector2 = col.get_normal()
			var side: float = _best_side(target_position, normal)
			_avoid = Vector2(-normal.y, normal.x) * side * speed * (0.55 + _avoidance_skill * 0.28)
	_update_stuck_state(delta, target_position)

	# El knockback decae de forma exponencial hasta desvanecerse.
	if _knockback != Vector2.ZERO:
		_knockback *= exp(-knockback_decay * delta)
		if _knockback.length_squared() < 1.0:
			_knockback = Vector2.ZERO

	if _attack_anim_timer > 0.0:
		_attack_anim_timer -= delta

	# Daño por contacto continuo; el cooldown del jugador regula el ritmo.
	_try_contact_damage()
	_animate_visual()


func configure(enemy_type: EnemyData, health_multiplier: float = 1.0, speed_multiplier: float = 1.0, damage_multiplier: float = 1.0) -> void:
	enemy_data = enemy_type
	_health_multiplier = health_multiplier
	_speed_multiplier = speed_multiplier
	_damage_multiplier = damage_multiplier
	if is_node_ready():
		_apply_config()


## Recibe daño de un proyectil. `knockback_dir` viene normalizado desde la bala.
func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if _is_dead:
		return

	# Blindado: resiste parcialmente los ataques FRONTALES (debil de lado/atras).
	# El disparo viaja en knockback_dir: es frontal si llega contra la cara.
	if _behavior == &"armored" and knockback_dir != Vector2.ZERO:
		var facing := Vector2.RIGHT.rotated(_face_angle)
		if facing.dot(-knockback_dir.normalized()) > 0.35:
			amount = maxi(1, int(round(amount * 0.4)))
			# Chispa gris: se LEE que el golpe reboto en el blindaje frontal.
			Feedback.hit_effect(global_position, Color(0.7, 0.75, 0.85, 0.8), 0.18, 0.9)

	# Embestidor aturdido tras fallar/chocar: ventana de vulnerabilidad.
	if _behavior == &"charger" and _behavior_state == 3:
		amount = int(round(amount * 1.5))

	# Mutacion "chatarra": placas que reducen el daño y se rompen por etapas
	# (cada 25% de vida perdida cae una placa, con chispa que se LEE).
	if _elite_kind == &"chatarra" and _scrap_plates > 0:
		amount = maxi(1, int(round(amount * 0.55)))
	# Mutacion "sobrecargado": durante el aturdimiento es VULNERABLE.
	if _elite_kind == &"sobrecargado" and _mutation_state == 1:
		amount = int(round(amount * 1.5))

	# Objetivo prioritario del Gato Policia: el enemigo marcado recibe daño
	# extra de TODO el equipo (jugadores, compañeros y torretas).
	if has_meta(&"companion_mark"):
		amount = max(1, int(round(amount * (1.0 + CompanionBalance.POLICE_MARK_DAMAGE_BONUS))))

	current_health -= amount

	# Rotura de placas de chatarra por umbrales de vida (75/50/25%).
	if _elite_kind == &"chatarra" and _scrap_plates > 0 and max_health > 0:
		var ratio: float = float(current_health) / float(max_health)
		# La placa N cae al bajar del 25%*N de vida (3 placas: 75/50/25%).
		while _scrap_plates > 0 and ratio < 0.25 * float(_scrap_plates):
			_scrap_plates -= 1
			Feedback.hit_effect(global_position, Color(0.75, 0.78, 0.85, 0.9), 0.35, 1.6)
			if _scrap_plates == 0:
				# Sin blindaje: se acelera (nucleo expuesto, mas agresivo).
				speed *= 1.1

	# Game feel: número de daño flotante + destello de impacto.
	Feedback.damage_number(global_position + Vector2(0, -18), amount)
	Feedback.hit_effect(global_position, Color(1.0, 0.95, 0.6, 0.9), 0.3, 1.1)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"enemy_hit")

	if knockback_dir != Vector2.ZERO:
		_knockback += knockback_dir.normalized() * knockback_strength

	if current_health <= 0:
		_die()
	else:
		_flash_hit()


## Suma de empujes de los enemigos cercanos para que no se apilen en un punto.
func _separation(delta: float) -> Vector2:
	_separation_timer -= delta
	if _separation_timer > 0.0:
		return _separation_cache
	_separation_timer = separation_update_interval + randf_range(0.0, separation_update_interval * 0.45)
	var push: Vector2 = Vector2.ZERO
	var radius_sq: float = separation_radius * separation_radius
	var found: int = 0
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var offset: Vector2 = global_position - (other as Node2D).global_position
		var dist_sq: float = offset.length_squared()
		if dist_sq > 0.01 and dist_sq < radius_sq:
			# Más cerca = empuje más fuerte (peso 1/dist).
			push += offset / sqrt(dist_sq) * (1.0 - dist_sq / radius_sq)
			found += 1
			if found >= separation_neighbor_limit:
				break
	_separation_cache = push * separation_strength
	return _separation_cache


func _steered_direction(target_position: Vector2, delta: float) -> Vector2:
	if _recovery_timer > 0.0:
		_recovery_timer -= delta
		if _has_subtarget:
			return global_position.direction_to(_subtarget)

	if _has_subtarget:
		if global_position.distance_to(_subtarget) < 34.0 or global_position.distance_to(target_position) < global_position.distance_to(_subtarget):
			_has_subtarget = false
		else:
			return global_position.direction_to(_subtarget)

	var direct: Vector2 = global_position.direction_to(target_position)
	if not _would_hit_obstacle(direct):
		return direct

	var left: Vector2 = direct.rotated(PI * 0.5)
	var right: Vector2 = direct.rotated(-PI * 0.5)
	var left_clear: bool = not _would_hit_obstacle((direct + left * _avoidance_skill).normalized())
	var right_clear: bool = not _would_hit_obstacle((direct + right * _avoidance_skill).normalized())
	var chosen: Vector2 = direct
	if left_clear and right_clear:
		var left_point: Vector2 = global_position + left * _lookahead_distance * 2.0
		var right_point: Vector2 = global_position + right * _lookahead_distance * 2.0
		chosen = (direct + (left if left_point.distance_to(target_position) < right_point.distance_to(target_position) else right) * _avoidance_skill).normalized()
	elif left_clear:
		chosen = (direct + left * _avoidance_skill).normalized()
	elif right_clear:
		chosen = (direct + right * _avoidance_skill).normalized()
	else:
		var side: Vector2 = left if sin(_time + _wobble_phase) > 0.0 else right
		chosen = side
	_set_subtarget(global_position + chosen * _lookahead_distance * 2.4)
	return chosen


func _would_hit_obstacle(direction: Vector2) -> bool:
	if direction == Vector2.ZERO:
		return false
	return test_move(global_transform, direction.normalized() * _lookahead_distance)


func _best_side(target_position: Vector2, normal: Vector2) -> float:
	var side_a := Vector2(-normal.y, normal.x)
	var side_b := -side_a
	var a_score: float = (global_position + side_a * _lookahead_distance).distance_to(target_position)
	var b_score: float = (global_position + side_b * _lookahead_distance).distance_to(target_position)
	return 1.0 if a_score < b_score else -1.0


func _set_subtarget(pos: Vector2) -> void:
	_subtarget = pos
	_has_subtarget = true


func _update_stuck_state(delta: float, target_position: Vector2) -> void:
	_stuck_check_timer += delta
	if _stuck_check_timer < 0.25:
		return
	var moved: float = global_position.distance_to(_last_position)
	var blocked: bool = get_slide_collision_count() > 0 or _would_hit_obstacle(global_position.direction_to(target_position))
	if moved < 4.0 and blocked:
		_stuck_time += _stuck_check_timer
		# El atasco DURO solo cuenta cuando el rodeo lateral ya no progresa (poco
		# movimiento real pese a estar bloqueado varias comprobaciones seguidas).
		if moved < 4.0:
			_hard_stuck_time += _stuck_check_timer
	else:
		_stuck_time = max(0.0, _stuck_time - _stuck_check_timer * 1.5)
		_hard_stuck_time = max(0.0, _hard_stuck_time - _stuck_check_timer * 2.0)
		if is_in_group("stuck_enemies") and _stuck_time <= 0.05:
			remove_from_group("stuck_enemies")
	if _stuck_time > 0.75:
		add_to_group("stuck_enemies")
		var direct: Vector2 = global_position.direction_to(target_position)
		var side: Vector2 = direct.rotated(PI * 0.5 * (1.0 if sin(_time + _wobble_phase) > 0.0 else -1.0))
		_set_subtarget(global_position + (side * 120.0 + direct * 45.0))
		_avoid = side * speed * (0.7 + _avoidance_skill * 0.25)
		_recovery_timer = 0.45
		_stuck_time = 0.25
	# Acuñado sin salida: activa el modo fantasma para atravesar el obstaculo y
	# avanzar recto hacia el objetivo. Ultimo recurso, breve y poco frecuente.
	if _hard_stuck_time > _hard_stuck_limit and _ghost_timer <= 0.0:
		_ghost_timer = GHOST_DURATION
		set_collision_mask_value(5, false)
		_has_subtarget = false
		_avoid = Vector2.ZERO
		_set_subtarget(target_position)
		_hard_stuck_time = 0.0
		_stuck_time = 0.0
		if is_in_group("stuck_enemies"):
			remove_from_group("stuck_enemies")
	_last_position = global_position
	_stuck_check_timer = 0.0


func _randomize_movement() -> void:
	_speed_jitter = randf_range(0.9, 1.12)
	_wobble_phase = randf() * TAU
	_wobble_strength = randf_range(0.12, 0.35)
	_wobble_speed = randf_range(2.5, 4.5)


## Jugador objetivo: en coop, el jugador ACTIVO (ni muerto ni derribado) mas
## cercano; en solo, el unico jugador. Fallback al grupo "player" por compatibilidad.
func _resolve_target_player() -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if p.has_method("is_active") and not p.is_active():
			continue
		var d: float = global_position.distance_squared_to((p as Node2D).global_position)
		if d < best_distance:
			best_distance = d
			best = p
	if best == null:
		best = get_tree().get_first_node_in_group("player") as Node2D
	return best


## Compañero targetable mas cercano, cacheado en ticks de 0.25 s: antes cada
## enemigo recorria el grupo "companions" DOS veces por frame (persecucion y
## contacto); con hordas grandes era un coste innecesario.
func _nearest_companion_cached(delta: float) -> Node2D:
	_companion_scan_timer -= delta
	if _companion_scan_timer > 0.0:
		if is_instance_valid(_cached_companion) and _cached_companion.has_method("can_be_targeted") \
				and _cached_companion.can_be_targeted():
			return _cached_companion
		return null
	_companion_scan_timer = 0.25
	_cached_companion = null
	var best_distance: float = INF
	for companion in get_tree().get_nodes_in_group("companions"):
		if not is_instance_valid(companion):
			continue
		if not companion.has_method("can_be_targeted") or not companion.can_be_targeted():
			continue
		var distance: float = global_position.distance_to(companion.global_position)
		if distance < best_distance:
			best_distance = distance
			_cached_companion = companion
	return _cached_companion


func _pick_chase_target() -> Node2D:
	var best_target: Node2D = _player
	var player_distance: float = global_position.distance_to(_player.global_position)
	if is_instance_valid(_cached_companion):
		var distance: float = global_position.distance_to(_cached_companion.global_position)
		if distance < min(player_distance * 0.82, 180.0):
			best_target = _cached_companion
	return best_target


func _try_contact_damage() -> void:
	var hit_companion: Node2D = _cached_companion if is_instance_valid(_cached_companion) else null
	if hit_companion != null \
			and global_position.distance_to(hit_companion.global_position) <= contact_range \
			and hit_companion.has_method("take_damage"):
		hit_companion.take_damage(contact_damage, global_position.direction_to(hit_companion.global_position))
		_trigger_attack_anim()
		return
	if global_position.distance_to(_player.global_position) <= contact_range:
		if _player.has_method("take_damage"):
			_player.take_damage(contact_damage)
			_trigger_attack_anim()


## Ralentizacion temporal (barricada/empujon de los compañeros). No se apila:
## conserva la mas fuerte y extiende la duracion.
func apply_slow(mult: float, duration: float) -> void:
	if _is_dead:
		return
	_slow_mult = clampf(minf(_slow_mult, mult), 0.2, 1.0)
	_slow_timer = maxf(_slow_timer, duration)


## Animacion de mordisco (ETAPA ARTISTICA 3, 3.1): se dispara al INTENTAR un
## ataque en rango, con cadencia propia (no cada frame de contacto). La
## animacion NUNCA controla el dano: solo lo representa. Sin perfil de sprite
## activo no hace nada (el procedural conserva su lenguaje actual).
func _trigger_attack_anim() -> void:
	if _attack_anim_timer > 0.0:
		return
	_attack_anim_timer = 0.6  # ~cadencia del cooldown de dano del jugador (0.5)
	if _sprite_visual != null and _sprite_visual.has_method("play_attack"):
		_sprite_visual.play_attack()


## Feedback breve al recibir un impacto: leve "punch" de escala + destello,
## sin partículas. El punch garantiza que se note aunque no haya HDR 2D.
func _flash_hit() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	scale = _base_scale * 1.18
	modulate = Color(1.8, 1.8, 1.8, 1.0)
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(self, "scale", _base_scale, 0.12)
	_flash_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.12)


func _animate_visual() -> void:
	# En modo SPRITE el bob/trote/rotacion procedural no se aplica: la hoja de
	# sprites y el resolver de direcciones lo representan. El aura de elite
	# vive FUERA del Visual y sigue pulsando en ambos modos.
	if _sprite_visual != null and _sprite_visual.has_method("is_sprite_active") and _sprite_visual.is_sprite_active():
		if is_instance_valid(_elite_aura):
			var sprite_aura_pulse: float = 1.0 + sin(_time * 4.0) * 0.14
			_elite_aura.scale = Vector2(sprite_aura_pulse, sprite_aura_pulse)
		return
	# Orientación: el Visual rota hacia el movimiento, pero se voltea en vertical
	# cuando mira a la izquierda para que el perro nunca aparezca boca abajo.
	# La sombra (fuera del Visual) queda siempre plana bajo el cuerpo.
	if is_instance_valid(_visual):
		_visual.rotation = _face_angle
		var face_sign: float = -1.0 if absf(wrapf(_face_angle, -PI, PI)) > PI * 0.5 else 1.0
		_visual.scale = Vector2(_spawn_scale, _spawn_scale * face_sign)

	var pace: float = 9.0 + speed * 0.035
	var gait: float = sin(_time * pace)
	var bob: float = sin(_time * pace * 0.5) * 1.4
	if is_instance_valid(_body):
		_body.position.y = bob
	if is_instance_valid(_outline):
		_outline.position.y = bob
	if is_instance_valid(_snout):
		_snout.position.y = bob
	if is_instance_valid(_jaw):
		_jaw.position.y = bob + max(0.0, gait) * 2.0
	if is_instance_valid(_legs):
		_legs.position.y = abs(gait) * 2.2
	if is_instance_valid(_tail):
		_tail.rotation = sin(_time * pace * 0.7) * 0.18
	if is_instance_valid(_ears):
		_ears.position.y = -abs(gait) * 1.2
	if is_instance_valid(_drool):
		_drool.scale.y = 0.85 + max(0.0, gait) * 0.28
	if is_instance_valid(_spikes):
		_spikes.rotation = sin(_time * pace * 0.4) * 0.04
	if is_instance_valid(_pupil_left):
		_pupil_left.position.x = 0.4 + sin(_time * 3.2 + _wobble_phase) * 0.6
	if is_instance_valid(_pupil_right):
		_pupil_right.position.x = 0.4 + sin(_time * 3.2 + _wobble_phase) * 0.6
	var eye_pulse: float = 0.92 + abs(sin(_time * 5.0)) * 0.28
	if is_instance_valid(_eye_left):
		_eye_left.modulate = Color(eye_pulse, eye_pulse, eye_pulse, 1.0)
	if is_instance_valid(_eye_right):
		_eye_right.modulate = Color(eye_pulse, eye_pulse, eye_pulse, 1.0)
	# Aura de elite: pulso lento de escala y alfa.
	if is_instance_valid(_elite_aura):
		var aura_pulse: float = 1.0 + sin(_time * 4.0) * 0.14
		_elite_aura.scale = Vector2(aura_pulse, aura_pulse)


func _die() -> void:
	_is_dead = true
	velocity = Vector2.ZERO
	# Matar al lider ANTES de que termine el telegrafo cancela la carga: es el
	# contrajuego de la mecanica y debe funcionar tambien si muere por una zona,
	# una explosion o un compañero, no solo por disparo directo.
	_cancel_pack_charge()
	_release_flank_claim(true)
	# Sale del grupo y deja de colisionar para que las balas no lo persigan.
	# Se difiere el cambio de física porque la muerte ocurre dentro del
	# callback de colisión de la bala (no se puede tocar el estado en el flush).
	remove_from_group("enemies")
	set_deferred("collision_layer", 0)
	call_deferred("set_physics_process", false)

	# Efectos de muerte por comportamiento (division, zona infecciosa, guardian).
	_behavior_on_death()
	# Efectos de muerte de la mutacion elite (esporas, parasitos, explosion).
	if _elite_kind != &"":
		_mutation_on_death()

	died.emit(global_position, xp_value)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"enemy_die")
	_drop_xp_orb()
	_drop_powerup()

	# Game feel: pedazos que salen volando + destello + racha de bajas (combo).
	var death_color: Color = enemy_data.body_color if enemy_data != null else Color(0.5, 0.65, 0.45)
	Feedback.death_burst(global_position, death_color)
	Feedback.hit_effect(global_position, death_color.lightened(0.3), 0.4, 1.6)
	Feedback.register_kill()
	if _elite_kind != &"":
		var missions: Node = get_node_or_null("/root/Missions")
		if missions != null:
			missions.add(&"elite_kills")
	if is_instance_valid(_player) and global_position.distance_to(_player.global_position) < 260.0:
		Feedback.shake(0.12)

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()

	# Desaparición rápida: aplasta y desvanece (los pedazos hacen el resto).
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(_base_scale.x * 1.3, _base_scale.y * 0.1), 0.12)
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	tween.chain().tween_callback(queue_free)


## Power-up del suelo al morir (FASE 12). Los ELITES lo sueltan garantizado; los
## comunes con probabilidad baja. La tirada y la tabla las decide el LootDirector:
## aqui solo se avisa de la muerte.
func _drop_powerup() -> void:
	var director: Node = get_tree().get_first_node_in_group("loot_director")
	if not is_instance_valid(director):
		return
	director.call("try_drop_from_enemy", get_parent(), global_position, _elite_kind != &"")


func _drop_xp_orb() -> void:
	if xp_orb_scene == null:
		return

	var orb := xp_orb_scene.instantiate() as Node2D
	if orb == null:
		return
	orb.set("xp_value", xp_value)
	orb.global_position = global_position
	# Pequeño rebote/dispersión al soltarse, para que la muerte se sienta viva.
	orb.set("pop_velocity", Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 140.0))
	# Se añade al árbol del nivel (no al enemigo, que va a desaparecer) de forma
	# diferida, porque la muerte ocurre dentro del flush de física de la bala.
	get_parent().add_child.call_deferred(orb)


func _apply_config() -> void:
	if enemy_data != null:
		max_health = max(1, int(round(enemy_data.max_health * _health_multiplier)))
		speed = enemy_data.speed * _speed_multiplier
		contact_damage = max(1, int(round(enemy_data.contact_damage * _damage_multiplier)))
		xp_value = enemy_data.xp_value
		_tint(enemy_data.body_color, enemy_data.accent_color, enemy_data.eye_color)
		scale = enemy_data.visual_scale
	else:
		max_health = max(1, int(round(max_health * _health_multiplier)))
		speed *= _speed_multiplier
		contact_damage = max(1, int(round(contact_damage * _damage_multiplier)))

	# Personalidad por tipo: silueta, esquive y fisica de empuje distintos.
	var enemy_id: StringName = enemy_data.id if enemy_data != null else &""
	var show_gear: bool = true  # puas/collar (los pesados los llevan; los ligeros no)
	match enemy_id:
		&"runner_zombie_dog":
			# Veloz y escurridizo, silueta limpia.
			_avoidance_skill = 1.55
			_lookahead_distance = 72.0
			separation_radius = 34.0
			separation_strength = 54.0
			show_gear = false
		&"tank_zombie_dog":
			# Mastin pesado: casi inmune al empuje, avanza como un muro.
			_avoidance_skill = 0.75
			_lookahead_distance = 46.0
			knockback_strength = 40.0
			separation_radius = 42.0
			separation_strength = 30.0
			_wobble_strength *= 0.4
		&"pup_zombie_dog":
			# Cachorro liviano: sale despedido con cada golpe, ataca en enjambre.
			_avoidance_skill = 1.3
			_lookahead_distance = 60.0
			knockback_strength = 300.0
			separation_radius = 20.0
			separation_strength = 44.0
			_wobble_strength *= 1.6
			show_gear = false
		_:
			_avoidance_skill = 1.0
			_lookahead_distance = 52.0
	if is_instance_valid(_spikes):
		_spikes.visible = show_gear
	if is_instance_valid(_collar):
		_collar.visible = show_gear
	if is_instance_valid(_stud):
		_stud.visible = show_gear

	# FASE VISUAL 2: glow de ojos FAKE por tipo (Polygon2D, nunca Light2D en
	# enemigos comunes). El runner brilla el doble: se lee venir a toda velocidad.
	var eye_glow := get_node_or_null("Visual/EyeGlow") as Polygon2D
	if eye_glow != null:
		if enemy_id == &"runner_zombie_dog":
			eye_glow.self_modulate = Color(1.6, 1.6, 1.6, 2.2)
			eye_glow.scale = Vector2(1.35, 1.35)
		else:
			eye_glow.self_modulate = Color(1, 1, 1, 1)
			eye_glow.scale = Vector2.ONE

	# Comportamiento por fase (EnemyData.behavior): grupos y arranque de timers.
	_behavior = enemy_data.behavior if enemy_data != null else &""
	if enemy_data != null and enemy_data.role == &"boss_minion":
		add_to_group("boss_minions")
	match _behavior:
		&"pack":
			add_to_group("pack_dogs")
			_ensure_pack_ring()
		&"flanker":
			add_to_group("flankers")
			_flank_side = 1.0 if randf() < 0.5 else -1.0
		&"howler":
			_behavior_timer = 2.0  # primer aullido temprano: su rol se lee pronto
		&"spitter":
			_behavior_timer = 1.6
		&"charger":
			_behavior_timer = 2.2
			knockback_strength = 40.0
		&"hunter":
			_behavior_timer = 2.0
		&"boss_healer":
			_heal_left = HEALER_TOTAL_HEAL

	_base_scale = scale
	current_health = max_health
	if _elite_kind != &"":
		_apply_elite()


## Marca este enemigo como elite. Si aun no se configuro, se aplica despues.
func make_elite(kind: StringName) -> void:
	_elite_kind = kind
	if is_node_ready():
		_apply_elite()


func _apply_elite() -> void:
	var aura_color := Color(1, 1, 1, 0.18)
	match _elite_kind:
		&"veloz":
			speed *= 1.45
			max_health = int(round(max_health * 1.4))
			aura_color = Color(0.35, 0.9, 1.0, 0.20)
		&"blindado":
			max_health = int(round(max_health * 3.0))
			knockback_strength *= 0.35
			aura_color = Color(1.0, 0.85, 0.3, 0.20)
		&"gigante":
			max_health = int(round(max_health * 2.2))
			contact_damage = int(round(contact_damage * 1.5))
			scale *= 1.35
			_base_scale = scale
			aura_color = Color(1.0, 0.4, 0.3, 0.20)
		# --- Mutaciones por bioma (FASE 11) ------------------------------------
		&"lider_manada":
			# Barrio: reorganiza la manada (potencia periodica a los cercanos).
			max_health = int(round(max_health * 1.8))
			_mutation_timer = 2.0
			aura_color = Color(1.0, 0.72, 0.2, 0.22)
		&"carronero":
			# Barrio: se alimenta del campo de batalla (se cura junto a los
			# restos/orbes de las bajas recientes).
			max_health = int(round(max_health * 2.0))
			_mutation_timer = 1.0
			aura_color = Color(0.75, 0.5, 0.25, 0.22)
		&"esporoso":
			# Parque: al morir contamina el suelo (zona infecciosa pequeña).
			max_health = int(round(max_health * 1.6))
			aura_color = Color(0.55, 0.9, 0.3, 0.22)
		&"parasito":
			# Parque: al morir libera criaturas menores.
			max_health = int(round(max_health * 1.7))
			aura_color = Color(0.4, 0.8, 0.55, 0.22)
		&"volatil":
			# Industrial: explota al morir dañando a AMBOS bandos (bien colocado,
			# el jugador lo vuelve en contra de la horda).
			max_health = int(round(max_health * 1.5))
			contact_damage = int(round(contact_damage * 1.2))
			aura_color = Color(1.0, 0.55, 0.15, 0.26)
		&"chatarra":
			# Industrial: 3 placas que reducen daño y caen por etapas (75/50/25%).
			max_health = int(round(max_health * 1.9))
			_scrap_plates = 3
			knockback_strength *= 0.5
			aura_color = Color(0.72, 0.75, 0.82, 0.22)
		&"sabueso":
			# Oscuridad: sigue el rastro (atraviesa antes los obstaculos).
			speed *= 1.12
			max_health = int(round(max_health * 1.6))
			_hard_stuck_limit = 0.9
			aura_color = Color(0.5, 0.35, 0.75, 0.22)
		&"nocturno":
			# Oscuridad: mas rapido y de silueta oscura (los ojos delatan).
			speed *= 1.22
			max_health = int(round(max_health * 1.6))
			modulate = Color(0.62, 0.62, 0.75, 1.0)
			aura_color = Color(0.25, 0.25, 0.5, 0.24)
		&"sobrecargado":
			# Fabrica: alterna sobrecarga veloz y aturdimiento vulnerable.
			max_health = int(round(max_health * 1.8))
			_mutation_state = 0
			_mutation_state_timer = 1.8
			aura_color = Color(0.3, 0.85, 1.0, 0.24)
	current_health = max_health
	xp_value *= 4
	# Aura pulsante bajo el cuerpo: el jugador identifica al elite al instante.
	if _elite_aura == null:
		_elite_aura = Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 20:
			var a: float = TAU * float(i) / 20.0
			pts.append(Vector2(cos(a) * 26.0, sin(a) * 22.0))
		_elite_aura.polygon = pts
		add_child(_elite_aura)
		move_child(_elite_aura, 0)
	_elite_aura.color = aura_color


## Pinta las piezas del placeholder a partir de los colores del EnemyData.
func _tint(body_color: Color, accent_color: Color, eye_color: Color) -> void:
	_body.color = body_color
	_snout.color = accent_color
	_eye_left.color = eye_color
	_eye_right.color = eye_color
	if is_instance_valid(_pupil_left):
		_pupil_left.color = eye_color.darkened(0.88)
	if is_instance_valid(_pupil_right):
		_pupil_right.color = eye_color.darkened(0.88)
	_ears.color = body_color.darkened(0.18)
	_legs.color = body_color.darkened(0.30)
	_tail.color = body_color.darkened(0.18)
	_outline.color = body_color.darkened(0.62)
	if is_instance_valid(_scar):
		_scar.color = body_color.lerp(Color(0.34, 0.08, 0.08), 0.58)
	if is_instance_valid(_collar):
		_collar.color = accent_color.lerp(Color(0.48, 0.10, 0.10), 0.44)
	if is_instance_valid(_stud):
		_stud.color = eye_color.lightened(0.12)
	if is_instance_valid(_drool):
		_drool.color = eye_color.lerp(Color(0.48, 0.96, 0.82), 0.60)
	if is_instance_valid(_spikes):
		_spikes.color = body_color.darkened(0.72)
	if is_instance_valid(_jaw):
		_jaw.color = accent_color.darkened(0.28)
	# Halo tenue tras los ojos: refuerza la lectura "zombi" con el color de ojos.
	var glow := get_node_or_null("Visual/EyeGlow") as Polygon2D
	if glow != null:
		glow.color = Color(eye_color.r, eye_color.g, eye_color.b, 0.14)


# --- Comportamientos de fase (Partidas rapidas por fases) ----------------------
# Cada rama es pequeña y legible: efectos periodicos en _behavior_tick, estados
# con control total del movimiento en _behavior_full_control y desvios de
# objetivo en _behavior_target_position. Los limites globales (proyectiles,
# zonas) viven en RunPhaseConfig.


## Efectos periodicos del comportamiento (aullido, escupitajo, bonus de manada).
func _behavior_tick(delta: float) -> void:
	# Caducidad de los estados de coordinacion (territorio, ordenes, rutas). Son
	# restas sobre floats: coste despreciable y evita punteros colgados.
	if _territory_timer > 0.0:
		_territory_timer -= delta
		if _territory_timer <= 0.0:
			_territory_strength = 0.0
	if _order_timer > 0.0:
		_order_timer -= delta
		if _order_timer <= 0.0:
			_order = &""
	if _flank_route_timer > 0.0:
		_flank_route_timer -= delta
	if _howler_call_timer > 0.0:
		_howler_call_timer -= delta
	match _behavior:
		&"pack":
			_pack_tick(delta)
		&"flanker":
			_flanker_tick(delta)
		&"howler":
			_behavior_timer -= delta
			if _behavior_timer <= 0.0:
				# El aullido tarda menos en repetirse dentro de territorio propio.
				_behavior_timer = 4.5 if in_territory() else 6.0
				_howl()
		&"spitter":
			_behavior_timer -= delta
			if _behavior_timer <= 0.0 and is_instance_valid(_player):
				var d: float = global_position.distance_to(_player.global_position)
				if d < 560.0 and get_tree().get_node_count_in_group(ENEMY_PROJECTILE_SCRIPT.GROUP) \
						< RunPhaseConfig.MAX_ENEMY_PROJECTILES:
					_behavior_timer = 2.8
					_spit()
		&"boss_healer":
			_update_healer_link()


## true si el comportamiento tomo control TOTAL del movimiento este frame.
func _behavior_full_control(delta: float) -> bool:
	match _behavior:
		&"charger":
			return _charger_process(delta)
		&"hunter":
			return _hunter_process(delta)
		&"boss_exploder":
			return _exploder_process(delta)
		&"boss_healer":
			return _healer_channel_process(delta)
	return false


## Desvio del punto objetivo segun el comportamiento (rodeos, kiting, jefe).
func _behavior_target_position(default_target: Vector2) -> Vector2:
	match _behavior:
		&"pack":
			# Durante el telegrafo el lider se PARA y se hace ver: la carga tiene
			# anticipacion real, no es un aceleron sorpresa.
			if _charge_telegraph > 0.0:
				return global_position
			var pack_dist: float = global_position.distance_to(default_target)
			# Orden vigente de un Aullador: manda sobre la conducta por defecto
			# mientras dure. "regroup" junta al grupo en el punto de la orden;
			# "press" va directo; el resto sigue la logica normal de abajo.
			match get_order():
				&"regroup":
					if global_position.distance_to(_order_point) > 190.0:
						return _order_point
				&"press":
					return default_target
			# Nivel 2+: si la manada tiene rutas urbanas vigentes, este perro se
			# aproxima POR SU RUTA hasta estar cerca; solo entonces converge. Es
			# lo que hace que lleguen por calles distintas en vez de en bloque.
			if behavior_level >= 2 and _pack_route_index >= 0 and pack_dist > 340.0:
				var routes := _pack_routes
				if _pack_route_index < routes.size():
					return routes[_pack_route_index]
			# Semicirculo: cada perro ocupa un arco fijo (por id de instancia),
			# asi rodean en vez de apilarse. En territorio el arco se cierra algo
			# mas: la manada se agrupa mejor en su terreno.
			if behavior_level >= 2 and pack_dist > 150.0 and pack_dist < 460.0:
				var slot: int = absi(int(get_instance_id())) % 5
				var to_me: Vector2 = (global_position - default_target).normalized()
				var spread: float = 0.5 if not in_territory() else 0.42
				var slot_dir: Vector2 = to_me.rotated((float(slot) - 2.0) * spread)
				return default_target + slot_dir * 130.0
			return default_target
		&"flanker":
			# Nivel 2+: va a la RUTA lateral elegida (una salida probable del
			# jugador) mientras siga lejos. Cerca ya converge al objetivo: no se
			# queda bailando en una esquina.
			if behavior_level >= 2 and _flank_route != Vector2.ZERO \
					and global_position.distance_to(default_target) > 260.0:
				return _flank_route
			# Nivel 1: rodeo lateral simple. El lado se elige al nacer y no cambia
			# constantemente (nada de saltos instantaneos de un flanco al otro).
			if global_position.distance_to(default_target) > 220.0:
				var to_me2: Vector2 = (global_position - default_target).normalized()
				var side: Vector2 = Vector2(-to_me2.y, to_me2.x) * _flank_side
				return default_target + side * 170.0
			return default_target
		&"spitter":
			# Mantiene distancia: huye si lo acorralan, avanza si queda lejos.
			if not is_instance_valid(_player):
				return default_target
			var d: float = global_position.distance_to(_player.global_position)
			if d < 240.0:
				return global_position + (global_position - _player.global_position).normalized() * 200.0
			if d < 420.0:
				return global_position
			return default_target
		&"hunter":
			if is_instance_valid(_hunter_target):
				return _hunter_target.global_position
			return default_target
		&"boss_guardian":
			# Se interpone entre el jefe y el jugador.
			_resolve_boss()
			if _valid_boss():
				return _boss.global_position + _boss.global_position.direction_to(default_target) * 110.0
			return default_target
		&"boss_healer":
			_resolve_boss()
			if _valid_boss():
				return _boss.global_position
			return default_target
	return default_target


# --- Rutas urbanas compartidas ---------------------------------------------------

## Rutas de aproximacion vigentes alrededor de `center`, cacheadas para TODA la
## manada. Se recalculan como mucho cada ROUTE_REFRESH_INTERVAL segundos, o si el
## objetivo se ha movido lo bastante como para que las rutas viejas no sirvan.
##
## Esta es la consulta que hace que la manada "use las calles": los puntos salen
## de MapGeometry.approach_points(), que los coloca sobre corredores viales
## realmente separados entre si.
func _shared_routes(center: Vector2) -> Array[Vector2]:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - _pack_routes_time < ROUTE_REFRESH_INTERVAL \
			and _pack_routes_center.distance_to(center) < 320.0:
		return _pack_routes
	_pack_routes_time = now
	_pack_routes_center = center
	_pack_routes = []
	var manager: Node = get_tree().get_first_node_in_group("map_manager")
	if not is_instance_valid(manager) or not manager.has_method("get_world_seed"):
		return _pack_routes
	var map = manager.get_active_map() if manager.has_method("get_active_map") else null
	if map == null:
		return _pack_routes
	# 4 rutas: suficientes para repartir la manada y dejar hueco entre ellas.
	_pack_routes = MapGeometry.approach_points(
		manager.get_world_seed(), map.biome, center, 420.0, 4)
	return _pack_routes


# --- Perro de manada ------------------------------------------------------------

func _pack_tick(delta: float) -> void:
	# Nivel 3: carga coordinada. Cada perro sortea su temporizador; al dispararse
	# con manada cerca, se marca LIDER un instante y ordena la carga (potenciacion
	# breve de los perros cercanos, canal del Aullador: no se apila, tope x1.5).
	if behavior_level >= 3:
		_pack_charge_timer -= delta
	# El telegrafo corre por frame (es la ventana de reaccion del jugador); el
	# resto del escaneo de manada sigue a 0.5 s.
	if _charge_telegraph > 0.0:
		_charge_telegraph -= delta
		# Reusa la linea de telegrafo del Embestidor (mismo lenguaje visual: si
		# ves esa linea roja, algo va a cargar) apuntando al jugador.
		if is_instance_valid(_player):
			_behavior_dir = global_position.direction_to(_player.global_position)
			_ensure_charge_line()
			_charge_line.visible = true
			_update_charge_line()
		if _charge_telegraph <= 0.0:
			if is_instance_valid(_charge_line):
				_charge_line.visible = false
			_resolve_pack_charge()
	_pack_scan_timer -= delta
	if _pack_scan_timer > 0.0:
		return
	_pack_scan_timer = 0.5
	var near: int = 0
	for other in get_tree().get_nodes_in_group("pack_dogs"):
		if other == self or not is_instance_valid(other):
			continue
		if global_position.distance_to((other as Node2D).global_position) <= PACK_RADIUS:
			near += 1
			if near >= 3:
				break
	# Bonus LIMITADO (tope PACK_BONUS_CAP): nunca se acumula indefinidamente.
	_pack_bonus = minf(PACK_BONUS_CAP, float(near) * PACK_BONUS_PER_DOG)
	if is_instance_valid(_pack_ring):
		_pack_ring.visible = _pack_bonus > 0.0

	# Nivel 2: reparto de RUTAS urbanas. Cada perro se queda con la ruta que le
	# pilla mas a mano de las que la manada tiene vigentes, y no dos con la misma
	# si hay alternativas: por eso el indice se deriva del id de instancia y solo
	# se reasigna cuando cambia el juego de rutas.
	if behavior_level >= 2 and is_instance_valid(_player):
		var routes := _shared_routes(_player.global_position)
		if routes.is_empty():
			_pack_route_index = -1
		else:
			_pack_route_index = absi(int(get_instance_id())) % routes.size()

	if behavior_level >= 3 and _pack_charge_timer <= 0.0:
		# Dentro de territorio la manada se organiza ANTES: es el efecto de la
		# marca que el jugador debe poder notar y desactivar destruyendola.
		_pack_charge_timer = randf_range(8.0, 12.0)
		if in_territory():
			_pack_charge_timer *= 0.65
		if near >= 2 and is_instance_valid(_player) \
				and global_position.distance_to(_player.global_position) < 520.0 \
				and active_charge_count() < MAX_SIMULTANEOUS_CHARGES:
			_begin_pack_charge()
	# Orden "charge" de un Aullador: adelanta la carga sin saltarse ni el tope
	# simultaneo ni el telegrafo.
	elif behavior_level >= 3 and get_order() == &"charge" and _charge_telegraph <= 0.0 \
			and not _charge_is_leader and active_charge_count() < MAX_SIMULTANEOUS_CHARGES \
			and is_instance_valid(_player) \
			and global_position.distance_to(_player.global_position) < 460.0:
		_order = &""  # la orden se consume: no dispara cargas en bucle
		_begin_pack_charge()


## Este perro se marca LIDER y ANUNCIA la carga. La carga no ocurre aun: primero
## corre el telegrafo (CHARGE_TELEGRAPH). Matar al lider durante esa ventana
## cancela la carga entera — es el contrajuego explicito de la mecanica.
func _begin_pack_charge() -> void:
	_charge_is_leader = true
	_charge_telegraph = CHARGE_TELEGRAPH
	_active_charge_leaders.append(self)
	RunTelemetry.count(&"pack_charges_started")
	# Aviso inconfundible: destello del lider + aullido. Sin esto la carga seria
	# daño sin anticipacion, que el diseño prohibe.
	Feedback.hit_effect(global_position, Color(1.0, 0.72, 0.2, 0.9), 0.7, 3.0)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"event_alert")


## Fin del telegrafo: se ejecuta la carga si el lider sigue vivo y la formacion
## aguanta. Si no queda manada cerca, la carga DEGRADA a un aceleron individual
## en vez de cancelarse en seco (el perro ya se habia comprometido).
func _resolve_pack_charge() -> void:
	_charge_is_leader = false
	_active_charge_leaders.erase(self)
	if _is_dead:
		return
	apply_howler_buff(1.4, 1.8)
	var buffed: int = 0
	for other in get_tree().get_nodes_in_group("pack_dogs"):
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue
		if global_position.distance_to((other as Node2D).global_position) <= PACK_RADIUS * 1.4 \
				and other.has_method("apply_howler_buff"):
			other.apply_howler_buff(1.4, 1.8)
			buffed += 1
			if buffed >= 6:
				break
	if buffed == 0:
		RunTelemetry.count(&"pack_charges_degraded")
	else:
		RunTelemetry.count(&"pack_charges_executed")
	Feedback.hit_effect(global_position, Color(1.0, 0.55, 0.15, 0.8), 0.5, 2.2)


## Cancelacion de la carga: la llama la muerte del lider. Los perros que estaban
## esperando la orden vuelven a su conducta normal sin acelerones.
func _cancel_pack_charge() -> void:
	if not _charge_is_leader:
		return
	_charge_is_leader = false
	_charge_telegraph = 0.0
	_active_charge_leaders.erase(self)
	RunTelemetry.count(&"pack_charges_cancelled")


func _ensure_pack_ring() -> void:
	if _pack_ring != null:
		return
	_pack_ring = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		pts.append(Vector2(cos(a) * 22.0, sin(a) * 18.0))
	_pack_ring.polygon = pts
	_pack_ring.color = Color(1.0, 0.75, 0.25, 0.16)
	_pack_ring.visible = false
	add_child(_pack_ring)
	move_child(_pack_ring, 0)


# --- Flanqueador ------------------------------------------------------------------

## Reserva/suelta el "cierre de ruta" contra el jugador objetivo. La reserva es
## lo que impide que TODOS los flanqueadores sellen a la vez todas las salidas.
func _claim_flank_close(target: Node) -> bool:
	if target == null:
		return false
	var key: int = target.get_instance_id()
	# Como mucho la MITAD de las salidas puede estar cerrada a la vez, y nunca
	# mas de 2 flanqueadores por jugador: siempre queda por donde salir.
	if closing_flanker_count(target) >= 2:
		return false
	var list: Array = _closing_flankers.get(key, [])
	if not list.has(self):
		list.append(self)
	_closing_flankers[key] = list
	_flank_closing = true
	return true


## Suelta el cierre de ruta. `by_death` distingue las dos formas de terminar un
## flanqueo, que NO significan lo mismo al leer la telemetria: si el jugador mata
## al flanqueador (interrupted) el contrajuego funciono; si el flanqueador
## abandona por su cuenta (abandoned) es la IA cediendo la ruta.
func _release_flank_claim(by_death: bool = false) -> void:
	if not _flank_closing:
		return
	_flank_closing = false
	for key in _closing_flankers:
		(_closing_flankers[key] as Array).erase(self)
	if by_death:
		RunTelemetry.count(&"flanks_interrupted_by_player")
	else:
		RunTelemetry.count(&"flanks_abandoned")


## Logica periodica del flanqueador. Nivel 1 no necesita nada aqui (su rodeo
## lateral vive en _behavior_target_position); los niveles 2 y 3 eligen y
## mantienen una RUTA lateral concreta.
func _flanker_tick(_delta: float) -> void:
	if behavior_level < 2 or not is_instance_valid(_player):
		return
	if _flank_route_timer > 0.0:
		return
	# Cadencia baja a proposito: recalcular el destino cada frame produce el
	# movimiento erratico y los cambios bruscos de objetivo que el diseño veta.
	_flank_route_timer = 1.2

	# Nivel 2: predice hacia donde va el jugador y busca una ruta lateral que
	# desemboque en esa salida probable.
	var player_vel: Vector2 = Vector2.ZERO
	if _player.has_method("get_velocity"):
		player_vel = _player.get_velocity()
	elif _player.get("velocity") != null:
		player_vel = _player.get("velocity")
	var predicted: Vector2 = _player.global_position + player_vel.normalized() * 260.0

	var routes := _shared_routes(_player.global_position)
	if routes.is_empty():
		_flank_route = predicted
		return

	# Se queda con la ruta mas cercana a la salida predicha, no a si mismo: la
	# gracia del flanqueo es llegar antes ADONDE VA el jugador.
	var best: Vector2 = routes[0]
	var best_distance: float = INF
	for point in routes:
		var d: float = point.distance_to(predicted)
		if d < best_distance:
			best_distance = d
			best = point
	# Un flanqueo EMPIEZA cuando el perro se compromete con una ruta nueva.
	if not _flank_route.is_equal_approx(best):
		_flank_route = best
		_flank_arrived = false
		RunTelemetry.count(&"flanks_started")

	# Nivel 3: ademas de posicionarse, INTENTA cerrar esa ruta. La reserva puede
	# denegarse (ya hay dos cerrando): entonces solo presiona, sin sellar.
	if behavior_level >= 3:
		var wants_close: bool = in_territory() or randf() < 0.5
		if wants_close and not _flank_closing:
			_claim_flank_close(_player)
		elif _flank_closing:
			# Abandona el cierre si el punto dejo de ser util o navegable.
			if global_position.distance_to(_flank_route) > 900.0 \
					or not MapGeometry.is_clear(self, _flank_route, 30.0):
				_release_flank_claim()

	# Un flanqueo se COMPLETA cuando el perro llega de verdad a ocupar la salida
	# que eligio. Antes se contaba al reservarla, que solo medía intencion.
	if not _flank_arrived and global_position.distance_to(_flank_route) < 140.0:
		_flank_arrived = true
		RunTelemetry.count(&"flanks_completed")


# --- Aullador ---------------------------------------------------------------------

func _howl() -> void:
	if not is_instance_valid(_player) or global_position.distance_to(_player.global_position) > 700.0:
		return
	# Aviso visual y sonoro inconfundible: debe volverse objetivo prioritario.
	Feedback.hit_effect(global_position, Color(1.0, 0.95, 0.5, 0.85), 0.7, 3.2)
	Feedback.hit_effect(global_position, Color(1.0, 0.9, 0.4, 0.6), 0.35, 1.8)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"event_alert")
	# Nivel 1: potenciacion moderada de los cercanos (tope duro en el receptor).
	var nearby: Array[Node2D] = []
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue
		if global_position.distance_to((other as Node2D).global_position) <= 260.0:
			if other.has_method("apply_howler_buff"):
				other.apply_howler_buff(1.3, 4.0)
			if other.has_method("receive_order"):
				nearby.append(other as Node2D)

	# Nivel 2: llama a una manada pequeña que entra POR UNA RUTA URBANA distinta
	# de la que ya esta presionando. Respeta presupuesto y tope del spawner, y
	# los invocados dan XP reducida (una llamada no puede financiar la build).
	if behavior_level >= 2:
		_howler_call_pack()

	# Nivel 3: da una ORDEN concreta al grupo cercano, con duracion acotada.
	if behavior_level >= 3 and not nearby.is_empty():
		_howler_give_order(nearby)


## Llamada de refuerzos del Aullador (N2). Entra por una ruta urbana distinta a
## la del propio aullador para que la presion venga de dos sitios.
func _howler_call_pack() -> void:
	# Cooldown PROPIO, mucho mas largo que el del aullido: el aullador coordina a
	# menudo pero solo trae refuerzos de vez en cuando. Sin esto, cada aullido
	# (4.5-6 s) inyectaba perros y la partida se ganaba/perdia por cantidad.
	if _howler_call_timer > 0.0:
		return
	_howler_call_timer = 20.0
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if not is_instance_valid(spawner) or not spawner.has_method("spawn_pack_from_street"):
		return
	if not is_instance_valid(_player):
		return
	var routes := _shared_routes(_player.global_position)
	if routes.is_empty():
		return
	# La ruta MAS LEJANA a este aullador: la llamada abre un segundo frente.
	var far: Vector2 = routes[0]
	var best: float = -1.0
	for point in routes:
		var d: float = point.distance_to(global_position)
		if d > best:
			best = d
			far = point
	var called: int = spawner.spawn_pack_from_street(&"zombie_dog", 2, far, 1)
	if called > 0:
		RunTelemetry.count(&"howler_calls", called)


## Orden del Aullador (N3): elige UNA orden para el grupo cercano y la reparte.
## Duracion acotada y cooldown implicito (el aullido tiene su propio periodo):
## no existen ordenes globales permanentes.
func _howler_give_order(group: Array[Node2D]) -> void:
	if not is_instance_valid(_player):
		return
	# La orden se elige por SITUACION, no al azar puro: si el grupo es pequeño
	# manda agrupar; si hay masa, presiona o flanquea. En territorio propio se
	# permite la carga coordinada.
	var order: StringName = &"press"
	if group.size() <= 2:
		order = &"regroup"
	elif in_territory() and active_charge_count() < MAX_SIMULTANEOUS_CHARGES:
		order = &"charge"
	elif randf() < 0.5:
		order = &"flank"
	var point: Vector2 = _player.global_position
	var given: int = 0
	for member in group:
		member.receive_order(order, point, 4.0)
		given += 1
		if given >= 8:
			break
	RunTelemetry.count(&"howler_orders")
	RunTelemetry.count(StringName("howler_order_%s" % order))
	# La orden se ve: pulso del color del aullador hacia el grupo.
	Feedback.hit_effect(global_position, Color(1.0, 0.9, 0.45, 0.7), 0.5, 2.4)


## La marca de aullido informa a este perro de que esta EN TERRITORIO. No aplica
## estadisticas: solo deja constancia de la fuerza y del centro. Lo que cambia es
## la CONDUCTA (agruparse antes, esperar rezagados, repartir rutas, cargar antes).
func enter_territory(strength: float, center: Vector2, radius: float) -> void:
	if _is_dead:
		return
	# Prioridad, no acumulacion: si ya esta en un territorio mas fuerte, se queda
	# con aquel. Dos marcas superpuestas no dan doble coordinacion.
	if strength >= _territory_strength:
		_territory_strength = strength
		_territory_center = center
		_territory_radius = radius
	# TTL algo mayor que el tick de la marca (1 s): al salir del radio se apaga
	# solo, sin que la marca tenga que perseguir a quien se fue.
	_territory_timer = 1.6


## true si el enemigo esta dentro de un territorio de manada activo.
func in_territory() -> bool:
	return _territory_strength > 0.0 and _territory_timer > 0.0


## Orden de un Aullador (N3). Duracion acotada: no existen ordenes permanentes.
func receive_order(order: StringName, point: Vector2, duration: float) -> void:
	if _is_dead:
		return
	_order = order
	_order_point = point
	_order_timer = duration


func get_order() -> StringName:
	return _order if _order_timer > 0.0 else &""


## Potenciacion temporal del Aullador. No se apila: gana la mas fuerte, con tope
## duro x1.5, y los aulladores no se potencian entre si.
func apply_howler_buff(mult: float, duration: float) -> void:
	if _is_dead or _behavior == &"howler":
		return
	_buff_mult = clampf(maxf(_buff_mult, mult), 1.0, 1.5)
	_buff_timer = maxf(_buff_timer, duration)


## Empuje externo simple (el Embestidor arrolla a la horda a su paso).
func apply_push(impulse: Vector2) -> void:
	if _is_dead:
		return
	_knockback += impulse


# --- Escupidor ---------------------------------------------------------------------

func _spit() -> void:
	# Nivel 2+: dispara LIDERADO hacia la ruta de escape (usa la velocidad del
	# jugador amortiguada); nivel 1 dispara directo.
	var aim: Vector2 = _player.global_position
	var player_vel: Vector2 = Vector2.ZERO
	if _player is CharacterBody2D:
		player_vel = (_player as CharacterBody2D).velocity
	if behavior_level >= 2 and player_vel != Vector2.ZERO:
		aim += player_vel * 0.5
	_spit_projectile(global_position.direction_to(aim))
	# Nivel 3: segundo proyectil que CIERRA la escapatoria (barrera), si el
	# presupuesto global de proyectiles lo permite.
	if behavior_level >= 3 and player_vel.length_squared() > 100.0 \
			and get_tree().get_node_count_in_group(ENEMY_PROJECTILE_SCRIPT.GROUP) \
			< RunPhaseConfig.MAX_ENEMY_PROJECTILES:
		var escape_point: Vector2 = _player.global_position + player_vel.normalized() * 150.0
		_spit_projectile(global_position.direction_to(escape_point))
	# Destello de aviso en el momento del disparo.
	Feedback.hit_effect(global_position, Color(0.6, 1.0, 0.4, 0.7), 0.25, 1.2)


func _spit_projectile(direction: Vector2) -> void:
	var proj := Node2D.new()
	proj.set_script(ENEMY_PROJECTILE_SCRIPT)
	proj.set("velocity", direction * 220.0)
	proj.set("damage", maxi(1, int(round(6.0 * _damage_multiplier))))
	proj.position = global_position
	get_parent().add_child(proj)


# --- Embestidor ----------------------------------------------------------------------

func _charger_process(delta: float) -> bool:
	_behavior_timer -= delta
	match _behavior_state:
		1:  # Telegrafo: linea visible que reapunta levemente.
			velocity = velocity.move_toward(Vector2.ZERO, speed * 6.0 * delta)
			move_and_slide()
			if is_instance_valid(_player):
				_behavior_dir = _behavior_dir.lerp(
					global_position.direction_to(_player.global_position), 0.05).normalized()
			_update_charge_line()
			_behavior_state_timer -= delta
			if _behavior_state_timer <= 0.0:
				_behavior_state = 2
				# Nivel 2+: carga mas larga (recorre el corredor completo).
				_behavior_state_timer = 0.7 if behavior_level >= 2 else 0.55
				_behavior_hit_done = false
				if is_instance_valid(_charge_line):
					_charge_line.visible = false
				Feedback.shake(0.12)
			return true
		2:  # Embestida fuerte y recta; arrolla a otros enemigos a su paso.
			velocity = _behavior_dir * speed * 4.2
			var collided := move_and_slide()
			_face_angle = lerp_angle(_face_angle, _behavior_dir.angle(), 0.3)
			if not _behavior_hit_done and is_instance_valid(_player) \
					and global_position.distance_to(_player.global_position) <= contact_range + 14.0:
				if _player.has_method("take_damage"):
					_player.take_damage(int(round(contact_damage * 1.5)))
				_behavior_hit_done = true
			_push_enemies_in_path()
			# Nivel 3: la embestida ROMPE obstaculos destructibles al impactar
			# (activa por fin los datos destructible de ObstacleData).
			if collided and behavior_level >= 3:
				var col := get_last_slide_collision()
				if col != null:
					var hit: Object = col.get_collider()
					if hit != null and hit is Node and (hit as Node).is_in_group("obstacles") \
							and hit.has_method("absorb_projectile"):
						hit.absorb_projectile(60)
			_behavior_state_timer -= delta
			if collided or _behavior_state_timer <= 0.0:
				# Queda VULNERABLE si choca con un obstaculo o falla la carga.
				_behavior_state = 3
				_behavior_state_timer = 1.3 if collided else 0.9
				if collided:
					Feedback.shake(0.2)
					Feedback.hit_effect(global_position, Color(1.0, 0.6, 0.3, 0.7), 0.4, 1.6)
			return true
		3:  # Aturdido: quieto y vulnerable (take_damage x1.5).
			velocity = Vector2.ZERO
			_behavior_state_timer -= delta
			if _behavior_state_timer <= 0.0:
				_behavior_state = 0
				_behavior_timer = 3.2
			return true
	# Estado 0 (acecho): persecucion normal; entra en telegrafo por cercania.
	# Nivel 2+: busca lineas de carga mas LARGAS (dispara desde mas lejos).
	var trigger_range: float = CHARGER_TRIGGER_RANGE + (140.0 if behavior_level >= 2 else 0.0)
	if _behavior_timer <= 0.0 and is_instance_valid(_player) \
			and global_position.distance_to(_player.global_position) < trigger_range:
		_behavior_state = 1
		_behavior_state_timer = 0.9
		_behavior_dir = global_position.direction_to(_player.global_position)
		_ensure_charge_line()
		_charge_line.visible = true
	return false


func _push_enemies_in_path() -> void:
	var pushed: int = 0
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other) or not other.has_method("apply_push"):
			continue
		if global_position.distance_to((other as Node2D).global_position) <= 48.0:
			other.apply_push(_behavior_dir * 260.0)
			pushed += 1
			if pushed >= 6:
				break


func _ensure_charge_line() -> void:
	if _charge_line != null:
		return
	_charge_line = Line2D.new()
	_charge_line.width = 7.0
	_charge_line.default_color = Color(1.0, 0.35, 0.25, 0.55)
	_charge_line.z_index = -1
	add_child(_charge_line)


func _update_charge_line() -> void:
	if not is_instance_valid(_charge_line):
		return
	# Longitud aproximada del recorrido real de la carga, compensando la escala
	# del nodo (los hijos heredan visual_scale).
	var length: float = speed * 2.6 / maxf(scale.x, 0.01)
	_charge_line.points = PackedVector2Array([Vector2.ZERO, _behavior_dir * length])
	_charge_line.default_color.a = 0.3 + 0.4 * absf(sin(_time * 14.0))


# --- Cazador ----------------------------------------------------------------------------

func _hunter_process(delta: float) -> bool:
	_behavior_timer -= delta
	_hunter_retarget(delta)
	match _behavior_state:
		1:  # Anuncio del salto: se detiene y avisa (doble anillo ya emitido).
			velocity = velocity.move_toward(Vector2.ZERO, speed * 6.0 * delta)
			move_and_slide()
			_behavior_state_timer -= delta
			if _behavior_state_timer <= 0.0:
				if is_instance_valid(_hunter_target):
					_behavior_state = 2
					_behavior_state_timer = 0.4
					_behavior_hit_done = false
					_behavior_dir = global_position.direction_to(_hunter_target.global_position)
				else:
					_behavior_state = 0
			return true
		2:  # Salto rapido y recto.
			velocity = _behavior_dir * speed * 3.6
			move_and_slide()
			_face_angle = lerp_angle(_face_angle, _behavior_dir.angle(), 0.3)
			if not _behavior_hit_done and is_instance_valid(_hunter_target) \
					and global_position.distance_to(_hunter_target.global_position) <= contact_range + 10.0:
				if _hunter_target.has_method("take_damage"):
					_hunter_target.take_damage(int(round(contact_damage * 1.3)))
				_behavior_hit_done = true
			_behavior_state_timer -= delta
			if _behavior_state_timer <= 0.0:
				_behavior_state = 3
				_behavior_state_timer = 0.6
			return true
		3:  # Recuperacion breve tras el salto.
			velocity = velocity.move_toward(Vector2.ZERO, speed * 4.0 * delta)
			move_and_slide()
			_behavior_state_timer -= delta
			if _behavior_state_timer <= 0.0:
				_behavior_state = 0
				_behavior_timer = 4.0
			return true
	if _behavior_timer <= 0.0 and is_instance_valid(_hunter_target) \
			and global_position.distance_to(_hunter_target.global_position) < HUNTER_LEAP_RANGE:
		_behavior_state = 1
		_behavior_state_timer = 0.7
		# Salto claramente anunciado ANTES de ejecutarse.
		Feedback.hit_effect(global_position, Color(1.0, 0.25, 0.25, 0.85), 0.5, 2.2)
		Feedback.hit_effect(global_position, Color(1.0, 0.5, 0.3, 0.6), 0.25, 1.3)
	return false


## El Cazador elige al jugador MAS VULNERABLE (menor % de vida; en coop prioriza
## al herido) y lo mantiene un tiempo minimo: no cambia de objetivo sin parar.
func _hunter_retarget(delta: float) -> void:
	_hunter_target_timer -= delta
	if _hunter_target_timer > 0.0 and is_instance_valid(_hunter_target) \
			and (not _hunter_target.has_method("is_active") or _hunter_target.is_active()):
		return
	_hunter_target_timer = 4.0
	var best: Node2D = null
	var best_ratio: float = INF
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if p.has_method("is_active") and not p.is_active():
			continue
		var max_h: float = maxf(1.0, float(p.get("max_health")))
		var ratio: float = float(p.get("current_health")) / max_h
		if ratio < best_ratio:
			best_ratio = ratio
			best = p
	_hunter_target = best if best != null else _player


# --- Esbirros del jefe -------------------------------------------------------------------

func _exploder_process(delta: float) -> bool:
	if _behavior_state != 1:
		# Persecucion normal (rapida); enciende la mecha al acercarse.
		if is_instance_valid(_player) and global_position.distance_to(_player.global_position) < 95.0:
			_behavior_state = 1
			_behavior_state_timer = 0.8
		return false
	# Mecha encendida: quieto, parpadea en rojo y crece (señal clara y esquivable).
	velocity = Vector2.ZERO
	_behavior_state_timer -= delta
	var blink: float = 0.5 + 0.5 * absf(sin(_time * 22.0))
	modulate = Color(1.0 + blink, 1.0 - blink * 0.5, 1.0 - blink * 0.5, 1.0)
	scale = _base_scale * (1.0 + (0.8 - _behavior_state_timer) * 0.35)
	if _behavior_state_timer <= 0.0:
		_explode()
	return true


## Explosion del Explosivo: daña a jugadores Y a enemigos/jefe cercanos — bien
## posicionada, el jugador puede volverla en contra del propio jefe.
func _explode() -> void:
	var radius: float = 130.0
	Feedback.hit_effect(global_position, Color(1.0, 0.55, 0.2, 0.9), 0.8, 3.4)
	Feedback.shake(0.25)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"enemy_die")
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if global_position.distance_to((p as Node2D).global_position) <= radius \
				and p.has_method("take_damage"):
			p.take_damage(16)
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue
		if global_position.distance_to((other as Node2D).global_position) <= radius \
				and other.has_method("take_damage"):
			other.take_damage(25, global_position.direction_to((other as Node2D).global_position))
	_die()


func _healer_channel_process(delta: float) -> bool:
	_resolve_boss()
	if not _valid_boss():
		return false  # sin jefe vivo se comporta como enemigo normal
	if _behavior_state != 1:
		# Camina hacia el jefe (_behavior_target_position); canaliza al llegar.
		if global_position.distance_to(_boss.global_position) < 90.0:
			_behavior_state = 1
			_behavior_state_timer = 2.4
			_heal_tick_timer = 0.0
		return false
	velocity = Vector2.ZERO
	_behavior_state_timer -= delta
	_heal_tick_timer -= delta
	if _heal_tick_timer <= 0.0 and _heal_left > 0:
		_heal_tick_timer = 0.4
		var chunk: int = mini(12, _heal_left)
		_heal_left -= chunk
		if _boss.has_method("receive_minion_heal"):
			_boss.receive_minion_heal(chunk)
		Feedback.hit_effect(_boss.global_position, Color(0.4, 1.0, 0.6, 0.5), 0.3, 1.4)
	if _behavior_state_timer <= 0.0 or _heal_left <= 0:
		_die()  # se consume al terminar la canalizacion
	return true


## Conexion VISUAL del sanador con su jefe (linea verde pulsante).
func _update_healer_link() -> void:
	_resolve_boss()
	if not _valid_boss():
		if is_instance_valid(_healer_link):
			_healer_link.visible = false
		return
	if _healer_link == null:
		_healer_link = Line2D.new()
		_healer_link.width = 3.0
		_healer_link.default_color = Color(0.4, 1.0, 0.6, 0.45)
		_healer_link.z_index = -1
		add_child(_healer_link)
	_healer_link.visible = true
	var to_boss: Vector2 = (_boss.global_position - global_position) / maxf(scale.x, 0.01)
	_healer_link.points = PackedVector2Array([Vector2.ZERO, to_boss])
	_healer_link.default_color.a = 0.3 + 0.25 * absf(sin(_time * 6.0))


func _resolve_boss() -> void:
	if _valid_boss():
		return
	_boss = null
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b is Node2D:
			_boss = b
			return
	for mb in get_tree().get_nodes_in_group("miniboss"):
		if is_instance_valid(mb) and mb is Node2D:
			_boss = mb
			return


func _valid_boss() -> bool:
	return _boss != null and is_instance_valid(_boss) and _boss.is_inside_tree()


## Vincula el esbirro a su jefe (lo llama el jefe al invocarlo).
func bind_boss(boss_node: Node2D) -> void:
	_boss = boss_node


# --- Efectos continuos de las mutaciones elite (FASE 11) ------------------------------------

func _mutation_tick(delta: float) -> void:
	match _elite_kind:
		&"lider_manada":
			_mutation_timer -= delta
			if _mutation_timer <= 0.0:
				_mutation_timer = 2.5
				var buffed: int = 0
				for other in get_tree().get_nodes_in_group("enemies"):
					if other == self or not is_instance_valid(other) or not (other is Node2D):
						continue
					if other.is_in_group("map_interactables"):
						continue
					if global_position.distance_to((other as Node2D).global_position) <= 240.0 \
							and other.has_method("apply_howler_buff"):
						other.apply_howler_buff(1.22, 2.6)
						buffed += 1
						if buffed >= 8:
							break
				if buffed > 0:
					Feedback.hit_effect(global_position, Color(1.0, 0.72, 0.2, 0.5), 0.3, 1.5)
		&"carronero":
			_mutation_timer -= delta
			if _mutation_timer <= 0.0:
				_mutation_timer = 1.0
				if current_health >= max_health:
					return
				# Se cura junto a los restos de las bajas (orbes de XP cercanos).
				for orb in get_tree().get_nodes_in_group("xp_orbs"):
					if not is_instance_valid(orb) or not (orb is Node2D):
						continue
					if global_position.distance_to((orb as Node2D).global_position) <= 220.0:
						current_health = mini(max_health, current_health + 4)
						Feedback.hit_effect(global_position, Color(0.75, 0.5, 0.25, 0.5), 0.2, 1.1)
						break
		&"sobrecargado":
			_mutation_state_timer -= delta
			if _mutation_state == 0:
				_mutation_speed_mult = 1.55
				if _mutation_state_timer <= 0.0:
					_mutation_state = 1
					_mutation_state_timer = 1.2
					Feedback.hit_effect(global_position, Color(0.3, 0.85, 1.0, 0.6), 0.35, 1.4)
			else:
				# Aturdido: casi quieto y VULNERABLE (take_damage x1.5).
				_mutation_speed_mult = 0.25
				if _mutation_state_timer <= 0.0:
					_mutation_state = 0
					_mutation_state_timer = 1.8


## Efectos de muerte de la mutacion elite (esporoso/parasito/volatil).
func _mutation_on_death() -> void:
	match _elite_kind:
		&"esporoso":
			HAZARD_ZONE_SCRIPT.try_spawn(get_parent(), global_position,
				{"kind": &"infection", "radius": 55.0, "duration": 4.0,
				"damage_per_tick": maxi(1, int(round(4.0 * _damage_multiplier)))})
		&"parasito":
			_split_on_death()
		&"volatil":
			# Explosion dual: daña jugadores Y enemigos cercanos.
			var radius: float = 115.0
			Feedback.hit_effect(global_position, Color(1.0, 0.55, 0.15, 0.9), 0.7, 3.0)
			Feedback.shake(0.2)
			for p in get_tree().get_nodes_in_group("players"):
				if not is_instance_valid(p) or not (p is Node2D):
					continue
				if global_position.distance_to((p as Node2D).global_position) <= radius \
						and p.has_method("take_damage"):
					p.take_damage(12)
			var hits: int = 0
			for other in get_tree().get_nodes_in_group("enemies"):
				if other == self or not is_instance_valid(other) or not (other is Node2D):
					continue
				if global_position.distance_to((other as Node2D).global_position) <= radius \
						and other.has_method("take_damage"):
					other.take_damage(22, global_position.direction_to((other as Node2D).global_position))
					hits += 1
					if hits >= 10:
						break


# --- Efectos de muerte por comportamiento ---------------------------------------------------

func _behavior_on_death() -> void:
	match _behavior:
		&"splitter":
			_split_on_death()
		&"infection_carrier":
			_leave_hazard_zone()
		&"boss_guardian":
			# Su muerte abre una ventana de vulnerabilidad en el jefe.
			if _valid_boss() and _boss.has_method("notify_guardian_down"):
				_boss.notify_guardian_down()


## El Mutante Divisor genera DOS cachorros pequeños al morir. Solo se divide una
## vez, y los cachorros (comunes) no pueden volver a dividirse.
func _split_on_death() -> void:
	var pup_data: EnemyData = load(PUP_DATA_PATH)
	var scene := load("res://scenes/enemies/Enemy.tscn") as PackedScene
	if scene == null or pup_data == null:
		return
	for i in 2:
		var child := scene.instantiate() as Node2D
		if child == null:
			continue
		if child.has_method("configure"):
			child.call("configure", pup_data, 0.8, 1.0, 1.0)
		child.position = global_position + Vector2(24.0 if i == 0 else -24.0, 0.0)
		get_parent().add_child.call_deferred(child)


## El Portador deja una zona peligrosa claramente señalada. try_spawn aplica el
## presupuesto por tipo y fusiona con zonas superpuestas (FASE 11).
func _leave_hazard_zone() -> void:
	HAZARD_ZONE_SCRIPT.try_spawn(get_parent(), global_position,
		{"kind": &"infection", "damage_per_tick": maxi(1, int(round(4.0 * _damage_multiplier)))})
