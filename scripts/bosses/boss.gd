extends CharacterBody2D
## Jefe principal (Rottweiler Alfa Zombi). Maquina de estados con 3 patrones:
## persecucion, embestida (con telegrafo) e invocacion de perros. Cambia de fase
## segun su vida (phase_thresholds). Vive en el grupo "enemies" para que TODAS las
## armas y companeros puedan danarlo, y en el grupo "boss" para limpieza/HUD.
##
## La barra de vida la dibuja el HUD via la senal health_changed; al morir emite
## died(data) para que BossSpawner muestre recompensa/mensaje y limpie la barra.

const BossData = preload("res://scripts/bosses/boss_data.gd")
const ENEMY_SCENE := preload("res://scenes/enemies/Enemy.tscn")
const XP_ORB_SCENE := preload("res://scenes/loot/XPOrb.tscn")

signal health_changed(current: int, maximum: int, display_name: String)
signal died(data: BossData)

enum State { CHASE, WINDUP, CHARGE, RECOVER, SUMMON }

## Tope de vida para que el escalado por dificultad no cree jefes imposibles.
const MAX_HEALTH_CAP: int = 9000
## Tope de enemigos invocados vivos a la vez (evita acumulacion de nodos).
const MAX_SUMMONED: int = 14

@export var windup_time: float = 0.9
@export var charge_time: float = 0.55
@export var charge_speed: float = 720.0
@export var recover_time: float = 0.7
@export var contact_range: float = 64.0
@export var summon_count: int = 4
## Multiplicador de vida del jefe en coop local (Fase Coop 1.5). 1.0 en solo.
@export var coop_health_mult: float = 1.55

var data: BossData
var max_health: int = 1200
var current_health: int = 1200
var phase: int = 1

var _player: Node2D
var _state: int = State.CHASE
var _state_timer: float = 0.0
var _attack_timer: float = 3.0
var _charge_dir: Vector2 = Vector2.RIGHT
var _charge_hit_done: bool = false
var _contact_timer: float = 0.0
var _is_dead: bool = false
var _anim_time: float = 0.0
var _summoned: Array[Node2D] = []
var _flash_tween: Tween
var _summon_pulse: float = 0.0
## Ángulo visual: solo rota el nodo Visual (con volteo vertical al mirar a la
## izquierda) para que el jefe nunca quede boca abajo y la sombra no gire.
var _face_angle: float = 0.0
var _avoid: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.ZERO
var _stuck_time: float = 0.0
var _stuck_check_timer: float = 0.0

@onready var _visual: Node2D = $Visual
@onready var _aura: Polygon2D = $Aura
@onready var _telegraph: Node2D = $Telegraph
@onready var _eye_left: Polygon2D = $Visual/EyeLeft
@onready var _eye_right: Polygon2D = $Visual/EyeRight
## Luz dinamica del jefe (FASE VISUAL 2). Puede ser null (luces desactivadas).
var _light: GlowLight


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	_player = _resolve_target_player()
	set_collision_mask_value(5, true)
	_last_position = global_position
	_telegraph.visible = false
	_attack_timer = data.attack_cooldown if data != null else 4.0
	# Entrada de jefe: doble onda expansiva + shake fuerte. Debe sentirse un evento.
	var accent: Color = data.accent_color if data != null else Color(1.0, 0.3, 0.25)
	Feedback.hit_effect(global_position, accent, 0.8, 4.2)
	Feedback.hit_effect(global_position, accent.lightened(0.3), 0.4, 2.4)
	Feedback.shake(0.5)
	# FASE VISUAL 2: pulso oscuro de aparicion (el mundo "traga aire") + luz propia.
	Feedback.hitstop(0.09, 0.12)
	_light = GlowLight.attach(self, accent, 250.0, 1.0, 2.0, 0.0, true)
	if is_instance_valid(_light):
		# La luz nace apagada y sube en ~0.8 s: aparicion dramatica, no un flashazo.
		var light_in := create_tween()
		light_in.tween_method(_light.set_base_energy, 0.0, 1.0, 0.8)


## Configura el jefe a partir de su BossData y la dificultad actual. La vida sube
## con difficulty_score pero queda acotada para no volverse imposible.
func configure(boss_data: BossData, difficulty_score: float) -> void:
	data = boss_data
	var scaled: float = data.max_health * (1.0 + max(0.0, difficulty_score) * data.difficulty_multiplier)
	# Coop local: mas vida para que el jefe aguante el fuego de 2 jugadores.
	if _is_coop():
		scaled *= coop_health_mult
	max_health = clampi(int(round(scaled)), data.max_health, MAX_HEALTH_CAP)
	current_health = max_health
	phase = 1
	_attack_timer = data.attack_cooldown
	if is_node_ready():
		_apply_visuals()
		_emit_health()


func _apply_visuals() -> void:
	if data == null:
		return
	scale = Vector2.ONE * data.visual_scale
	if is_instance_valid(_aura):
		_aura.color = Color(data.accent_color.r, data.accent_color.g, data.accent_color.b, 0.16)
	_recolor()


## Aplica el color del data sobre el cuerpo conservando contraste de las piezas.
func _recolor() -> void:
	var body := $Visual/Body as Polygon2D
	if body != null:
		body.color = data.visual_color
	var head := $Visual/Head as Polygon2D
	if head != null:
		head.color = data.visual_color.lightened(0.06)
	if is_instance_valid(_eye_left):
		_eye_left.color = data.accent_color
	if is_instance_valid(_eye_right):
		_eye_right.color = data.accent_color


func _physics_process(delta: float) -> void:
	if _is_dead or data == null:
		return
	# Objetivo: en coop, el jugador ACTIVO mas cercano (ignora derribados); en solo,
	# el unico jugador. Si no hay ninguno vivo, el jefe se detiene (wipe inminente).
	_player = _resolve_target_player()
	if not is_instance_valid(_player):
		velocity = Vector2.ZERO
		return

	_anim_time += delta
	_update_phase()
	_animate(delta)
	if _contact_timer > 0.0:
		_contact_timer -= delta

	match _state:
		State.CHASE:
			_state_chase(delta)
		State.WINDUP:
			_state_windup(delta)
		State.CHARGE:
			_state_charge(delta)
		State.RECOVER:
			_state_recover(delta)
		State.SUMMON:
			_state_summon(delta)


# --- Estados -----------------------------------------------------------------

func _steered_direction(target_position: Vector2) -> Vector2:
	var direct: Vector2 = global_position.direction_to(target_position)
	if not test_move(global_transform, direct * 96.0):
		return direct
	var left: Vector2 = direct.rotated(PI * 0.5)
	var right: Vector2 = direct.rotated(-PI * 0.5)
	var left_clear: bool = not test_move(global_transform, (direct + left * 0.65).normalized() * 122.0)
	var right_clear: bool = not test_move(global_transform, (direct + right * 0.65).normalized() * 122.0)
	if left_clear and right_clear:
		var left_score: float = (global_position + left * 122.0).distance_to(target_position)
		var right_score: float = (global_position + right * 122.0).distance_to(target_position)
		return (direct + (left if left_score < right_score else right) * 0.65).normalized()
	if left_clear:
		return (direct + left * 0.65).normalized()
	if right_clear:
		return (direct + right * 0.65).normalized()
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
	if _stuck_time > 1.0:
		add_to_group("stuck_enemies")
		var side := global_position.direction_to(_player.global_position).rotated(PI * 0.5 * (1.0 if sin(_anim_time) > 0.0 else -1.0))
		_avoid = side * data.move_speed * 1.1
		_stuck_time = 0.25
	_last_position = global_position
	_stuck_check_timer = 0.0


func _state_chase(delta: float) -> void:
	var dir: Vector2 = _steered_direction(_player.global_position)
	_avoid = _avoid.move_toward(Vector2.ZERO, data.move_speed * 3.0 * delta)
	velocity = dir * data.move_speed + _avoid
	move_and_slide()
	_update_stuck_state(delta)
	_face_angle = lerp_angle(_face_angle, dir.angle(), 0.08)
	_contact(data.contact_damage, false)

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_start_special()


## Elige el patron especial segun la fase y arranca su telegrafo.
func _start_special() -> void:
	# En fase 3 alterna embestida e invocacion; en fases 1-2 solo embestida.
	if phase >= 3 and randf() < 0.5:
		_enter_summon()
	else:
		_enter_windup()


func _enter_windup() -> void:
	_state = State.WINDUP
	_state_timer = windup_time
	_charge_dir = global_position.direction_to(_player.global_position)
	_telegraph.visible = true
	_telegraph.global_rotation = _charge_dir.angle()
	# Onda roja de aviso en el suelo: telegrafiado imposible de perder.
	Feedback.hit_effect(global_position, Color(1.0, 0.4, 0.35, 0.8), 0.5, 2.4)
	_visual_action(&"charge_windup")


func _state_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, data.move_speed * 4.0 * delta)
	move_and_slide()
	# Reapunta levemente hacia el jugador hasta el ultimo momento.
	_charge_dir = _charge_dir.lerp(global_position.direction_to(_player.global_position), 0.04).normalized()
	_telegraph.global_rotation = _charge_dir.angle()
	# Pulso del telegrafo para que se note el aviso.
	var t: float = 1.0 - (_state_timer / max(0.01, windup_time))
	_telegraph.modulate.a = 0.4 + 0.6 * abs(sin(t * 12.0))
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_charge()


func _enter_charge() -> void:
	_state = State.CHARGE
	_state_timer = charge_time
	_charge_hit_done = false
	_telegraph.visible = false
	Feedback.shake(0.25)
	_visual_action(&"charge")


func _state_charge(delta: float) -> void:
	velocity = _charge_dir * charge_speed
	var collided := move_and_slide()
	_face_angle = lerp_angle(_face_angle, _charge_dir.angle(), 0.22)
	# La embestida pega fuerte una vez por carga, con knockback.
	if not _charge_hit_done and _contact(data.attack_damage, true):
		_charge_hit_done = true
	_state_timer -= delta
	if _state_timer <= 0.0 or collided:
		_state = State.RECOVER
		_state_timer = recover_time


func _state_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, data.move_speed * 6.0 * delta)
	move_and_slide()
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state = State.CHASE
		_attack_timer = _next_attack_cooldown()


func _enter_summon() -> void:
	_state = State.SUMMON
	_state_timer = 0.6
	_summon_pulse = 1.0
	Feedback.shake(0.2)
	Feedback.hit_effect(global_position, data.accent_color, 0.6, 3.0)
	_visual_action(&"summon")
	_spawn_minions()


func _state_summon(delta: float) -> void:
	velocity = Vector2.ZERO
	_summon_pulse = max(0.0, _summon_pulse - delta * 1.6)
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state = State.CHASE
		_attack_timer = _next_attack_cooldown()


# --- Fases y daño ------------------------------------------------------------

func _update_phase() -> void:
	var ratio: float = float(current_health) / float(max_health)
	var new_phase: int = 1
	var thresholds: PackedFloat32Array = data.phase_thresholds
	for value in thresholds:
		if ratio <= value:
			new_phase += 1
	if new_phase != phase:
		phase = new_phase
		_on_phase_changed()


func _on_phase_changed() -> void:
	# Feedback de cambio de fase: destello y shake.
	Feedback.shake(0.3)
	Feedback.hit_effect(global_position, data.accent_color, 0.8, 3.5)
	# FASE VISUAL 2: la fase se LEE. Micro hit-stop, el aura vira hacia rojo
	# agresivo, los ojos estallan en blanco y la luz sube de energia.
	Feedback.hitstop(0.06, 0.15)
	_visual_action(&"phase_change")
	var aggression: float = clampf(0.45 * float(phase - 1), 0.0, 0.9)
	var phase_color: Color = data.accent_color.lerp(Color(1.0, 0.22, 0.16), aggression)
	if is_instance_valid(_aura):
		_aura.color = Color(phase_color.r, phase_color.g, phase_color.b, _aura.color.a)
	if is_instance_valid(_light):
		_light.color = phase_color
		_light.set_base_energy(1.0 + aggression * 0.5)
	for eye in [_eye_left, _eye_right]:
		if is_instance_valid(eye):
			eye.color = Color(1.0, 0.95, 0.85)
			var eye_tween := create_tween()
			eye_tween.tween_property(eye, "color", Color(1.0, 0.6, 0.15).lerp(Color(1.0, 0.3, 0.1), aggression), 0.6)


## Cooldown de ataque mas corto a medida que avanza la fase (mas presion).
func _next_attack_cooldown() -> float:
	var factor: float = 1.0
	if phase == 2:
		factor = 0.7
	elif phase >= 3:
		factor = 0.5
	return max(1.0, data.attack_cooldown * factor)


## Aplica daño por contacto al jugador (prioritario) y a companeros en rango.
## Devuelve true si golpeo a alguien. Usa un cooldown interno para no danar cada
## frame (el jugador ademas tiene su propio cooldown de invulnerabilidad).
func _contact(amount: int, with_knockback: bool) -> bool:
	if _contact_timer > 0.0:
		return false
	var hit_any: bool = false
	# Jugador (prioritario).
	if global_position.distance_to(_player.global_position) <= contact_range:
		if _player.has_method("take_damage"):
			_player.take_damage(amount)
			if with_knockback and _player.has_method("apply_knockback"):
				_player.apply_knockback(global_position.direction_to(_player.global_position) * data.knockback)
			hit_any = true
	# Companeros (el jefe los daña, pero no los persigue).
	for companion in get_tree().get_nodes_in_group("companions"):
		if not is_instance_valid(companion) or not companion.has_method("take_damage"):
			continue
		if not companion.has_method("can_be_targeted") or not companion.can_be_targeted():
			continue
		if global_position.distance_to(companion.global_position) <= contact_range:
			companion.take_damage(amount, global_position.direction_to(companion.global_position))
			hit_any = true
	if hit_any:
		_contact_timer = 0.45
	return hit_any


func take_damage(amount: int, _knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if _is_dead:
		return
	current_health = max(0, current_health - amount)
	Feedback.damage_number(global_position + Vector2(0, -50), amount, Color(1.0, 0.8, 0.5))
	_flash_hit()
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"boss_hit")
	_emit_health()
	if current_health <= 0:
		_die()


func _flash_hit() -> void:
	# Flash unificado (ETAPA ARTISTICA 2); fallback al codigo clasico.
	var sv: Node = get_node_or_null("SpriteVisual")
	if sv != null and sv.has_method("flash_damage"):
		sv.flash_damage(Color(1.8, 1.5, 1.5, 1.0), 0.12)
		return
	if not is_instance_valid(_visual):
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_visual.modulate = Color(1.8, 1.5, 1.5, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visual, "modulate", Color(1, 1, 1, 1), 0.12)


## Accion visual explicita hacia el SpriteVisual (no hace nada sin perfil).
func _visual_action(action: StringName) -> void:
	var sv: Node = get_node_or_null("SpriteVisual")
	if sv != null and sv.has_method("play_action"):
		sv.play_action(action)


# --- Invocacion --------------------------------------------------------------

func _spawn_minions() -> void:
	_prune_summoned()
	var allowed: int = MAX_SUMMONED - _summoned.size()
	var count: int = min(summon_count, allowed)
	for i in count:
		var minion := ENEMY_SCENE.instantiate() as Node2D
		if minion == null:
			continue
		var angle: float = TAU * float(i) / float(max(1, count)) + randf() * 0.4
		minion.global_position = global_position + Vector2.RIGHT.rotated(angle) * 70.0
		get_parent().add_child(minion)
		_summoned.append(minion)


func _prune_summoned() -> void:
	for index in range(_summoned.size() - 1, -1, -1):
		if not is_instance_valid(_summoned[index]):
			_summoned.remove_at(index)


# --- Muerte / recompensa -----------------------------------------------------

func _die() -> void:
	_is_dead = true
	velocity = Vector2.ZERO
	remove_from_group("enemies")
	set_deferred("collision_layer", 0)
	call_deferred("set_physics_process", false)
	_telegraph.visible = false
	_drop_reward()
	# Hit-stop dramatico: la derrota del jefe congela el tiempo un instante.
	Feedback.hitstop(0.14, 0.05)
	Feedback.shake(0.6)
	Feedback.death_burst(global_position, data.body_color, 10)
	var missions: Node = get_node_or_null("/root/Missions")
	if missions != null:
		missions.add(&"boss_kills")
	died.emit(data)
	# Muerte en cadena: explosiones escalonadas alrededor del cuerpo mientras se
	# encoge, y una onda final grande. La derrota del jefe debe sentirse un evento.
	var accent: Color = data.accent_color
	var center: Vector2 = global_position
	var burst := create_tween()
	for i in 4:
		burst.tween_interval(0.14)
		burst.tween_callback(func() -> void:
			var offset := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(14.0, 52.0)
			Feedback.hit_effect(center + offset, accent.lightened(randf_range(0.0, 0.3)), 0.5, 2.2)
			Feedback.shake(0.18))
	burst.tween_callback(func() -> void:
		Feedback.hit_effect(center, accent, 1.0, 5.5)
		Feedback.shake(0.5))
	# FASE VISUAL 2: la luz del jefe estalla al morir y se apaga con el cuerpo
	# (el modulate no afecta a las Light2D: hay que apagarla explicitamente).
	if is_instance_valid(_light):
		var light_out := create_tween()
		light_out.tween_method(_light.set_base_energy, 2.4, 0.0, 0.75)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", scale * 0.15, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.75)
	tween.chain().tween_callback(queue_free)


## Suelta la recompensa en varios orbes para que el iman de XP los recoja.
func _drop_reward() -> void:
	var orbs: int = 6
	var per_orb: int = max(1, int(round(float(data.xp_reward) / float(orbs))))
	for i in orbs:
		var orb := XP_ORB_SCENE.instantiate() as Node2D
		if orb == null:
			continue
		orb.set("xp_value", per_orb)
		orb.global_position = global_position
		orb.set("pop_velocity", Vector2.RIGHT.rotated(randf() * TAU) * randf_range(80.0, 200.0))
		get_parent().add_child.call_deferred(orb)


func _emit_health() -> void:
	health_changed.emit(current_health, max_health, data.display_name if data != null else "Jefe")


## Jugador objetivo: en coop el ACTIVO mas cercano (ni muerto ni derribado); en solo
## el unico jugador. Fallback al grupo "player" por compatibilidad.
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


func _animate(delta: float) -> void:
	if not is_instance_valid(_visual):
		return
	# En modo SPRITE la respiracion/rotacion procedural no se aplica; el aura
	# (nodo aparte) sigue pulsando mas abajo en ambos modos.
	var sv: Node = get_node_or_null("SpriteVisual")
	var sprite_mode: bool = sv != null and sv.has_method("is_sprite_active") and sv.is_sprite_active()
	if not sprite_mode:
		var breathe: float = sin(_anim_time * 2.0) * 0.03
		var face_sign: float = -1.0 if absf(wrapf(_face_angle, -PI, PI)) > PI * 0.5 else 1.0
		_visual.rotation = _face_angle
		_visual.scale = _visual.scale.lerp(Vector2(1.0 + breathe, face_sign * (1.0 - breathe)), 0.2)
	if is_instance_valid(_aura):
		var pulse: float = 0.16 + 0.06 * sin(_anim_time * 3.0) + _summon_pulse * 0.3
		_aura.modulate.a = pulse
	# Ojos mas intensos en fases avanzadas.
	var glow: float = 1.0 + 0.4 * float(phase - 1)
	if is_instance_valid(_eye_left):
		_eye_left.modulate = Color(glow, glow, glow, 1.0)
		_eye_right.modulate = Color(glow, glow, glow, 1.0)
