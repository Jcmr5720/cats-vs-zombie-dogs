extends Node
## Controla el estado general de la partida: tiempo de supervivencia, fin de
## juego al morir el jugador y reinicio con la tecla "restart".

signal time_updated(seconds: float)
signal game_over

enum State { PLAYING, GAME_OVER }

## Asignados en MainLevel para evitar búsquedas frágiles por ruta.
@export var player_path: NodePath
@export var hud_path: NodePath

var state: State = State.PLAYING
var elapsed_time: float = 0.0

var _player: Node
var _hud: Node


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_hud = get_node_or_null(hud_path)

	if _player != null and _player.has_signal("died"):
		_player.died.connect(_on_player_died)

	# El HUD escucha el tiempo de este manager. Desde Fase 07 el panel de fin de
	# partida (con Sardinas) lo muestra el MapManager, no este nodo.
	if _hud != null and _hud.has_method("on_time_updated"):
		time_updated.connect(_hud.on_time_updated)


func _process(delta: float) -> void:
	if state == State.PLAYING:
		elapsed_time += delta
		time_updated.emit(elapsed_time)


func _on_player_died() -> void:
	state = State.GAME_OVER
	game_over.emit()
