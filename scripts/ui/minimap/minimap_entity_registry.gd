extends Node
## Registro central de entidades detectables por el minimapa (Sistema Minimapa).
## Aprovecha los grupos que las entidades YA usan al hacer _ready ("players",
## "enemies", "boss", "miniboss", "companions", "rescue_points", "obstacles"):
## nada del gameplay tuvo que tocarse para registrarse.
##
## Rendimiento: NO se recorre el arbol cada frame. Cada grupo se fotografia con
## get_nodes_in_group() a una cadencia propia (los enemigos mas a menudo, los
## obstaculos casi nunca) y los consumidores leen la foto cacheada. Un nodo
## liberado entre refrescos simplemente falla is_instance_valid() en el consumidor
## y se ignora; el siguiente refresco lo elimina de la foto.

## Grupo -> segundos entre refrescos de su foto.
const REFRESH_INTERVALS: Dictionary = {
	&"players": 0.4,
	&"companions": 0.6,
	&"enemies": 0.35,
	&"rescue_points": 0.7,
	&"boss": 0.5,
	&"miniboss": 0.5,
	&"obstacles": 3.0,
}

var _cache: Dictionary = {}
var _timers: Dictionary = {}


func _ready() -> void:
	for group in REFRESH_INTERVALS:
		_cache[group] = []
		# Primera foto TEMPRANA (el radar no debe tardar segundos en poblarse) pero
		# escalonada entre grupos para no refrescar todos el mismo frame.
		_timers[group] = randf() * minf(0.4, float(REFRESH_INTERVALS[group]))


func _process(delta: float) -> void:
	for group in REFRESH_INTERVALS:
		_timers[group] = float(_timers[group]) - delta
		if _timers[group] <= 0.0:
			_timers[group] = float(REFRESH_INTERVALS[group])
			_cache[group] = get_tree().get_nodes_in_group(group)


## Foto cacheada del grupo. Puede contener nodos ya liberados: el consumidor
## DEBE validar con is_instance_valid() + is_inside_tree() antes de usarlos.
func get_list(group: StringName) -> Array:
	return _cache.get(group, [])


## Fuerza un refresco inmediato (p. ej. al crear el minimapa del P2).
func refresh_now(group: StringName) -> void:
	if REFRESH_INTERVALS.has(group):
		_timers[group] = float(REFRESH_INTERVALS[group])
		_cache[group] = get_tree().get_nodes_in_group(group)
