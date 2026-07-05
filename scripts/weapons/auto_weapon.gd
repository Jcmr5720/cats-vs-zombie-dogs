extends Node2D
## Arma automática del gato. Cada cierto cooldown busca al enemigo más cercano
## dentro de su rango y dispara uno o varios proyectiles hacia él.

@export var damage: int = 10
@export var fire_cooldown: float = 0.45
@export var attack_range: float = 500.0
@export var projectile_speed: float = 600.0
@export var projectile_scene: PackedScene
@export var projectile_count: int = 1
@export var projectile_spread_degrees: float = 10.0

# Topes sanos para que los upgrades acumulados no rompan el balance (Fase 2.8).
const MIN_COOLDOWN: float = 0.15
const MAX_RANGE: float = 850.0
const MAX_PROJECTILES: int = 5

var _cooldown_timer: float = 0.0
var _external_damage_multiplier: float = 1.0


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		return

	var target: Node2D = _find_nearest_enemy()
	if target != null:
		_fire_at(target)
		_cooldown_timer = fire_cooldown


## Busca el enemigo vivo más cercano dentro del rango. Devuelve null si no hay.
func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = attack_range

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = enemy

	return nearest


func multiply_damage(multiplier: float) -> void:
	damage = max(1, int(round(damage * multiplier)))


func multiply_cooldown(multiplier: float) -> void:
	# Tope mínimo para evitar una cadencia rota acumulando upgrades.
	fire_cooldown = clampf(fire_cooldown * multiplier, MIN_COOLDOWN, 5.0)


func multiply_range(multiplier: float) -> void:
	attack_range = clampf(attack_range * multiplier, 32.0, MAX_RANGE)


func add_projectiles(amount: int) -> void:
	projectile_count = clampi(projectile_count + amount, 1, MAX_PROJECTILES)


func set_external_damage_multiplier(multiplier: float) -> void:
	_external_damage_multiplier = max(0.1, multiplier)


func _fire_at(target: Node2D) -> void:
	if projectile_scene == null:
		return

	var base_direction: Vector2 = global_position.direction_to(target.global_position)
	var total_projectiles: int = max(projectile_count, 1)
	var start_angle: float = -projectile_spread_degrees * float(total_projectiles - 1) * 0.5

	for index in total_projectiles:
		var projectile := projectile_scene.instantiate() as Node2D
		var angle_offset: float = deg_to_rad(start_angle + projectile_spread_degrees * float(index))
		if projectile == null:
			continue
		projectile.global_position = global_position
		var final_damage: int = max(1, int(round(damage * _external_damage_multiplier)))
		projectile.call("setup", base_direction.rotated(angle_offset), projectile_speed, final_damage)
		# El proyectil vive en el nivel para no depender del jugador/arma.
		get_tree().current_scene.add_child(projectile)
