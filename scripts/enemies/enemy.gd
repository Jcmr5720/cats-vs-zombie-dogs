extends CharacterBody2D
## Perro zombi. Persigue al jugador con un leve zigzag para no amontonarse,
## recibe daño (con flash de impacto), muere con una desaparición animada y
## suelta un orbe de experiencia. Se configura con un EnemyData y multiplicadores
## de dificultad para reutilizar la misma escena con muchas variantes.

signal died(position: Vector2, xp_value: int)

const EnemyData = preload("res://scripts/enemies/enemy_data.gd")

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
	# El jugador se localiza por grupo para no acoplar referencias en la escena.
	_player = get_tree().get_first_node_in_group("player")
	# Pop de aparición: el cuerpo crece desde pequeño (la colisión no se toca).
	_spawn_scale = 0.25
	var pop := create_tween()
	pop.tween_property(self, "_spawn_scale", 1.0, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		velocity = Vector2.ZERO
		return

	_time += delta
	_chase_target = _pick_chase_target()
	var target_position: Vector2 = _player.global_position
	if is_instance_valid(_chase_target):
		target_position = _chase_target.global_position
	var direction: Vector2 = _steered_direction(target_position, delta)
	# Zigzag suave: cada enemigo serpentea con fase y fuerza propias.
	var wobble: float = sin(_time * _wobble_speed + _wobble_phase) * _wobble_strength
	if not _has_subtarget:
		direction = direction.rotated(wobble)
	velocity = direction * speed * _speed_jitter + _separation(delta) + _knockback + _avoid
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
	else:
		_stuck_time = max(0.0, _stuck_time - _stuck_check_timer * 1.5)
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
	_last_position = global_position
	_stuck_check_timer = 0.0


func _randomize_movement() -> void:
	_speed_jitter = randf_range(0.9, 1.12)
	_wobble_phase = randf() * TAU
	_wobble_strength = randf_range(0.12, 0.35)
	_wobble_speed = randf_range(2.5, 4.5)


func _pick_chase_target() -> Node2D:
	var best_target: Node2D = _player
	var player_distance: float = global_position.distance_to(_player.global_position)
	var best_distance: float = player_distance
	for companion in get_tree().get_nodes_in_group("companions"):
		if not is_instance_valid(companion):
			continue
		if not companion.has_method("can_be_targeted") or not companion.can_be_targeted():
			continue
		var distance: float = global_position.distance_to(companion.global_position)
		if distance < min(player_distance * 0.82, 180.0) and distance < best_distance:
			best_distance = distance
			best_target = companion
	return best_target


func _try_contact_damage() -> void:
	var hit_companion: Node2D = _nearest_contact_companion()
	if hit_companion != null and hit_companion.has_method("take_damage"):
		hit_companion.take_damage(contact_damage, global_position.direction_to(hit_companion.global_position))
		return
	if global_position.distance_to(_player.global_position) <= contact_range:
		if _player.has_method("take_damage"):
			_player.take_damage(contact_damage)


func _nearest_contact_companion() -> Node2D:
	var nearest: Node2D = null
	var best_distance: float = contact_range
	for companion in get_tree().get_nodes_in_group("companions"):
		if not is_instance_valid(companion):
			continue
		if not companion.has_method("can_be_targeted") or not companion.can_be_targeted():
			continue
		var distance: float = global_position.distance_to(companion.global_position)
		if distance <= best_distance:
			best_distance = distance
			nearest = companion
	return nearest


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
