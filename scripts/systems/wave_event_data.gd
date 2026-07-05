class_name WaveEventData
extends Resource
## Describe un evento de partida programado por tiempo. El WaveEventManager
## mantiene una lista de estos y los dispara cuando el reloj de partida alcanza
## `time`. Es deliberadamente simple para que la estructura sea facil de extender.
##
## Tipos soportados por WaveEventManager:
##   &"horde"        : sube el spawn de enemigos normales durante `duration` s.
##   &"runner_pack"  : sube mucho la probabilidad de runners durante `duration` s.
##   &"miniboss"     : aparece un mini-jefe (elite).
##   &"boss"         : aparece el jefe principal con barra de vida.
##   &"xp_bonus"     : (reservado/expandible) aviso de bonus temporal de XP.

@export var type: StringName = &"horde"
## Segundo de partida en que se dispara el evento.
@export var time: float = 60.0
## Duracion del efecto (para horde / runner_pack). 0 = instantaneo.
@export var duration: float = 20.0
## Intensidad del efecto (multiplicador de spawn para horde, peso extra runners).
@export var intensity: float = 1.0
## Texto central que muestra el HUD al dispararse.
@export var label: String = ""
## Si > 0, el evento se vuelve a programar cada `repeat_interval` segundos.
@export var repeat_interval: float = 0.0
