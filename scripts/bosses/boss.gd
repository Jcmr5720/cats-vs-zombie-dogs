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
const HAZARD_ZONE_SCRIPT := preload("res://scripts/enemies/hazard_zone.gd")
const MAP_INTERACTABLE := preload("res://scripts/maps/map_interactable.gd")
const HUNT_CORRIDOR := preload("res://scripts/bosses/hunt_corridor.gd")

signal health_changed(current: int, maximum: int, display_name: String)
signal died(data: BossData)
## Transformacion a la forma ELITE: el HUD abre una SEGUNDA barra (no es curacion).
signal elite_transformed(display_name: String, maximum: int)

enum State { CHASE, WINDUP, CHARGE, RECOVER, SUMMON }

## Tope de vida para que el escalado por dificultad no cree jefes imposibles.
const MAX_HEALTH_CAP: int = 9000
## Tope de enemigos invocados vivos a la vez (evita acumulacion de nodos).
const MAX_SUMMONED: int = 14
## Transformacion elite (Partidas rapidas), en DOS pasos desacoplados:
## 1) FORMA elite (visual + patrones intensos): se activa a 4:15 (via director) O
##    al bajar del 35% de vida, lo primero, y nunca antes del tiempo minimo de
##    combate. NO toca la vida (no es una curacion): solo cambia forma y patrones.
## 2) SEGUNDA barra: al DERROTAR la forma normal (su barra llega a 0), en vez de
##    morir aparece una barra nueva ~28% de la vida ORIGINAL (fase 2 clara). El
##    total a derribar es ~128% de la vida original: mas dura, sin regalar daño.
const ELITE_MIN_COMBAT_TIME: float = 12.0
const ELITE_HP_TRIGGER: float = 0.35
const ELITE_BAR_FRACTION: float = 0.28

@export var windup_time: float = 0.9
@export var charge_time: float = 0.55
@export var charge_speed: float = 720.0
@export var recover_time: float = 0.7
@export var contact_range: float = 64.0
@export var summon_count: int = 4
## Multiplicador de vida del jefe en coop local (Fase Coop 1.5). 1.0 en solo.
## (Obsoleto, Fase correccion: la vida coop de jefes vive en GameBalance.BOSS_COOP_HEALTH_MULT.)
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

# --- Partidas rapidas: elite, furia final y esbirros del jefe -------------------
## FORMA elite activa (visual + patrones intensos). No se crea otro enemigo.
var _elite: bool = false
## Activacion de forma pedida pero pendiente (espera a que acabe el ataque activo).
var _elite_pending: bool = false
var _elite_requested: bool = false
## Ya en la SEGUNDA barra (fase 2, tras derrotar la forma normal).
var _second_bar: bool = false
## Vida ORIGINAL de la forma normal (base de la barra elite ~28%).
var _original_max: int = 0
## Segundos de combate desde que aparecio (para el tiempo minimo de transform).
var _alive_time: float = 0.0
## Furia final (5:00): mas velocidad/cadencia con tope; sigue siendo evitable.
var _enraged: bool = false
var _move_speed_mult: float = 1.0
## La version elite encadena UNA segunda embestida por patron (no infinitas).
var _second_charge_done: bool = false
## Guardianes vivos protegen al jefe; al caer uno se abre una ventana de
## vulnerabilidad temporal.
var _guardians: Array[Node2D] = []
var _guardian_vuln_timer: float = 0.0
## Total curado por sanadores (limitado: nunca grandes porcentajes repetidos).
var _minion_heal_total: int = 0
## FASE 11: modificador de guion de esta partida (RunScript.boss_modifier).
var _run_modifier: StringName = &""
## Reglas ambientales activas (BossData.environment_rules).
## territory_marks: marcas plantadas por el jefe (tope 2 vivas).
var _planted_marks: Array[Node2D] = []
## scrap_plates: placas de blindaje que caen con las fases.
var _boss_plates: int = 0
## consume_zones: cadencia de la curacion por consumo de zonas.
var _consume_tick: float = 0.0
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
## con difficulty_score pero queda acotada DOS veces (GameBalance): el factor por
## score tiene techo y el total en px de vida tambien (MAX_HEALTH_CAP).
func configure(boss_data: BossData, difficulty_score: float) -> void:
	data = boss_data
	var factor: float = minf(GameBalance.BOSS_HEALTH_SCORE_FACTOR_CAP,
		1.0 + max(0.0, difficulty_score) * data.difficulty_multiplier)
	var scaled: float = data.max_health * factor
	# Coop local: mas vida para que el jefe aguante el fuego de 2 jugadores
	# (UNA sola vez, centralizado en GameBalance).
	if _is_coop():
		scaled *= GameBalance.BOSS_COOP_HEALTH_MULT
	max_health = clampi(int(round(scaled)), data.max_health, MAX_HEALTH_CAP)
	current_health = max_health
	_original_max = max_health
	phase = 1
	_attack_timer = data.attack_cooldown
	# FASE 11: reglas ambientales del mapa (BossData.environment_rules).
	if data.environment_rules.has(&"scrap_plates"):
		_boss_plates = 2
	if data.environment_rules.has(&"territory_marks"):
		# Marca territorio al ENTRAR (la ve nacer el jugador: objetivo claro).
		call_deferred("_plant_territory_mark")
	if is_node_ready():
		_apply_visuals()
		_emit_health()


## FASE 11: modificador del guion de la semilla (lo aplica BossSpawner tras
## configure). Ids no reconocidos no hacen nada.
func apply_run_modifier(id: StringName) -> void:
	if _is_dead or id == &"":
		return
	_run_modifier = id
	match id:
		&"veloz_alfa":
			# Mas presion de movimiento (la cadencia de ataque conserva su suelo).
			_move_speed_mult *= 1.12
		&"invocador":
			# +1 (no mas): cada invocado da XP y abarataria el examen final.
			summon_count += 1
		&"marcador":
			# Marca un territorio EXTRA de inmediato (Barrio).
			call_deferred("_plant_territory_mark")
		&"pantanoso":
			# Sus embestidas dejan zona peligrosa SIEMPRE (no solo en elite).
			if data != null:
				data = data.duplicate()
				data.elite_leaves_hazard = true
		&"acorazado":
			# Empieza acorazado: 15% menos de daño hasta el primer cambio de fase.
			_boss_plates = maxi(_boss_plates, 1)


## Escalado del Rottweiler Alfa por umbral de vida (FASE 2). Cada fase añade una
## HERRAMIENTA, no una estadistica: orden de carga, ruptura de barricada, nueva
## zona de caceria. `phase` ya viene incrementada por _on_phase_changed.
func _alpha_phase_escalation() -> void:
	match phase:
		2:
			# 75 %: ordena una carga coordinada a la manada de una interseccion.
			_alpha_order_charge()
		3:
			# 50 %: rompe barricadas cercanas (cambia la geometria tactica del
			# combate: las rutas que el jugador estaba usando dejan de servir) e
			# invoca una combinacion corta de corredores y flanqueadores.
			_alpha_break_barricades()
			_alpha_call_mixed_group()
		4:
			# 25 %: nueva zona de caceria — otra marca, mas coordinacion.
			_plant_territory_mark()
			_alpha_order_charge()


## El Alfa ordena carga coordinada a los perros de manada cercanos. Respeta el
## tope global de cargas simultaneas y su telegrafo: no es daño sin aviso.
func _alpha_order_charge() -> void:
	var given: int = 0
	for dog in get_tree().get_nodes_in_group("pack_dogs"):
		if not is_instance_valid(dog) or not (dog is Node2D):
			continue
		if global_position.distance_to((dog as Node2D).global_position) > 700.0:
			continue
		if dog.has_method("receive_order"):
			dog.receive_order(&"charge", global_position, 4.0)
			given += 1
			if given >= 6:
				break
	if given > 0:
		RunTelemetry.count(&"alpha_charge_orders")
		Feedback.hit_effect(global_position, Color(1.0, 0.6, 0.2, 0.85), 0.8, 3.4)


## 50 %: el Alfa ATRAVIESA las barricadas cercanas. Reusa los datos de obstaculo
## destructible ya existentes: rompe lo que sea destruible en su radio.
func _alpha_break_barricades() -> void:
	var broken: int = 0
	for obstacle in get_tree().get_nodes_in_group("obstacles"):
		if not is_instance_valid(obstacle) or not (obstacle is Node2D):
			continue
		if global_position.distance_to((obstacle as Node2D).global_position) > 420.0:
			continue
		# `destructible` vive en el recurso ObstacleData, no en el nodo: pedirlo
		# directamente al nodo devolvia null (y bool(null) revienta en runtime).
		var obstacle_data: ObstacleData = obstacle.get("data") as ObstacleData
		if obstacle_data == null or not obstacle_data.destructible:
			continue
		# Misma via de destruccion que la embestida N3 del corredor: pasa por
		# _break() y conserva flash, barril explosivo, orbe de XP y salida del
		# grupo. queue_free() directo se saltaria todo eso.
		if obstacle.has_method("absorb_projectile"):
			obstacle.absorb_projectile(9999)
		else:
			obstacle.queue_free()
		broken += 1
		if broken >= 6:
			break
	if broken > 0:
		RunTelemetry.count(&"alpha_barricades_broken", broken)
		Feedback.shake(0.35)


## 50 %: combinacion LIMITADA de corredores y flanqueadores, entrando por calles.
func _alpha_call_mixed_group() -> void:
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if not is_instance_valid(spawner):
		return
	if spawner.has_method("spawn_pack_urban"):
		# Combinacion CORTA (2+1). El valor de esta llamada es que los dos roles
		# entren por calles distintas, no el numero de perros: subir la cantidad
		# aqui es exactamente la dificultad barata que el diseño rechaza, y en
		# los soaks de balance empujaba la partida fuera de la ventana de
		# victoria de una build normal.
		spawner.spawn_pack_urban(&"runner_zombie_dog", 2, 2)
		spawner.spawn_pack_urban(&"flanker_zombie_dog", 1, 1)
		RunTelemetry.count(&"alpha_mixed_calls")


## Semilla y bioma del mapa activo (para consultar la geometria de emplazamiento).
func _map_seed() -> int:
	var manager: Node = get_tree().get_first_node_in_group("map_manager")
	if is_instance_valid(manager) and manager.has_method("get_world_seed"):
		return manager.get_world_seed()
	return 0


func _map_biome() -> StringName:
	var manager: Node = get_tree().get_first_node_in_group("map_manager")
	if is_instance_valid(manager) and manager.has_method("get_active_map"):
		var map = manager.get_active_map()
		if map != null:
			return map.biome
	return &"neighborhood"


## Planta una marca de aullido cerca del jefe (tope 2 vivas por jefe).
func _plant_territory_mark() -> void:
	if _is_dead or not is_inside_tree():
		return
	for index in range(_planted_marks.size() - 1, -1, -1):
		if not is_instance_valid(_planted_marks[index]):
			_planted_marks.remove_at(index)
	if _planted_marks.size() >= 2:
		return
	# El Alfa reclama TERRENO, no un punto al azar: la marca va a una posicion
	# tactica del plano (interseccion de calles) y nunca dentro de un edificio.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("boss_mark:%d:%d" % [_map_seed(), _planted_marks.size()])
	var placement := MapGeometry.find_tactical_position(
		_map_seed(), _map_biome(), global_position, 160.0, 420.0, rng, self)
	if not placement["found"]:
		return
	var mark := MAP_INTERACTABLE.spawn(&"howl_post", get_parent(), placement["pos"], rng)
	var pos: Vector2 = placement["pos"]
	if mark != null:
		_planted_marks.append(mark)
		Feedback.hit_effect(pos, Color(1.0, 0.72, 0.2, 0.8), 0.6, 2.4)


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
	_alive_time += delta
	_update_phase()
	_animate(delta)
	if _contact_timer > 0.0:
		_contact_timer -= delta
	if _guardian_vuln_timer > 0.0:
		_guardian_vuln_timer -= delta

	# FASE 11 (consume_zones, Mastin del Pantano): parado sobre una zona
	# infecciosa se cura CONSUMIENDOLA. El jugador puede negarle la curacion
	# controlando DONDE mata a los portadores.
	if data != null and data.environment_rules.has(&"consume_zones"):
		_consume_tick -= delta
		if _consume_tick <= 0.0:
			_consume_tick = 0.5
			_try_consume_zone()

	# Activacion de la FORMA elite pendiente: cuando el jefe esta en un estado
	# SEGURO (persiguiendo, sin telegrafo ni ataque en curso).
	if _elite_pending and _can_transform_now():
		_activate_elite_form()

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
	velocity = dir * data.move_speed * _move_speed_mult + _avoid
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


## chained=true: segunda embestida ELITE encadenada (telegrafo mas corto pero
## visible; no resetea el contador de encadenado).
func _enter_windup(chained: bool = false) -> void:
	_state = State.WINDUP
	_state_timer = windup_time * (0.55 if chained else 1.0)
	if not chained:
		_second_charge_done = false
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
		# Identidad del Parque (elite): la embestida deja una zona peligrosa.
		if _elite and data.elite_leaves_hazard:
			_leave_hazard_zone()
		# Habilidad extra de la version ELITE: encadena UNA segunda embestida
		# (telegrafiada) por patron. Si choco, respeta la recuperacion normal.
		if _elite and not _second_charge_done and not collided:
			_second_charge_done = true
			_enter_windup(true)
			_telegraph.visible = true
		else:
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
	# Esbirros del jefe: aparecen en MOMENTOS DEFINIDOS (los umbrales de vida de
	# phase_thresholds, p.ej. 75/50/25%), nunca de forma continua.
	_spawn_threshold_minions()
	# FASE 11: reglas ambientales por cambio de fase.
	if data != null and data.environment_rules.has(&"territory_marks"):
		_plant_territory_mark()
		# FASE 2 (Barrio): el Alfa ESCALA EN COORDINACION, no en estadisticas.
		# Cada umbral de vida usa una herramienta urbana distinta.
		_alpha_phase_escalation()
	if _boss_plates > 0:
		# Cae una placa: chispa metalica clara (ventana de daño real).
		_boss_plates -= 1
		Feedback.hit_effect(global_position, Color(0.75, 0.78, 0.85, 0.9), 0.6, 2.8)
	# Feedback de cambio de fase: destello y shake.
	Feedback.shake(0.3)
	Feedback.hit_effect(global_position, data.accent_color, 0.8, 3.5)
	# FASE VISUAL 2: la fase se LEE. Micro hit-stop, el aura vira hacia rojo
	# agresivo, los ojos estallan en blanco y la luz sube de energia.
	Feedback.hitstop(0.06, 0.15)
	_visual_action(&"phase_change")
	# En forma elite se conserva la identidad magenta (no revertir a rojo).
	if _elite:
		return
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
## Elite y furia final lo acortan mas, con SUELO duro: nunca ataques encadenados
## inevitables.
func _next_attack_cooldown() -> float:
	var factor: float = 1.0
	if phase == 2:
		factor = 0.7
	elif phase >= 3:
		factor = 0.5
	if _elite:
		factor *= 0.85
	if _enraged:
		factor *= 0.8
	return max(0.9, data.attack_cooldown * factor)


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
	# Guardian vivo: reduce el daño que recibe el jefe. Al caer el guardian se
	# abre una ventana de vulnerabilidad (notify_guardian_down).
	if _guardian_alive():
		amount = maxi(1, int(round(amount * 0.6)))
	elif _guardian_vuln_timer > 0.0:
		amount = int(round(amount * 1.3))
	# FASE 11: placas de blindaje (scrap_plates/acorazado): daño reducido hasta
	# que las fases las rompan.
	if _boss_plates > 0:
		amount = maxi(1, int(round(amount * 0.85)))

	# Telemetria de balance (solo con BOSS_DEBUG=1 en el entorno): histograma del
	# daño recibido, para atribuir fuentes de DPS en los soaks headless.
	if OS.has_environment("BOSS_DEBUG"):
		var histo: Dictionary = get_meta(&"dmg_histo", {})
		histo[amount] = int(histo.get(amount, 0)) + 1
		set_meta(&"dmg_histo", histo)
		var total: int = int(get_meta(&"dmg_total", 0)) + amount
		set_meta(&"dmg_total", total)
		if int(get_meta(&"dmg_log_tick", 0)) != int(_alive_time / 10.0):
			set_meta(&"dmg_log_tick", int(_alive_time / 10.0))
			print("BOSSDBG t=%.0f hp=%d/%d total_dmg=%d histo=%s" % [_alive_time, current_health, max_health, total, str(histo)])
	current_health = max(0, current_health - amount)
	Feedback.damage_number(global_position + Vector2(0, -50), amount, Color(1.0, 0.8, 0.5))
	_flash_hit()
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"boss_hit")

	# Disparo por vida: la FORMA elite (visual/patrones) se activa al bajar del 35%
	# (cumplido el tiempo minimo de combate), lo que ocurra antes que 4:15. No cura.
	if not _elite and not _elite_requested and not _second_bar and _original_max > 0 \
			and float(current_health) / float(_original_max) <= ELITE_HP_TRIGGER:
		request_elite_transform()

	# Derrota de la forma normal: en vez de morir, aparece la SEGUNDA barra (~28%).
	# Solo se muere al vaciar esa segunda barra.
	if current_health <= 0 and not _second_bar:
		_enter_second_bar()
		return

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
	# Elite: la invocacion se refuerza (esbirros modificados), siempre bajo el
	# mismo tope MAX_SUMMONED.
	var wanted: int = summon_count + (2 if _elite else 0)
	var count: int = min(wanted, allowed)
	for i in count:
		var minion := ENEMY_SCENE.instantiate() as Node2D
		if minion == null:
			continue
		var angle: float = TAU * float(i) / float(max(1, count)) + randf() * 0.4
		minion.global_position = global_position + Vector2.RIGHT.rotated(angle) * 70.0
		# FASE 11 (balance): los invocados del jefe dan XP simbolica. La invocacion
		# continua financiaba cartas al jugador DURANTE el examen final (bucle de
		# XP que abarataba al jefe).
		minion.set("xp_value", 1)
		get_parent().add_child(minion)
		_summoned.append(minion)


func _prune_summoned() -> void:
	for index in range(_summoned.size() - 1, -1, -1):
		if not is_instance_valid(_summoned[index]):
			_summoned.remove_at(index)
	for index in range(_guardians.size() - 1, -1, -1):
		if not is_instance_valid(_guardians[index]):
			_guardians.remove_at(index)


## Esbirros de clase (Guardian/Sanador/Explosivo) en los umbrales de vida.
## Maximo DOS clases por jefe (se ignoran las demas); cantidades pequeñas y
## bajo el tope global MAX_SUMMONED.
func _spawn_threshold_minions() -> void:
	if data == null or data.minion_classes.is_empty():
		return
	_prune_summoned()
	var classes: Array[StringName] = []
	for c in data.minion_classes:
		classes.append(c)
		if classes.size() >= 2:
			break
	for minion_id in classes:
		var mdata = RunPhaseConfig.load_enemy_data(minion_id)
		if mdata == null:
			continue
		var count: int = 2 if minion_id == &"boss_exploder" else 1
		if _elite:
			count += 1  # esbirros modificados en la version elite
		for i in count:
			if _summoned.size() >= MAX_SUMMONED:
				return
			var minion := ENEMY_SCENE.instantiate() as Node2D
			if minion == null:
				continue
			if minion.has_method("configure"):
				minion.call("configure", mdata, 1.0, 1.0, 1.0)
			var angle: float = randf() * TAU
			minion.global_position = global_position + Vector2.RIGHT.rotated(angle) * 90.0
			get_parent().add_child(minion)
			if minion.has_method("bind_boss"):
				minion.bind_boss(self)
			_summoned.append(minion)
			if mdata.behavior == &"boss_guardian":
				_guardians.append(minion)


func _guardian_alive() -> bool:
	for g in _guardians:
		if is_instance_valid(g) and g.is_inside_tree():
			return true
	return false


## La llama el guardian al morir: ventana temporal de vulnerabilidad del jefe.
func notify_guardian_down() -> void:
	_guardian_vuln_timer = 4.0
	Feedback.hit_effect(global_position, Color(0.5, 0.8, 1.0, 0.8), 0.6, 2.6)


## Curacion LIMITADA de los sanadores: el total curado por esbirros nunca supera
## el 25% de la vida maxima (sin bucles de curacion infinitos).
func receive_minion_heal(amount: int) -> void:
	if _is_dead or amount <= 0:
		return
	var cap: int = int(round(max_health * 0.25))
	var allowed: int = mini(amount, cap - _minion_heal_total)
	if allowed <= 0:
		return
	_minion_heal_total += allowed
	current_health = mini(max_health, current_health + allowed)
	_emit_health()


## Pide activar la FORMA elite (la llama el PhaseDirector a 4:15 o el propio jefe
## al bajar del 35%). No cambia la vida: queda PENDIENTE y se activa en cuanto el
## jefe esta en un estado seguro (persiguiendo, sin ataque en curso). Idempotente.
func request_elite_transform() -> void:
	if _is_dead or _elite or _elite_requested:
		return
	_elite_requested = true
	_elite_pending = true


## Alias historico (algunos llamadores/tests usan este nombre).
func transform_elite() -> void:
	request_elite_transform()


## Seguro para activar la forma? Cumplido el tiempo minimo de combate, persiguiendo
## y sin telegrafo/ataque en curso. Asi espera a que acabe la embestida.
func _can_transform_now() -> bool:
	if _alive_time < ELITE_MIN_COMBAT_TIME:
		return false
	if _state != State.CHASE:
		return false
	return not (is_instance_valid(_telegraph) and _telegraph.visible)


## Activa la FORMA elite: identidad visual propia + patrones mas intensos. NO
## toca la vida (no es una curacion). Idempotente. `abrupt` la usa la entrada a
## la segunda barra para activarla al vuelo sin esperar estado seguro.
func _activate_elite_form(abrupt: bool = false) -> void:
	if _is_dead or _elite:
		return
	_elite = true
	_elite_pending = false
	if not abrupt:
		# Limpieza suave: cancela cualquier telegrafo pendiente al entrar en forma.
		if is_instance_valid(_telegraph):
			_telegraph.visible = false
	Feedback.hitstop(0.1, 0.12)
	Feedback.shake(0.5)
	var elite_color := Color(1.0, 0.25, 0.55)
	Feedback.hit_effect(global_position, elite_color, 0.9, 4.6)
	Feedback.hit_effect(global_position, elite_color.lightened(0.3), 0.45, 2.4)
	# Patrones mas intensos pero legibles + identidad visual propia (una sola vez).
	charge_speed *= 1.12
	scale *= 1.15
	if is_instance_valid(_aura):
		_aura.color = Color(elite_color.r, elite_color.g, elite_color.b, 0.2)
	if is_instance_valid(_light):
		_light.color = elite_color
		_light.set_base_energy(1.6)
	for eye in [_eye_left, _eye_right]:
		if is_instance_valid(eye):
			eye.color = Color(1.0, 0.95, 0.9)
	_visual_action(&"phase_change")
	# FASE 2 (Barrio): la forma elite del Alfa abre un CORREDOR DE CACERIA sobre
	# una calle real. Solo los jefes con reglas de territorio: el Mastin y el de
	# Chatarra tienen las suyas.
	if data != null and data.environment_rules.has(&"territory_marks"):
		_open_hunt_corridor()


## Corredor de caceria elite: se ancla a la calle real mas cercana al jefe y se
## extiende a lo largo de ella. Estrecho (cabe en la calzada) y finito: siempre
## se puede salir por los lados y siempre expira.
func _open_hunt_corridor() -> void:
	var world_seed: int = _map_seed()
	var biome: StringName = _map_biome()
	var roads := MapGeometry.roads_near(world_seed, biome, global_position, 700.0)
	if roads.is_empty():
		return
	# La calle mas cercana al jefe: la caceria ocurre donde ya se esta peleando.
	var best: Dictionary = {}
	var best_distance: float = INF
	for road in roads:
		var along: float = global_position.x if road["axis"] == &"vertical" else global_position.y
		var distance: float = absf(float(road["coord"]) - along)
		if distance < best_distance:
			best_distance = distance
			best = road
	if best.is_empty():
		return
	var vertical: bool = best["axis"] == &"vertical"
	var coord: float = float(best["coord"])
	# Centrado en la proyeccion del jefe sobre la calle, 1800 px de largo: un
	# tramo de avenida, no el mapa.
	var center: Vector2 = Vector2(coord, global_position.y) if vertical \
		else Vector2(global_position.x, coord)
	var axis: Vector2 = Vector2.DOWN if vertical else Vector2.RIGHT
	# La direccion de caza apunta hacia el jugador: el corredor le empuja.
	if is_instance_valid(_player) and (_player.global_position - center).dot(axis) < 0.0:
		axis = -axis
	var post: Node2D = _planted_marks[0] if not _planted_marks.is_empty() \
		and is_instance_valid(_planted_marks[0]) else null
	HUNT_CORRIDOR.spawn(get_parent(), center - axis * 900.0, center + axis * 900.0,
		float(best["half_width"]), post)


## Derrotada la forma normal (barra a 0): aparece la SEGUNDA barra ~28% de la
## ORIGINAL como fase 2 clara. Fuerza la forma elite si aun no estaba activa,
## limpia telegrafos/estados y reinicia fases y curacion de esbirros.
func _enter_second_bar() -> void:
	if _is_dead or _second_bar:
		return
	_second_bar = true
	if not _elite:
		_activate_elite_form(true)  # al vuelo: reemplaza a la muerte, sin esperar

	# Limpieza segura: cancela ataque/telegrafo y vuelve a persecucion.
	_state = State.CHASE
	_state_timer = 0.0
	_charge_hit_done = false
	_second_charge_done = false
	velocity = Vector2.ZERO
	if is_instance_valid(_telegraph):
		_telegraph.visible = false
	_attack_timer = _next_attack_cooldown()

	# SEGUNDA barra (fase nueva, NO curacion): 28% de la vida original, llena.
	max_health = maxi(1, int(round(_original_max * ELITE_BAR_FRACTION)))
	current_health = max_health
	phase = 1
	_minion_heal_total = 0

	Feedback.hitstop(0.14, 0.08)
	Feedback.shake(0.6)
	var elite_color := Color(1.0, 0.25, 0.55)
	Feedback.hit_effect(global_position, elite_color, 1.0, 5.2)
	Feedback.hit_effect(global_position, elite_color.lightened(0.3), 0.5, 2.6)

	# El HUD abre una barra NUEVA con el nombre elite (fase 2 clara).
	elite_transformed.emit(_elite_display_name(), max_health)
	_emit_health()


## Nombre mostrado en la barra elite (BossData.elite_name o "<nombre> ELITE").
func _elite_display_name() -> String:
	if data == null:
		return "Jefe elite"
	return data.elite_name if data.elite_name != "" else "%s ELITE" % data.display_name


func is_elite() -> bool:
	return _elite


func is_elite_pending() -> bool:
	return _elite_pending


func is_second_bar() -> bool:
	return _second_bar


## Furia final (5:00): acelera al jefe con TOPE (presion final, no injusticia).
func enrage() -> void:
	if _is_dead or _enraged:
		return
	_enraged = true
	_move_speed_mult = 1.1
	Feedback.shake(0.4)
	Feedback.hit_effect(global_position, Color(1.0, 0.4, 0.1, 0.9), 0.8, 4.0)


## Zona peligrosa al final de la embestida elite (identidad del Parque).
## try_spawn aplica presupuesto por tipo y fusion (FASE 11).
func _leave_hazard_zone() -> void:
	HAZARD_ZONE_SCRIPT.try_spawn(get_parent(), global_position,
		{"kind": &"infection", "radius": 85.0, "duration": 3.5})


## Curacion por consumo de zona infecciosa (regla consume_zones). Limitada por
## el mismo tope de curacion de esbirros: sin bucles infinitos.
func _try_consume_zone() -> void:
	if current_health >= max_health:
		return
	for z in get_tree().get_nodes_in_group(HAZARD_ZONE_SCRIPT.GROUP):
		if not is_instance_valid(z) or not (z is Node2D):
			continue
		if z.get("kind") != &"infection":
			continue
		var zone_radius: float = float(z.get("radius"))
		if global_position.distance_to((z as Node2D).global_position) > zone_radius + 30.0:
			continue
		if z.has_method("consume"):
			z.consume(0.6)
		receive_minion_heal(int(round(max_health * 0.01)))
		RunTelemetry.count(&"boss_heal_from_zones", int(round(max_health * 0.01)))
		RunTelemetry.count(&"boss_zones_consumed")
		Feedback.hit_effect(global_position, Color(0.55, 0.9, 0.3, 0.6), 0.35, 1.6)
		return


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
	Feedback.death_burst(global_position, data.visual_color, 10)
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

	# FASE 12: el jefe suelta una MUTACION y un NUCLEO DE EVOLUCION. Entre el
	# mini-jefe y el jefe salen como mucho 2 nucleos, que es justo el tope de
	# evoluciones por partida (WeaponManager.MAX_EVOLUTIONS_PER_RUN).
	var director: Node = get_tree().get_first_node_in_group("loot_director")
	if is_instance_valid(director):
		director.call("drop_mutation", get_parent(), global_position)
		director.call("drop_evolution_core", get_parent(), global_position)


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
