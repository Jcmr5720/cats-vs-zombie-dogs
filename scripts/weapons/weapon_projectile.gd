extends Area2D
## Proyectil modular del jugador. Soporta bala directa, pierce (atraviesa varios
## enemigos) y explosion en area al impactar. Lo configuran las armas via setup().
## Es independiente del Projectile.tscn de los companeros para no acoplar sistemas.

var _direction: Vector2 = Vector2.RIGHT
var _speed: float = 600.0
var _damage: int = 8
var _knockback: float = 120.0
var _pierce: int = 0
var _explosion_radius: float = 0.0
var _lifetime: float = 2.0
var _weapon_type: StringName = &"projectile"
var _hit_bodies: Array = []
var _halo_base_scale: Vector2 = Vector2.ONE
## Tope global de proyectiles vivos (Fase 08.75). Al superarlo se limpia el mas
## lejano al jugador para no acumular balas sin limite.
const MAX_PROJECTILES: int = 250

@onready var _visual: Polygon2D = $Visual
@onready var _halo: Polygon2D = $Halo
@onready var _core: Polygon2D = $Core
@onready var _trail: Line2D = $Trail


func setup(direction: Vector2, opts: Dictionary) -> void:
	_direction = direction.normalized()
	_speed = opts.get("speed", 600.0)
	_damage = opts.get("damage", 8)
	_knockback = opts.get("knockback", 120.0)
	_pierce = opts.get("pierce", 0)
	_explosion_radius = opts.get("explosion_radius", 0.0)
	_lifetime = opts.get("lifetime", 2.0)
	rotation = _direction.angle()
	var color: Color = opts.get("color", Color(1, 0.95, 0.7))
	var visual_scale: float = opts.get("visual_scale", 1.0)
	_weapon_type = opts.get("weapon_type", &"projectile")
	if not is_node_ready():
		await ready
	_apply_visual_style(color, visual_scale)


func _ready() -> void:
	add_to_group("projectiles")
	# Detecta tambien los obstaculos solidos (capa 5) para chocar/dañarlos.
	set_collision_mask_value(5, true)
	_enforce_projectile_cap()
	body_entered.connect(_on_body_entered)
	var timer := get_tree().create_timer(_lifetime)
	timer.timeout.connect(_on_lifetime_expired)


## Si hay demasiados proyectiles vivos, libera el mas lejano al jugador (viejo /
## fuera de rango), manteniendo acotado el total.
func _enforce_projectile_cap() -> void:
	var group := get_tree().get_nodes_in_group("projectiles")
	if group.size() <= MAX_PROJECTILES:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var farthest: Node2D = null
	var best_sq: float = -1.0
	for p in group:
		if p == self or not is_instance_valid(p) or not (p is Node2D):
			continue
		var d: float = (p as Node2D).global_position.distance_squared_to((player as Node2D).global_position)
		if d > best_sq:
			best_sq = d
			farthest = p
	if farthest != null:
		farthest.queue_free()


func _physics_process(delta: float) -> void:
	_sweep_move(_direction * _speed * delta)
	if is_instance_valid(_halo):
		var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.018) * 0.10
		_halo.scale = _halo_base_scale * pulse


## Movimiento con BARRIDO: a velocidad alta la bala recorre varias veces el
## cuerpo de un enemigo en un solo tick de fisica y el overlap del Area2D no
## llega a registrarse (tunneling: el disparo "atraviesa" sin dañar). Se traza
## un rayo del origen al destino del tick y cada impacto se procesa igual que
## body_entered; con pierce se continua el resto del trayecto.
func _sweep_move(travel: Vector2) -> void:
	var space := get_world_2d().direct_space_state if get_world_2d() != null else null
	if space == null or travel == Vector2.ZERO:
		global_position += travel
		return
	var destination: Vector2 = global_position + travel
	for _i in 4:  # tope de impactos procesados por tick (pierce encadenado)
		var params := PhysicsRayQueryParameters2D.create(global_position, destination, collision_mask)
		params.collide_with_areas = false
		var exclude: Array[RID] = []
		for b in _hit_bodies:
			if is_instance_valid(b) and b is CollisionObject2D:
				exclude.append((b as CollisionObject2D).get_rid())
		params.exclude = exclude
		var hit: Dictionary = space.intersect_ray(params)
		if hit.is_empty():
			global_position = destination
			return
		global_position = hit.get("position", destination)
		var collider = hit.get("collider")
		if collider is Node2D:
			_on_body_entered(collider)
		if is_queued_for_deletion() or not is_inside_tree():
			return  # la bala murio en el impacto (sin pierce restante)
	global_position = destination


func _on_body_entered(body: Node2D) -> void:
	# Obstaculos: el boomerang los atraviesa; el resto los daña (si destructible) y
	# se detiene si el obstaculo bloquea proyectiles.
	if body.is_in_group("obstacles"):
		if _weapon_type == &"boomerang":
			return
		if body in _hit_bodies:
			return
		_hit_bodies.append(body)
		var blocks: bool = true
		if body.has_method("absorb_projectile"):
			blocks = body.absorb_projectile(_damage)
		if blocks:
			if _explosion_radius > 0.0:
				_explode()
			queue_free()
		return

	if not body.is_in_group("enemies") or not body.has_method("take_damage"):
		return
	if body in _hit_bodies:
		return
	_hit_bodies.append(body)

	if _explosion_radius > 0.0:
		_explode()
		queue_free()
		return

	body.take_damage(_damage, _direction)

	if _pierce > 0:
		_pierce -= 1
	else:
		queue_free()


## Daña a todos los enemigos dentro del radio y muestra un destello de explosion.
func _explode() -> void:
	var radius_sq: float = _explosion_radius * _explosion_radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		var offset: Vector2 = (enemy as Node2D).global_position - global_position
		if offset.length_squared() <= radius_sq:
			var dir: Vector2 = offset.normalized() if offset.length_squared() > 0.01 else _direction
			enemy.take_damage(_damage, dir)
	# Las explosiones tambien rompen destructibles cercanos (cajas/barriles).
	for obst in get_tree().get_nodes_in_group("obstacles"):
		if not is_instance_valid(obst) or not obst.has_method("absorb_projectile"):
			continue
		if (obst as Node2D).global_position.distance_squared_to(global_position) <= radius_sq:
			obst.absorb_projectile(_damage)
	var color: Color = _visual.color if is_instance_valid(_visual) else Color(1, 0.8, 0.4)
	Feedback.hit_effect(global_position, color, 0.4, _explosion_radius / 14.0)
	Feedback.shake(0.10)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"explosion")


func _apply_visual_style(color: Color, visual_scale: float) -> void:
	_visual.color = color
	_visual.scale = Vector2(visual_scale, visual_scale)
	_core.color = color.lightened(0.35)
	_halo.color = Color(color.r, color.g, color.b, 0.24)
	_trail.default_color = Color(color.r, color.g, color.b, 0.36)

	match _weapon_type:
		&"explosive":
			_visual.polygon = PackedVector2Array([
				Vector2(-14, -7), Vector2(-6, -13), Vector2(5, -12),
				Vector2(13, -5), Vector2(15, 5), Vector2(7, 13),
				Vector2(-6, 13), Vector2(-15, 5),
			])
			_core.polygon = PackedVector2Array([
				Vector2(-8, -2), Vector2(-2, -7), Vector2(6, -5),
				Vector2(8, 3), Vector2(2, 8), Vector2(-6, 5),
			])
			_halo.polygon = PackedVector2Array([
				Vector2(20, 0), Vector2(9, 8), Vector2(0, 20), Vector2(-8, 9),
				Vector2(-20, 0), Vector2(-9, -8), Vector2(0, -20), Vector2(8, -9),
			])
			_halo_base_scale = Vector2(1.55, 1.55)
			_halo.scale = _halo_base_scale
			_trail.width = 8.0
		&"boomerang":
			_visual.polygon = PackedVector2Array([
				Vector2(-16, -5), Vector2(-5, -10), Vector2(8, -8),
				Vector2(17, 0), Vector2(8, 8), Vector2(-5, 10),
				Vector2(-16, 5), Vector2(-8, 0),
			])
			_core.polygon = PackedVector2Array([
				Vector2(-7, -2), Vector2(8, 0), Vector2(-7, 2),
			])
			_halo.polygon = PackedVector2Array([
				Vector2(18, 0), Vector2(9, 8), Vector2(-6, 11), Vector2(-18, 5),
				Vector2(-18, -5), Vector2(-6, -11), Vector2(9, -8),
			])
			_halo_base_scale = Vector2(1.18, 0.86)
			_halo.scale = _halo_base_scale
			_trail.width = 4.5
		_:
			_visual.polygon = PackedVector2Array([
				Vector2(-12, -4), Vector2(6, -5), Vector2(16, 0),
				Vector2(6, 5), Vector2(-12, 4),
			])
			_core.polygon = PackedVector2Array([
				Vector2(-3, -2), Vector2(8, -2), Vector2(12, 0),
				Vector2(8, 2), Vector2(-3, 2),
			])
			_halo.polygon = PackedVector2Array([
				Vector2(16, 0), Vector2(11, 8), Vector2(0, 12), Vector2(-12, 8),
				Vector2(-16, 0), Vector2(-12, -8), Vector2(0, -12), Vector2(11, -8),
			])
			_halo_base_scale = Vector2(1.05, 0.82)
			_halo.scale = _halo_base_scale
			_trail.width = 4.0


func _on_lifetime_expired() -> void:
	if is_instance_valid(self):
		queue_free()
