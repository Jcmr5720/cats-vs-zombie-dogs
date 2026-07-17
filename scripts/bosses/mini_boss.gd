extends CharacterBody2D
## Mini-jefe (Bulldog Bruto Zombi). Mas grande, mas vida y mas lento que un enemigo
## normal; pega fuerte por contacto y empuja al jugador. Vive en el grupo "enemies"
## (para recibir daño de todas las armas) y "miniboss" (para limpieza). Muestra una
## barra de vida pequena propia encima.
##
## Partidas rapidas: ahora tiene DOS patrones propios, ambos telegrafiados:
## - Habilidad principal: ONDA EXPANSIVA (anillo de aviso creciente y golpe en
##   area alrededor suyo; se esquiva saliendo del anillo).
## - Ataque secundario: EMBESTIDA CORTA (pausa de apuntado y acelera en recta).
## Al derrotarlo entrega una Mutacion (la orquesta el PhaseDirector).

const BossData = preload("res://scripts/bosses/boss_data.gd")
const XP_ORB_SCENE := preload("res://scenes/loot/XPOrb.tscn")

signal died(data: BossData)

const MAX_HEALTH_CAP: int = 4000

@export var contact_range: float = 52.0
## Multiplicador de vida del mini-jefe en coop local (Fase Coop 1.5). 1.0 en solo.
## (Obsoleto, Fase correccion: la vida coop de jefes vive en GameBalance.BOSS_COOP_HEALTH_MULT.)
@export var coop_health_mult: float = 1.45

var data: BossData
var max_health: int = 320
var current_health: int = 320

enum MBState { CHASE, SLAM_WINDUP, LUNGE_WINDUP, LUNGE }

## Radio de la onda expansiva (px de mundo) y tiempos de los patrones.
const SLAM_RADIUS: float = 150.0
const SLAM_WINDUP_TIME: float = 0.9
const LUNGE_WINDUP_TIME: float = 0.5
const LUNGE_TIME: float = 0.4
const ATTACK_COOLDOWN: float = 4.5

var _player: Node2D
var _is_dead: bool = false
var _contact_timer: float = 0.0
var _anim_time: float = 0.0

# --- Patrones (Partidas rapidas) ---
var _mb_state: int = MBState.CHASE
var _mb_timer: float = 0.0
var _attack_timer: float = 3.0
## Alterna: onda expansiva (principal) <-> embestida corta (secundario).
var _next_is_slam: bool = true
var _slam_ring: Polygon2D
var _lunge_dir: Vector2 = Vector2.ZERO
var _lunge_hit: bool = false
var _flash_tween: Tween
## Ángulo visual suavizado (el Visual rota; el cuerpo se voltea al mirar a la izquierda).
var _face_angle: float = 0.0
var _avoid: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.ZERO
var _stuck_time: float = 0.0
var _stuck_check_timer: float = 0.0

@onready var _visual: Node2D = $Visual
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _aura: Polygon2D = get_node_or_null("Aura")
## Luz dinamica (FASE VISUAL 2). Puede ser null (luces desactivadas).
var _light: GlowLight


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("miniboss")
	_player = _resolve_target_player()
	set_collision_mask_value(5, true)
	_last_position = global_position
	_update_bar()
	# Entrada con presencia: destello grande + shake para anunciar al "elite".
	Feedback.hit_effect(global_position, Color(1.0, 0.7, 0.25, 0.9), 0.6, 3.0)
	Feedback.shake(0.3)
	# FASE VISUAL 2: luz ambarina propia, mas pequena que la del jefe principal.
	var mb_accent: Color = data.accent_color if data != null else Color(1.0, 0.7, 0.25)
	_light = GlowLight.attach(self, mb_accent, 150.0, 0.75, 2.6, 0.0, true)


func configure(boss_data: BossData, difficulty_score: float) -> void:
	data = boss_data
	# Doble techo centralizado (GameBalance): factor por score + px absolutos.
	var factor: float = minf(GameBalance.MINIBOSS_HEALTH_SCORE_FACTOR_CAP,
		1.0 + max(0.0, difficulty_score) * data.difficulty_multiplier)
	var scaled: float = data.max_health * factor
	if _is_coop():
		scaled *= GameBalance.BOSS_COOP_HEALTH_MULT
	max_health = clampi(int(round(scaled)), data.max_health, MAX_HEALTH_CAP)
	current_health = max_health
	if is_node_ready():
		_apply_visuals()
		_update_bar()


func _apply_visuals() -> void:
	if data == null:
		return
	scale = Vector2.ONE * data.visual_scale
	var body := $Visual/Body as Polygon2D
	if body != null:
		body.color = data.visual_color
	var head := $Visual/Head as Polygon2D
	if head != null:
		head.color = data.visual_color.lightened(0.05)
	for eye_name in ["EyeLeft", "EyeRight"]:
		var eye := get_node_or_null("Visual/%s" % eye_name) as Polygon2D
		if eye != null:
			eye.color = data.accent_color


func _physics_process(delta: float) -> void:
	if _is_dead or data == null:
		return
	# Objetivo: en coop el jugador ACTIVO mas cercano; en solo el unico jugador.
	_player = _resolve_target_player()
	if not is_instance_valid(_player):
		velocity = Vector2.ZERO
		return

	_anim_time += delta
	if _contact_timer > 0.0:
		_contact_timer -= delta

	match _mb_state:
		MBState.SLAM_WINDUP:
			_mb_slam_windup(delta)
		MBState.LUNGE_WINDUP:
			_mb_lunge_windup(delta)
		MBState.LUNGE:
			_mb_lunge(delta)
		_:
			var dir: Vector2 = _steered_direction(_player.global_position)
			_avoid = _avoid.move_toward(Vector2.ZERO, data.move_speed * 3.0 * delta)
			velocity = dir * data.move_speed + _avoid
			move_and_slide()
			_update_stuck_state(delta)
			_face_angle = lerp_angle(_face_angle, dir.angle(), 0.10)
			_contact()
			# Alterna sus dos patrones cuando el jugador esta a rango util.
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				var d: float = global_position.distance_to(_player.global_position)
				if _next_is_slam and d < SLAM_RADIUS * 1.4:
					_start_slam()
				elif not _next_is_slam and d < 420.0:
					_start_lunge()
	_animate(delta)


# --- Patrones -------------------------------------------------------------------

func _start_slam() -> void:
	_mb_state = MBState.SLAM_WINDUP
	_mb_timer = SLAM_WINDUP_TIME
	_next_is_slam = false
	_ensure_slam_ring()
	_slam_ring.visible = true
	_play_alert()


func _mb_slam_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, data.move_speed * 6.0 * delta)
	move_and_slide()
	_mb_timer -= delta
	# El anillo crece hasta el radio real del golpe y pulsa: aviso inconfundible.
	if is_instance_valid(_slam_ring):
		var t: float = 1.0 - _mb_timer / SLAM_WINDUP_TIME
		_slam_ring.scale = Vector2.ONE * maxf(0.15, t)
		_slam_ring.modulate.a = 0.5 + 0.5 * absf(sin(t * 14.0))
	if _mb_timer <= 0.0:
		_do_slam()


func _do_slam() -> void:
	_mb_state = MBState.CHASE
	_attack_timer = ATTACK_COOLDOWN
	if is_instance_valid(_slam_ring):
		_slam_ring.visible = false
	Feedback.shake(0.35)
	Feedback.hit_effect(global_position, Color(1.0, 0.7, 0.25, 0.9), 0.7, 3.6)
	Feedback.hit_effect(global_position, Color(1.0, 0.85, 0.5, 0.6), 0.35, 2.0)
	# Golpe en area: jugadores y companeros dentro del anillo.
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if global_position.distance_to((p as Node2D).global_position) <= SLAM_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(data.contact_damage)
			if p.has_method("apply_knockback"):
				p.apply_knockback(global_position.direction_to((p as Node2D).global_position) * data.knockback * 1.2)
	for c in get_tree().get_nodes_in_group("companions"):
		if not is_instance_valid(c) or not c.has_method("take_damage"):
			continue
		if not c.has_method("can_be_targeted") or not c.can_be_targeted():
			continue
		if global_position.distance_to((c as Node2D).global_position) <= SLAM_RADIUS:
			c.take_damage(data.contact_damage, global_position.direction_to((c as Node2D).global_position))


func _start_lunge() -> void:
	_mb_state = MBState.LUNGE_WINDUP
	_mb_timer = LUNGE_WINDUP_TIME
	_next_is_slam = true
	_lunge_dir = global_position.direction_to(_player.global_position)
	_play_alert()
	Feedback.hit_effect(global_position, Color(1.0, 0.5, 0.2, 0.7), 0.4, 1.8)


func _mb_lunge_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, data.move_speed * 6.0 * delta)
	move_and_slide()
	# Reapunta levemente hasta el ultimo instante (aviso legible, no teledirigido).
	_lunge_dir = _lunge_dir.lerp(global_position.direction_to(_player.global_position), 0.06).normalized()
	_face_angle = lerp_angle(_face_angle, _lunge_dir.angle(), 0.2)
	_mb_timer -= delta
	if _mb_timer <= 0.0:
		_mb_state = MBState.LUNGE
		_mb_timer = LUNGE_TIME
		_lunge_hit = false


func _mb_lunge(delta: float) -> void:
	velocity = _lunge_dir * data.move_speed * 4.5
	var collided := move_and_slide()
	_face_angle = lerp_angle(_face_angle, _lunge_dir.angle(), 0.3)
	if not _lunge_hit and global_position.distance_to(_player.global_position) <= contact_range + 16.0:
		if _player.has_method("take_damage"):
			_player.take_damage(data.contact_damage)
		if _player.has_method("apply_knockback"):
			_player.apply_knockback(global_position.direction_to(_player.global_position) * data.knockback)
		_lunge_hit = true
	_mb_timer -= delta
	if _mb_timer <= 0.0 or collided:
		_mb_state = MBState.CHASE
		_attack_timer = ATTACK_COOLDOWN * 0.85


## Anillo de aviso de la onda expansiva (radio real del golpe, compensando la
## escala del nodo: los hijos heredan visual_scale).
func _ensure_slam_ring() -> void:
	if _slam_ring != null:
		return
	_slam_ring = Polygon2D.new()
	var pts := PackedVector2Array()
	var r: float = SLAM_RADIUS / maxf(scale.x, 0.01)
	for i in 40:
		var a: float = TAU * float(i) / 40.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	# Anillo (poligono con agujero simulado: dos vueltas) — suficiente y barato:
	# un disco translucido con borde mas marcado via self_modulate.
	_slam_ring.polygon = pts
	_slam_ring.color = Color(1.0, 0.55, 0.2, 0.18)
	_slam_ring.z_index = -1
	add_child(_slam_ring)


func _play_alert() -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"event_alert")


func _steered_direction(target_position: Vector2) -> Vector2:
	var direct: Vector2 = global_position.direction_to(target_position)
	if not test_move(global_transform, direct * 74.0):
		return direct
	var left: Vector2 = direct.rotated(PI * 0.5)
	var right: Vector2 = direct.rotated(-PI * 0.5)
	var left_clear: bool = not test_move(global_transform, (direct + left * 0.85).normalized() * 90.0)
	var right_clear: bool = not test_move(global_transform, (direct + right * 0.85).normalized() * 90.0)
	if left_clear and right_clear:
		var left_score: float = (global_position + left * 90.0).distance_to(target_position)
		var right_score: float = (global_position + right * 90.0).distance_to(target_position)
		return (direct + (left if left_score < right_score else right) * 0.85).normalized()
	if left_clear:
		return (direct + left * 0.85).normalized()
	if right_clear:
		return (direct + right * 0.85).normalized()
	return left if sin(_anim_time) > 0.0 else right


func _update_stuck_state(delta: float) -> void:
	_stuck_check_timer += delta
	if _stuck_check_timer < 0.35:
		return
	var moved: float = global_position.distance_to(_last_position)
	if moved < 3.0 and get_slide_collision_count() > 0:
		_stuck_time += _stuck_check_timer
	else:
		_stuck_time = max(0.0, _stuck_time - _stuck_check_timer)
		if is_in_group("stuck_enemies") and _stuck_time <= 0.05:
			remove_from_group("stuck_enemies")
	if _stuck_time > 0.9:
		add_to_group("stuck_enemies")
		var side := global_position.direction_to(_player.global_position).rotated(PI * 0.5 * (1.0 if sin(_anim_time) > 0.0 else -1.0))
		_avoid = side * data.move_speed * 0.9
		_stuck_time = 0.25
	_last_position = global_position
	_stuck_check_timer = 0.0


func _contact() -> void:
	if _contact_timer > 0.0:
		return
	# Jugador (prioritario): daño + leve empuje.
	if global_position.distance_to(_player.global_position) <= contact_range:
		if _player.has_method("take_damage"):
			_player.take_damage(data.contact_damage)
			if _player.has_method("apply_knockback"):
				_player.apply_knockback(global_position.direction_to(_player.global_position) * data.knockback)
			_contact_timer = 0.5
			return
	for companion in get_tree().get_nodes_in_group("companions"):
		if not is_instance_valid(companion) or not companion.has_method("take_damage"):
			continue
		if not companion.has_method("can_be_targeted") or not companion.can_be_targeted():
			continue
		if global_position.distance_to(companion.global_position) <= contact_range:
			companion.take_damage(data.contact_damage, global_position.direction_to(companion.global_position))
			_contact_timer = 0.5
			return


func take_damage(amount: int, _knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if _is_dead:
		return
	current_health = max(0, current_health - amount)
	Feedback.damage_number(global_position + Vector2(0, -36), amount, Color(1.0, 0.82, 0.5))
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"boss_hit")
	_flash_hit()
	_update_bar()
	if current_health <= 0:
		_die()


func _flash_hit() -> void:
	# Flash unificado (ETAPA ARTISTICA 2); fallback al codigo clasico.
	var sv: Node = get_node_or_null("SpriteVisual")
	if sv != null and sv.has_method("flash_damage"):
		sv.flash_damage(Color(1.8, 1.6, 1.6, 1.0), 0.12)
		return
	if not is_instance_valid(_visual):
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_visual.modulate = Color(1.8, 1.6, 1.6, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visual, "modulate", Color(1, 1, 1, 1), 0.12)


func _die() -> void:
	_is_dead = true
	velocity = Vector2.ZERO
	remove_from_group("enemies")
	set_deferred("collision_layer", 0)
	call_deferred("set_physics_process", false)
	_drop_reward()
	Feedback.shake(0.3)
	Feedback.hit_effect(global_position, data.accent_color, 0.8, 3.5)
	Feedback.death_burst(global_position, data.visual_color if data != null else Color(0.5, 0.6, 0.45), 8)
	Feedback.hitstop(0.09, 0.07)
	var missions: Node = get_node_or_null("/root/Missions")
	if missions != null:
		missions.add(&"boss_kills")
	died.emit(data)
	# La luz se apaga con el cuerpo (el modulate no afecta a las Light2D).
	if is_instance_valid(_light):
		var light_out := create_tween()
		light_out.tween_method(_light.set_base_energy, 1.4, 0.0, 0.3)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", scale * 0.2, 0.3)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)


func _drop_reward() -> void:
	var orbs: int = 4
	var per_orb: int = max(1, int(round(float(data.xp_reward) / float(orbs))))
	for i in orbs:
		var orb := XP_ORB_SCENE.instantiate() as Node2D
		if orb == null:
			continue
		orb.set("xp_value", per_orb)
		orb.global_position = global_position
		orb.set("pop_velocity", Vector2.RIGHT.rotated(randf() * TAU) * randf_range(70.0, 160.0))
		get_parent().add_child.call_deferred(orb)


## Jugador objetivo: en coop el ACTIVO mas cercano; en solo el unico jugador.
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


func _is_coop() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_coop") and gf.is_coop()


func _update_bar() -> void:
	if not is_instance_valid(_health_bar):
		return
	_health_bar.max_value = max_health
	_health_bar.value = current_health
	_health_bar.visible = not _is_dead


func _animate(_delta: float) -> void:
	if not is_instance_valid(_visual):
		return
	# En modo SPRITE el waddle/rotacion procedural no se aplica; el aura sigue.
	var sv: Node = get_node_or_null("SpriteVisual")
	var sprite_mode: bool = sv != null and sv.has_method("is_sprite_active") and sv.is_sprite_active()
	if not sprite_mode:
		var waddle: float = sin(_anim_time * 7.0) * 0.06
		# Rota el Visual con volteo vertical al mirar a la izquierda: el mini-jefe
		# nunca queda boca abajo y su sombra (fuera del Visual) no gira.
		var face_sign: float = -1.0 if absf(wrapf(_face_angle, -PI, PI)) > PI * 0.5 else 1.0
		_visual.rotation = _face_angle
		_visual.scale = _visual.scale.lerp(Vector2(1.0 + waddle, face_sign * (1.0 - waddle)), 0.2)
	if is_instance_valid(_aura):
		_aura.modulate.a = 0.75 + 0.25 * sin(_anim_time * 3.4)
