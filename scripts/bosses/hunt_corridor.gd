extends Node2D
## Corredor de caceria del Rottweiler Alfa (FASE 2, fase elite del Barrio).
##
## Es una FRANJA anclada a una calle real del plano (via `MapGeometry`), no una
## forma libre: el jugador que ha aprendido a leer las avenidas del Barrio sabe
## de antemano por donde puede pasar esto. Dentro del corredor el Alfa prepara
## cargas y envia manadas en UNA direccion.
##
## Reglas de justicia, todas comprobadas por `tests/test_barrio.gd`:
##   - Se telegrafia (`arm_delay`) antes de activarse.
##   - Es estrecho (media anchura de la calle): SIEMPRE se sale por los lados.
##   - Nunca cubre el mapa: tiene largo finito y expira solo.
##   - Se puede desactivar destruyendo la marca que lo ancla.
##   - No daña por si mismo. La presion la ponen el jefe y la manada.
##
## No sustituye a `hazard_zone` (circular y con daño): esto es una franja de
## LECTURA TACTICA sin daño, con geometria y ciclo de vida distintos.

const GROUP := &"hunt_corridors"

## Extremos de la franja, en coordenadas globales.
var start_point: Vector2 = Vector2.ZERO
var end_point: Vector2 = Vector2.ZERO
## Media anchura: la hereda de la calle, para que quepa dentro de ella.
var half_width: float = 100.0
## Segundos de aviso antes de activarse (no hay caceria durante el telegrafo).
var arm_delay: float = 1.6
## Vida util una vez activo. Expira solo: la caceria no es permanente.
var duration: float = 26.0
## Marca que lo ancla: si el jugador la destruye, el corredor se apaga.
var anchor_post: Node2D

var _time: float = 0.0
var _dead: bool = false


## Crea el corredor. `parent` debe estar en el arbol.
static func spawn(parent: Node, from: Vector2, to: Vector2, width: float,
		post: Node2D = null) -> Node2D:
	if parent == null or not parent.is_inside_tree():
		return null
	# Uno por partida: dos corredores a la vez taparian el mapa.
	if parent.get_tree().get_node_count_in_group(GROUP) > 0:
		return null
	var node := Node2D.new()
	node.set_script(load("res://scripts/bosses/hunt_corridor.gd"))
	node.set("start_point", from)
	node.set("end_point", to)
	node.set("half_width", clampf(width, 70.0, 130.0))
	node.set("anchor_post", post)
	node.position = Vector2.ZERO
	parent.add_child.call_deferred(node)
	RunTelemetry.count(&"hunt_corridors_created")
	return node


func _ready() -> void:
	add_to_group(GROUP)
	z_index = -2
	Feedback.shake(0.3)


func is_armed() -> bool:
	return arm_delay <= 0.0 and not _dead


## Direccion de la caceria (hacia donde empuja el Alfa a la manada).
func direction() -> Vector2:
	return (end_point - start_point).normalized()


## true si `pos` cae dentro de la franja. Proyeccion sobre el segmento: barato.
func contains(pos: Vector2) -> bool:
	if _dead:
		return false
	var axis: Vector2 = end_point - start_point
	var length_squared: float = axis.length_squared()
	if length_squared <= 1.0:
		return false
	var t: float = clampf((pos - start_point).dot(axis) / length_squared, 0.0, 1.0)
	var closest: Vector2 = start_point + axis * t
	return pos.distance_to(closest) <= half_width


## Apagado explicito: lo llama la destruccion de la marca que lo ancla.
func deactivate() -> void:
	if _dead:
		return
	_dead = true
	RunTelemetry.count(&"hunt_corridors_deactivated")
	Feedback.hit_effect((start_point + end_point) * 0.5, Color(0.6, 1.0, 0.8, 0.9), 0.9, 4.0)
	queue_free()


func _process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	queue_redraw()
	if arm_delay > 0.0:
		arm_delay -= delta
		if arm_delay <= 0.0:
			Feedback.shake(0.25)
		return
	# La marca que lo ancla ha caido: el corredor se apaga. Es el contrajuego.
	if anchor_post != null and not is_instance_valid(anchor_post):
		deactivate()
		return
	duration -= delta
	if duration <= 0.0:
		_dead = true
		RunTelemetry.count(&"hunt_corridors_expired")
		queue_free()
		return
	# Telemetria: cuanto tiempo pasa cada jugador dentro de la franja.
	if RunTelemetry.enabled:
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p is Node2D and contains((p as Node2D).global_position):
				RunTelemetry.add_time(&"player_time_in_hunt_corridor", delta)


func _draw() -> void:
	var axis: Vector2 = end_point - start_point
	if axis.length_squared() < 1.0:
		return
	var dir: Vector2 = axis.normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x) * half_width
	# Coordenadas locales (el nodo esta en el origen del mundo).
	var a: Vector2 = start_point + side
	var b: Vector2 = end_point + side
	var c: Vector2 = end_point - side
	var d: Vector2 = start_point - side
	var accent := Color(1.0, 0.35, 0.25)

	if arm_delay > 0.0:
		# TELEGRAFO: solo el contorno, parpadeando. Aun no hay caceria.
		var blink: float = 0.3 + 0.5 * absf(sin(_time * 9.0))
		var outline := PackedVector2Array([a, b, c, d, a])
		draw_polyline(outline, Color(accent.r, accent.g, accent.b, blink), 4.0, true)
		return

	# Activo: relleno tenue + flechas que indican HACIA DONDE empuja la caceria.
	var fade: float = clampf(duration / 2.0, 0.0, 1.0)
	draw_colored_polygon(PackedVector2Array([a, b, c, d]),
		Color(accent.r, accent.g, accent.b, 0.10 * fade))
	draw_polyline(PackedVector2Array([a, b]), Color(accent.r, accent.g, accent.b, 0.5 * fade), 3.0, true)
	draw_polyline(PackedVector2Array([d, c]), Color(accent.r, accent.g, accent.b, 0.5 * fade), 3.0, true)
	var length: float = axis.length()
	var flow: float = fmod(_time * 150.0, 220.0)
	var count: int = int(length / 220.0)
	for i in count:
		var at: float = float(i) * 220.0 + flow
		if at > length:
			continue
		var tip: Vector2 = start_point + dir * at
		var back: Vector2 = tip - dir * 34.0
		var wing: Vector2 = Vector2(-dir.y, dir.x) * 18.0
		draw_polyline(PackedVector2Array([back + wing, tip, back - wing]),
			Color(accent.r, accent.g, accent.b, 0.45 * fade), 3.0, true)
