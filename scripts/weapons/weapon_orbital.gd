extends Node2D
## Un "rascador" que gira alrededor del jugador y daña a los enemigos que toca,
## con cooldown de daño por enemigo para no vaciar la vida en un frame. La crea y
## parametriza WeaponBase (tipo orbital); varios comparten velocidad y radio,
## repartidos por `angle_offset` para quedar equidistantes.

@export var hit_radius: float = 20.0

var _player: Node2D
var _radius: float = 90.0
var _angular_speed: float = 2.2
var _damage: int = 5
var _hit_cooldown: float = 0.4
var _angle: float = 0.0
var _recent_hits: Dictionary = {}

@onready var _visual: Polygon2D = $Visual
@onready var _spark: Polygon2D = $Spark
@onready var _trail: Line2D = $Trail


func setup(player: Node2D, angle_offset: float, color: Color) -> void:
	_player = player
	_angle = angle_offset
	if not is_node_ready():
		await ready
	_visual.color = color
	_spark.color = color.lightened(0.35)
	_trail.default_color = Color(color.r, color.g, color.b, 0.28)


func configure(radius: float, angular_speed: float, damage: int, hit_cooldown: float) -> void:
	_radius = radius
	_angular_speed = angular_speed
	_damage = damage
	_hit_cooldown = hit_cooldown


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	_angle += _angular_speed * delta
	global_position = _player.global_position + Vector2.RIGHT.rotated(_angle) * _radius
	rotation = _angle + PI * 0.5
	if is_instance_valid(_visual):
		_visual.scale = Vector2.ONE * (1.0 + sin(_angle * 3.0) * 0.08)

	# Enfria los golpes recientes por enemigo.
	for key in _recent_hits.keys():
		_recent_hits[key] -= delta
		if _recent_hits[key] <= 0.0:
			_recent_hits.erase(key)

	_apply_contact_damage()


func _apply_contact_damage() -> void:
	var hit_radius_sq: float = hit_radius * hit_radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		var id: int = enemy.get_instance_id()
		if _recent_hits.has(id):
			continue
		var offset: Vector2 = (enemy as Node2D).global_position - global_position
		if offset.length_squared() <= hit_radius_sq:
			enemy.take_damage(_damage, offset.normalized())
			_play_audio(&"orbital_hit")
			_recent_hits[id] = _hit_cooldown


func _play_audio(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(name)
