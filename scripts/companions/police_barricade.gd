extends Node2D
## Barricada policial temporal (habilidad del Gato Policia).
## Zona circular que ralentiza y empuja levemente a los enemigos que entran.
## NO bloquea al jugador ni a los proyectiles aliados (no tiene colision fisica:
## trabaja por distancia sobre el grupo "enemies" en ticks, no cada frame).
## Sinergia Policia + Medico: si hay un medico activo, cura un poco a los
## jugadores dentro de la zona en cada tick.

const CompanionBalance = preload("res://scripts/companions/companion_balance.gd")

var _radius: float = CompanionBalance.POLICE_BARRICADE_RADIUS
var _duration: float = CompanionBalance.POLICE_BARRICADE_DURATION
var _heal_allies: bool = false
var _elapsed: float = 0.0
var _tick_timer: float = 0.0
var _ring: Line2D
var _fill: Polygon2D
## Enemigos ya empujados (el empujon de entrada se aplica una sola vez).
var _pushed: Dictionary = {}

const TICK_INTERVAL: float = 0.4


func configure(radius: float, duration: float, heal_allies: bool) -> void:
	_radius = radius
	_duration = duration
	_heal_allies = heal_allies


func _ready() -> void:
	add_to_group("companion_zones")
	_build_visual()
	# Pop de aparicion (telegrafica clara, arte provisional).
	scale = Vector2(0.2, 0.2)
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		_fade_out()
		return
	# Pulso visual leve.
	if is_instance_valid(_ring):
		_ring.modulate.a = 0.75 + sin(_elapsed * 6.0) * 0.25
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_apply_tick()


func _apply_tick() -> void:
	var radius_sq: float = _radius * _radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var offset: Vector2 = (enemy as Node2D).global_position - global_position
		if offset.length_squared() > radius_sq:
			continue
		if enemy.has_method("apply_slow"):
			enemy.apply_slow(CompanionBalance.POLICE_BARRICADE_SLOW, TICK_INTERVAL + 0.15)
		# Empujon de entrada (una vez por enemigo): interrumpe cargas.
		var key: int = enemy.get_instance_id()
		if not _pushed.has(key) and enemy.has_method("take_damage"):
			_pushed[key] = true
			var dir: Vector2 = offset.normalized() if offset != Vector2.ZERO else Vector2.RIGHT
			enemy.take_damage(1, dir)
	# Sinergia Policia + Medico: pequeña zona segura que cura a los jugadores.
	if _heal_allies:
		for p in get_tree().get_nodes_in_group("players"):
			if not is_instance_valid(p) or not (p is Node2D):
				continue
			if p.has_method("is_active") and not p.is_active():
				continue
			if global_position.distance_squared_to((p as Node2D).global_position) <= radius_sq:
				if p.has_method("heal"):
					p.heal(CompanionBalance.SYNERGY_BARRICADE_HEAL)


func _fade_out() -> void:
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)


## Visual provisional (formas planas, sin arte definitivo): anillo azul policial
## con relleno tenue. Sin particulas ni luces (barato para hordas).
func _build_visual() -> void:
	var points := PackedVector2Array()
	var segments: int = 28
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(a), sin(a)) * _radius)
	_fill = Polygon2D.new()
	_fill.polygon = points
	_fill.color = Color(0.30, 0.55, 0.95, 0.10)
	add_child(_fill)
	_ring = Line2D.new()
	_ring.points = points
	_ring.closed = true
	_ring.width = 4.0
	_ring.default_color = Color(0.45, 0.72, 1.0, 0.85)
	add_child(_ring)
	# Rotulo identificador: la zona se lee como herramienta del Gato Policia
	# (ralentiza enemigos), no como decoracion del mapa.
	var tag := Label.new()
	tag.text = "⛨ Barricada policial"
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", Color(0.6, 0.82, 1.0, 0.95))
	tag.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.14, 0.9))
	tag.add_theme_constant_override("outline_size", 4)
	tag.position = Vector2(-52.0, -_radius - 22.0)
	add_child(tag)
