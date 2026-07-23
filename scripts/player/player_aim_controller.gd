class_name PlayerAimController
extends Node2D
## Punteria de UN jugador (Rework de apuntado). El AUTODISPARO NO CAMBIA: el
## jugador nunca pulsa un boton para disparar. Lo unico que decide este nodo es la
## DIRECCION del disparo.
##
## Responsabilidades (todas por jugador, nada global):
##   - detectar que dispositivo esta usando SU jugador (raton / mando / teclado),
##   - leer la direccion apuntada y conservar la ultima valida,
##   - administrar su modo (manual / asistido / automatico) desde Settings,
##   - resolver la correccion asistida (con histeresis) UNA vez por frame,
##   - exponer la direccion final a las armas,
##   - dibujar SU reticula en SU mitad de pantalla.
##
## Nada de "J1 = raton, J2 = stick": el dispositivo se detecta por uso y se puede
## fijar a mano en Opciones. Dos mandos, mando+teclado o teclado compartido
## funcionan por igual porque cada jugador lee SU device id y SUS acciones.

const Targeting = preload("res://scripts/weapons/targeting.gd")

# --- Modos --------------------------------------------------------------------
const MODE_MANUAL := &"manual"
const MODE_ASSIST := &"assist"
const MODE_AUTO := &"auto"

# --- Dispositivos --------------------------------------------------------------
const DEVICE_AUTO := &"auto"      # se detecta por uso (defecto)
const DEVICE_MOUSE := &"mouse"
const DEVICE_GAMEPAD := &"gamepad"
const DEVICE_KEYBOARD := &"keyboard"

## Niveles de asistencia -> medio angulo del cono, en grados. "off" desactiva la
## correccion aunque el modo sea asistido (equivale a manual puro).
const ASSIST_CONE_DEGREES: Dictionary = {
	"off": 0.0,
	"baja": 14.0,
	"media": 24.0,
	"alta": 38.0,
}
const DEFAULT_ASSIST_LEVEL: String = "baja"

## Distancia del punto de mira cuando la fuente es DIRECCIONAL (stick/teclado): no
## hay cursor, asi que la reticula vive a distancia fija delante del gato.
const DIRECTIONAL_AIM_DISTANCE: float = 220.0
## Zona muerta radial del stick. Por debajo se CONSERVA la ultima direccion: soltar
## el stick no debe reapuntar el arma ni generar temblor al volver al centro.
const STICK_DEADZONE: float = 0.22
## Umbral para considerar que el jugador "uso" el stick (reclamar dispositivo).
const STICK_CLAIM_THRESHOLD: float = 0.5
## Alcance maximo de la busqueda de objetivo asistido.
const ASSIST_RANGE: float = 520.0
## Refresco de la asistencia (s). No hace falta por frame: 20 Hz basta para la
## reticula y para el disparo, y evita repetir la consulta de enemigos.
const ASSIST_REFRESH: float = 0.05
## Histeresis: un objetivo ya elegido se conserva mientras siga dentro de este
## multiplicador del cono. Sin esto la mira salta entre dos enemigos cada frame.
const ASSIST_KEEP_FACTOR: float = 1.6

## Capa de visibilidad de la reticula por jugador (bit 2 = J1, bit 3 = J2). Las
## mitades del split apagan la capa del OTRO jugador en su canvas_cull_mask, asi
## que cada reticula se dibuja una sola vez y en la pantalla correcta.
static func reticle_visibility_layer(player_id: int) -> int:
	return 1 << clampi(player_id, 1, 2)


var _player: Node2D
var _player_id: int = 1
var _mode: StringName = MODE_MANUAL
var _mode_override: StringName = &""
var _assist_cone_degrees: float = ASSIST_CONE_DEGREES[DEFAULT_ASSIST_LEVEL]

## Dispositivo configurado ("auto" = detectar) y el REALMENTE resuelto.
var _device_setting: StringName = DEVICE_AUTO
var _device: StringName = DEVICE_KEYBOARD
## Mando asignado a este jugador (-1 = ninguno todavia).
var _pad_device: int = -1

var _aim_direction: Vector2 = Vector2.RIGHT
var _aim_point: Vector2 = Vector2.ZERO
## Objetivo asistido vigente {enemy, pos, velocity} o vacio.
var _assist_target: Dictionary = {}
var _assist_timer: float = 0.0
## true cuando la asistencia esta corrigiendo AHORA (la reticula lo refleja).
var _assist_locked: bool = false

var _settings: Node
var _split: Node
## Ayuda contextual de arranque: se muestra una vez por partida.
var _hint_shown: bool = false
var _hint_timer: float = 1.2


func _ready() -> void:
	# top_level: la reticula vive en coordenadas de MUNDO, no pegada al gato.
	top_level = true
	z_index = 40
	visibility_layer = reticle_visibility_layer(_resolve_player_id())
	add_to_group("player_aim")
	_player = get_parent() as Node2D
	_settings = get_node_or_null("/root/Settings")
	if _settings != null and _settings.has_signal("settings_changed"):
		_settings.settings_changed.connect(_refresh_from_settings)
	_refresh_from_settings()
	_assign_initial_pad()
	if is_instance_valid(_player) and _player.has_method("get_last_facing_direction"):
		_aim_direction = _player.get_last_facing_direction()
	_aim_point = _origin() + _aim_direction * DIRECTIONAL_AIM_DISTANCE


func _resolve_player_id() -> int:
	var parent := get_parent()
	if parent != null and parent.get("player_id") != null:
		_player_id = maxi(1, int(parent.get("player_id")))
	return _player_id


# --- Deteccion de dispositivo ---------------------------------------------------
# Se hace por EVENTO (no por frame) y solo cuando el ajuste es "auto". Un jugador
# reclama un dispositivo al usarlo, siempre que no lo tenga ya el otro jugador.

func _input(event: InputEvent) -> void:
	if _device_setting != DEVICE_AUTO or _mode == MODE_AUTO:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_claim_mouse()
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) >= STICK_CLAIM_THRESHOLD:
			_claim_pad(motion.device)
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_claim_pad((event as InputEventJoypadButton).device)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if _is_my_aim_key(event):
			_device = DEVICE_KEYBOARD


## Solo las teclas de MI apuntado cambian mi dispositivo a teclado: las de
## movimiento no, porque un jugador con raton tambien se mueve con el teclado.
func _is_my_aim_key(event: InputEvent) -> bool:
	for suffix in ["up", "down", "left", "right"]:
		var action := StringName("p%d_aim_%s" % [_player_id, suffix])
		if InputMap.has_action(action) and event.is_action(action):
			return true
	return false


func _claim_mouse() -> void:
	if _device == DEVICE_MOUSE:
		return
	# El raton es uno solo: no se lo quita a quien ya lo esta usando.
	for other in get_tree().get_nodes_in_group("player_aim"):
		if other != self and is_instance_valid(other) and other.get_device() == DEVICE_MOUSE:
			return
	_device = DEVICE_MOUSE
	_show_device_hint()


func _claim_pad(device: int) -> void:
	if _device == DEVICE_GAMEPAD and _pad_device == device:
		return
	for other in get_tree().get_nodes_in_group("player_aim"):
		if other != self and is_instance_valid(other) and other.get_pad_device() == device:
			return  # ese mando ya tiene dueño
	_pad_device = device
	_device = DEVICE_GAMEPAD
	_show_device_hint()


## Reparto inicial de mandos por orden de conexion, para que en "dos mandos" cada
## jugador tenga el suyo antes incluso de tocar el stick. Al reconectar, Godot
## conserva el device id, asi que la asignacion sigue siendo valida.
func _assign_initial_pad() -> void:
	var pads: Array = Input.get_connected_joypads()
	var index: int = clampi(_player_id - 1, 0, 99)
	if index < pads.size():
		var candidate: int = int(pads[index])
		var taken: bool = false
		for other in get_tree().get_nodes_in_group("player_aim"):
			if other != self and is_instance_valid(other) and other.get_pad_device() == candidate:
				taken = true
		if not taken:
			_pad_device = candidate
	# Sin mando y sin raton reclamado todavia: el J1 arranca en raton (es el caso
	# tipico de partida en solo) y el resto en teclado. Es solo el estado INICIAL:
	# en cuanto el jugador use otro dispositivo, la deteccion lo corrige.
	if _device_setting == DEVICE_AUTO:
		if _pad_device >= 0:
			_device = DEVICE_GAMEPAD
		elif _player_id <= 1:
			_device = DEVICE_MOUSE
		else:
			_device = DEVICE_KEYBOARD


# --- Ciclo ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	if _mode == MODE_AUTO:
		# En automatico este nodo no hace NADA: ni reticula ni consultas.
		if visible:
			visible = false
		return

	_update_direction()
	if _mode == MODE_ASSIST and _assist_cone_degrees > 0.0:
		_assist_timer -= delta
		if _assist_timer <= 0.0:
			_assist_timer = ASSIST_REFRESH
			_refresh_assist()
	elif not _assist_target.is_empty():
		_assist_target.clear()
		_assist_locked = false

	global_position = _aim_point
	var active: bool = not _player.has_method("is_active") or _player.is_active()
	visible = active
	if active:
		queue_redraw()

	if not _hint_shown:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_show_device_hint()


# --- API publica ----------------------------------------------------------------

## Direccion FINAL del disparo: la del jugador, ya corregida por la asistencia si
## el modo es asistido y hay objetivo. Unitaria y nunca Vector2.ZERO.
func get_aim_direction() -> Vector2:
	if _assist_locked and not _assist_target.is_empty():
		var to_target: Vector2 = (_assist_target["pos"] as Vector2) - _origin()
		if to_target.length_squared() > 1.0:
			return to_target.normalized()
	return _aim_direction


## Direccion CRUDA del jugador, sin asistencia (la que dibuja la reticula).
func get_raw_aim_direction() -> Vector2:
	return _aim_direction


func get_aim_world_position() -> Vector2:
	return _aim_point


func get_aim_mode() -> StringName:
	return _mode


func is_manual_aim() -> bool:
	return _mode == MODE_MANUAL


func is_assisted_aim() -> bool:
	return _mode == MODE_ASSIST


func is_auto_aim() -> bool:
	return _mode == MODE_AUTO


## Objetivo asistido vigente ({enemy, pos, velocity}) o vacio. Lo consultan las
## armas de proyectil para aplicar SU propio lead (cada arma tiene otra velocidad
## de bala, asi que el calculo no puede vivir aqui).
func get_assist_target() -> Dictionary:
	return _assist_target if _assist_locked else {}


func get_device() -> StringName:
	return _device


func get_pad_device() -> int:
	return _pad_device


## Fija el modo por codigo, por encima de Settings (tests y soaks de balance).
func set_mode(mode: StringName) -> void:
	if mode == MODE_AUTO or mode == MODE_ASSIST:
		_mode_override = mode
	else:
		_mode_override = MODE_MANUAL
	_mode = _mode_override
	if _mode == MODE_AUTO:
		visible = false


func clear_mode_override() -> void:
	_mode_override = &""
	_refresh_from_settings()


## Fuerza el dispositivo (tests; en juego lo hace el ajuste de Opciones).
func set_device(device: StringName, pad: int = -1) -> void:
	_device = device
	if pad >= 0:
		_pad_device = pad


# --- Ajustes -------------------------------------------------------------------

func _refresh_from_settings() -> void:
	_resolve_player_id()
	var pid: int = clampi(_player_id, 1, 2)
	if _mode_override != &"":
		_mode = _mode_override
	else:
		var raw: String = "manual"
		if _settings != null and _settings.has_method("get_value"):
			raw = str(_settings.get_value("player_%d_aim_mode" % pid, "manual"))
		match raw:
			"auto": _mode = MODE_AUTO
			"assist": _mode = MODE_ASSIST
			_: _mode = MODE_MANUAL

	var level: String = DEFAULT_ASSIST_LEVEL
	var device_raw: String = String(DEVICE_AUTO)
	if _settings != null and _settings.has_method("get_value"):
		level = str(_settings.get_value("player_%d_aim_assist" % pid, DEFAULT_ASSIST_LEVEL))
		device_raw = str(_settings.get_value("player_%d_aim_device" % pid, String(DEVICE_AUTO)))
	_assist_cone_degrees = float(ASSIST_CONE_DEGREES.get(level, ASSIST_CONE_DEGREES[DEFAULT_ASSIST_LEVEL]))
	_device_setting = StringName(device_raw)
	if _device_setting != DEVICE_AUTO:
		_device = _device_setting
		if _device == DEVICE_GAMEPAD and _pad_device < 0:
			_assign_initial_pad()


# --- Lectura de direccion --------------------------------------------------------

func _origin() -> Vector2:
	return _player.global_position if is_instance_valid(_player) else global_position


func _update_direction() -> void:
	var origin: Vector2 = _origin()
	match _device:
		DEVICE_MOUSE:
			_update_from_mouse(origin)
		DEVICE_GAMEPAD:
			_update_from_stick(origin)
		_:
			_update_from_keys(origin)


## Raton -> mundo. En split hay que pasar por la camara de SU mitad; si el cursor
## esta sobre la mitad del OTRO jugador se CONSERVA la ultima direccion (no se
## bloquea el cursor ni se recorta: solo se ignora esa posicion, que para esta
## camara significaria un punto equivocado).
func _update_from_mouse(origin: Vector2) -> void:
	var point: Vector2
	var split: Node = _coop_split()
	if split == null:
		point = get_global_mouse_position()
	else:
		var index: int = clampi(_player_id - 1, 0, 1)
		var screen: Vector2 = get_viewport().get_mouse_position()
		if not split.contains_point(index, screen):
			return  # cursor en la otra mitad: se mantiene la ultima direccion
		point = split.screen_to_world(index, screen)
	var to_point: Vector2 = point - origin
	if to_point.length_squared() < 1.0:
		return
	_aim_point = point
	_aim_direction = to_point.normalized()


## Stick derecho del MANDO ASIGNADO a este jugador (no una accion compartida: asi
## dos mandos apuntan de forma independiente). Zona muerta radial con reescalado:
## por debajo del umbral se conserva la ultima direccion, sin temblor al centrar.
func _update_from_stick(origin: Vector2) -> void:
	if _pad_device < 0:
		_update_from_keys(origin)
		return
	var stick := Vector2(
		Input.get_joy_axis(_pad_device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(_pad_device, JOY_AXIS_RIGHT_Y))
	_aim_direction = stick_direction(stick, _aim_direction, STICK_DEADZONE)
	_aim_point = origin + _aim_direction * DIRECTIONAL_AIM_DISTANCE


## Regla pura del stick (estatica para poder probarla sin mando): por debajo de la
## zona muerta se devuelve la ULTIMA direccion valida — nada de temblor al soltar
## el stick ni de reapuntar por el ruido del sensor. Por encima, direccion
## normalizada (la magnitud no aporta: la mira no tiene "intensidad").
static func stick_direction(raw: Vector2, last_direction: Vector2, deadzone: float) -> Vector2:
	var magnitude: float = raw.length()
	if magnitude < maxf(0.0, deadzone) or magnitude <= 0.0:
		return last_direction
	return raw / magnitude


## Teclado: cuatro acciones de apuntado PROPIAS del jugador, independientes del
## movimiento y remapeables. Sin pulsacion se conserva la ultima direccion.
func _update_from_keys(origin: Vector2) -> void:
	var pid: int = clampi(_player_id, 1, 2)
	var left := StringName("p%d_aim_left" % pid)
	if InputMap.has_action(left):
		var keys: Vector2 = Input.get_vector(
			left,
			StringName("p%d_aim_right" % pid),
			StringName("p%d_aim_up" % pid),
			StringName("p%d_aim_down" % pid))
		if keys.length_squared() > 0.01:
			_aim_direction = keys.normalized()
	_aim_point = origin + _aim_direction * DIRECTIONAL_AIM_DISTANCE


# --- Asistencia -----------------------------------------------------------------

## Elige el objetivo de la asistencia DENTRO del cono, reutilizando el scoring del
## auto-apuntado (amenaza / marca del Policia). Con histeresis: el objetivo vigente
## se conserva mientras siga vivo, en rango y dentro de un cono ampliado, para que
## la mira no salte entre dos enemigos pegados.
func _refresh_assist() -> void:
	var origin: Vector2 = _origin()

	# 1) ¿Sigue valiendo el objetivo anterior? (cono ampliado = histeresis)
	if not _assist_target.is_empty():
		var previous = _assist_target.get("enemy")
		if is_instance_valid(previous) and _is_enemy_alive(previous):
			var offset: Vector2 = (previous as Node2D).global_position - origin
			var keep_cos: float = cos(deg_to_rad(minf(90.0, _assist_cone_degrees * ASSIST_KEEP_FACTOR)))
			if offset.length() <= ASSIST_RANGE and offset.normalized().dot(_aim_direction) >= keep_cos:
				_assist_target["pos"] = (previous as Node2D).global_position
				_assist_target["velocity"] = (previous as CharacterBody2D).velocity if previous is CharacterBody2D else Vector2.ZERO
				_assist_locked = true
				return
		_assist_target.clear()
		_assist_locked = false

	# 2) Busqueda nueva: UNA pasada compartida (gather_candidates) + cono + scoring.
	var candidates: Array[Dictionary] = Targeting.gather_candidates(
		get_tree().get_nodes_in_group("enemies"), origin, origin, ASSIST_RANGE)
	candidates = Targeting.filter_cone(candidates, origin, _aim_direction, _assist_cone_degrees)
	var picked: Dictionary = Targeting.pick_projectile_target(candidates, origin)
	if picked.is_empty():
		_assist_locked = false
		return
	_assist_target = {
		"enemy": picked["enemy"],
		"pos": picked["pos"],
		"velocity": picked["velocity"],
	}
	_assist_locked = true


func _is_enemy_alive(enemy: Node) -> bool:
	if enemy.has_method("is_dead") and enemy.is_dead():
		return false
	var hp = enemy.get("current_health")
	return hp == null or int(hp) > 0


func _coop_split() -> Node:
	if is_instance_valid(_split):
		return _split
	_split = get_tree().get_first_node_in_group("coop_split")
	return _split


# --- Ayuda contextual de arranque ------------------------------------------------

## Mensaje breve al empezar (o al cambiar de dispositivo) explicando COMO se apunta.
## Usa el rotulo de eventos del HUD, que se desvanece solo: no ocupa HUD fijo.
func _show_device_hint() -> void:
	_hint_shown = true
	if _mode == MODE_AUTO:
		return
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("show_event_message"):
		return
	var text: String = ""
	match _device:
		DEVICE_MOUSE:
			text = "Apunta con el ratón"
		DEVICE_GAMEPAD:
			text = "Apunta con el stick derecho"
		_:
			text = "Apunta con las teclas configuradas"
	if _is_coop():
		text = "%s · %s" % [CoopConfig.player_tag(_player_id), text]
	hud.show_event_message(text, 2.4)


func _is_coop() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_coop") and gf.is_coop()


# --- Reticula --------------------------------------------------------------------

## Dibujada en el mundo, con la capa de visibilidad del jugador para que en split
## cada mitad pinte SOLO la suya. Contorno oscuro + trazo claro: legible sobre
## fondos claros y oscuros. Cuando la asistencia esta corrigiendo, la reticula se
## cierra y añade un anillo interior (estado visual distinto, no otro nodo).
func _draw() -> void:
	var color: Color = CoopConfig.player_color(_player_id)
	var shadow := Color(0.0, 0.0, 0.0, 0.55)
	var radius: float = 9.0 if _assist_locked else 12.0
	var gap: float = 4.0 if _assist_locked else 5.5

	# Contorno oscuro (legibilidad sobre fondo claro).
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, shadow, 4.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.45), 2.0, true)
	for i in 4:
		var dir: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / 4.0)
		draw_line(dir * gap, dir * (radius + 3.0), shadow, 4.0, true)
		draw_line(dir * gap, dir * (radius + 3.0), color, 2.0, true)
	if _assist_locked:
		# Anillo interior: "la asistencia esta corrigiendo hacia un enemigo".
		draw_arc(Vector2.ZERO, 3.5, 0.0, TAU, 12, Color(color.r, color.g, color.b, 0.95), 2.0, true)
