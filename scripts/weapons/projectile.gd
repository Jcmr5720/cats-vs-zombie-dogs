extends Area2D
## Bala que viaja en línea recta, daña al primer enemigo que toca y se
## autodestruye al impactar o tras agotar su tiempo de vida.

@export var lifetime: float = 2.0
const MAX_PROJECTILES: int = 250

var _direction: Vector2 = Vector2.RIGHT
var _speed: float = 600.0
var _damage: int = 10


## Configura el proyectil al ser disparado por el arma.
func setup(direction: Vector2, speed: float, damage: int) -> void:
	_direction = direction.normalized()
	_speed = speed
	_damage = damage
	# Orienta el sprite hacia su trayectoria (la estela apunta +X local).
	rotation = _direction.angle()


func _ready() -> void:
	add_to_group("projectiles")
	set_collision_mask_value(5, true)  # detecta obstaculos solidos (capa 5)
	_enforce_projectile_cap()
	body_entered.connect(_on_body_entered)

	# Timer de vida: si no golpea nada, se destruye solo.
	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(_on_lifetime_expired)


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
	global_position += _direction * _speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("obstacles"):
		var blocks: bool = true
		if body.has_method("absorb_projectile"):
			blocks = body.absorb_projectile(_damage)
		if blocks:
			queue_free()
		return
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		# Pasa la dirección del disparo para que el enemigo reciba knockback.
		body.take_damage(_damage, _direction)
		queue_free()


func _on_lifetime_expired() -> void:
	# Puede haberse destruido ya por impacto.
	if is_instance_valid(self):
		queue_free()
