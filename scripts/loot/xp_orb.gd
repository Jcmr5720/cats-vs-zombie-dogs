extends Area2D
## Orbe de experiencia que suelta un enemigo al morir.
##
## Game feel:
## - Pulso y rotación para que destaque.
## - Rebote inicial (pop_velocity) al soltarse, con fricción.
## - Magnetismo: cuando el jugador entra en el rango de ATRACCIÓN, el orbe vuela
##   hacia él acelerando; al entrar en el rango de RECOLECCIÓN se recoge.
## El rango de atracción se deriva del radio de recolección del propio jugador,
## así el upgrade "pickup_range" también agranda el imán.

@export var xp_value: int = 3
## Impulso inicial al soltarse (lo fija el enemigo al morir).
@export var pop_velocity: Vector2 = Vector2.ZERO
## El imán se activa a este múltiplo del radio de recolección del jugador.
@export var attract_multiplier: float = 2.8
## Distancia a la que se recoge directamente (rango de recolección base).
@export var collect_radius: float = 24.0
@export var attract_accel: float = 1150.0
@export var max_attract_speed: float = 780.0
@export var pop_friction: float = 6.0
## Tope de orbes vivos (Fase 08.75). Al superarlo, el orbe nuevo se FUSIONA con el
## mas cercano (suma su XP) en vez de acumular nodos y tirar el rendimiento.
@export var max_xp_orbs: int = 120

var _time: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _player: Node2D
var _collected: bool = false
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	add_to_group("xp_orbs")
	_velocity = pop_velocity
	_player = get_tree().get_first_node_in_group("player")
	# Control de saturacion: si ya hay demasiados orbes, funde este con el mas
	# cercano para no perder XP y no crear nodos sin limite.
	if get_tree().get_node_count_in_group("xp_orbs") > max_xp_orbs:
		if _merge_into_nearest():
			return


## Busca el orbe vivo mas cercano y le transfiere esta XP; luego se autolibera.
## Devuelve true si logro fusionarse (y por tanto este orbe debe desaparecer).
func _merge_into_nearest() -> bool:
	var nearest: Node2D = null
	var best_sq: float = INF
	for orb in get_tree().get_nodes_in_group("xp_orbs"):
		if orb == self or not is_instance_valid(orb) or orb.get("_collected"):
			continue
		var d: float = global_position.distance_squared_to((orb as Node2D).global_position)
		if d < best_sq:
			best_sq = d
			nearest = orb
	if nearest == null:
		return false
	nearest.set("xp_value", int(nearest.get("xp_value")) + xp_value)
	queue_free()
	return true


func _process(delta: float) -> void:
	# Tras recogerse, el tween de recolección controla el visual: no lo pisamos.
	if _collected:
		return

	_time += delta

	if is_instance_valid(_visual):
		_visual.rotation += delta * 1.6
		var pulse: float = 1.0 + sin(_time * 4.5) * 0.12
		_visual.scale = Vector2(pulse, pulse)

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")

	if is_instance_valid(_player):
		var to_player: Vector2 = _player.global_position - global_position
		var distance: float = to_player.length()
		var attract_radius: float = _player_pickup_radius() * attract_multiplier

		if distance <= collect_radius:
			collect(_player)
			return

		if distance < attract_radius:
			# Imán: acelera hacia el jugador, cada vez más rápido al acercarse.
			var pull: float = attract_accel * (1.0 + (1.0 - distance / attract_radius) * 2.0)
			_velocity = _velocity.move_toward(to_player.normalized() * max_attract_speed, pull * delta)
		else:
			# Fuera del imán: solo el rebote inicial con fricción.
			_velocity *= exp(-pop_friction * delta)

		# Brillo progresivo mientras vuela hacia el jugador: se "enciende" al acercarse.
		if is_instance_valid(_visual):
			var speed_ratio: float = clampf(_velocity.length() / max_attract_speed, 0.0, 1.0)
			_visual.modulate = Color(1, 1, 1).lerp(Color(1.7, 1.9, 2.1), speed_ratio)
	else:
		_velocity *= exp(-pop_friction * delta)

	global_position += _velocity * delta


## Empuje externo hacia una posicion (pasiva "Mantenimiento de campo" del Gato
## Ingeniero): acerca el orbe al jugador para que el iman normal lo capture.
## No lo recoge directamente: la recoleccion sigue siendo del jugador.
func nudge_toward(target: Vector2, speed: float) -> void:
	if _collected:
		return
	var direction: Vector2 = global_position.direction_to(target)
	if direction != Vector2.ZERO:
		_velocity = direction * speed


func _player_pickup_radius() -> float:
	if is_instance_valid(_player) and _player.has_method("get_pickup_radius"):
		return _player.get_pickup_radius()
	return 90.0


## Llamado por el imán o por el área de recolección del jugador.
func collect(player: Node) -> void:
	if _collected:
		return
	_collected = true
	if player.has_method("add_experience"):
		player.add_experience(xp_value)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"xp_collect")

	# Mini animación de recolección: se encoge y brilla antes de liberarse.
	set_deferred("monitorable", false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "scale", Vector2(2.0, 2.0), 0.12)
	tween.tween_property(_visual, "modulate:a", 0.0, 0.12)
	tween.chain().tween_callback(queue_free)
