extends Node2D
## Zona peligrosa temporal (charco infeccioso). La deja el Portador de Infeccion
## al morir y el jefe del Parque en su fase elite. Autodibujada, claramente
## señalada (anillo pulsante), dana por tics a los jugadores dentro y desaparece
## a los pocos segundos. Limite global en RunPhaseConfig.MAX_HAZARD_ZONES
## (lo comprueba quien la crea).

const GROUP := &"hazard_zones"

var radius: float = 70.0
var damage_per_tick: int = 4
var duration: float = 3.0
var color: Color = Color(0.55, 0.9, 0.3, 1.0)

var _time: float = 0.0
var _tick_timer: float = 0.35  # pequeño margen: no dana el mismo frame de nacer


func _ready() -> void:
	add_to_group(GROUP)
	z_index = -1


func _process(delta: float) -> void:
	_time += delta
	duration -= delta
	if duration <= 0.0:
		queue_free()
		return
	queue_redraw()
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = 0.5
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if p.has_method("is_active") and not p.is_active():
			continue
		if global_position.distance_to((p as Node2D).global_position) <= radius:
			if p.has_method("take_damage"):
				p.take_damage(damage_per_tick)


func _draw() -> void:
	# Se desvanece al final para avisar de que va a desaparecer.
	var fade: float = clampf(duration / 0.6, 0.0, 1.0)
	var pulse: float = 0.85 + sin(_time * 6.0) * 0.15
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.16 * fade))
	draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 40,
		Color(color.r, color.g, color.b, 0.55 * fade), 3.0, true)
	# Burbujas interiores simples (arte provisional pero legible).
	for i in 5:
		var a: float = float(i) * TAU / 5.0 + _time * 0.8
		var d: float = radius * (0.25 + 0.35 * float(i % 3) / 2.0)
		draw_circle(Vector2(cos(a), sin(a)) * d, 4.0, Color(color.r, color.g, color.b, 0.30 * fade))
