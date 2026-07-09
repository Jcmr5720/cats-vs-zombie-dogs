extends "res://scripts/systems/camera_effects.gd"
## Camara cooperativa (Fase Coop Local). Solo se instancia en modo local_coop; en
## solo se sigue usando la camara hija del Player (sin cambios).
##
## Sigue el PUNTO MEDIO entre los jugadores ACTIVOS y ajusta el zoom de forma suave:
## si se separan, hace zoom out (ven mas mapa); si se juntan, zoom in. Hereda el
## modelo de "trauma" de camera_effects.gd, asi que Feedback.shake sigue funcionando.

## Zoom cuando los jugadores estan juntos (mas cerca = mas detalle).
@export var max_zoom: float = 1.35
## Zoom minimo cuando estan al limite de separacion (ven mas mapa).
@export var min_zoom: float = 1.0
@export var zoom_smoothness: float = 4.0
@export var follow_smoothness: float = 5.0
## Distancia (px) entre jugadores que corresponde al zoom minimo.
@export var max_allowed_distance: float = 900.0

var _target_zoom: float = 1.0


func _ready() -> void:
	super._ready()  # registra el shake (grupo "screen_shake")
	# Procesa siempre (incluso en la pausa de subida de nivel), como la camara solo.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_target_zoom = max_zoom
	zoom = Vector2(max_zoom, max_zoom)


func _process(delta: float) -> void:
	var players := _active_players()
	if not players.is_empty():
		var center: Vector2 = _centroid(players)
		var spread: float = _max_spread(players)
		# Seguimiento suave e independiente del framerate.
		var follow_t: float = 1.0 - exp(-follow_smoothness * delta)
		global_position = global_position.lerp(center, follow_t)
		# Cuanto mas separados, menos zoom (mas campo de vision).
		var t: float = clampf(spread / max_allowed_distance, 0.0, 1.0)
		_target_zoom = lerpf(max_zoom, min_zoom, t)
		var zoom_t: float = 1.0 - exp(-zoom_smoothness * delta)
		var z: float = lerpf(zoom.x, _target_zoom, zoom_t)
		zoom = Vector2(z, z)
	# El shake heredado se aplica sobre 'offset' (independiente de la posicion).
	super._process(delta)


## Jugadores activos (ni muertos ni derribados). Si no hay ninguno activo, cae a
## cualquiera del grupo para no dejar la camara a la deriva.
func _active_players() -> Array:
	var active: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if p.has_method("is_active") and not p.is_active():
			continue
		active.append(p)
	if active.is_empty():
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p is Node2D:
				active.append(p)
	return active


func _centroid(nodes: Array) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for n in nodes:
		sum += (n as Node2D).global_position
	return sum / float(nodes.size())


func _max_spread(nodes: Array) -> float:
	var best: float = 0.0
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var d: float = (nodes[i] as Node2D).global_position.distance_to((nodes[j] as Node2D).global_position)
			if d > best:
				best = d
	return best
