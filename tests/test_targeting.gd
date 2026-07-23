extends Node2D
## Pruebas del auto-apuntado inteligente (scripts/weapons/targeting.gd).
## Se ejecuta como ESCENA para contar con autoloads reales:
##   godot --headless --path . res://tests/TestTargeting.tscn
## El helper es puro (recibe listas), asi que casi todo se valida de forma
## sincrona con enemigos stub de posicion/velocidad/vida conocidas.

const Targeting = preload("res://scripts/weapons/targeting.gd")

var _failures: Array[String] = []
var _checks: int = 0


## Enemigo stub: CharacterBody2D con los campos que lee gather_candidates.
class StubEnemy:
	extends CharacterBody2D
	var current_health: int = 20
	var _elite_kind: StringName = &""

	func _init(pos: Vector2, vel: Vector2 = Vector2.ZERO, hp: int = 20) -> void:
		global_position = pos
		velocity = vel
		current_health = hp
		add_to_group("enemies")

	func take_damage(_a: int, _d: Vector2 = Vector2.ZERO) -> void:
		pass


## Jugador stub minimo para montar un WeaponManager real.
class StubPlayer:
	extends CharacterBody2D
	var player_id: int = 1

	func _init() -> void:
		add_to_group("players")
		add_to_group("player")

	func is_dead() -> bool:
		return false

	func get_last_facing_direction() -> Vector2:
		return Vector2.RIGHT


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		print("FALLO: ", label)


func _make(pos: Vector2, vel: Vector2 = Vector2.ZERO, hp: int = 20) -> StubEnemy:
	var e := StubEnemy.new(pos, vel, hp)
	add_child(e)
	e.set_physics_process(false)  # estaticos: solo importan sus datos
	return e


func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.remove_from_group("enemies")
		e.queue_free()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().physics_frame
	var origin := Vector2.ZERO

	# --- 1) Peligro: el que se acerca al jugador gana sobre el rezagado quieto ---
	var idle := _make(Vector2(-60, 0))                      # mas cercano, quieto, detras
	var threat := _make(Vector2(100, 0), Vector2(-90, 0))   # mas lejos, viniendo hacia ti
	var cands := Targeting.gather_candidates(get_tree().get_nodes_in_group("enemies"), origin, origin, 500.0)
	_check(cands.size() == 2, "gather encuentra 2 candidatos")
	var picked: Dictionary = Targeting.pick_projectile_target(cands, origin)
	_check(picked.get("enemy") == threat, "prioriza la amenaza que se acerca sobre el quieto cercano")
	_clear()
	await get_tree().physics_frame

	# --- 2) Marca del policia desempata --------------------------------------------
	var plain := _make(Vector2(100, 0))
	var marked := _make(Vector2(110, 0))
	marked.set_meta(&"companion_mark", true)
	cands = Targeting.gather_candidates(get_tree().get_nodes_in_group("enemies"), origin, origin, 500.0)
	picked = Targeting.pick_projectile_target(cands, origin)
	_check(picked.get("enemy") == marked, "la marca del policia desempata a distancia similar")
	_check(is_instance_valid(plain), "stub valido (sanidad)")
	_clear()
	await get_tree().physics_frame

	# --- 3) Laser: prefiere el tanque de 85 HP sobre el cachorro de 6 --------------
	var pup := _make(Vector2(80, 0), Vector2.ZERO, 6)
	var tank := _make(Vector2(160, 0), Vector2.ZERO, 85)
	cands = Targeting.gather_candidates(get_tree().get_nodes_in_group("enemies"), origin, origin, 620.0)
	picked = Targeting.pick_laser_target(cands, origin)
	_check(picked.get("enemy") == tank, "el laser prefiere el tanque sobre el cachorro")
	# Y un elite del mismo HP gana al no-elite.
	var elite := _make(Vector2(200, 0), Vector2.ZERO, 85)
	elite._elite_kind = &"blindado"
	cands = Targeting.gather_candidates(get_tree().get_nodes_in_group("enemies"), origin, origin, 620.0)
	picked = Targeting.pick_laser_target(cands, origin)
	_check(picked.get("enemy") == elite, "el laser prefiere al elite")
	_check(is_instance_valid(pup), "stub valido (sanidad)")
	_clear()
	await get_tree().physics_frame

	# --- 4) Boomerang: elige la fila de 4 alineados sobre el cercano aislado -------
	_make(Vector2(0, -70))  # aislado, mas cercano
	for i in 4:
		_make(Vector2(100 + i * 60, 0))  # fila a la derecha
	cands = Targeting.gather_candidates(get_tree().get_nodes_in_group("enemies"), origin, origin, 520.0)
	var dir: Vector2 = Targeting.pick_pierce_direction(cands, origin, origin)
	_check(dir.x > 0.9 and absf(dir.y) < 0.3, "el pierce apunta a la fila alineada (dir=%s)" % dir)
	_clear()
	await get_tree().physics_frame

	# --- 5) Explosivo/zona: racimo de 5 sobre el solitario cercano, en el centroide -
	_make(Vector2(60, 0))  # solitario cercano
	var cluster_positions: Array[Vector2] = []
	for i in 5:
		var pos := Vector2(220 + (i % 3) * 30, -40 + (i / 3) * 30)
		cluster_positions.append(pos)
		_make(pos)
	cands = Targeting.gather_candidates(get_tree().get_nodes_in_group("enemies"), origin, origin, 500.0)
	var area_pos: Vector2 = Targeting.pick_area_position(cands, 90.0, origin)
	var centroid := Vector2.ZERO
	for p in cluster_positions:
		centroid += p
	centroid /= float(cluster_positions.size())
	_check(area_pos.distance_to(centroid) < 40.0,
		"la zona cae en el centroide del racimo (a %.0f px)" % area_pos.distance_to(centroid))
	_clear()
	await get_tree().physics_frame

	# --- 6) Intercept: blanco cruzando en perpendicular -----------------------------
	# Blanco en (300,0) moviendose hacia abajo a 150; bala a 600. El tiro debe
	# inclinarse hacia +Y (a donde VA), no directo a la posicion actual.
	var lead_dir: Vector2 = Targeting.intercept_direction(origin, Vector2(300, 0), Vector2(0, 150), 600.0)
	_check(lead_dir.y > 0.05, "el intercept lidera hacia el movimiento (y=%.3f)" % lead_dir.y)
	# La lateral esta amortiguada: el angulo debe ser MENOR que el intercept pleno.
	var full_t: float = 300.0 / 600.0  # aprox
	var full_dir: Vector2 = (Vector2(300, 0) + Vector2(0, 150) * full_t).normalized()
	_check(lead_dir.y < full_dir.y, "la componente lateral esta amortiguada")
	# Sin solucion (blanco mas rapido que la bala alejandose): tiro directo.
	var direct: Vector2 = Targeting.intercept_direction(origin, Vector2(300, 0), Vector2(900, 0), 400.0)
	_check(absf(direct.angle_to(Vector2.RIGHT)) < 0.01, "sin solucion de intercept, tiro directo")
	# Blanco quieto: tiro directo exacto.
	var still: Vector2 = Targeting.intercept_direction(origin, Vector2(0, 200), Vector2.ZERO, 600.0)
	_check(still.is_equal_approx(Vector2.DOWN), "blanco quieto = tiro directo")

	# --- 7) Torreta: la marca gana SIEMPRE (sinergia Policia + Ingeniero) ----------
	var turret := Node2D.new()
	turret.set_script(load("res://scripts/companions/companion_turret.gd"))
	add_child(turret)
	turret.global_position = origin
	var big := _make(Vector2(90, 0), Vector2.ZERO, 200)
	big._elite_kind = &"gigante"
	var marked_far := _make(Vector2(300, 0), Vector2.ZERO, 10)
	marked_far.set_meta(&"companion_mark", true)
	var turret_target: Node2D = turret._pick_target()
	_check(turret_target == marked_far, "la torreta prefiere al marcado sobre el elite gordo")
	turret.queue_free()
	_clear()
	await get_tree().physics_frame

	# --- 8) Humo integrado: un arma real dispara con el nuevo apuntado -------------
	var player := StubPlayer.new()
	add_child(player)
	player.global_position = origin
	var wm := Node2D.new()
	wm.set_script(load("res://scripts/weapons/weapon_manager.gd"))
	player.add_child(wm)
	var runner := _make(Vector2(250, 0), Vector2(0, 150), 500)
	await get_tree().physics_frame
	var pistol: Node2D = wm.get_weapon(&"cat_pistol")
	_check(pistol != null, "arma inicial montada")
	var fired: bool = pistol.call("_fire_projectiles")
	_check(fired, "el arma dispara con el nuevo apuntado")
	await get_tree().physics_frame
	var projectiles: Array = get_tree().get_nodes_in_group("projectiles")
	_check(projectiles.size() > 0, "hay proyectil en vuelo")
	if projectiles.size() > 0:
		var p: Node2D = projectiles[0]
		var proj_dir: Vector2 = Vector2.RIGHT.rotated(p.rotation)
		_check(proj_dir.y > 0.02, "el proyectil real sale liderado hacia el movimiento del runner")
	_check(is_instance_valid(runner), "stub valido (sanidad)")

	# Se retira el jugador automatico antes de las pruebas de punteria manual, para
	# que su pistola no siga disparando y ensuciando el grupo "projectiles".
	player.queue_free()
	_clear()
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()
	await get_tree().physics_frame

	# --- 9) Cono de asistencia: solo entran los enemigos dentro del angulo ----------
	var front := _make(Vector2(200, 0))                # 0 grados: dentro
	var edge := _make(Vector2(200, 60))                # ~17 grados: dentro
	var side := _make(Vector2(200, 200))               # 45 grados: fuera
	var behind := _make(Vector2(-200, 0))              # 180 grados: fuera
	cands = Targeting.gather_candidates(get_tree().get_nodes_in_group("enemies"), origin, origin, 600.0)
	var cone: Array[Dictionary] = Targeting.filter_cone(cands, origin, Vector2.RIGHT, 22.0)
	var cone_enemies: Array = []
	for c in cone:
		cone_enemies.append(c["enemy"])
	_check(cone_enemies.has(front) and cone_enemies.has(edge), "el cono conserva lo que esta al frente")
	_check(not cone_enemies.has(side) and not cone_enemies.has(behind), "el cono descarta los laterales y la espalda")
	_check(cone.size() == 2, "el cono deja exactamente 2 candidatos (%d)" % cone.size())
	_check(cone.size() < 2 or float(cone[0]["dist_sq"]) <= float(cone[1]["dist_sq"]),
		"el cono conserva el orden por distancia")
	# El angulo es un PARAMETRO: uno mas ancho admite al lateral de 45 grados.
	_check(Targeting.filter_cone(cands, origin, Vector2.RIGHT, 50.0).size() == 3,
		"el medio angulo del cono es configurable (50 grados admite el lateral)")
	# Un cono de 0 grados (asistencia "off") no deja pasar nada lateral.
	_check(Targeting.filter_cone(cands, origin, Vector2.RIGHT, 0.0).size() <= 1,
		"con asistencia off el cono no admite correccion lateral")
	# Con mira nula no hay nada que recortar.
	_check(Targeting.filter_cone(cands, origin, Vector2.ZERO, 22.0).size() == cands.size(),
		"sin direccion de mira el cono no filtra")
	_clear()
	await get_tree().physics_frame

	# --- 10) Haz del laser: el primero que cruza la linea, nunca el de la espalda ---
	var far_in_line := _make(Vector2(400, 10))
	var near_in_line := _make(Vector2(180, -12))
	var off_line := _make(Vector2(200, 300))
	var back_in_line := _make(Vector2(-150, 0))
	cands = Targeting.gather_candidates(get_tree().get_nodes_in_group("enemies"), origin, origin, 700.0)
	var beam_hit: Node2D = Targeting.pick_first_in_beam(cands, origin, Vector2.RIGHT, 38.0)
	_check(beam_hit == near_in_line, "el haz alcanza al primero de la linea, no al de mas atras")
	_check(is_instance_valid(far_in_line) and is_instance_valid(off_line), "stubs validos (sanidad)")
	# Apuntando a la espalda alcanza al de atras, no a los de delante.
	beam_hit = Targeting.pick_first_in_beam(cands, origin, Vector2.LEFT, 38.0)
	_check(beam_hit == back_in_line, "apuntando atras el haz alcanza al de atras")
	# Nadie en la linea (hacia abajo): sin impacto.
	beam_hit = Targeting.pick_first_in_beam(cands, origin, Vector2.DOWN, 38.0)
	_check(beam_hit == null, "sin nadie en la linea el haz no alcanza a ninguno")
	_clear()
	await get_tree().physics_frame

	# --- Resultado -------------------------------------------------------------------
	print("test_targeting: %d checks, %d fallos" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("test_targeting: OK")
	else:
		for f in _failures:
			print("  - ", f)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0 if _failures.is_empty() else 1)
