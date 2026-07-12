extends CharacterBody2D
## Gato companero con vida propia, estado derribado y revive por canalizacion.
## Rework de jugabilidad: supervivencia (50% de daño, invulnerabilidad, proteccion
## al revivir, auto-respawn), correa de seguridad (regreso/teletransporte), roles
## con pasiva + habilidad activa (Policia/Medico/Ingeniero) y escalado central.

const CompanionData = preload("res://scripts/companions/companion_data.gd")
const CompanionBalance = preload("res://scripts/companions/companion_balance.gd")
const PoliceBarricadeScript = preload("res://scripts/companions/police_barricade.gd")
const CompanionTurretScript = preload("res://scripts/companions/companion_turret.gd")

signal snapshot_changed(snapshot: Dictionary)
signal downed(data: CompanionData)
signal revived(data: CompanionData)

@export var projectile_scene: PackedScene
@export var damage_cooldown: float = CompanionBalance.HURT_INVULN_TIME

var companion_data: CompanionData
var formation_target: Vector2
var follow_smoothness: float = 5.0
var current_health: int = 1
var state: StringName = &"active"

var _player: Node2D
var _manager: Node
var _action_cooldown: float = 0.0
var _damage_timer: float = 0.0
var _damage_multiplier: float = 1.0
var _cooldown_multiplier: float = 1.0
var _medic_heal_bonus: int = 0
var _incoming_damage_multiplier: float = 1.0
var _revive_time_multiplier: float = 1.0
var _anim_time: float = 0.0
var _regen_timer: float = 0.0
var _revive_progress: float = 0.0
var _reviver_inside: bool = false
var _hurt_tween: Tween
var _bounce_tween: Tween
var _knockback: Vector2 = Vector2.ZERO
var _base_visual_scale: Vector2 = Vector2.ONE

# --- Rework: supervivencia ------------------------------------------------------
## Proteccion total tras revivir/reaparecer (no recibe daño).
var _protection_timer: float = 0.0
## Tiempo acumulado derribado sin que nadie lo reviva (auto-respawn al limite).
var _downed_timer: float = 0.0
## Ritmo de revive externo (medico cercano). Expira solo si el medico se va.
var _external_revive_rate: float = 0.0
var _external_revive_expiry: float = 0.0

# --- Rework: correa / IA segura -------------------------------------------------
## Modo regreso: demasiado lejos del lider; no ataca y vuelve mas rapido.
var _return_mode: bool = false
## Orden de reagrupamiento activa (ignora enemigos, vuelve a formacion).
var _regroup_timer: float = 0.0
## Deteccion de atasco en modo regreso (teletransporte seguro al limite).
var _stuck_timer: float = 0.0
var _last_stuck_position: Vector2 = Vector2.ZERO
## Aviso de "compañero lejos" con antirrebote (no spamear el HUD).
var _far_warning_timer: float = 0.0

# --- Rework: habilidades --------------------------------------------------------
var _ability_cooldown_timer: float = 0.0
## Bloqueo de habilidad tras un auto-respawn (penalizacion).
var _ability_lockout: float = 0.0
## Chequeo de condiciones de disparo automatico (cada 0.5 s, no cada frame).
var _trigger_check_timer: float = 0.0
## Pasiva del policia: marca de objetivo prioritario.
var _mark_timer: float = 0.0
var _marked_enemy: Node2D
## Empujon de emergencia del policia (cooldown interno independiente).
var _push_cooldown: float = 0.0
## Pasiva del ingeniero: arrastre de orbes de XP.
var _orb_pull_timer: float = 0.0
## Torreta activa del ingeniero (maximo una).
var _turret: Node2D
## Throttle del snapshot mientras se recupera el cooldown (para el HUD).
var _snapshot_throttle: float = 0.0

# --- Rework: escalado (lo fija el CompanionManager, formulas en CompanionBalance)
var _scaling_health_bonus: int = 0
var _scaling_damage_multiplier: float = 1.0

## Controlador visual de sprites (ETAPA ARTISTICA 2/3). Puede no existir.
@onready var _sprite_visual: Node = get_node_or_null("SpriteVisual")
@onready var _visual: Node2D = $Visual
@onready var _body: Polygon2D = $Visual/Body
@onready var _belly: Polygon2D = $Visual/Belly
@onready var _head: Polygon2D = $Visual/Head
@onready var _muzzle: Polygon2D = $Visual/Muzzle
@onready var _ear_left: Polygon2D = $Visual/EarLeft
@onready var _ear_right: Polygon2D = $Visual/EarRight
@onready var _tail: Polygon2D = $Visual/Tail
@onready var _eye_left: Polygon2D = $Visual/EyeLeft
@onready var _eye_right: Polygon2D = $Visual/EyeRight
@onready var _role_marker: Polygon2D = $Visual/RoleMarker
@onready var _role_hat: Polygon2D = $Visual/RoleHat
@onready var _hat_detail: Polygon2D = $Visual/HatDetail
@onready var _outline: Polygon2D = $Visual/Outline
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _status_label: Label = $StatusLabel
@onready var _revive_area: Area2D = $ReviveArea
@onready var _revive_bar: ProgressBar = $ReviveBar
@onready var _revive_label: Label = $ReviveLabel
@onready var _revive_collision: CollisionShape2D = $ReviveArea/CollisionShape2D


func _ready() -> void:
	add_to_group("companions")
	# Colisiona con los obstaculos de mapa (capa 5, Fase 08.75).
	set_collision_mask_value(5, true)
	_base_visual_scale = _visual.scale
	_revive_area.body_entered.connect(_on_revive_area_body_entered)
	_revive_area.body_exited.connect(_on_revive_area_body_exited)
	_revive_area.monitoring = false
	_revive_collision.disabled = true
	_revive_bar.visible = false
	_revive_label.visible = false
	_update_health_bar()
	_update_state_visuals()


func _exit_tree() -> void:
	# Limpieza al salir del arbol (cambio de mapa/reinicio): la marca del policia
	# no debe quedar activa sobre un enemigo que sigue vivo.
	_clear_mark()


func configure(data: CompanionData, player: Node2D, manager: Node, projectile: PackedScene) -> void:
	companion_data = data
	_player = player
	_manager = manager
	projectile_scene = projectile
	formation_target = global_position
	current_health = max(1, _max_health())
	state = &"active"
	_protection_timer = CompanionBalance.REVIVE_PROTECTION_TIME
	_downed_timer = 0.0
	_return_mode = false
	_regroup_timer = 0.0
	_ability_cooldown_timer = 0.0
	_ability_lockout = 0.0
	_last_stuck_position = global_position
	_apply_visuals()
	_update_health_bar()
	_update_state_visuals()
	_emit_snapshot()
	_play_join_bounce(0.24, Vector2(1.16, 0.88))


func set_formation_target(target: Vector2, smoothness: float) -> void:
	formation_target = target
	follow_smoothness = smoothness


func set_bonuses(
	damage_multiplier: float,
	cooldown_multiplier: float,
	medic_heal_bonus: int,
	incoming_damage_multiplier: float,
	revive_time_multiplier: float
) -> void:
	_damage_multiplier = damage_multiplier
	_cooldown_multiplier = cooldown_multiplier
	_medic_heal_bonus = medic_heal_bonus
	_incoming_damage_multiplier = incoming_damage_multiplier
	_revive_time_multiplier = revive_time_multiplier


## Vida maxima efectiva: CompanionData + bonus plano del Refugio + escalado de
## partida (minutos + vida del jugador; formula en CompanionBalance.health_bonus).
func _max_health() -> int:
	var base: int = companion_data.max_health if companion_data != null else 1
	return base + _shelter_health_bonus + _scaling_health_bonus


## Escalado central (lo empuja el CompanionManager cada 2 s). Al subir el bonus
## de vida tambien cura la diferencia (el compañero no queda "porcentualmente"
## mas herido al escalar). El multiplicador de daño llega ya con tope aplicado.
func set_scaling(health_bonus: int, damage_multiplier: float) -> void:
	var delta: int = maxi(0, health_bonus) - _scaling_health_bonus
	_scaling_health_bonus = maxi(0, health_bonus)
	_scaling_damage_multiplier = clampf(damage_multiplier, 1.0, CompanionBalance.DAMAGE_SCALE_CAP)
	if delta > 0 and not is_downed():
		current_health += delta
	_update_health_bar()


## Vida extra plana del Refugio (Camas de Colonia). Al aplicarse por primera vez
## tambien cura la diferencia, para que el compañero recien rescatado nazca lleno.
var _shelter_health_bonus: int = 0

func set_shelter_health_bonus(amount: int) -> void:
	var delta: int = maxi(0, amount) - _shelter_health_bonus
	_shelter_health_bonus = maxi(0, amount)
	if delta > 0 and not is_downed():
		current_health += delta
	_update_health_bar()


func _physics_process(delta: float) -> void:
	if companion_data == null:
		return
	var leader: Node2D = _leader()
	if leader == null:
		velocity = Vector2.ZERO
		return

	if _action_cooldown > 0.0:
		_action_cooldown -= delta
	if _damage_timer > 0.0:
		_damage_timer -= delta
	if _protection_timer > 0.0:
		_protection_timer -= delta
	if _push_cooldown > 0.0:
		_push_cooldown -= delta
	if _regroup_timer > 0.0:
		_regroup_timer -= delta
	if _far_warning_timer > 0.0:
		_far_warning_timer -= delta
	if _ability_lockout > 0.0:
		_ability_lockout -= delta
	if _ability_cooldown_timer > 0.0:
		_ability_cooldown_timer -= delta
		_throttled_snapshot(delta)
		if _ability_cooldown_timer <= 0.0:
			_emit_snapshot()  # habilidad lista: el HUD lo refleja al instante

	if _knockback != Vector2.ZERO:
		_knockback *= exp(-10.0 * delta)
		if _knockback.length_squared() < 1.0:
			_knockback = Vector2.ZERO

	if is_downed():
		_downed_timer += delta
		if _downed_timer >= CompanionBalance.DOWNED_AUTO_RESPAWN_TIME:
			_auto_respawn(leader)
			return
		_update_revive(delta)
		_animate_visual(delta)
		return

	_update_leash(delta, leader)
	_update_follow(delta)
	if not _return_mode and _regroup_timer <= 0.0:
		_update_role()
		_update_ability(delta, leader)
	_update_passive_regen(delta)
	_animate_visual(delta)


## Lider de referencia: el jugador activo que decide el manager (estable en coop,
## sin saltos constantes entre P1 y P2). Fallback al player asignado al configurar.
func _leader() -> Node2D:
	if is_instance_valid(_manager) and _manager.has_method("get_leader"):
		var leader: Node2D = _manager.get_leader()
		if is_instance_valid(leader):
			return leader
	if is_instance_valid(_player) and not _player_is_dead():
		return _player
	return null


## Correa de seguridad: mas alla de la distancia blanda deja de atacar y vuelve;
## mas alla de la de emergencia (o atrapado mientras vuelve) se reposiciona junto
## al lider en un punto seguro. Los compañeros nunca participan del encuadre de
## la CoopCamera (esa solo mira el grupo "players"), asi que esto no toca el zoom.
func _update_leash(delta: float, leader: Node2D) -> void:
	var distance: float = global_position.distance_to(leader.global_position)

	if distance > CompanionBalance.EMERGENCY_LEASH_DISTANCE:
		_safe_teleport(leader)
		return

	if _return_mode:
		# Atrapado contra un obstaculo mientras vuelve? Teletransporte seguro.
		if global_position.distance_to(_last_stuck_position) < 6.0:
			_stuck_timer += delta
			if _stuck_timer >= CompanionBalance.STUCK_TELEPORT_TIME:
				_safe_teleport(leader)
				return
		else:
			_stuck_timer = 0.0
			_last_stuck_position = global_position
		# Sale del modo regreso al acercarse de nuevo (con histeresis).
		if distance < CompanionBalance.SOFT_LEASH_DISTANCE * 0.55:
			_return_mode = false
			_stuck_timer = 0.0
	elif distance > CompanionBalance.SOFT_LEASH_DISTANCE:
		_return_mode = true
		_stuck_timer = 0.0
		_last_stuck_position = global_position
		if _far_warning_timer <= 0.0:
			_far_warning_timer = 6.0
			if is_instance_valid(_manager) and _manager.has_method("notify_companion_far"):
				_manager.notify_companion_far(companion_data)


## Reposicion segura junto al lider: nunca dentro de un obstaculo ni encima de
## enemigos. Transicion discreta (pequeño destello, sin efectos costosos).
func _safe_teleport(leader: Node2D) -> void:
	global_position = _find_safe_spot(leader)
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_return_mode = false
	_stuck_timer = 0.0
	_protection_timer = maxf(_protection_timer, 0.6)
	Feedback.hit_effect(global_position, Color(0.8, 0.9, 1.0, 0.6), 0.25, 1.1)


## Busca un punto libre alrededor del lider: sin colision con obstaculos
## (test_move) y sin enemigos demasiado cerca. Fallback: la posicion del lider.
func _find_safe_spot(leader: Node2D) -> Vector2:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var clearance_sq: float = CompanionBalance.SAFE_SPOT_ENEMY_CLEARANCE * CompanionBalance.SAFE_SPOT_ENEMY_CLEARANCE
	for i in 8:
		var angle: float = TAU * float(i) / 8.0
		var candidate: Vector2 = leader.global_position + Vector2.RIGHT.rotated(angle) * CompanionBalance.SAFE_SPOT_RADIUS
		if test_move(Transform2D(0.0, candidate), Vector2(0.0, 1.0)):
			continue
		var blocked: bool = false
		for enemy in enemies:
			if not is_instance_valid(enemy) or not (enemy is Node2D):
				continue
			if candidate.distance_squared_to((enemy as Node2D).global_position) < clearance_sq:
				blocked = true
				break
		if not blocked:
			return candidate
	return leader.global_position


## Aura de regeneracion sostenida (medico): cura un poco a aliados/jugador
## cercanos cada cierto intervalo, dando utilidad continua fuera de combate.
func _update_passive_regen(delta: float) -> void:
	if companion_data.passive_regen <= 0:
		return
	_regen_timer -= delta
	if _regen_timer > 0.0:
		return
	_regen_timer = max(0.25, companion_data.passive_regen_interval)

	var amount: int = max(1, companion_data.passive_regen + (_medic_heal_bonus / 3))
	var healed_any: bool = false
	var range_sq: float = companion_data.passive_regen_range * companion_data.passive_regen_range

	var needy := _neediest_player()
	if needy != null and needy.has_method("heal"):
		if global_position.distance_squared_to(needy.global_position) <= range_sq:
			needy.heal(amount)
			healed_any = true

	for ally in get_tree().get_nodes_in_group("companions"):
		if ally == self or not is_instance_valid(ally):
			continue
		if not ally.has_method("is_downed") or ally.is_downed():
			continue
		if not ally.has_method("get_health_ratio") or ally.get_health_ratio() >= 1.0:
			continue
		if global_position.distance_squared_to(ally.global_position) <= range_sq:
			ally.heal(amount)
			healed_any = true

	if healed_any:
		Feedback.hit_effect(global_position, Color(0.55, 1.0, 0.72, 0.55), 0.25, 1.25)
		_play_audio(&"medic_heal")


func _update_follow(delta: float) -> void:
	var to_target: Vector2 = formation_target - global_position
	var distance: float = to_target.length()
	# Modo regreso / reagrupamiento: vuelve mas rapido e ignora el ataque.
	var speed_cap: float = companion_data.move_speed
	if _regroup_timer > 0.0:
		speed_cap *= CompanionBalance.REGROUP_SPEED_BONUS
	elif _return_mode:
		speed_cap *= CompanionBalance.RETURN_SPEED_BONUS
	if distance <= 4.0:
		velocity = velocity.move_toward(Vector2.ZERO, companion_data.move_speed * delta * 4.0)
	else:
		var desired_speed: float = min(speed_cap, distance * follow_smoothness)
		velocity = to_target.normalized() * desired_speed + _knockback
	move_and_slide()


func _update_role() -> void:
	if _action_cooldown > 0.0:
		return

	match companion_data.role:
		&"medic":
			_try_heal_target()
		&"police":
			var police_target := _find_priority_enemy(true)
			if police_target != null:
				_fire_at(police_target)
				_action_cooldown = _effective_attack_cooldown()
		_:
			var target := _find_priority_enemy(false)
			if target != null:
				_fire_at(target)
				_action_cooldown = _effective_attack_cooldown()


## Jugador ACTIVO mas herido (P1 o P2 en coop; el unico en solo). Ignora derribados
## (a los jugadores los revive el otro jugador, no el medico) y a quien esta lleno.
func _neediest_player() -> Node2D:
	var best: Node2D = null
	var lowest_ratio: float = 1.0
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		if p.has_method("is_active") and not p.is_active():
			continue
		var cur = p.get("current_health")
		var mx = p.get("max_health")
		if cur == null or mx == null or int(mx) <= 0:
			continue
		var ratio: float = float(cur) / float(mx)
		if ratio < 1.0 and ratio < lowest_ratio:
			lowest_ratio = ratio
			best = p
	return best


func _try_heal_target() -> void:
	# Coop: cura al jugador ACTIVO mas herido (no solo a P1).
	var heal_target: Node = _neediest_player()

	if heal_target == null:
		var lowest_ratio: float = 1.1
		for ally in get_tree().get_nodes_in_group("companions"):
			if ally == self or not is_instance_valid(ally):
				continue
			if not ally.has_method("is_downed") or ally.is_downed():
				continue
			if not ally.has_method("get_health_ratio"):
				continue
			if global_position.distance_to(ally.global_position) > companion_data.attack_range:
				continue
			var ratio: float = ally.get_health_ratio()
			if ratio < lowest_ratio:
				lowest_ratio = ratio
				heal_target = ally

	if heal_target == null:
		return

	var heal_amount: int = max(1, companion_data.heal_amount + _medic_heal_bonus)
	if heal_target.has_method("heal"):
		heal_target.heal(heal_amount)
		_action_cooldown = max(0.1, companion_data.heal_cooldown)
		var target_position: Vector2 = heal_target.global_position if heal_target is Node2D else global_position
		Feedback.hit_effect(target_position, Color(0.55, 1.0, 0.72, 0.9), 0.30, 1.55)
		_play_audio(&"medic_heal")
		_play_join_bounce(0.10, Vector2(1.06, 0.95))
		# Accion visual explicita de curacion (anim "ability" del medico).
		var sv: Node = get_node_or_null("SpriteVisual")
		if sv != null and sv.has_method("play_ability"):
			sv.play_ability()


func _find_priority_enemy(near_player: bool) -> Node2D:
	# El policia dispara primero a su enemigo marcado si sigue en rango.
	if companion_data.role == &"police" and is_instance_valid(_marked_enemy) \
			and _marked_enemy.is_in_group("enemies") \
			and global_position.distance_to(_marked_enemy.global_position) <= companion_data.attack_range:
		return _marked_enemy

	var nearest: Node2D = null
	var nearest_distance: float = companion_data.attack_range
	var leader: Node2D = _leader()
	var reference: Vector2 = leader.global_position if near_player and is_instance_valid(leader) else global_position

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var distance_from_reference: float = reference.distance_to(enemy.global_position)
		if distance_from_reference > nearest_distance:
			continue
		if global_position.distance_to(enemy.global_position) > companion_data.attack_range * 1.15:
			continue
		nearest_distance = distance_from_reference
		nearest = enemy
	return nearest


func _fire_at(target: Node2D) -> void:
	if projectile_scene == null:
		return
	var projectile := projectile_scene.instantiate() as Node2D
	if projectile == null:
		return

	var direction: Vector2 = global_position.direction_to(target.global_position)
	projectile.global_position = global_position + direction * 18.0
	projectile.modulate = companion_data.projectile_color
	if companion_data.role == &"engineer":
		projectile.scale = Vector2(1.25, 1.25)
	projectile.call("setup", direction, companion_data.projectile_speed, _effective_attack_damage())
	get_tree().current_scene.add_child(projectile)
	# Accion visual explicita (solo representa; sin logica en el controlador).
	var sv: Node = get_node_or_null("SpriteVisual")
	if sv != null and sv.has_method("play_attack"):
		sv.play_attack()
	Feedback.hit_effect(projectile.global_position, companion_data.projectile_color, 0.16, 0.54)
	if companion_data.role == &"engineer":
		Feedback.hit_effect(projectile.global_position, companion_data.projectile_color.lightened(0.12), 0.20, 0.70)
	_play_join_bounce(0.08, Vector2(1.08, 0.94))


# --- Habilidades de rol (pasiva + activa automatica) ----------------------------

## Nombre legible de la habilidad activa (HUD/tooltips).
func get_ability_name() -> String:
	if companion_data == null:
		return ""
	match companion_data.role:
		&"police":
			return "Barricada policial"
		&"medic":
			return "Emergencia de nueve vidas"
		_:
			return "Zona fortificada"


func _update_ability(delta: float, leader: Node2D) -> void:
	if _ability_lockout > 0.0:
		return

	match companion_data.role:
		&"police":
			_update_police_mark(delta, leader)
		&"medic":
			_update_medic_assist(delta)
		&"engineer":
			_update_engineer_orbs(delta, leader)

	# Disparo automatico de la habilidad activa y chequeos que recorren el grupo
	# de enemigos: SIEMPRE en ticks de 0.5 s, nunca cada frame.
	_trigger_check_timer -= delta
	if _trigger_check_timer > 0.0:
		return
	_trigger_check_timer = 0.5

	if companion_data.role == &"police":
		_update_police_push(leader)
	if _ability_cooldown_timer > 0.0:
		return

	match companion_data.role:
		&"police":
			if _count_enemies_near(leader.global_position, CompanionBalance.POLICE_BARRICADE_TRIGGER_RANGE) \
					>= CompanionBalance.POLICE_BARRICADE_TRIGGER_COUNT:
				_cast_police_barricade(leader)
		&"medic":
			var needy := _neediest_player()
			if needy != null and _player_health_ratio(needy) < CompanionBalance.MEDIC_EMERGENCY_THRESHOLD:
				_cast_medic_emergency(needy)
		&"engineer":
			if not is_instance_valid(_turret) \
					and _count_enemies_near(global_position, CompanionBalance.ENGINEER_TURRET_TRIGGER_RANGE) \
					>= CompanionBalance.ENGINEER_TURRET_TRIGGER_COUNT:
				_cast_engineer_turret()


## --- Policia: pasiva "Objetivo prioritario" ------------------------------------
## Marca elites/jefes (o al enemigo mas peligroso cercano) con un anillo visible.
## El marcado recibe daño extra de TODO el equipo (lo aplica enemy.take_damage).
func _update_police_mark(delta: float, leader: Node2D) -> void:
	_mark_timer -= delta
	if _mark_timer > 0.0:
		return
	_mark_timer = CompanionBalance.POLICE_MARK_INTERVAL
	if is_instance_valid(_marked_enemy) and _marked_enemy.is_in_group("enemies"):
		return  # la marca actual sigue viva; no rotar marcas sin necesidad
	_clear_mark()

	var best: Node2D = null
	var best_score: float = -INF
	var range_sq: float = CompanionBalance.POLICE_MARK_RANGE * CompanionBalance.POLICE_MARK_RANGE
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var dist_sq: float = leader.global_position.distance_squared_to((enemy as Node2D).global_position)
		if dist_sq > range_sq:
			continue
		var score: float = -dist_sq
		# Prioriza especiales: elites (y cualquier cosa que no sea perro comun).
		var elite = enemy.get("_elite_kind")
		if elite != null and elite != &"":
			score += range_sq * 4.0
		if score > best_score:
			best_score = score
			best = enemy
	if best == null:
		return

	_marked_enemy = best
	best.set_meta(&"companion_mark", true)
	# Anillo visual: hijo del enemigo (muere con el, sin limpieza manual).
	var ring := Line2D.new()
	ring.name = "CompanionMarkRing"
	var points := PackedVector2Array()
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		points.append(Vector2(cos(a) * 24.0, sin(a) * 21.0))
	ring.points = points
	ring.closed = true
	ring.width = 3.0
	ring.default_color = Color(0.95, 0.82, 0.35, 0.9)
	best.add_child(ring)
	Feedback.hit_effect((best as Node2D).global_position, Color(0.95, 0.82, 0.35, 0.8), 0.3, 1.2)


func _clear_mark() -> void:
	if is_instance_valid(_marked_enemy):
		_marked_enemy.remove_meta(&"companion_mark")
		var ring := _marked_enemy.get_node_or_null("CompanionMarkRing")
		if ring != null:
			ring.queue_free()
	_marked_enemy = null


## --- Policia: empujon de emergencia (protege al jugador vulnerable) ------------
func _update_police_push(leader: Node2D) -> void:
	if _push_cooldown > 0.0:
		return
	var needy := _neediest_player()
	var protect: Node2D = needy if needy != null else leader
	if _player_health_ratio(protect) >= CompanionBalance.POLICE_PROTECT_THRESHOLD:
		return
	var pushed: int = 0
	var range_sq: float = CompanionBalance.POLICE_PUSH_RANGE * CompanionBalance.POLICE_PUSH_RANGE
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var offset: Vector2 = (enemy as Node2D).global_position - protect.global_position
		if offset.length_squared() > range_sq:
			continue
		if enemy.has_method("take_damage"):
			var dir: Vector2 = offset.normalized() if offset != Vector2.ZERO else Vector2.RIGHT
			enemy.take_damage(1, dir)
			if enemy.has_method("apply_slow"):
				enemy.apply_slow(0.6, 1.0)
			pushed += 1
	if pushed > 0:
		_push_cooldown = CompanionBalance.POLICE_PUSH_COOLDOWN
		Feedback.hit_effect(protect.global_position, Color(0.45, 0.72, 1.0, 0.7), 0.3, 1.5)
		_play_audio(&"companion_ability")


## --- Policia: habilidad "Barricada policial" -----------------------------------
func _cast_police_barricade(leader: Node2D) -> void:
	var zone := Node2D.new()
	zone.set_script(PoliceBarricadeScript)
	# Sinergia Policia + Medico: la barricada cura si hay un medico activo.
	var with_medic: bool = _manager_has_active_role(&"medic")
	zone.call("configure", CompanionBalance.POLICE_BARRICADE_RADIUS, CompanionBalance.POLICE_BARRICADE_DURATION, with_medic)
	# Entre el lider y el centro de masa enemiga cercano (donde mas presion hay).
	var threat: Vector2 = _enemy_centroid_near(leader.global_position, CompanionBalance.POLICE_BARRICADE_TRIGGER_RANGE)
	zone.global_position = leader.global_position.lerp(threat, 0.5)
	get_tree().current_scene.add_child(zone)
	_start_ability_cooldown(CompanionBalance.POLICE_BARRICADE_COOLDOWN)
	_play_ability_feedback()


## --- Medico: asistencia de revive (pasiva extra) --------------------------------
## Canaliza el revive de compañeros caidos cercanos, aunque el jugador no este.
func _update_medic_assist(_delta: float) -> void:
	for ally in get_tree().get_nodes_in_group("companions"):
		if ally == self or not is_instance_valid(ally):
			continue
		if not ally.has_method("is_downed") or not ally.is_downed():
			continue
		if global_position.distance_to((ally as Node2D).global_position) > CompanionBalance.MEDIC_ASSIST_RANGE:
			continue
		if ally.has_method("add_external_revive"):
			ally.add_external_revive(CompanionBalance.MEDIC_ASSIST_REVIVE_RATE)


## Ritmo de revive externo (aportado por el medico). Expira en 0.3 s si el
## medico se aleja o cae (no queda pegado para siempre).
func add_external_revive(rate: float) -> void:
	_external_revive_rate = maxf(_external_revive_rate, rate)
	_external_revive_expiry = 0.3


## --- Medico: habilidad "Emergencia de nueve vidas" -----------------------------
func _cast_medic_emergency(target: Node2D) -> void:
	var heal_amount: int = max(1, int(round(
		(companion_data.heal_amount + _medic_heal_bonus) * CompanionBalance.MEDIC_EMERGENCY_HEAL_MULT
	)))
	if target.has_method("heal"):
		target.heal(heal_amount)
	if target.has_method("apply_companion_shield"):
		target.apply_companion_shield(CompanionBalance.MEDIC_SHIELD_REDUCTION, CompanionBalance.MEDIC_SHIELD_DURATION)
	Feedback.hit_effect(target.global_position, Color(0.55, 1.0, 0.72, 0.9), 0.45, 2.0)
	_start_ability_cooldown(CompanionBalance.MEDIC_ABILITY_COOLDOWN)
	_play_ability_feedback()
	_play_audio(&"medic_heal")


## --- Ingeniero: pasiva "Mantenimiento de campo" (arrastre de orbes) ------------
## Empuja orbes de XP cercanos hacia el lider. No roba XP: los orbes solo se
## recogen al tocar al jugador (la XP compartida no se altera).
func _update_engineer_orbs(delta: float, leader: Node2D) -> void:
	_orb_pull_timer -= delta
	if _orb_pull_timer > 0.0:
		return
	_orb_pull_timer = CompanionBalance.ENGINEER_ORB_PULL_INTERVAL
	var radius_sq: float = CompanionBalance.ENGINEER_ORB_PULL_RADIUS * CompanionBalance.ENGINEER_ORB_PULL_RADIUS
	for orb in get_tree().get_nodes_in_group("xp_orbs"):
		if not is_instance_valid(orb) or not (orb is Node2D):
			continue
		if global_position.distance_squared_to((orb as Node2D).global_position) > radius_sq:
			continue
		if orb.has_method("nudge_toward"):
			orb.nudge_toward(leader.global_position, CompanionBalance.ENGINEER_ORB_PULL_SPEED)


## --- Ingeniero: habilidad "Zona fortificada" (torreta temporal) ----------------
func _cast_engineer_turret() -> void:
	var turret := Node2D.new()
	turret.set_script(CompanionTurretScript)
	var turret_damage: int = max(1, int(round(_effective_attack_damage() * CompanionBalance.ENGINEER_TURRET_DAMAGE_FACTOR)))
	# Sinergia Medico + Ingeniero: la torreta emite pulsos de curacion.
	var with_medic: bool = _manager_has_active_role(&"medic")
	turret.call("configure", projectile_scene, turret_damage, with_medic)
	# Se instala en la posicion actual del ingeniero: siempre navegable y nunca
	# dentro de una pared (el propio ingeniero esta parado ahi).
	turret.global_position = global_position
	get_tree().current_scene.add_child(turret)
	_turret = turret
	_start_ability_cooldown(CompanionBalance.ENGINEER_TURRET_COOLDOWN)
	_play_ability_feedback()


# --- Utilidades de habilidades ---------------------------------------------------

func _start_ability_cooldown(cooldown: float) -> void:
	# Se beneficia parcialmente de la reduccion de cooldown de los upgrades de
	# compañeros (mismo multiplicador que el ataque, con su tope global).
	_ability_cooldown_timer = max(4.0, cooldown * _cooldown_multiplier)
	_emit_snapshot()


func _play_ability_feedback() -> void:
	_play_join_bounce(0.16, Vector2(1.14, 0.90))
	var sv: Node = get_node_or_null("SpriteVisual")
	if sv != null and sv.has_method("play_ability"):
		sv.play_ability()


func _manager_has_active_role(role: StringName) -> bool:
	return is_instance_valid(_manager) and _manager.has_method("has_active_role") \
		and _manager.has_active_role(role)


func _count_enemies_near(center: Vector2, radius: float) -> int:
	var count: int = 0
	var radius_sq: float = radius * radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		if center.distance_squared_to((enemy as Node2D).global_position) <= radius_sq:
			count += 1
	return count


func _enemy_centroid_near(center: Vector2, radius: float) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	var radius_sq: float = radius * radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var pos: Vector2 = (enemy as Node2D).global_position
		if center.distance_squared_to(pos) <= radius_sq:
			sum += pos
			count += 1
	return sum / float(count) if count > 0 else center


func _player_health_ratio(p: Node2D) -> float:
	var cur = p.get("current_health")
	var mx = p.get("max_health")
	if cur == null or mx == null or int(mx) <= 0:
		return 1.0
	return float(cur) / float(mx)


# --- Reagrupamiento y auto-respawn ----------------------------------------------

## Orden "Reagruparse": abandona el objetivo, ignora enemigos y vuelve a la
## formacion con velocidad extra. No consume la habilidad especial.
func start_regroup() -> void:
	if is_downed():
		return
	_regroup_timer = CompanionBalance.REGROUP_DURATION
	_return_mode = false
	_stuck_timer = 0.0


## Si nadie lo revive a tiempo, reaparece junto al lider con penalizacion:
## poca vida y su habilidad bloqueada un rato. No hay muerte definitiva.
func _auto_respawn(leader: Node2D) -> void:
	current_health = max(1, int(round(_max_health() * CompanionBalance.RESPAWN_HEALTH_PERCENT)))
	state = &"hurt"
	_revive_progress = 0.0
	_reviver_inside = false
	_external_revive_rate = 0.0
	_downed_timer = 0.0
	_protection_timer = CompanionBalance.REVIVE_PROTECTION_TIME
	_ability_lockout = CompanionBalance.RESPAWN_ABILITY_LOCKOUT
	global_position = _find_safe_spot(leader)
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_update_health_bar()
	_update_state_visuals()
	Feedback.hit_effect(global_position, Color(0.62, 1.0, 0.72, 0.95), 0.40, 1.8)
	_play_join_bounce(0.18, Vector2(1.12, 0.92))
	revived.emit(companion_data)
	_emit_snapshot()


## Snapshot con antirrebote mientras el cooldown se recupera (el HUD muestra la
## barra de habilidad sin reconstruirse cada frame).
func _throttled_snapshot(delta: float) -> void:
	_snapshot_throttle -= delta
	if _snapshot_throttle <= 0.0:
		_snapshot_throttle = 1.0
		_emit_snapshot()


func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if companion_data == null or is_downed() or _damage_timer > 0.0 or _protection_timer > 0.0:
		return

	_damage_timer = damage_cooldown
	# Los compañeros reciben solo una fraccion del daño normal (resistencia base
	# contra contacto masivo y zonas persistentes), ademas de su reduccion propia.
	var reduced_amount: int = max(1, int(round(
		amount * CompanionBalance.INCOMING_DAMAGE_FACTOR
		* (1.0 - companion_data.damage_reduction) * _incoming_damage_multiplier
	)))
	current_health = max(0, current_health - reduced_amount)
	if knockback_dir != Vector2.ZERO:
		_knockback += knockback_dir.normalized() * 110.0
	_flash_hurt()
	Feedback.damage_number(global_position + Vector2(0, -20), reduced_amount, Color(1.0, 0.7, 0.7, 1.0))
	_update_state_from_health()
	_emit_snapshot()

	if current_health <= 0:
		_enter_downed()


func heal(amount: int) -> void:
	if amount <= 0 or is_downed():
		return
	current_health = min(_max_health(), current_health + amount)
	_update_state_from_health()
	_update_health_bar()
	_emit_snapshot()


func is_downed() -> bool:
	return state == &"downed" or state == &"reviving"


func can_be_targeted() -> bool:
	return companion_data != null and not is_downed()


func get_follow_distance() -> float:
	if companion_data == null:
		return 0.0
	return companion_data.follow_distance


func get_health_ratio() -> float:
	if companion_data == null or _max_health() <= 0:
		return 0.0
	return float(current_health) / float(_max_health())


func build_snapshot() -> Dictionary:
	# Cooldown de habilidad normalizado para el HUD (0 = lista, 1 = recien usada).
	var base_cooldown: float = _ability_base_cooldown()
	var cooldown_ratio: float = 0.0
	if base_cooldown > 0.0 and _ability_cooldown_timer > 0.0:
		cooldown_ratio = clampf(_ability_cooldown_timer / base_cooldown, 0.0, 1.0)
	return {
		"id": companion_data.id if companion_data != null else &"",
		"display_name": companion_data.display_name if companion_data != null else "",
		"role": companion_data.role if companion_data != null else &"",
		"state": state,
		"current_health": current_health,
		"max_health": _max_health() if companion_data != null else 1,
		"visual_color": companion_data.visual_color if companion_data != null else Color.WHITE,
		"accent_color": companion_data.accent_color if companion_data != null else Color.BLACK,
		"ability_name": get_ability_name(),
		"ability_ready": _ability_cooldown_timer <= 0.0 and _ability_lockout <= 0.0,
		"ability_locked": _ability_lockout > 0.0,
		"ability_cooldown_ratio": cooldown_ratio,
	}


func _ability_base_cooldown() -> float:
	if companion_data == null:
		return 0.0
	match companion_data.role:
		&"police":
			return CompanionBalance.POLICE_BARRICADE_COOLDOWN
		&"medic":
			return CompanionBalance.MEDIC_ABILITY_COOLDOWN
		_:
			return CompanionBalance.ENGINEER_TURRET_COOLDOWN


func _emit_snapshot() -> void:
	snapshot_changed.emit(build_snapshot())


func _update_state_from_health() -> void:
	if current_health <= 0:
		return
	state = &"hurt" if get_health_ratio() < 0.55 else &"active"
	_update_health_bar()
	_update_state_visuals()


func _enter_downed() -> void:
	current_health = 0
	state = &"downed"
	velocity = Vector2.ZERO
	_action_cooldown = 0.0
	_revive_progress = 0.0
	_reviver_inside = false
	_downed_timer = 0.0
	_return_mode = false
	_regroup_timer = 0.0
	_external_revive_rate = 0.0
	_clear_mark()
	_update_health_bar()
	_update_state_visuals()
	Feedback.hit_effect(global_position, Color(1.0, 0.55, 0.55, 0.95), 0.35, 1.4)
	downed.emit(companion_data)
	_emit_snapshot()


func _update_revive(delta: float) -> void:
	# Ritmo total de revive: jugador encima (1.0) + asistencia del medico (se
	# suman: el medico acelera el rescate o lo canaliza solo si esta cerca).
	var rate: float = 1.0 if (_reviver_inside and not _player_is_dead()) else 0.0
	if _external_revive_expiry > 0.0:
		_external_revive_expiry -= delta
		if _external_revive_expiry <= 0.0:
			_external_revive_rate = 0.0
	rate += _external_revive_rate

	if rate <= 0.0:
		if state == &"reviving":
			state = &"downed"
			_update_state_visuals()
			_emit_snapshot()
		return

	var was_reviving: bool = state == &"reviving"
	state = &"reviving"
	_revive_label.visible = true
	_revive_bar.visible = true
	_revive_progress = min(_effective_revive_time(), _revive_progress + delta * rate)
	# La barra de revive es local al companion: se puede actualizar cada frame.
	_revive_bar.value = (_revive_progress / _effective_revive_time()) * 100.0
	_update_state_visuals()
	# El snapshot cruza al manager/HUD/bono del jugador: solo en la transicion
	# downed -> reviving, no cada frame, para no recalcular todo continuamente.
	if not was_reviving:
		_emit_snapshot()
	if _revive_progress >= _effective_revive_time():
		_complete_revive()


## Daño efectivo = base * upgrades/refugio (_damage_multiplier) * escalado de
## partida (_scaling_damage_multiplier, con tope). Factores separados: sin doble
## aplicacion ni escalado infinito.
func _effective_attack_damage() -> int:
	return max(1, int(round(companion_data.attack_damage * _damage_multiplier * _scaling_damage_multiplier)))


func _effective_attack_cooldown() -> float:
	return max(0.18, companion_data.attack_cooldown * _cooldown_multiplier)


func _effective_revive_time() -> float:
	return max(0.35, companion_data.revive_time * _revive_time_multiplier)


func _apply_visuals() -> void:
	if companion_data == null:
		return
	_body.color = companion_data.visual_color
	_head.color = companion_data.visual_color.lightened(0.03)
	_belly.color = companion_data.detail_color
	_muzzle.color = companion_data.detail_color.lightened(0.05)
	_ear_left.color = companion_data.visual_color.darkened(0.10)
	_ear_right.color = companion_data.visual_color.darkened(0.10)
	_tail.color = companion_data.visual_color.darkened(0.2)
	_role_marker.color = companion_data.accent_color
	_role_hat.color = companion_data.accent_color.darkened(0.08)
	_health_bar.modulate = companion_data.visual_color.lightened(0.1)
	if is_instance_valid(_outline):
		_outline.color = companion_data.visual_color.darkened(0.68)
	# Chaleco de rol (FASE VISUAL 1): color fijo por rol, refuerza la lectura
	# del uniforme junto al gorro. Nodo opcional (get_node_or_null: no rompe
	# escenas antiguas sin chaleco).
	var vest := get_node_or_null("Visual/Vest") as Polygon2D
	if vest != null:
		match companion_data.role:
			&"police":
				vest.color = Color(0.14, 0.23, 0.44, 0.92)
			&"medic":
				vest.color = Color(0.94, 0.96, 0.93, 0.92)
			_:
				vest.color = Color(0.98, 0.62, 0.14, 0.92)
	# Uniforme por rol: gorra de policia con placa dorada, gorro blanco de medico
	# con cruz roja y casco amarillo de ingeniero. Colores fijos para que los tres
	# se distingan de un vistazo aunque cambien los datos.
	match companion_data.role:
		&"police":
			_role_hat.color = Color(0.14, 0.23, 0.44)
			_role_hat.polygon = PackedVector2Array([
				Vector2(-10, -20), Vector2(10, -20), Vector2(8, -27), Vector2(-8, -27)
			])
			if is_instance_valid(_hat_detail):
				_hat_detail.color = Color(0.07, 0.12, 0.24)
				_hat_detail.polygon = PackedVector2Array([
					Vector2(-13, -20), Vector2(13, -20), Vector2(11, -16.5), Vector2(-11, -16.5)
				])
			# Placa dorada (estrella) en el pecho.
			_role_marker.color = Color(0.95, 0.82, 0.35)
			_role_marker.polygon = PackedVector2Array([
				Vector2(0, -3), Vector2(1.8, 0.4), Vector2(5.5, 0.8), Vector2(2.8, 3.2),
				Vector2(3.4, 7.2), Vector2(0, 5.2), Vector2(-3.4, 7.2), Vector2(-2.8, 3.2),
				Vector2(-5.5, 0.8), Vector2(-1.8, 0.4)
			])
			_body.scale = Vector2(1.0, 1.0)
		&"medic":
			_role_hat.color = Color(0.96, 0.97, 0.95)
			_role_hat.polygon = PackedVector2Array([
				Vector2(-7, -24), Vector2(7, -24), Vector2(7, -15), Vector2(-7, -15)
			])
			if is_instance_valid(_hat_detail):
				# Cruz roja sobre el gorro.
				_hat_detail.color = Color(0.88, 0.25, 0.28)
				_hat_detail.polygon = PackedVector2Array([
					Vector2(-1.5, -23), Vector2(1.5, -23), Vector2(1.5, -21), Vector2(4.5, -21),
					Vector2(4.5, -18), Vector2(1.5, -18), Vector2(1.5, -16), Vector2(-1.5, -16),
					Vector2(-1.5, -18), Vector2(-4.5, -18), Vector2(-4.5, -21), Vector2(-1.5, -21)
				])
			# Cruz roja tambien en el pecho.
			_role_marker.color = Color(0.88, 0.25, 0.28)
			_role_marker.polygon = PackedVector2Array([
				Vector2(-2, -6), Vector2(2, -6), Vector2(2, -2), Vector2(6, -2),
				Vector2(6, 2), Vector2(2, 2), Vector2(2, 6), Vector2(-2, 6),
				Vector2(-2, 2), Vector2(-6, 2), Vector2(-6, -2), Vector2(-2, -2)
			])
			_body.scale = Vector2(0.94, 0.96)
		_:
			# Ingeniero: casco de obra amarillo con visera.
			_role_hat.color = Color(0.98, 0.78, 0.22)
			_role_hat.polygon = PackedVector2Array([
				Vector2(-11, -18), Vector2(-9, -25), Vector2(-4, -28), Vector2(4, -28),
				Vector2(9, -25), Vector2(11, -18)
			])
			if is_instance_valid(_hat_detail):
				_hat_detail.color = Color(0.84, 0.6, 0.14)
				_hat_detail.polygon = PackedVector2Array([
					Vector2(-13, -18), Vector2(13, -18), Vector2(12, -15), Vector2(-12, -15)
				])
			# Tuerca (hexagono) en el pecho.
			_role_marker.color = companion_data.accent_color
			_role_marker.polygon = PackedVector2Array([
				Vector2(-6, -2), Vector2(6, -2), Vector2(8, 2), Vector2(4, 7), Vector2(-4, 7), Vector2(-8, 2)
			])
			_body.scale = Vector2(1.08, 1.06)


func _animate_visual(delta: float) -> void:
	if not is_instance_valid(_visual):
		return
	# En modo SPRITE el sway/respiracion procedural no se aplica (lo representa
	# la animacion dibujada; el estado downed usa la anim "downed").
	if _sprite_visual != null and _sprite_visual.has_method("is_sprite_active") and _sprite_visual.is_sprite_active():
		return
	_anim_time += delta
	var breathe: float = sin(_anim_time * 2.4) * 0.03
	var sway: float = sin(_anim_time * 6.2) * 0.04
	var target_scale := Vector2(1.0 + breathe - sway, 1.0 + breathe + sway)
	if is_downed():
		target_scale = Vector2(0.92, 0.92)
	_visual.scale = _visual.scale.lerp(target_scale, 0.20)
	if is_instance_valid(_tail):
		var tail_amp: float = 0.04 if is_downed() else 0.20
		var tail_speed: float = 2.2 if is_downed() else 6.5
		_tail.rotation = sin(_anim_time * tail_speed) * tail_amp


func _flash_hurt() -> void:
	# Flash unificado (ETAPA ARTISTICA 2): aplica al visual activo y restaura
	# el tinte de estado previo. Fallback al codigo clasico si no hay nodo.
	var sv: Node = get_node_or_null("SpriteVisual")
	if sv != null and sv.has_method("flash_damage"):
		sv.flash_damage(Color(1.8, 0.45, 0.45, 1.0), 0.28)
		return
	if _hurt_tween != null and _hurt_tween.is_valid():
		_hurt_tween.kill()
	_visual.modulate = Color(1.8, 0.45, 0.45, 1.0)
	_hurt_tween = create_tween()
	_hurt_tween.tween_property(_visual, "modulate", Color(1, 1, 1, 1), 0.28)


func _play_join_bounce(duration: float = 0.20, target_scale: Vector2 = Vector2(1.14, 0.90)) -> void:
	if not is_instance_valid(_visual):
		return
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	_visual.scale = _base_visual_scale
	_bounce_tween = create_tween()
	_bounce_tween.tween_property(_visual, "scale", target_scale, duration * 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bounce_tween.tween_property(_visual, "scale", _base_visual_scale, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_health_bar() -> void:
	if companion_data == null:
		return
	_health_bar.max_value = _max_health()
	_health_bar.value = current_health
	_health_bar.visible = not is_downed()


func _update_state_visuals() -> void:
	if companion_data == null:
		return
	_revive_area.monitoring = is_downed()
	_revive_collision.disabled = not is_downed()
	_revive_bar.visible = state == &"reviving"
	_revive_label.visible = state == &"reviving"
	match state:
		&"active":
			_status_label.text = companion_data.display_name
			_status_label.modulate = Color(0.94, 0.97, 1.0, 0.95)
			_visual.rotation = lerp_angle(_visual.rotation, 0.0, 0.35)
			_visual.modulate = Color(1, 1, 1, 1)
		&"hurt":
			_status_label.text = "Herido"
			_status_label.modulate = Color(1.0, 0.88, 0.55, 0.95)
			_visual.rotation = lerp_angle(_visual.rotation, 0.0, 0.35)
			_visual.modulate = Color(1.0, 0.95, 0.95, 1)
		&"reviving":
			_status_label.text = "Reviviendo"
			_status_label.modulate = Color(0.75, 1.0, 0.76, 0.95)
			_visual.rotation = lerp_angle(_visual.rotation, -0.85, 0.35)
			_visual.modulate = Color(0.82, 0.9, 0.82, 0.95)
			_revive_label.text = "Reviviendo..."
		_:
			_status_label.text = "CAIDO"
			_status_label.modulate = Color(1.0, 0.62, 0.62, 0.95)
			_visual.rotation = lerp_angle(_visual.rotation, -1.10, 0.35)
			_visual.modulate = Color(0.72, 0.72, 0.72, 0.9)
			_revive_label.text = "Ayuda"


func _complete_revive() -> void:
	if not is_downed():
		return
	current_health = max(1, int(round(_max_health() * companion_data.revive_health_percent)))
	state = &"hurt"
	_revive_progress = 0.0
	_reviver_inside = false
	_external_revive_rate = 0.0
	_downed_timer = 0.0
	# Proteccion al levantarse: no puede ser destruido al instante si esta rodeado.
	_protection_timer = CompanionBalance.REVIVE_PROTECTION_TIME
	_update_health_bar()
	_update_state_visuals()
	Feedback.hit_effect(global_position, Color(0.62, 1.0, 0.72, 0.95), 0.40, 1.8)
	_play_join_bounce(0.18, Vector2(1.12, 0.92))
	revived.emit(companion_data)
	_emit_snapshot()


func _on_revive_area_body_entered(body: Node) -> void:
	# Coop: cualquier jugador (grupo "players") puede revivir al compañero. En solo
	# el unico jugador tambien esta en ese grupo, asi que el comportamiento es igual.
	if not body.is_in_group("players") or not is_downed():
		return
	_reviver_inside = true
	_revive_progress = 0.0


func _on_revive_area_body_exited(body: Node) -> void:
	if not body.is_in_group("players"):
		return
	# Aun queda otro jugador dentro del area? Entonces no cancelar el revive.
	if _any_player_in_revive_area(body):
		return
	_reviver_inside = false
	_revive_progress = 0.0
	_revive_bar.value = 0.0
	if state == &"reviving":
		state = &"downed"
		_update_state_visuals()
		_emit_snapshot()


## Coop: ¿queda algun otro jugador dentro del area de revive al salir uno?
func _any_player_in_revive_area(exiting: Node) -> bool:
	if not is_instance_valid(_revive_area) or not _revive_area.monitoring:
		# Al completar el revive se apaga el monitoring y Godot emite body_exited:
		# consultar overlaps con el area apagada es un error (y ya no importa).
		return false
	for b in _revive_area.get_overlapping_bodies():
		if b == exiting or not is_instance_valid(b):
			continue
		if b.is_in_group("players"):
			return true
	return false


func _player_is_dead() -> bool:
	return is_instance_valid(_player) and _player.has_method("is_dead") and _player.is_dead()


func _play_audio(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(name)
