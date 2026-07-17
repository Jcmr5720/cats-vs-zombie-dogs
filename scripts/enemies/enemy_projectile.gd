extends Node2D
## Proyectil enemigo del Escupidor: lento, grande y visible (esquivable a pie).
## Autodibujado (sin escena): burbuja acida con halo. Viaja en linea recta, dana
## al primer jugador que toca y desaparece sola al agotar su vida util.
## El limite GLOBAL de proyectiles enemigos vive en RunPhaseConfig
## (MAX_ENEMY_PROJECTILES) y lo comprueba el Escupidor ANTES de disparar.

const GROUP := &"enemy_projectiles"

var velocity: Vector2 = Vector2.ZERO
var damage: int = 8
var lifetime: float = 3.5
## Radio de impacto contra jugadores.
var hit_radius: float = 22.0

var _time: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 5


func _process(delta: float) -> void:
	_time += delta
	lifetime -= delta
	if lifetime <= 0.0:
		_splash()
		return
	global_position += velocity * delta
	queue_redraw()

	# Impacto contra cualquier jugador ACTIVO (solo: P1; coop: cualquiera).
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if p.has_method("is_active") and not p.is_active():
			continue
		if global_position.distance_to((p as Node2D).global_position) <= hit_radius:
			if p.has_method("take_damage"):
				p.take_damage(damage)
			_splash()
			return


func _splash() -> void:
	Feedback.hit_effect(global_position, Color(0.55, 1.0, 0.35, 0.7), 0.3, 1.2)
	queue_free()


func _draw() -> void:
	# Halo pulsante + nucleo: se lee venir desde lejos.
	var pulse: float = 1.0 + sin(_time * 9.0) * 0.15
	draw_circle(Vector2.ZERO, 11.0 * pulse, Color(0.5, 0.95, 0.3, 0.25))
	draw_circle(Vector2.ZERO, 6.5, Color(0.55, 1.0, 0.35, 0.9))
	draw_circle(Vector2.ZERO, 3.0, Color(0.85, 1.0, 0.6, 1.0))
	# Estela corta que marca la trayectoria.
	var back: Vector2 = -velocity.normalized() * 16.0
	draw_line(Vector2.ZERO, back, Color(0.55, 1.0, 0.35, 0.35), 3.0)
