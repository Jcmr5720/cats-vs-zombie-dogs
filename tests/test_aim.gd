extends Node2D
## Pruebas del sistema de punteria por jugador (PlayerAimController + armas).
## Se ejecuta como ESCENA para tener autoloads reales (Settings, Feedback, ...):
##   godot --headless --path . res://tests/TestAim.tscn
##
## Lo que NO se puede probar aqui (headless no tiene raton ni mandos): la lectura
## real del cursor, del stick y la pantalla dividida. De esas partes se prueba la
## REGLA PURA (zona muerta, conversion de coordenadas) y queda la lista de pruebas
## manuales en docs/COOP.md.

const PlayerScene := preload("res://scenes/player/Player.tscn")
const AimController := preload("res://scripts/player/player_aim_controller.gd")
const SplitScreen := preload("res://scripts/systems/coop_split_screen.gd")

var _failures: Array[String] = []
var _checks: int = 0
var _reported: bool = false


## Enemigo stub con lo que lee gather_candidates.
class StubEnemy:
	extends CharacterBody2D
	var current_health: int = 40
	var _elite_kind: StringName = &""

	func _init(pos: Vector2) -> void:
		global_position = pos
		add_to_group("enemies")

	func take_damage(_a: int, _d: Vector2 = Vector2.ZERO) -> void:
		pass


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		print("FALLO: ", label)


func _make_enemy(pos: Vector2) -> StubEnemy:
	var e := StubEnemy.new(pos)
	add_child(e)
	e.set_physics_process(false)
	return e


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.remove_from_group("enemies")
		e.queue_free()


func _clear_projectiles() -> void:
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()


## Direccion del ultimo proyectil disparado (o Vector2.ZERO si no hay ninguno).
func _last_projectile_direction() -> Vector2:
	var projectiles: Array = get_tree().get_nodes_in_group("projectiles")
	if projectiles.is_empty():
		return Vector2.ZERO
	return Vector2.RIGHT.rotated((projectiles[0] as Node2D).rotation)


## Monta un jugador REAL (Player.tscn, con su PlayerAimController y WeaponManager).
func _spawn_player(player_id: int, position: Vector2) -> Node2D:
	var player := PlayerScene.instantiate() as Node2D
	player.set("player_id", player_id)
	add_child(player)
	player.global_position = position
	return player


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	var settings: Node = get_node_or_null("/root/Settings")

	# --- 1) Ajustes por jugador: independientes, con manual por defecto -----------
	_check(settings != null, "el autoload Settings existe")
	if settings != null:
		var defaults: Dictionary = settings.defaults()
		_check(str(defaults.get("player_1_aim_mode", "")) == "manual",
			"el modo por defecto del J1 es manual")
		_check(str(defaults.get("player_2_aim_mode", "")) == "manual",
			"el modo por defecto del J2 es manual")
		_check(str(defaults.get("player_1_aim_device", "")) == "auto",
			"el dispositivo por defecto se autodetecta (no esta atado al jugador)")
		# Guardado/carga independiente: cambiar el J1 no toca al J2.
		settings.set_value("player_1_aim_mode", "auto")
		settings.set_value("player_2_aim_mode", "assist")
		_check(str(settings.get_value("player_1_aim_mode", "")) == "auto",
			"el modo del J1 se guarda")
		_check(str(settings.get_value("player_2_aim_mode", "")) == "assist",
			"el modo del J2 se guarda y NO lo pisa el del J1")
		settings.set_value("player_1_aim_mode", "manual")
		settings.set_value("player_2_aim_mode", "manual")
		_check(str(settings.get_value("player_2_aim_mode", "")) == "manual",
			"volver a manual el J2 no altera nada mas")

	# --- 2) Zona muerta del stick (regla pura, sin mando) -------------------------
	var last := Vector2.UP
	_check(AimController.stick_direction(Vector2(0.05, 0.03), last, 0.22) == last,
		"el ruido del stick NO reapunta: conserva la ultima direccion")
	_check(AimController.stick_direction(Vector2.ZERO, last, 0.22) == last,
		"soltar el stick conserva la ultima direccion (sin temblor al centrar)")
	var pushed: Vector2 = AimController.stick_direction(Vector2(0.9, 0.0), last, 0.22)
	_check(pushed.is_equal_approx(Vector2.RIGHT), "el stick por encima del umbral sí apunta")
	_check(absf(AimController.stick_direction(Vector2(0.3, 0.4), last, 0.22).length() - 1.0) < 0.001,
		"la direccion del stick sale normalizada")
	# Justo por debajo del umbral: sigue conservando (frontera).
	_check(AimController.stick_direction(Vector2(0.21, 0.0), last, 0.22) == last,
		"justo por debajo de la zona muerta se conserva la direccion")

	# --- 3) Un jugador REAL con punteria manual -----------------------------------
	var p1 := _spawn_player(1, Vector2.ZERO)
	await get_tree().physics_frame
	await get_tree().process_frame
	var aim1: Node = p1.get_node_or_null("PlayerAimController")
	_check(aim1 != null, "el jugador monta su PlayerAimController")
	_check(p1.is_manual_aim(), "el jugador arranca en manual (defecto del juego)")
	var wm1: Node = p1.get_weapon_manager()
	var pistol1: Node2D = wm1.get_weapon(&"cat_pistol")
	_check(pistol1 != null, "arma inicial montada")

	# 3a) Manual SIN enemigos: dispara recto hacia la mira.
	aim1.set_device(&"keyboard")
	aim1.set("_aim_direction", Vector2.UP)
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame
	_check(bool(pistol1.call("_fire_projectiles")), "manual dispara aunque no haya enemigos")
	await get_tree().physics_frame
	_check(_last_projectile_direction().dot(Vector2.UP) > 0.95,
		"manual sin enemigos: la bala sale por la mira (%s)" % _last_projectile_direction())

	# 3b) Manual CON un enemigo fuera de la direccion: NO gira hacia el.
	_clear_projectiles()
	var flank := _make_enemy(Vector2(220, 0))  # a 90 grados de la mira (arriba)
	await get_tree().physics_frame
	pistol1.call("_fire_projectiles")
	await get_tree().physics_frame
	_check(_last_projectile_direction().dot(Vector2.UP) > 0.95,
		"manual NO gira hacia un enemigo fuera de la direccion elegida")
	_check(is_instance_valid(flank), "stub valido (sanidad)")

	# 3c) Manual con un enemigo JUSTO en la mira: sigue siendo la mira (sin lead).
	_clear_enemies()
	_clear_projectiles()
	_make_enemy(Vector2(0, -240))
	await get_tree().physics_frame
	pistol1.call("_fire_projectiles")
	await get_tree().physics_frame
	_check(_last_projectile_direction().dot(Vector2.UP) > 0.99,
		"manual puro no aplica correccion aunque el enemigo este delante")

	# --- 4) Asistido: corrige DENTRO del cono y respeta la mira fuera de el --------
	aim1.set_mode(&"assist")
	_check(p1.is_assisted_aim(), "el modo asistido queda activo")

	# 4a) Enemigo dentro del cono (~9 grados): la direccion final se corrige hacia el.
	_clear_enemies()
	_clear_projectiles()
	var inside := _make_enemy(Vector2(40, -250))
	aim1.set("_aim_direction", Vector2.UP)
	aim1.call("_refresh_assist")
	var assisted: Dictionary = p1.get_assist_target()
	_check(not assisted.is_empty(), "la asistencia engancha al enemigo dentro del cono")
	_check(assisted.get("enemy") == inside, "engancha al enemigo correcto")
	var assist_dir: Vector2 = p1.get_aim_direction()
	_check(assist_dir.x > 0.05 and assist_dir.y < 0.0,
		"la direccion final se corrige hacia el enemigo del cono (%s)" % assist_dir)
	_check(assist_dir.dot(Vector2.UP) > 0.9, "la correccion es LEVE: sigue siendo la mira del jugador")

	# 4b) Enemigo claramente FUERA del cono: la asistencia no lo toca.
	_clear_enemies()
	_make_enemy(Vector2(300, 0))  # 90 grados respecto a la mira (arriba)
	aim1.set("_aim_direction", Vector2.UP)
	aim1.set("_assist_target", {})
	aim1.set("_assist_locked", false)
	aim1.call("_refresh_assist")
	_check(p1.get_assist_target().is_empty(),
		"la asistencia NO engancha a un enemigo fuera del cono")
	_check(p1.get_aim_direction().dot(Vector2.UP) > 0.99,
		"sin objetivo valido, asistido conserva la direccion del jugador")

	# 4c) Enemigo a la ESPALDA: jamas se gira la mira hacia atras.
	_clear_enemies()
	_make_enemy(Vector2(0, 260))  # justo detras de una mira hacia arriba
	aim1.set("_assist_target", {})
	aim1.set("_assist_locked", false)
	aim1.call("_refresh_assist")
	_check(p1.get_assist_target().is_empty(), "la asistencia nunca engancha a la espalda")
	_check(p1.get_aim_direction().dot(Vector2.UP) > 0.99, "la mira no se gira hacia atras")

	# 4d) Histeresis: con dos enemigos pegados, el objetivo enganchado se conserva.
	_clear_enemies()
	var stable_a := _make_enemy(Vector2(20, -250))
	var stable_b := _make_enemy(Vector2(-20, -252))
	aim1.set("_aim_direction", Vector2.UP)
	aim1.set("_assist_target", {})
	aim1.set("_assist_locked", false)
	aim1.call("_refresh_assist")
	var first_target = p1.get_assist_target().get("enemy")
	_check(first_target != null, "la asistencia elige uno de los dos enemigos pegados")
	for _i in 5:
		aim1.call("_refresh_assist")
	_check(p1.get_assist_target().get("enemy") == first_target,
		"histeresis: la asistencia NO salta entre dos enemigos pegados")
	_check(is_instance_valid(stable_a) and is_instance_valid(stable_b), "stubs validos (sanidad)")

	# 4e) Asistencia "off" (cono 0): el modo asistido se comporta como manual.
	aim1.set("_assist_cone_degrees", 0.0)
	aim1.set("_assist_target", {})
	aim1.set("_assist_locked", false)
	aim1.call("_refresh_assist")
	_check(p1.get_assist_target().is_empty(), "con asistencia off no hay correccion")
	aim1.set("_assist_cone_degrees", 24.0)

	# --- 5) Automatico: el comportamiento clasico sigue intacto -------------------
	aim1.set_mode(&"auto")
	_check(p1.is_auto_aim(), "el modo automatico queda activo")
	_clear_enemies()
	_clear_projectiles()
	_make_enemy(Vector2(260, 0))            # el unico enemigo: a la derecha
	aim1.set("_aim_direction", Vector2.UP)  # la mira apunta a otro lado a proposito
	await get_tree().physics_frame
	pistol1.call("_fire_projectiles")
	await get_tree().physics_frame
	_check(_last_projectile_direction().dot(Vector2.RIGHT) > 0.9,
		"automatico ignora la mira y busca al enemigo, como siempre (%s)" % _last_projectile_direction())
	# Sin enemigos, el automatico NO dispara (comportamiento historico).
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame
	_check(not bool(pistol1.call("_fire_projectiles")),
		"automatico sin enemigos no dispara (comportamiento historico)")
	# La reticula no se dibuja en automatico.
	await get_tree().process_frame
	_check(not bool(aim1.get("visible")), "en automatico no hay reticula")

	# --- 6) Dos jugadores: modos y dispositivos INDEPENDIENTES --------------------
	var p2 := _spawn_player(2, Vector2(600, 0))
	await get_tree().physics_frame
	await get_tree().process_frame
	var aim2: Node = p2.get_node_or_null("PlayerAimController")
	_check(aim2 != null, "el segundo jugador monta su propio controlador")
	aim1.set_mode(&"manual")
	aim2.set_mode(&"auto")
	_check(p1.is_manual_aim() and p2.is_auto_aim(),
		"cada jugador tiene SU modo (J1 manual, J2 automatico)")
	aim1.set_mode(&"assist")
	_check(p2.is_auto_aim(), "cambiar el modo del J1 no modifica el del J2")
	aim2.set_mode(&"manual")
	_check(p1.is_assisted_aim(), "cambiar el modo del J2 no modifica el del J1")

	# Dispositivos: nada esta atado al numero de jugador.
	aim1.set_device(&"gamepad", 0)
	aim2.set_device(&"gamepad", 1)
	_check(aim1.get_pad_device() == 0 and aim2.get_pad_device() == 1,
		"dos mandos: cada jugador lee SU device id")
	aim1.set_device(&"gamepad", 0)
	aim2.set_device(&"mouse")
	_check(aim1.get_device() == &"gamepad" and aim2.get_device() == &"mouse",
		"J1 con mando y J2 con raton es una combinacion valida (sin reglas rigidas)")
	aim1.set_device(&"keyboard")
	aim2.set_device(&"keyboard")
	_check(aim1.get_device() == &"keyboard" and aim2.get_device() == &"keyboard",
		"dos jugadores en teclado es una combinacion valida")

	# El raton no se lo pueden quedar dos: _claim_mouse respeta a quien ya lo tiene.
	aim2.set_device(&"mouse")
	aim1.set_device(&"keyboard")
	aim1.call("_claim_mouse")
	_check(aim1.get_device() != &"mouse", "el raton no se le quita a quien ya lo esta usando")

	# Reticulas separadas por capa de visibilidad (nunca duplicadas en el split).
	_check(AimController.reticle_visibility_layer(1) != AimController.reticle_visibility_layer(2),
		"cada jugador dibuja su reticula en una capa distinta")

	# --- 7) Conversion pantalla -> mundo del split (regla pura, sin raton real) ----
	# El split vive dentro de un CanvasLayer (como en el juego, colgado del HUD):
	# solo asi sus anclajes resuelven contra el tamaño real del viewport.
	var layer := CanvasLayer.new()
	add_child(layer)
	var split := Control.new()
	split.set_script(SplitScreen)
	layer.add_child(split)
	split.call("setup", [p1, p2], null)
	# Los SubViewport necesitan un par de frames para adoptar su tamaño definitivo.
	for _f in 4:
		await get_tree().process_frame
	var world_point := Vector2(1234.0, -567.0)
	# Guarda anti-vacio: si las mitades no tuvieran tamaño real, las conversiones de
	# abajo devolverian la entrada sin tocarla y "pasarian" sin probar nada.
	_check(split.half_rect(0).size.x > 1.0 and split.half_rect(1).size.x > 1.0,
		"las dos mitades tienen tamaño real (%s / %s)" % [split.half_rect(0).size, split.half_rect(1).size])
	_check(not split.half_rect(0).has_point(split.half_rect(1).get_center()),
		"las mitades no se solapan")
	for index in 2:
		var screen: Vector2 = split.call("world_to_screen", index, world_point)
		var back: Vector2 = split.screen_to_world(index, screen)
		_check(back.distance_to(world_point) < 1.0,
			"mitad %d: pantalla<->mundo es reversible (error %.2f px)" % [index + 1, back.distance_to(world_point)])
		_check(split.contains_point(index, screen) or not split.half_rect(index).has_point(screen),
			"mitad %d: contains_point coincide con su rectangulo" % [index + 1])
	# Un punto de la mitad del J2 NO se considera dentro de la del J1.
	var r2: Rect2 = split.half_rect(1)
	if r2.size.x > 0.0:
		var inside_p2: Vector2 = r2.position + r2.size * 0.5
		_check(not split.contains_point(0, inside_p2),
			"un punto de la mitad del J2 no pertenece a la del J1")
		_check(split.contains_point(1, inside_p2), "y sí pertenece a la del J2")
	layer.queue_free()

	# --- 8) Armas NO direccionales: la orbital ignora la mira ---------------------
	_clear_enemies()
	aim1.set_mode(&"manual")
	aim1.set("_aim_direction", Vector2.UP)
	var orbital_data: Resource = load("res://data/weapons/spin_scratcher.tres")
	_check(bool(wm1.add_weapon(orbital_data)), "arma orbital añadida")
	await get_tree().process_frame
	await get_tree().process_frame
	var orbital: Node2D = wm1.get_weapon(&"spin_scratcher")
	_check(orbital != null, "la orbital vive en el inventario")
	if orbital != null:
		var orbitals: Array = orbital.get("_orbitals")
		_check(orbitals != null and orbitals.size() > 0, "la orbital genera sus rascadores")
		# Girar la mira 180 grados no debe mover los orbitales (no dependen de ella).
		var before: Array[Vector2] = []
		for o in orbitals:
			before.append((o as Node2D).global_position)
		aim1.set("_aim_direction", Vector2.DOWN)
		await get_tree().process_frame
		var moved_by_aim: bool = false
		for i in orbitals.size():
			# Giran solos (por tiempo), pero su distancia al gato no cambia por la mira.
			var radius_before: float = before[i].distance_to(p1.global_position)
			var radius_now: float = (orbitals[i] as Node2D).global_position.distance_to(p1.global_position)
			if absf(radius_before - radius_now) > 6.0:
				moved_by_aim = true
		_check(not moved_by_aim, "la orbital NO depende de la mira (radio estable al girarla)")

	# --- 9) Companeros: conservan SU auto-apuntado --------------------------------
	_clear_enemies()
	var turret := Node2D.new()
	turret.set_script(load("res://scripts/companions/companion_turret.gd"))
	add_child(turret)
	turret.global_position = p1.global_position
	# Enemigo a la derecha, mira del jugador hacia arriba: la torreta debe elegir al
	# enemigo (su propia logica), no seguir la mira del jugador.
	var turret_prey := _make_enemy(Vector2(200, 0))
	aim1.set("_aim_direction", Vector2.UP)
	await get_tree().physics_frame
	var turret_target = turret.call("_pick_target")
	_check(turret_target == turret_prey,
		"el companero conserva su auto-apuntado y no copia la mira del jugador")
	turret.queue_free()

	# --- 10) Sin nodos huerfanos --------------------------------------------------
	_clear_enemies()
	_clear_projectiles()
	p1.queue_free()
	p2.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var orphans: int = int(Engine.get_singleton(&"Performance").get_monitor(3))
	_check(orphans == 0, "sin nodos huerfanos tras liberar a los jugadores (%d)" % orphans)

	_report()


func _report() -> void:
	if _reported:
		return
	_reported = true
	print("test_aim: %d checks, %d fallos" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("test_aim: OK")
	else:
		for f in _failures:
			print("  - ", f)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0 if _failures.is_empty() else 1)
