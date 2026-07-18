extends CharacterBody2D
## Gato jugador. Se mueve con WASD/flechas, recibe daño con cooldown,
## acumula experiencia, sube de nivel y emite señales para que el HUD,
## el GameManager y el sistema de upgrades reaccionen sin acoplamiento directo.

signal health_changed(current: int, maximum: int)
signal experience_changed(current: int, needed: int)
signal level_changed(level: int)
signal level_up_requested(level: int)
signal damaged(amount: int)
signal died
## Fase Coop Local: el jugador cae DERRIBADO (no muere) en coop mientras quede otro
## en pie. El PlayerManager escucha estas señales para el revive y el Game Over.
signal downed(player_id: int)
signal revived(player_id: int)

## Identidad del jugador (1 = teclado/principal, 2 = gamepad en coop). En solo
## siempre es 1 y el comportamiento es idéntico al clásico.
@export var player_id: int = 1

@export var speed: float = 250.0
@export var max_health: int = 100
## Bajado de 10 a 8: la primera mejora llega antes y engancha desde el arranque.
@export var starting_experience_to_level: int = GameBalance.XP_FIRST_LEVEL
## Cuánto crece la experiencia necesaria por nivel (1.35 = +35%). Centralizado
## en GameBalance (Fase correccion): curvas de XP y dificultad en un solo sitio.
@export var experience_growth: float = GameBalance.XP_GROWTH
## Tiempo de invulnerabilidad tras recibir daño (evita daño cada frame).
@export var damage_cooldown: float = 0.5

# Topes sanos para que los upgrades no vuelvan al gato invencible (Fase 2.8).
const MAX_SPEED: float = 420.0
const MAX_HEALTH_CAP: int = 220
const MAX_PICKUP_SCALE: float = 2.4

## Identidad visual coop: colores centralizados en CoopConfig (mismos en la
## pantalla dividida y el panel de cartas). El reparto de XP tambien vive alli.
const P1_COLOR := CoopConfig.P1_COLOR
const P2_COLOR := CoopConfig.P2_COLOR


## Anillo de color bajo el gato: identidad visible en todo momento (coop).
class IdentityRing:
	extends Node2D
	var color := Color.WHITE
	## true = anillo SEGMENTADO (J2). La forma distingue a los jugadores ademas
	## del color (apoyo para daltonismo).
	var dashed := false

	func _draw() -> void:
		if dashed:
			for i in 6:
				var start: float = TAU * i / 6.0
				draw_arc(Vector2.ZERO, 26.0, start, start + TAU / 9.0, 8,
					Color(color.r, color.g, color.b, 0.85), 3.5, true)
		else:
			draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.8), 3.0, true)
		draw_arc(Vector2.ZERO, 31.0, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.25), 5.0, true)

var current_health: int
var level: int = 1
var experience: int = 0
var experience_to_level: int
## Cuántas mejoras ha elegido el jugador (lo usa la dificultad dinámica).
var upgrades_chosen: int = 0

var _damage_timer: float = 0.0
## Reduccion de dano recibido por sinergia (Medico + Rascador). Sutil, tope 0.5.
var _synergy_damage_reduction: float = 0.0
## Reduccion permanente de dano (Pelaje Erizado, Fase 09). Se combina de forma
## multiplicativa con la sinergia; NO usar set_synergy (el WeaponManager la pisa).
var _permanent_damage_reduction: float = 0.0
## Multiplicador de XP por mejoras permanentes (Instinto Felino, Fase 07).
var _xp_multiplier: float = 1.0
## Escudo temporal del Gato Medico ("Emergencia de nueve vidas"): reduccion de
## daño con vencimiento por tiempo real de juego (no requiere timer por frame).
var _companion_shield_reduction: float = 0.0
var _companion_shield_until_msec: int = 0
## Impulso externo (empuje de jefes/mini-jefes) que decae y se suma al movimiento.
var _knockback: Vector2 = Vector2.ZERO
var _is_dead: bool = false
## Coop: derribado (0 vida pero revivible). No se mueve, no dispara, no recoge XP.
var _is_downed: bool = false
## Nombres de acciones de input segun el jugador (P1 teclado, P2 gamepad/IJKL).
var _act_left: StringName = &"move_left"
var _act_right: StringName = &"move_right"
var _act_up: StringName = &"move_up"
var _act_down: StringName = &"move_down"
var _last_facing: Vector2 = Vector2.RIGHT
var _anim_time: float = 0.0
var _is_moving: bool = false
var _hurt_tween: Tween
## Temporizador de nubecitas de polvo al correr (game feel).
var _dust_timer: float = 0.0
## Controlador visual de sprites (ETAPA ARTISTICA 2/3). Puede no existir.
@onready var _sprite_visual: Node = get_node_or_null("SpriteVisual")
@onready var _weapons: Node = $WeaponManager
@onready var _pickup_area: Area2D = $PickupArea
@onready var _facing_indicator: Node2D = $FacingIndicator
@onready var _visual: Node2D = $Visual
@onready var _tail: Polygon2D = $Visual/Tail
@onready var _scarf: Polygon2D = $Visual/Scarf
@onready var _eye_left: Polygon2D = $Visual/EyeLeft
@onready var _eye_right: Polygon2D = $Visual/EyeRight


func _ready() -> void:
	# Colisiona con los obstaculos de mapa (capa 5, Fase 08.75) sin atravesarlos.
	set_collision_mask_value(5, true)
	_configure_input_profile()
	_apply_permanent_upgrades()
	current_health = max_health
	experience_to_level = starting_experience_to_level
	# Grupo "players" = todos los jugadores (targeting coop). El grupo "player"
	# (singular) lo conserva SOLO el jugador principal para no romper los sistemas
	# clasicos que esperan un unico jugador (spawner, camara solo, companeros).
	add_to_group("players")
	if player_id <= 1:
		add_to_group("player")
	else:
		_apply_second_player_look()
	# En coop AMBOS jugadores llevan anillo de color + placa J1/J2: la identidad
	# tiene que leerse de un vistazo (feedback directo de la beta).
	if _is_coop():
		_build_identity_marker()
	# Emite el estado inicial para que el HUD arranque sincronizado.
	health_changed.emit(current_health, max_health)
	experience_changed.emit(experience, experience_to_level)
	level_changed.emit(level)


## Elige las acciones de movimiento segun el jugador. P1 usa el input clasico;
## P2 usa el mapa p2_* (stick izquierdo del gamepad + IJKL como respaldo).
func _configure_input_profile() -> void:
	if player_id >= 2:
		_act_left = &"p2_move_left"
		_act_right = &"p2_move_right"
		_act_up = &"p2_move_up"
		_act_down = &"p2_move_down"


## Look distintivo del Jugador 2: tinte frio. La placa y el anillo de identidad
## los pone _build_identity_marker (para AMBOS jugadores, solo en coop).
func _apply_second_player_look() -> void:
	if is_instance_valid(_visual):
		_visual.modulate = Color(0.62, 0.78, 1.15, 1.0)


## Identidad coop: anillo de color bajo el gato (elipse en el suelo) + placa
## "J1"/"J2" sobre la cabeza, con el color fijo del jugador. Solo cosmetico.
func _build_identity_marker() -> void:
	var color: Color = P1_COLOR if player_id <= 1 else P2_COLOR
	var ring := IdentityRing.new()
	ring.color = color
	ring.dashed = player_id >= 2
	ring.position = Vector2(0, 16)
	ring.scale = Vector2(1.0, 0.55)
	ring.z_index = -1
	add_child(ring)

	var badge := Label.new()
	# Icono + numero: la FORMA identifica al jugador aunque no distinga colores.
	badge.text = CoopConfig.player_tag(player_id)
	badge.position = Vector2(-17, -60)
	badge.add_theme_font_override("font", UIFonts.fredoka(700))
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
	var chip := StyleBoxFlat.new()
	chip.bg_color = color
	chip.set_corner_radius_all(6)
	chip.set_content_margin_all(3)
	chip.content_margin_left = 7.0
	chip.content_margin_right = 7.0
	badge.add_theme_stylebox_override("normal", chip)
	add_child(badge)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	if _damage_timer > 0.0:
		_damage_timer -= delta

	# Derribado (coop): no responde a input, pero el knockback residual aun decae.
	var direction: Vector2 = Vector2.ZERO
	if not _is_downed:
		direction = Input.get_vector(_act_left, _act_right, _act_up, _act_down)
	velocity = direction * speed + _knockback
	move_and_slide()

	# El empuje externo (jefes) decae de forma exponencial.
	if _knockback != Vector2.ZERO:
		_knockback *= exp(-8.0 * delta)
		if _knockback.length_squared() < 1.0:
			_knockback = Vector2.ZERO

	# Dirección visual mínima: el indicador apunta hacia el último movimiento.
	if direction != Vector2.ZERO:
		_last_facing = direction
	_is_moving = direction != Vector2.ZERO
	if is_instance_valid(_facing_indicator):
		_facing_indicator.rotation = lerp_angle(_facing_indicator.rotation, _last_facing.angle(), 0.25)

	# Polvo bajo las patas mientras corre.
	_dust_timer -= delta
	if _is_moving and _dust_timer <= 0.0:
		_dust_timer = 0.18
		Feedback.dust_puff(global_position + Vector2(-_last_facing.x * 10.0, 18.0))

	_animate_visual(delta)


## Animación sutil del gato: respiración constante, "bounce"/squash al moverse y
## meneo de cola. Solo afecta al nodo Visual, nunca a la colisión.
func _animate_visual(delta: float) -> void:
	if not is_instance_valid(_visual):
		return
	# En modo SPRITE el squash/lean/parpadeo procedural NO se aplica: la
	# animacion dibujada lo representa. Al volver a procedural, el controlador
	# restaura el transform base (reset_visual_transform).
	if _sprite_visual != null and _sprite_visual.has_method("is_sprite_active") and _sprite_visual.is_sprite_active():
		return
	_anim_time += delta

	# Respiración base + squash-and-stretch suave al caminar.
	var breathe: float = sin(_anim_time * 2.2) * 0.025
	var walk: float = sin(_anim_time * 12.0) * 0.05 if _is_moving else 0.0
	var target := Vector2(1.0 + breathe - walk, 1.0 + breathe + walk)
	_visual.scale = _visual.scale.lerp(target, 0.3)

	# Inclinación hacia el movimiento horizontal: el gato "se lanza" al correr.
	var lean_target: float = _last_facing.x * 0.09 if _is_moving else 0.0
	_visual.rotation = lerpf(_visual.rotation, lean_target, 0.18)

	# Meneo de cola: más vivo al moverse.
	if is_instance_valid(_tail):
		var tail_speed: float = 9.0 if _is_moving else 2.5
		var tail_amp: float = 0.35 if _is_moving else 0.12
		_tail.rotation = sin(_anim_time * tail_speed) * tail_amp
	if is_instance_valid(_scarf):
		_scarf.rotation = sin(_anim_time * 7.0) * (0.16 if _is_moving else 0.05)
	if is_instance_valid(_eye_left) and is_instance_valid(_eye_right):
		var blink: bool = fmod(_anim_time, 4.2) > 4.08
		var eye_scale_y: float = 0.18 if blink else 1.0
		_eye_left.scale.y = lerpf(_eye_left.scale.y, eye_scale_y, 0.45)
		_eye_right.scale.y = lerpf(_eye_right.scale.y, eye_scale_y, 0.45)
		# Mirada direccional sutil: los ojos se desplazan hacia donde mira el gato,
		# alrededor de su posición base en la cara (fijada en Player.tscn).
		var glance: Vector2 = _last_facing.normalized() * Vector2(1.8, 1.2)
		_eye_left.position = _eye_left.position.lerp(Vector2(-6.5, -11) + glance, 0.18)
		_eye_right.position = _eye_right.position.lerp(Vector2(6.5, -11) + glance, 0.18)


## Recibe daño de un enemigo. Ignora golpes durante el cooldown o si esta derribado.
func take_damage(amount: int) -> void:
	if _is_dead or _is_downed or _damage_timer > 0.0:
		return

	_damage_timer = damage_cooldown
	# Sinergia defensiva + reduccion permanente + escudo del medico: multiplicativas.
	var shield: float = _companion_shield_reduction if Time.get_ticks_msec() < _companion_shield_until_msec else 0.0
	var final_amount: int = max(1, int(round(
		amount * (1.0 - _synergy_damage_reduction) * (1.0 - _permanent_damage_reduction) * (1.0 - shield)
	)))
	current_health = max(current_health - final_amount, 0)
	health_changed.emit(current_health, max_health)
	damaged.emit(final_amount)
	_play_audio(&"player_damage")
	if max_health > 0 and float(current_health) / float(max_health) <= 0.25:
		_play_audio(&"low_health")

	# Game feel: el gato parpadea en rojo, la camara da un shake leve y AudioManager
	# reproduce un SFX con cooldown interno.
	_flash_hurt()
	Feedback.shake(0.35)

	if current_health <= 0:
		if _is_coop():
			_go_downed()
		else:
			_die()


## Parpadeo rojo breve al recibir daño. Va por el flash unificado del
## SpriteVisual (ETAPA ARTISTICA 2): aplica al visual ACTIVO (sprite o
## procedural) y restaura el tinte previo (arregla ademas que el flash de P2
## volviera a blanco en vez de a su tinte frio). Fallback: codigo clasico.
func _flash_hurt() -> void:
	var sv: Node = get_node_or_null("SpriteVisual")
	if sv != null and sv.has_method("flash_damage"):
		sv.flash_damage(Color(1.8, 0.4, 0.4, 1.0), 0.35)
		return
	if not is_instance_valid(_visual):
		return
	if _hurt_tween != null and _hurt_tween.is_valid():
		_hurt_tween.kill()
	_visual.modulate = Color(1.8, 0.4, 0.4, 1.0)
	_hurt_tween = create_tween()
	_hurt_tween.tween_property(_visual, "modulate", Color(1, 1, 1, 1), 0.35)


## Radio de recolección de XP en píxeles del mundo (lo usa el imán del orbe).
func get_pickup_radius() -> float:
	if is_instance_valid(_pickup_area):
		# El upgrade de pickup escala el área; 90 es el radio base de la shape.
		return 90.0 * _pickup_area.scale.x
	return 90.0


## Llamado por XPOrb al ser recogido. En coop (Rework) cada jugador acumula SU
## propia XP y sube SU propio nivel (cartas independientes). Reparto (Fase 3,
## centralizado en CoopConfig): el recolector recibe XP_COLLECTOR_SHARE y el
## companero XP_PARTNER_SHARE con decaimiento por distancia — el total del equipo
## (~110%) ya no infla la progresion frente al modo solo, y separarse demasiado
## reduce la XP compartida (incentivo suave a cooperar, sin correa).
func add_experience(amount: int, from_share: bool = false) -> void:
	if _is_dead or _is_downed:
		return

	var gained: int = amount
	var coop: bool = _is_coop()
	if not from_share and coop:
		gained = maxi(1, int(round(amount * CoopConfig.XP_COLLECTOR_SHARE)))

	experience += max(1, int(round(gained * _xp_multiplier)))
	while experience >= experience_to_level:
		experience -= experience_to_level
		_level_up()

	experience_changed.emit(experience, experience_to_level)

	if not from_share and coop:
		var partner := _partner_player()
		if partner != null and partner is Node2D and partner.has_method("add_experience"):
			var share: float = CoopConfig.xp_share_at_distance(
				global_position.distance_to((partner as Node2D).global_position))
			if share > 0.0:
				partner.add_experience(maxi(1, int(ceil(amount * share))), true)


## Conectado a PickupArea.area_entered: recoge orbes de experiencia.
func _on_pickup_area_area_entered(area: Area2D) -> void:
	if _is_dead or _is_downed:
		return
	if area.is_in_group("xp_orbs") and area.has_method("collect"):
		area.collect(self)


## Aplica una carta de mejora. include_shared=false lo usa el PlayerManager en coop
## para el P2: aplica solo los efectos PROPIOS del jugador (velocidad, vida, armas)
## y NO toca al CompanionManager (bono de equipo que ya aplico el P1), para no
## duplicar los bonos compartidos.
func apply_upgrade(upgrade_id: StringName, include_shared: bool = true) -> void:
	var companion_manager: Node = get_tree().get_first_node_in_group("companion_manager") if include_shared else null
	# Magnitudes comunes reducidas en Fase 2.8 para que el escalado no sea tan
	# brusco; las mejoras raras/épicas mantienen más impacto (salen menos).
	match upgrade_id:
		&"weapon_damage":
			if is_instance_valid(_weapons) and _weapons.has_method("multiply_damage"):
				_weapons.multiply_damage(1.10)
		&"weapon_cooldown":
			if is_instance_valid(_weapons) and _weapons.has_method("multiply_cooldown"):
				_weapons.multiply_cooldown(0.90)
		&"player_speed":
			speed = min(speed * 1.06, MAX_SPEED)
		&"max_health":
			increase_max_health(15)
		&"extra_projectile":
			if is_instance_valid(_weapons) and _weapons.has_method("add_projectiles"):
				_weapons.add_projectiles(1)
		&"weapon_range":
			if is_instance_valid(_weapons) and _weapons.has_method("multiply_range"):
				_weapons.multiply_range(1.10)
		&"pickup_range":
			_increase_pickup_range(1.25)
		&"companion_damage":
			if is_instance_valid(companion_manager) and companion_manager.has_method("multiply_damage"):
				companion_manager.multiply_damage(1.10)
		&"companion_cooldown":
			if is_instance_valid(companion_manager) and companion_manager.has_method("multiply_cooldown"):
				companion_manager.multiply_cooldown(0.90)
		&"medic_boost":
			if is_instance_valid(companion_manager) and companion_manager.has_method("increase_medic_heal"):
				companion_manager.increase_medic_heal(2)
		&"colony_protection":
			if is_instance_valid(companion_manager) and companion_manager.has_method("multiply_incoming_damage"):
				companion_manager.multiply_incoming_damage(0.90)
		&"quick_revive":
			if is_instance_valid(companion_manager) and companion_manager.has_method("multiply_revive_time"):
				companion_manager.multiply_revive_time(0.80)
		&"colony_bond":
			if is_instance_valid(companion_manager) and companion_manager.has_method("increase_colony_bond_bonus"):
				companion_manager.increase_colony_bond_bonus(0.05)
		# --- MUTACIONES (recompensa del mini-boss; mas fuertes que una carta) ---
		&"mut_split_shots":
			if is_instance_valid(_weapons) and _weapons.has_method("add_projectiles"):
				_weapons.add_projectiles(2)
		&"mut_savage_power":
			if is_instance_valid(_weapons) and _weapons.has_method("multiply_damage"):
				_weapons.multiply_damage(1.35)
		&"mut_frenzy":
			if is_instance_valid(_weapons) and _weapons.has_method("multiply_cooldown"):
				_weapons.multiply_cooldown(0.70)
		&"mut_iron_hide":
			increase_max_health(40)
			_permanent_damage_reduction = clampf(_permanent_damage_reduction + 0.10, 0.0, 0.35)
		&"mut_wind_paws":
			speed = min(speed * 1.15, MAX_SPEED)
			_increase_pickup_range(1.5)

	upgrades_chosen += 1


func increase_max_health(amount: int) -> void:
	max_health = min(max_health + amount, MAX_HEALTH_CAP)
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)


## Escudo temporal del Gato Medico: reduce el daño recibido durante unos
## segundos. No vuelve al jugador inmortal (tope 0.8) y no se apila: renueva.
func apply_companion_shield(reduction: float, duration: float) -> void:
	if _is_dead:
		return
	_companion_shield_reduction = clampf(reduction, 0.0, 0.8)
	_companion_shield_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)
	# Telegrafica: destello verdoso sobre el gato (arte provisional).
	Feedback.hit_effect(global_position, Color(0.55, 1.0, 0.72, 0.8), 0.4, 1.6)


func heal(amount: int) -> void:
	if _is_dead or amount <= 0 or current_health >= max_health:
		return
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)


## Reduccion de dano recibido aportada por sinergias (la fija el WeaponManager).
func set_synergy_damage_reduction(reduction: float) -> void:
	_synergy_damage_reduction = clampf(reduction, 0.0, 0.5)


## Empuje externo (jefes/mini-jefes). Se acumula y decae en el _physics_process.
func apply_knockback(impulse: Vector2) -> void:
	if _is_dead:
		return
	_knockback += impulse


func set_external_damage_multiplier(multiplier: float) -> void:
	if is_instance_valid(_weapons) and _weapons.has_method("set_external_damage_multiplier"):
		_weapons.set_external_damage_multiplier(multiplier)


## Acceso al WeaponManager para el UpgradeManager (cartas de arma).
func get_weapon_manager() -> Node:
	return _weapons


## Aplica las mejoras permanentes (Fase 07) al iniciar la partida. Lee los valores
## del autoload MetaProgression; si no existe (p.ej. en tests), no hace nada.
## Fase Partida libre arcade: las mejoras permanentes y el Refugio SOLO afectan al
## Modo Historia. En Partida libre el reto es puro (todos en igualdad de condiciones).
func _apply_permanent_upgrades() -> void:
	if not _is_story_run():
		return
	var mp: Node = get_node_or_null("/root/MetaProgression")
	if mp == null:
		return
	max_health = min(max_health + mp.max_health_bonus(), MAX_HEALTH_CAP)
	speed = min(speed * mp.player_speed_mult(), MAX_SPEED)
	_xp_multiplier = mp.xp_mult()
	# Mejoras de historia (Fase 09): radio de recogida y armadura permanente.
	if mp.has_method("pickup_range_mult") and is_instance_valid(_pickup_area):
		var pickup_scale: float = min(_pickup_area.scale.x * mp.pickup_range_mult(), MAX_PICKUP_SCALE)
		_pickup_area.scale = Vector2(pickup_scale, pickup_scale)
	if mp.has_method("permanent_damage_reduction"):
		_permanent_damage_reduction = clampf(mp.permanent_damage_reduction(), 0.0, 0.25)

	# Refugio Felino (Fase 10): bonus de objetos COLOCADOS. Se SUMAN a las mejoras
	# permanentes (fuentes distintas, nunca se duplican) con topes propios.
	var shelter: Node = get_node_or_null("/root/Shelter")
	var shelter_damage_mult: float = 1.0
	if shelter != null and shelter.has_method("get_bonuses"):
		var bonuses: Dictionary = shelter.get_bonuses()
		max_health = min(max_health + int(round(float(bonuses.get("player_max_health_bonus", 0.0)))), MAX_HEALTH_CAP)
		speed = min(speed * (1.0 + float(bonuses.get("player_speed_bonus", 0.0))), MAX_SPEED)
		shelter_damage_mult = 1.0 + float(bonuses.get("player_damage_bonus", 0.0))
		# La reduccion del refugio se suma a la permanente, con tope global sano.
		_permanent_damage_reduction = clampf(_permanent_damage_reduction + float(bonuses.get("damage_reduction_bonus", 0.0)), 0.0, 0.35)

	if is_instance_valid(_weapons):
		if _weapons.has_method("set_permanent_damage_mult"):
			_weapons.set_permanent_damage_mult(mp.player_damage_mult() * shelter_damage_mult)
		if _weapons.has_method("set_permanent_cooldown_mult"):
			_weapons.set_permanent_cooldown_mult(mp.weapon_cooldown_mult())


func _increase_pickup_range(multiplier: float) -> void:
	if not is_instance_valid(_pickup_area):
		return
	var new_scale: float = min(_pickup_area.scale.x * multiplier, MAX_PICKUP_SCALE)
	_pickup_area.scale = Vector2(new_scale, new_scale)


func _level_up() -> void:
	level += 1
	experience_to_level = int(ceil(experience_to_level * experience_growth))
	level_changed.emit(level)
	_play_audio(&"level_up")
	# Estallido cian de subida de nivel sobre el gato: doble onda + shake leve.
	Feedback.hit_effect(global_position, Color(0.45, 0.86, 1.0, 0.9), 0.5, 2.6)
	Feedback.hit_effect(global_position, Color(0.8, 0.96, 1.0, 0.8), 0.25, 1.4)
	Feedback.shake(0.15)
	level_up_requested.emit(level)


func get_last_facing_direction() -> Vector2:
	return _last_facing.normalized()


func is_dead() -> bool:
	return _is_dead


func is_downed() -> bool:
	return _is_downed


func get_player_id() -> int:
	return player_id


## True mientras esta activo (ni muerto ni derribado): puede moverse, disparar y
## recoger XP. Lo usan enemigos y camara para elegir jugadores validos.
func is_active() -> bool:
	return not _is_dead and not _is_downed


func _is_coop() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_coop") and gf.is_coop()


## True solo en Modo Historia. En Partida libre (o sin GameFlow: F6/tests) es false,
## y las mejoras permanentes/refugio no se aplican.
func _is_story_run() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_story_run") and gf.is_story_run()


## El OTRO jugador del equipo en coop (para el reparto de XP). Null en solo.
func _partner_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and is_instance_valid(p):
			return p
	return null


## Coop: cae derribado. Detiene movimiento, apaga las armas y avisa al
## PlayerManager (que decide revive o Game Over). No emite "died".
func _go_downed() -> void:
	if _is_downed or _is_dead:
		return
	_is_downed = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_set_weapons_enabled(false)
	# En modo SPRITE el derribo lo representa la animacion "downed" (via la
	# senal); la rotacion/tinte procedural solo aplica al arte procedural.
	var sprite_mode: bool = _sprite_visual != null and _sprite_visual.has_method("is_sprite_active") and _sprite_visual.is_sprite_active()
	if is_instance_valid(_visual) and not sprite_mode:
		_visual.modulate = Color(0.45, 0.45, 0.5, 0.85)
		_visual.rotation = PI * 0.5  # tumbado de lado
	downed.emit(player_id)


## Coop: revive con un porcentaje de vida. Reactiva movimiento y armas.
func revive_player(health_percent: float = 0.4) -> void:
	if _is_dead or not _is_downed:
		return
	_is_downed = false
	current_health = max(1, int(round(max_health * clampf(health_percent, 0.05, 1.0))))
	# Invulnerabilidad al levantarse (Fase 9): al menos REVIVE_INVULN_SECONDS para
	# no revivir dentro de dano inevitable (horda encima del cuerpo).
	_damage_timer = maxf(damage_cooldown, CoopConfig.REVIVE_INVULN_SECONDS)
	_set_weapons_enabled(true)
	# Restaurar SIEMPRE el procedural (aunque este oculto en modo sprite: asi
	# un cambio de modo posterior no hereda la pose de derribado).
	if is_instance_valid(_visual):
		_visual.rotation = 0.0
		_visual.modulate = Color(0.62, 0.78, 1.15, 1.0) if player_id >= 2 else Color(1, 1, 1, 1)
	health_changed.emit(current_health, max_health)
	# FASE VISUAL 2: doble onda de revive (verde + blanca) para que el momento
	# se lea claro en medio del combate coop.
	Feedback.hit_effect(global_position, Color(0.5, 1.0, 0.7, 0.9), 0.4, 2.2)
	Feedback.hit_effect(global_position, Color(0.9, 1.0, 0.95, 0.7), 0.2, 1.3)
	revived.emit(player_id)


## Muerte definitiva del equipo (la fuerza el PlayerManager cuando TODOS estan
## derribados). Emite "died" para disparar el Game Over clasico (GameManager/MapManager).
func force_team_death() -> void:
	if _is_dead:
		return
	_is_downed = false
	_die()


## Enciende/apaga el WeaponManager (y sus armas hijas) sin destruirlo, para que un
## jugador derribado deje de disparar y vuelva a hacerlo intacto al revivir.
func _set_weapons_enabled(enabled: bool) -> void:
	if is_instance_valid(_weapons):
		_weapons.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


func _die() -> void:
	_is_dead = true
	velocity = Vector2.ZERO
	died.emit()


func _play_audio(sound_name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(sound_name)
