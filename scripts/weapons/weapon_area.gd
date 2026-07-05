extends Node2D
## Zona temporal que daña por tics a los enemigos dentro de su radio (Granada de
## Catnip). Se libera sola al agotar su duracion. La crea WeaponBase (tipo area).

var _damage: int = 4
var _radius: float = 110.0
var _duration: float = 3.0
var _tick_interval: float = 0.4
var _tick_timer: float = 0.0
var _life: float = 0.0

@onready var _visual: Polygon2D = $Visual
@onready var _inner: Polygon2D = $Inner
@onready var _ring: Polygon2D = $Ring


func setup(damage: int, radius: float, duration: float, tick_interval: float, color: Color) -> void:
	_damage = damage
	_radius = radius
	_duration = duration
	_tick_interval = max(0.1, tick_interval)
	if not is_node_ready():
		await ready
	_visual.color = color
	_inner.color = color.lightened(0.25)
	_ring.color = Color(color.r, color.g, color.b, 0.72)
	# Escala el circulo base (radio 1.0 en la escena) al radio real.
	_visual.scale = Vector2(_radius, _radius)
	_inner.scale = Vector2(_radius * 0.48, _radius * 0.48)
	_ring.scale = Vector2(_radius, _radius)
	_appear()


## La zona de dano es semitransparente para que se vea DONDE dana sin tapar a los
## enemigos ni al jugador (claridad en pantalla, Fase 04.5).
const AREA_ALPHA: float = 0.42

func _appear() -> void:
	_visual.modulate.a = 0.0
	_inner.modulate.a = 0.0
	_ring.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "modulate:a", AREA_ALPHA, 0.15)
	tween.tween_property(_inner, "modulate:a", 0.30, 0.15)
	tween.tween_property(_ring, "modulate:a", 0.70, 0.15)


func _process(delta: float) -> void:
	_life += delta
	# Pulso suave del area.
	if is_instance_valid(_visual):
		_visual.rotation += delta * 0.6
		_visual.modulate.a = AREA_ALPHA * (0.82 + sin(_life * 3.2) * 0.18)
	if is_instance_valid(_inner):
		_inner.rotation -= delta * 0.9
		_inner.modulate.a = 0.22 + sin(_life * 4.6) * 0.08
	if is_instance_valid(_ring):
		_ring.scale = Vector2.ONE * _radius * (1.0 + sin(_life * 5.0) * 0.035)
		_ring.modulate.a = 0.54 + abs(sin(_life * 5.0)) * 0.20
	if _life >= _duration:
		_fade_out()
		set_process(false)
		return

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = _tick_interval
		_apply_tick()


func _apply_tick() -> void:
	var radius_sq: float = _radius * _radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		var offset: Vector2 = (enemy as Node2D).global_position - global_position
		if offset.length_squared() <= radius_sq:
			enemy.take_damage(_damage, offset.normalized() if offset.length_squared() > 0.01 else Vector2.UP)


func _fade_out() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "modulate:a", 0.0, 0.25)
	tween.tween_property(_inner, "modulate:a", 0.0, 0.25)
	tween.tween_property(_ring, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)
