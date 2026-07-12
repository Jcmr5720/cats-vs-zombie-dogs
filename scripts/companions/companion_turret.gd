extends Node2D
## Torreta temporal del Gato Ingeniero ("Zona fortificada").
## Selecciona objetivo en ticks (no cada frame) y prioriza: enemigo marcado por
## el Policia (sinergia) > elite > el mas cercano. Dispara el mismo Projectile
## que los compañeros. Se autodestruye al agotar su duracion.
## Sinergia Medico + Ingeniero: si hay medico activo, emite un pulso de curacion
## periodico a los jugadores cercanos.

const CompanionBalance = preload("res://scripts/companions/companion_balance.gd")

var _projectile_scene: PackedScene
var _damage: int = 8
var _duration: float = CompanionBalance.ENGINEER_TURRET_DURATION
var _range: float = CompanionBalance.ENGINEER_TURRET_RANGE
var _fire_interval: float = CompanionBalance.ENGINEER_TURRET_FIRE_INTERVAL
var _heal_pulse: bool = false

var _elapsed: float = 0.0
var _fire_timer: float = 0.0
var _retarget_timer: float = 0.0
var _heal_timer: float = CompanionBalance.SYNERGY_TURRET_HEAL_INTERVAL
var _target: Node2D
var _head: Polygon2D
var _base_color := Color(1.0, 0.72, 0.32, 1.0)

const RETARGET_INTERVAL: float = 0.3


func configure(projectile_scene: PackedScene, damage: int, heal_pulse: bool) -> void:
	_projectile_scene = projectile_scene
	_damage = max(1, damage)
	_heal_pulse = heal_pulse


func _ready() -> void:
	add_to_group("companion_zones")
	_build_visual()
	scale = Vector2(0.2, 0.2)
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		_fade_out()
		return
	# Parpadeo en los ultimos 2 segundos: avisa que va a desaparecer.
	if _duration - _elapsed < 2.0:
		modulate.a = 0.55 + absf(sin(_elapsed * 9.0)) * 0.45

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _pick_target()

	_fire_timer -= delta
	if _fire_timer <= 0.0 and is_instance_valid(_target):
		_fire_timer = _fire_interval
		_fire()

	if _heal_pulse:
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = CompanionBalance.SYNERGY_TURRET_HEAL_INTERVAL
			_emit_heal_pulse()

	# El cañon apunta al objetivo.
	if is_instance_valid(_head) and is_instance_valid(_target):
		_head.rotation = global_position.direction_to(_target.global_position).angle()


## Prioridad: marcado por el Policia > elite > mas cercano. Un solo recorrido
## del grupo por tick (0.3 s), sin nodos ni calculos extra por enemigo.
func _pick_target() -> Node2D:
	var best: Node2D = null
	var best_score: float = -INF
	var range_sq: float = _range * _range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var dist_sq: float = global_position.distance_squared_to((enemy as Node2D).global_position)
		if dist_sq > range_sq:
			continue
		var score: float = -dist_sq
		if enemy.has_meta(&"companion_mark"):
			score += range_sq * 4.0
		elif enemy.get("_elite_kind") != null and enemy.get("_elite_kind") != &"":
			score += range_sq * 2.0
		if score > best_score:
			best_score = score
			best = enemy
	return best


func _fire() -> void:
	if _projectile_scene == null or not is_instance_valid(_target):
		return
	var projectile := _projectile_scene.instantiate() as Node2D
	if projectile == null:
		return
	var direction: Vector2 = global_position.direction_to(_target.global_position)
	projectile.global_position = global_position + direction * 14.0
	projectile.modulate = _base_color
	projectile.call("setup", direction, 520.0, _damage)
	get_tree().current_scene.add_child(projectile)


func _emit_heal_pulse() -> void:
	var radius_sq: float = CompanionBalance.SYNERGY_TURRET_HEAL_RADIUS * CompanionBalance.SYNERGY_TURRET_HEAL_RADIUS
	var healed: bool = false
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if p.has_method("is_active") and not p.is_active():
			continue
		if global_position.distance_squared_to((p as Node2D).global_position) <= radius_sq:
			if p.has_method("heal"):
				p.heal(CompanionBalance.SYNERGY_TURRET_HEAL)
				healed = true
	if healed:
		Feedback.hit_effect(global_position, Color(0.55, 1.0, 0.72, 0.5), 0.25, 1.1)


func _fade_out() -> void:
	set_process(false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_property(self, "scale", Vector2(1.2, 0.1), 0.2)
	tween.chain().tween_callback(queue_free)


## Visual provisional: base hexagonal amarilla de obra + cañon giratorio.
func _build_visual() -> void:
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-12, -4), Vector2(-6, -12), Vector2(6, -12),
		Vector2(12, -4), Vector2(12, 6), Vector2(6, 12), Vector2(-6, 12), Vector2(-12, 6)
	])
	base.color = Color(0.98, 0.78, 0.22, 1.0)
	add_child(base)
	var stripe := Polygon2D.new()
	stripe.polygon = PackedVector2Array([
		Vector2(-10, 2), Vector2(10, 2), Vector2(10, 6), Vector2(-10, 6)
	])
	stripe.color = Color(0.22, 0.18, 0.10, 0.9)
	add_child(stripe)
	_head = Polygon2D.new()
	_head.polygon = PackedVector2Array([
		Vector2(-3, -3), Vector2(16, -2), Vector2(16, 2), Vector2(-3, 3)
	])
	_head.color = Color(0.35, 0.30, 0.22, 1.0)
	add_child(_head)
