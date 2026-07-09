extends CharacterBody2D
## Gato companero con vida propia, estado derribado y revive por canalizacion.

const CompanionData = preload("res://scripts/companions/companion_data.gd")

signal snapshot_changed(snapshot: Dictionary)
signal downed(data: CompanionData)
signal revived(data: CompanionData)

@export var projectile_scene: PackedScene
@export var damage_cooldown: float = 0.6

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


func configure(data: CompanionData, player: Node2D, manager: Node, projectile: PackedScene) -> void:
	companion_data = data
	_player = player
	_manager = manager
	projectile_scene = projectile
	formation_target = global_position
	current_health = max(1, _max_health())
	state = &"active"
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


## Vida maxima efectiva: la del CompanionData + el bonus plano del Refugio.
func _max_health() -> int:
	var base: int = companion_data.max_health if companion_data != null else 1
	return base + _shelter_health_bonus


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
	if _player_is_dead():
		velocity = Vector2.ZERO
		return

	if _action_cooldown > 0.0:
		_action_cooldown -= delta
	if _damage_timer > 0.0:
		_damage_timer -= delta

	if _knockback != Vector2.ZERO:
		_knockback *= exp(-10.0 * delta)
		if _knockback.length_squared() < 1.0:
			_knockback = Vector2.ZERO

	if is_downed():
		_update_revive(delta)
		_animate_visual(delta)
		return

	_update_follow(delta)
	_update_role()
	_update_passive_regen(delta)
	_animate_visual(delta)


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
	if distance <= 4.0:
		velocity = velocity.move_toward(Vector2.ZERO, companion_data.move_speed * delta * 4.0)
	else:
		var desired_speed: float = min(companion_data.move_speed, distance * follow_smoothness)
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


func _find_priority_enemy(near_player: bool) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = companion_data.attack_range
	var reference: Vector2 = _player.global_position if near_player and is_instance_valid(_player) else global_position

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
	Feedback.hit_effect(projectile.global_position, companion_data.projectile_color, 0.16, 0.54)
	if companion_data.role == &"engineer":
		Feedback.hit_effect(projectile.global_position, companion_data.projectile_color.lightened(0.12), 0.20, 0.70)
	_play_join_bounce(0.08, Vector2(1.08, 0.94))


func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if companion_data == null or is_downed() or _damage_timer > 0.0:
		return

	_damage_timer = damage_cooldown
	var reduced_amount: int = max(1, int(round(amount * (1.0 - companion_data.damage_reduction) * _incoming_damage_multiplier)))
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
	return {
		"id": companion_data.id if companion_data != null else &"",
		"display_name": companion_data.display_name if companion_data != null else "",
		"role": companion_data.role if companion_data != null else &"",
		"state": state,
		"current_health": current_health,
		"max_health": _max_health() if companion_data != null else 1,
		"visual_color": companion_data.visual_color if companion_data != null else Color.WHITE,
		"accent_color": companion_data.accent_color if companion_data != null else Color.BLACK,
	}


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
	_update_health_bar()
	_update_state_visuals()
	Feedback.hit_effect(global_position, Color(1.0, 0.55, 0.55, 0.95), 0.35, 1.4)
	downed.emit(companion_data)
	_emit_snapshot()


func _update_revive(delta: float) -> void:
	if not _reviver_inside:
		if state == &"reviving":
			state = &"downed"
			_update_state_visuals()
			_emit_snapshot()
		return
	if _player_is_dead():
		return

	var was_reviving: bool = state == &"reviving"
	state = &"reviving"
	_revive_label.visible = true
	_revive_bar.visible = true
	_revive_progress = min(_effective_revive_time(), _revive_progress + delta)
	# La barra de revive es local al companion: se puede actualizar cada frame.
	_revive_bar.value = (_revive_progress / _effective_revive_time()) * 100.0
	_update_state_visuals()
	# El snapshot cruza al manager/HUD/bono del jugador: solo en la transicion
	# downed -> reviving, no cada frame, para no recalcular todo continuamente.
	if not was_reviving:
		_emit_snapshot()
	if _revive_progress >= _effective_revive_time():
		_complete_revive()


func _effective_attack_damage() -> int:
	return max(1, int(round(companion_data.attack_damage * _damage_multiplier)))


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
		_outline.color = companion_data.visual_color.darkened(0.58)
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
	if not is_instance_valid(_revive_area):
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
