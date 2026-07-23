extends Node2D
## Instancia viva de un arma. Resuelve el comportamiento segun `data.weapon_type`,
## escala stats por nivel y aplica modificadores globales del jugador + sinergias
## con companeros (consultados al WeaponManager). Una sola clase data-driven cubre
## proyectil / explosivo / boomerang / laser / orbital / area.

const WeaponData = preload("res://scripts/weapons/weapon_data.gd")
const Targeting = preload("res://scripts/weapons/targeting.gd")
const PROJECTILE_SCENE = preload("res://scenes/weapons/WeaponProjectile.tscn")
const ORBITAL_SCENE = preload("res://scenes/weapons/Orbital.tscn")
const AREA_SCENE = preload("res://scenes/weapons/CatnipArea.tscn")

## Topes de seguridad (Fase 04.5): evitan acumulacion de nodos/efectos que tiren
## FPS o vuelvan el juego trivial. Documentados en docs/FASE_04_5_*.
const MAX_ORBITALS: int = 6
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
	# Armas DIRECCIONALES (bala, explosivo, boomerang). Dos caminos bien separados:
	#
	#  - AUTOMATICO: el apuntado inteligente de siempre (Targeting): amenaza/marca en
	#    vez de "el mas cercano", fila alineada para el pierce, racimo para explosivos
	#    y tiro LIDERADO (intercept) para que los rapidos no esquiven las balas.
	#  - MANUAL / ASISTIDO: manda el jugador. La direccion viene ya resuelta del
	#    PlayerAimController (que en asistido incluye la correccion dentro del cono),
	#    asi que el arma NO vuelve a consultar enemigos: dispara donde le dicen. Con
	#    objetivo asistido se aplica el lead con la velocidad de bala de ESTA arma.
	var origin: Vector2 = _player.global_position
	var base_dir: Vector2 = Vector2.ZERO

	if _is_auto_aim():
		var candidates: Array[Dictionary] = Targeting.gather_candidates(
			get_tree().get_nodes_in_group("enemies"), origin, origin, _effective_range())
		if candidates.is_empty():
			return false
		match data.weapon_type:
			&"boomerang":
				# Direccion de la fila mas valiosa (el pierce quiere enemigos alineados).
				base_dir = Targeting.pick_pierce_direction(candidates, origin, origin)
			&"explosive":
				# Centroide del racimo mas valioso dentro del radio de explosion.
				var cluster: Vector2 = Targeting.pick_area_position(candidates, _effective_area(), origin)
				if cluster != Vector2.INF and cluster != origin:
					base_dir = origin.direction_to(cluster)
			_:
				var target: Dictionary = Targeting.pick_projectile_target(candidates, origin)
				if not target.is_empty():
					base_dir = Targeting.intercept_direction(
						origin, target["pos"], target["velocity"], data.projectile_speed)
		if base_dir == Vector2.ZERO:
			var fallback: Node2D = _find_nearest_enemy(_effective_range())
			if fallback == null:
				return false
			base_dir = origin.direction_to(fallback.global_position)
	else:
		base_dir = _aim_direction()
		# El boomerang no lidera (atraviesa una fila entera), el explosivo tampoco
		# (revienta en area): el lead solo tiene sentido para la bala directa.
		if data.weapon_type == &"projectile":
			var assist: Dictionary = _assist_target()
			if not assist.is_empty():
				base_dir = Targeting.intercept_direction(
					origin, assist["pos"], assist["velocity"], data.projectile_speed)

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
		_projectile_parent().add_child(projectile)
		projectile.call("setup", base_dir.rotated(angle_offset), opts)
		_muzzle_flash(base_dir.rotated(angle_offset), data.visual_color, is_explosive)
	_play_weapon_audio(&"shoot_strong" if is_explosive or data.weapon_type == &"boomerang" else &"shoot_basic")
	return true


## Medio grosor del haz del laser en punteria manual: un enemigo a menos de esto de
## la linea de tiro recibe el rayo. NO es asistencia (eso lo decide el cono del
## PlayerAimController): es el ancho fisico del haz.
const LASER_BEAM_HALF_WIDTH: float = 38.0
## Distancia maxima de cada salto del laser en cadena (evolucion Rayo Prisma).
const LASER_CHAIN_JUMP_RANGE: float = 260.0
## El dano decae por salto para que la cadena no multiplique el DPS sin costo.
const LASER_CHAIN_DAMAGE_FALLOFF: float = 0.8

func _fire_laser() -> bool:
	# El laser es el nuke single-target: prioriza elites/tanques/marcados en vez
	# de gastar el disparo en el cachorro mas cercano.
	var origin: Vector2 = _player.global_position
	var target: Node2D = null

	if _is_auto_aim():
		var candidates: Array[Dictionary] = Targeting.gather_candidates(
			get_tree().get_nodes_in_group("enemies"), origin, origin, _effective_range())
		var picked: Dictionary = Targeting.pick_laser_target(candidates, origin)
		target = picked.get("enemy") if not picked.is_empty() else _find_nearest_enemy(_effective_range())
		if target == null or not is_instance_valid(target):
			return false
	else:
		# El laser es HITSCAN: en manual no basta con una direccion, hay que saber a
		# quien alcanza el haz. Se toma el primer enemigo dentro del CORREDOR del
		# rayo (su grosor), no un cono de asistencia: el jugador apunta, el rayo pega
		# a lo que cruza. Con asistencia activa se respeta su objetivo.
		var assist: Dictionary = _assist_target()
		if not assist.is_empty():
			target = assist["enemy"]
		else:
			var beam: Array[Dictionary] = Targeting.gather_candidates(
				get_tree().get_nodes_in_group("enemies"), origin, origin, _effective_range())
			target = Targeting.pick_first_in_beam(beam, origin, _aim_direction(), LASER_BEAM_HALF_WIDTH)
		if target == null or not is_instance_valid(target):
			# Sin nadie en la linea: el haz se dibuja igual (sin daño), para que el
			# jugador vea que el arma obedece y no que se ha quedado muda.
			_show_laser_path(PackedVector2Array([origin, origin + _aim_direction() * _effective_range()]))
			_play_weapon_audio(&"laser")
			return true

	# Cadena: con `pierce > 0` (Rayo Prisma) el rayo salta hasta `pierce` enemigos
	# extra, cada salto al mas cercano del anterior, con dano decreciente.
	var points := PackedVector2Array([_player.global_position])
	var hit: Array[Node2D] = []
	var current: Node2D = target
	var damage: float = float(_effective_damage())
	var previous_position: Vector2 = _player.global_position
	for _jump in 1 + max(0, data.pierce):
		if current == null:
			break
		if current.has_method("take_damage"):
			var dir: Vector2 = previous_position.direction_to(current.global_position)
			current.take_damage(max(1, int(round(damage))), dir)
		points.append(current.global_position)
		hit.append(current)
		Feedback.hit_effect(current.global_position, data.visual_color, 0.3, 1.2)
		previous_position = current.global_position
		damage *= LASER_CHAIN_DAMAGE_FALLOFF
		current = _find_nearest_enemy_excluding(previous_position, LASER_CHAIN_JUMP_RANGE, hit)

	_show_laser_path(points)
	Feedback.hit_effect(_player.global_position + _player.global_position.direction_to(points[1]) * 34.0, data.visual_color, 0.18, 0.75)
	_play_weapon_audio(&"laser")
	return true


## Enemigo mas cercano a `origin` dentro de `max_range`, excluyendo los ya golpeados.
func _find_nearest_enemy_excluding(origin: Vector2, max_range: float, excluded: Array[Node2D]) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = max_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or excluded.has(enemy):
			continue
		var distance: float = origin.distance_to((enemy as Node2D).global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _fire_area() -> bool:
	# La zona cae en el CENTROIDE del racimo mas valioso (no encima de un enemigo
	## suelto). Sin candidatos conserva el fallback clasico: delante del jugador.
	# La zona (catnip) es un arma COLOCADA: no dispara en una direccion, elige un
	# PUNTO. En automatico ese punto es el centroide del racimo mas valioso; en
	# manual/asistido es donde apunta el jugador, recortado a su alcance.
	var origin: Vector2 = _player.global_position
	var max_area_range: float = _effective_range() * 1.4
	var spawn_position: Vector2 = Vector2.INF

	if _is_auto_aim():
		var candidates: Array[Dictionary] = Targeting.gather_candidates(
			get_tree().get_nodes_in_group("enemies"), origin, origin, max_area_range)
		spawn_position = Targeting.pick_area_position(candidates, _effective_area(), origin)
		if spawn_position == Vector2.INF:
			spawn_position = origin
			if _player.has_method("get_last_facing_direction"):
				spawn_position = origin + _player.get_last_facing_direction() * 120.0
	else:
		var to_aim: Vector2 = _aim_world_position() - origin
		spawn_position = origin + to_aim.limit_length(max_area_range)

	var area := AREA_SCENE.instantiate() as Node2D
	if area == null:
		return false
	area.global_position = spawn_position
	_projectile_parent().add_child(area)
	# Knockback negativo (Ovillo Agujero Negro): la zona ATRAE en vez de empujar.
	area.call("setup", _effective_damage(), _effective_area(), data.duration, data.tick_interval, data.visual_color, data.knockback < 0.0)
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

# --- Punteria del jugador (fachada) -------------------------------------------
# El arma NUNCA habla con el PlayerAimController: pregunta a su jugador. Asi no hay
# dependencia circular y un rig de test sin controlador sigue funcionando (responde
# "automatico", el comportamiento clasico). Companeros y torreta no pasan por aqui:
# conservan su propio auto-apuntado.

func _is_auto_aim() -> bool:
	if not is_instance_valid(_player) or not _player.has_method("is_auto_aim"):
		return true
	return _player.is_auto_aim()


func _aim_direction() -> Vector2:
	if is_instance_valid(_player) and _player.has_method("get_aim_direction"):
		var dir: Vector2 = _player.get_aim_direction()
		if dir != Vector2.ZERO:
			return dir.normalized()
	return Vector2.RIGHT


func _aim_world_position() -> Vector2:
	if is_instance_valid(_player) and _player.has_method("get_aim_world_position"):
		return _player.get_aim_world_position()
	return _player.global_position + _aim_direction() * 220.0


## Objetivo elegido por la ASISTENCIA (vacio en manual puro y en automatico).
func _assist_target() -> Dictionary:
	if is_instance_valid(_player) and _player.has_method("get_assist_target"):
		return _player.get_assist_target()
	return {}


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
	_show_laser_path(PackedVector2Array([from, to]))


## Dibuja el rayo como polilinea (soporta la cadena del Rayo Prisma sin nodos extra).
func _show_laser_path(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
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
	_laser_glow.points = points
	_laser_glow.modulate.a = 1.0
	_laser_glow.width = 14.0
	_laser_line.default_color = data.visual_color
	_laser_line.points = points
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
		# FASE 13: el HUD marca las armas evolucionadas y explica cada una en llano.
		"evolved": LootCatalog.is_evolved_weapon(data),
		"description": data.description if data != null else "",
	}


func _play_weapon_audio(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(name)


func _projectile_parent() -> Node:
	if get_tree() != null and get_tree().current_scene != null:
		return get_tree().current_scene
	if get_parent() != null:
		return get_parent()
	return get_tree().root


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
