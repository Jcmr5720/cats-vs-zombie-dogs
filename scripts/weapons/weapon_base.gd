extends Node2D
## Instancia viva de un arma. Resuelve el comportamiento segun `data.weapon_type`,
## escala stats por nivel y aplica modificadores globales del jugador + sinergias
## con companeros (consultados al WeaponManager). Una sola clase data-driven cubre
## proyectil / explosivo / boomerang / laser / orbital / area.

const WeaponData = preload("res://scripts/weapons/weapon_data.gd")
const PROJECTILE_SCENE = preload("res://scenes/weapons/WeaponProjectile.tscn")
const ORBITAL_SCENE = preload("res://scenes/weapons/Orbital.tscn")
const AREA_SCENE = preload("res://scenes/weapons/CatnipArea.tscn")

## Topes de seguridad (Fase 04.5): evitan acumulacion de nodos/efectos que tiren
## FPS o vuelvan el juego trivial. Documentados en docs/FASE_04_5_*.
const MAX_ORBITALS: int = 4
const MIN_WEAPON_COOLDOWN: float = 0.12
## Radio maximo de explosiones/zonas para que un area no limpie toda la pantalla.
const MAX_AREA_RADIUS: float = 230.0

var data: WeaponData
var level: int = 1

var _manager: Node
var _player: Node2D
var _cooldown_timer: float = 0.0
var _orbitals: Array[Node2D] = []
var _laser_line: Line2D
var _laser_glow: Line2D


func setup(weapon_data: WeaponData, manager: Node, player: Node2D) -> void:
	data = weapon_data
	_manager = manager
	_player = player
	level = 1
	_cooldown_timer = randf() * 0.25  # desfase para que no disparen todas a la vez
	if data.weapon_type == &"orbital":
		_rebuild_orbitals()


func level_up() -> void:
	if data == null:
		return
	level = min(level + 1, data.max_level)
	if data.weapon_type == &"orbital":
		_rebuild_orbitals()


func is_max_level() -> bool:
	return data != null and level >= data.max_level


func _process(delta: float) -> void:
	if data == null or not is_instance_valid(_player):
		return
	if _player.has_method("is_dead") and _player.is_dead():
		return

	if data.weapon_type == &"orbital":
		_reconfigure_orbitals()
		return

	_cooldown_timer -= delta
	if _cooldown_timer > 0.0:
		return

	var fired: bool = false
	match data.weapon_type:
		&"laser":
			fired = _fire_laser()
		&"area":
			fired = _fire_area()
		_:
			fired = _fire_projectiles()

	if fired:
		_cooldown_timer = _effective_cooldown()


# --- Disparo por tipo -------------------------------------------------------

func _fire_projectiles() -> bool:
	var target: Node2D = _find_nearest_enemy(_effective_range())
	if target == null:
		return false

	var base_dir: Vector2 = _player.global_position.direction_to(target.global_position)
	var count: int = _effective_projectiles()
	var start_angle: float = -data.spread_degrees * float(count - 1) * 0.5
	var is_explosive: bool = data.weapon_type == &"explosive"
	var opts: Dictionary = {
		"speed": data.projectile_speed,
		"damage": _effective_damage(),
		"knockback": data.knockback,
		"pierce": _effective_pierce(),
		"explosion_radius": _effective_area() if is_explosive else 0.0,
		"lifetime": 2.0,
		"color": data.visual_color,
		"visual_scale": _projectile_visual_scale(),
		"weapon_type": data.weapon_type,
	}

	for index in count:
		var projectile := PROJECTILE_SCENE.instantiate() as Node2D
		if projectile == null:
			continue
		var angle_offset: float = deg_to_rad(start_angle + data.spread_degrees * float(index))
		projectile.global_position = _player.global_position
		get_tree().current_scene.add_child(projectile)
		projectile.call("setup", base_dir.rotated(angle_offset), opts)
		_muzzle_flash(base_dir.rotated(angle_offset), data.visual_color, is_explosive)
	_play_weapon_audio(&"shoot_strong" if is_explosive or data.weapon_type == &"boomerang" else &"shoot_basic")
	return true


func _fire_laser() -> bool:
	var target: Node2D = _find_nearest_enemy(_effective_range())
	if target == null:
		return false
	if target.has_method("take_damage"):
		var dir: Vector2 = _player.global_position.direction_to(target.global_position)
		target.take_damage(_effective_damage(), dir)
		Feedback.hit_effect(_player.global_position + dir * 34.0, data.visual_color, 0.18, 0.75)
	_show_laser(_player.global_position, target.global_position)
	Feedback.hit_effect(target.global_position, data.visual_color, 0.3, 1.2)
	_play_weapon_audio(&"laser")
	return true


func _fire_area() -> bool:
	var target: Node2D = _find_nearest_enemy(_effective_range() * 1.4)
	var spawn_position: Vector2 = _player.global_position
	if target != null:
		spawn_position = target.global_position
	elif _player.has_method("get_last_facing_direction"):
		spawn_position = _player.global_position + _player.get_last_facing_direction() * 120.0

	var area := AREA_SCENE.instantiate() as Node2D
	if area == null:
		return false
	area.global_position = spawn_position
	get_tree().current_scene.add_child(area)
	area.call("setup", _effective_damage(), _effective_area(), data.duration, data.tick_interval, data.visual_color)
	_play_weapon_audio(&"shoot_strong")
	return true


# --- Orbitales --------------------------------------------------------------

func _rebuild_orbitals() -> void:
	for orbital in _orbitals:
		if is_instance_valid(orbital):
			orbital.queue_free()
	_orbitals.clear()

	var count: int = _effective_orbital_count()
	for index in count:
		var orbital := ORBITAL_SCENE.instantiate() as Node2D
		if orbital == null:
			continue
		add_child(orbital)
		orbital.call("setup", _player, TAU * float(index) / float(count), data.visual_color)
		_orbitals.append(orbital)
	_reconfigure_orbitals()


func _reconfigure_orbitals() -> void:
	var radius: float = data.area_radius * (1.0 + 0.10 * float(level - 1))
	var angular_speed: float = 2.2 * (1.0 + 0.12 * float(level - 1))
	for orbital in _orbitals:
		if is_instance_valid(orbital) and orbital.has_method("configure"):
			orbital.configure(radius, angular_speed, _effective_damage(), data.tick_interval)


# --- Stats efectivos (nivel + globales + sinergias) -------------------------

func _effective_damage() -> int:
	var value: float = data.damage * (1.0 + 0.15 * float(level - 1))
	if data.scales_with_global_stats:
		value *= _manager.global_damage_mult()
	value *= _manager.synergy_damage_mult(data)
	return max(1, int(round(value)))


func _effective_cooldown() -> float:
	var value: float = data.cooldown * (1.0 - 0.06 * float(level - 1))
	if data.scales_with_global_stats:
		value *= _manager.global_cooldown_mult()
	value *= _manager.synergy_cooldown_mult()
	return max(MIN_WEAPON_COOLDOWN, value)


func _effective_range() -> float:
	var value: float = data.range * (1.0 + 0.05 * float(level - 1))
	if data.scales_with_global_stats:
		value *= _manager.global_range_mult()
	return value


func _effective_projectiles() -> int:
	var count: int = data.projectile_count
	if data.weapon_type == &"projectile" and level >= 4:
		count += 1
	if data.weapon_type == &"boomerang" and level >= 5:
		count += 1
	if data.scales_with_global_stats and data.weapon_type in [&"projectile", &"boomerang", &"explosive"]:
		count += _manager.global_extra_projectiles()
	return max(1, count)


func _effective_pierce() -> int:
	var value: int = data.pierce
	if data.weapon_type == &"boomerang":
		if level >= 3:
			value += 1
		if level >= 5:
			value += 1
	return value


func _effective_area() -> float:
	var value: float = data.area_radius * (1.0 + 0.18 * float(level - 1))
	value *= _manager.synergy_area_mult(data)
	return min(value, MAX_AREA_RADIUS)


func _effective_orbital_count() -> int:
	var count: int = max(1, data.projectile_count)
	if level >= 4:
		count += 1
	return min(count, MAX_ORBITALS)


func _projectile_visual_scale() -> float:
	match data.weapon_type:
		&"explosive":
			return 1.7
		&"boomerang":
			return 1.3
		_:
			return 1.0


# --- Utilidades -------------------------------------------------------------

func _find_nearest_enemy(max_range: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = max_range
	var origin: Vector2 = _player.global_position
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var distance: float = origin.distance_to((enemy as Node2D).global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _show_laser(from: Vector2, to: Vector2) -> void:
	if _laser_glow == null:
		_laser_glow = Line2D.new()
		_laser_glow.width = 14.0
		_laser_glow.top_level = true
		_laser_glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_laser_glow.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_laser_glow)
	if _laser_line == null:
		_laser_line = Line2D.new()
		_laser_line.width = 7.0
		_laser_line.top_level = true
		_laser_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_laser_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_laser_line)
	_laser_glow.default_color = Color(data.visual_color.r, data.visual_color.g, data.visual_color.b, 0.26)
	_laser_glow.points = PackedVector2Array([from, to])
	_laser_glow.modulate.a = 1.0
	_laser_glow.width = 14.0
	_laser_line.default_color = data.visual_color
	_laser_line.points = PackedVector2Array([from, to])
	_laser_line.modulate.a = 1.0
	_laser_line.width = 7.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_laser_glow, "modulate:a", 0.0, 0.24)
	tween.tween_property(_laser_glow, "width", 4.0, 0.24)
	tween.tween_property(_laser_line, "modulate:a", 0.0, 0.20)
	tween.tween_property(_laser_line, "width", 2.0, 0.20)


func _muzzle_flash(direction: Vector2, color: Color, strong: bool) -> void:
	if not is_instance_valid(_player):
		return
	var quality_scale: float = 1.0
	var fb: Node = get_node_or_null("/root/Feedback")
	if fb != null:
		if bool(fb.get("effects_intensity")) == false:
			quality_scale = 0.65
	Feedback.hit_effect(_player.global_position + direction.normalized() * 26.0, color.lightened(0.18), 0.10 * quality_scale, (0.58 if strong else 0.34) * quality_scale)


func get_snapshot() -> Dictionary:
	return {
		"id": data.id if data != null else &"",
		"display_name": data.display_name if data != null else "",
		"level": level,
		"max_level": data.max_level if data != null else 5,
		"weapon_type": data.weapon_type if data != null else &"",
		"color": data.visual_color if data != null else Color.WHITE,
	}


func _play_weapon_audio(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(name)


## Texto corto de lo que aporta SUBIR al siguiente nivel (para las cartas).
func next_level_description() -> String:
	var next: int = level + 1
	match data.weapon_type:
		&"projectile":
			return "+1 proyectil." if next == 4 else "Mas dano y cadencia."
		&"explosive":
			return "Explosion mayor." if next == 5 else "Mas area y dano."
		&"boomerang":
			if next == 3 or next == 5:
				return "Atraviesa mas enemigos."
			return "Mas dano y velocidad."
		&"laser":
			return "Mas rango." if next == 3 else "Mas dano y cadencia."
		&"orbital":
			return "+1 rascador." if next == 4 else "Mas dano, radio y giro."
		&"area":
			return "Zona mas grande y danina."
		_:
			return "Mejora el arma."
