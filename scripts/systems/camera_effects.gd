extends Camera2D
## Screen shake suave y desactivable para la cámara que sigue al jugador.
## Usa un modelo de "trauma" (Vince/GDC): el trauma se acumula y decae solo;
## el desplazamiento es trauma^2 para que los golpes pequeños casi no muevan la
## cámara y solo los fuertes la sacudan. Así nunca marea.
##
## Otros sistemas piden shake vía el autoload Feedback.shake(amount), que busca
## este nodo por el grupo "screen_shake".

## Pon en false para desactivar TODO el shake (accesibilidad / pruebas).
@export var shake_enabled: bool = true
## Desplazamiento máximo en píxeles con trauma = 1.0.
@export var max_offset: float = 14.0
## Rotación máxima en radianes con trauma = 1.0 (muy sutil).
@export var max_roll: float = 0.025
## Velocidad de decaimiento del trauma por segundo.
@export var decay: float = 1.6

var _trauma: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	add_to_group("screen_shake")


## Suma trauma (se satura en 1.0). amount típico: 0.15 suave .. 0.8 fuerte.
func add_trauma(amount: float) -> void:
	if not shake_enabled:
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
			rotation = 0.0
		return

	_time += delta
	_trauma = max(_trauma - decay * delta, 0.0)
	var amount: float = _trauma * _trauma  # respuesta cuadrática: golpes suaves apenas mueven.

	# Ruido pseudo-aleatorio rápido a partir de senos desfasados.
	var t: float = _time * 35.0
	offset = Vector2(
		sin(t * 1.13 + 0.4),
		sin(t * 1.77 + 2.1)
	) * (max_offset * amount)
	rotation = sin(t * 1.51 + 1.0) * (max_roll * amount)
