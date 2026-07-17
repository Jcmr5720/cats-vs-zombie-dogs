extends "res://scripts/systems/camera_effects.gd"
## Camara de pantalla dividida (Rework Coop). Vive dentro del SubViewport de cada
## jugador y lo sigue en exclusiva: cada jugador tiene SIEMPRE a su gato centrado,
## sin correa ni zoom compartido (la causa de que los testers "se perdieran").
## Hereda el modelo de trauma de camera_effects.gd: Feedback.shake sacude las dos
## mitades a la vez (grupo "screen_shake").

## Jugador al que sigue esta camara. Lo fija CoopSplitScreen al montar la vista.
var target: Node2D

## Zoom base de cada mitad: un pelin alejado para compensar el ancho reducido.
@export var base_zoom: float = CoopConfig.SPLIT_BASE_ZOOM
@export var follow_smoothness: float = 6.0


func _ready() -> void:
	super._ready()  # registra el shake (grupo "screen_shake")
	# Procesa siempre: durante la pausa de cartas la camara sigue viva (shake/idle).
	process_mode = Node.PROCESS_MODE_ALWAYS
	zoom = Vector2(base_zoom, base_zoom)
	if is_instance_valid(target):
		global_position = target.global_position


func _process(delta: float) -> void:
	if is_instance_valid(target):
		# Seguimiento suave e independiente del framerate. Si el jugador esta
		# derribado la camara se queda con el (el companero llega a rescatarlo).
		var t: float = 1.0 - exp(-follow_smoothness * delta)
		global_position = global_position.lerp(target.global_position, t)
	# El shake heredado se aplica sobre 'offset' (independiente de la posicion).
	super._process(delta)
