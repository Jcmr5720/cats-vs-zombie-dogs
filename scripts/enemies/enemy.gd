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
	velocity = direction * speed * _speed_jitter * _slow_mult * _buff_mult * (1.0 + _pack_bonus) \
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

	# Objetivo prioritario del Gato Policia: el enemigo marcado recibe daño
	# extra de TODO el equipo (jugadores, compañeros y torretas).
	if has_meta(&"companion_mark"):
		amount = max(1, int(round(amount * (1.0 + CompanionBalance.POLICE_MARK_DAMAGE_BONUS))))

	current_health -= amount

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
	if _hard_stuck_time > HARD_STUCK_LIMIT and _ghost_timer <= 0.0:
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
	# Sale del grupo y deja de colisionar para que las balas no lo persigan.
	# Se difiere el cambio de física porque la muerte ocurre dentro del
	# callback de colisión de la bala (no se puede tocar el estado en el flush).
	remove_from_group("enemies")
	set_deferred("collision_layer", 0)
	call_deferred("set_physics_process", false)

	# Efectos de muerte por comportamiento (division, zona infecciosa, guardian).
	_behavior_on_death()

	died.emit(global_position, xp_value)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"enemy_die")
	_drop_xp_orb()

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
	match _behavior:
		&"pack":
			_pack_tick(delta)
		&"howler":
			_behavior_timer -= delta
			if _behavior_timer <= 0.0:
				_behavior_timer = 6.0
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
		&"flanker":
			# Rodea: apunta a un punto LATERAL fijo del objetivo hasta acercarse
			# (el lado se elige al nacer y no cambia constantemente).
			if global_position.distance_to(default_target) > 220.0:
				var to_me: Vector2 = (global_position - default_target).normalized()
				var side: Vector2 = Vector2(-to_me.y, to_me.x) * _flank_side
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


# --- Perro de manada ------------------------------------------------------------

func _pack_tick(delta: float) -> void:
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
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue
		if global_position.distance_to((other as Node2D).global_position) <= 260.0 \
				and other.has_method("apply_howler_buff"):
			other.apply_howler_buff(1.3, 4.0)


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
	var proj := Node2D.new()
	proj.set_script(ENEMY_PROJECTILE_SCRIPT)
	proj.set("velocity", global_position.direction_to(_player.global_position) * 220.0)
	proj.set("damage", maxi(1, int(round(6.0 * _damage_multiplier))))
	proj.position = global_position
	get_parent().add_child(proj)
	# Destello de aviso en el momento del disparo.
	Feedback.hit_effect(global_position, Color(0.6, 1.0, 0.4, 0.7), 0.25, 1.2)


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
				_behavior_state_timer = 0.55
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
	if _behavior_timer <= 0.0 and is_instance_valid(_player) \
			and global_position.distance_to(_player.global_position) < CHARGER_TRIGGER_RANGE:
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


## El Portador deja una zona peligrosa claramente señalada (limite global).
func _leave_hazard_zone() -> void:
	if get_tree().get_node_count_in_group(HAZARD_ZONE_SCRIPT.GROUP) >= RunPhaseConfig.MAX_HAZARD_ZONES:
		return
	var zone := Node2D.new()
	zone.set_script(HAZARD_ZONE_SCRIPT)
	zone.position = global_position
	zone.set("damage_per_tick", maxi(1, int(round(4.0 * _damage_multiplier))))
	get_parent().add_child.call_deferred(zone)
