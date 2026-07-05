extends Node2D
## Flecha sutil que orbita al jugador y apunta hacia el punto de rescate activo.
## Es hija del Player (sigue su posicion automaticamente y se reinicia con la
## escena). Solo aparece si hay un rescate activo y aun estas lejos de el, para
## no estorbar cuando ya llegaste.

@export var orbit_radius: float = 58.0
## Si el punto esta mas cerca que esto, la flecha se oculta (ya estas encima).
@export var hide_within: float = 150.0

@onready var _arrow: Node2D = $Arrow

var _time: float = 0.0


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	_time += delta
	var target: Node2D = _nearest_rescue_point()
	if target == null:
		if visible:
			visible = false
		return

	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()
	if distance < hide_within:
		visible = false
		return

	visible = true
	var direction: Vector2 = to_target / distance
	_arrow.position = direction * orbit_radius
	_arrow.rotation = direction.angle()
	_arrow.modulate.a = 0.5 + sin(_time * 4.0) * 0.18


func _nearest_rescue_point() -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for point in get_tree().get_nodes_in_group("rescue_points"):
		if not is_instance_valid(point):
			continue
		var distance: float = global_position.distance_to((point as Node2D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best
