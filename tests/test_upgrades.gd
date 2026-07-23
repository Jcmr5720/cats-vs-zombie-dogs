extends Node2D
## Pruebas de armas y evoluciones. Se ejecuta como ESCENA para contar con
## autoloads reales:
##   godot --headless --path . res://tests/TestUpgrades.tscn
## Valida: las 8 armas del registry, la evolucion de punta a punta (requisito de
## power-up + conservacion del slot), el laser en cadena y la zona con atraccion.
##
## FASE 12: los bloques de cartas (reroll, banish, no-skip) desaparecieron con el
## UpgradeManager. Su sustituto —el loot del suelo— se prueba en test_ground_loot
## y test_loot_drops.

var _failures: Array[String] = []
var _checks: int = 0


## Jugador minimo con la interfaz que usan UpgradeManager y WeaponManager.
class StubPlayer:
	extends CharacterBody2D
	signal level_up_requested(level: int)
	var player_id: int = 1
	var current_health: int = 100
	var max_health: int = 100
	var level: int = 1
	var speed: float = 250.0
	var xp_gained: int = 0
	var applied_upgrades: Array = []
	var owned_powerups: Array[StringName] = []
	var _wm: Node2D

	func _init() -> void:
		add_to_group("players")
		add_to_group("player")

	func is_dead() -> bool:
		return false

	func heal(amount: int) -> void:
		current_health = mini(max_health, current_health + amount)

	func add_experience(amount: int) -> void:
		xp_gained += amount

	func apply_upgrade(upgrade_id: StringName, _include_shared: bool = true) -> void:
		applied_upgrades.append(upgrade_id)
		if not owned_powerups.has(upgrade_id):
			owned_powerups.append(upgrade_id)

	func get_last_facing_direction() -> Vector2:
		return Vector2.RIGHT

	func get_weapon_manager() -> Node:
		return _wm


## HUD minimo: el WeaponManager le avisa de armas nuevas y mejoras.
class StubHud:
	extends Node
	var messages: Array = []

	func show_event_message(text: String) -> void:
		messages.append(text)


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		print("FALLO: ", label)


func _wait(seconds: float) -> void:
	var frames: int = int(ceil(seconds * 60.0))
	for _i in frames:
		await get_tree().physics_frame


func _run() -> void:
	await get_tree().physics_frame

	# --- Montaje: jugador stub + WeaponManager real + UpgradeManager real --------
	var player := StubPlayer.new()
	player.global_position = Vector2(300, 300)
	add_child(player)

	var wm := Node2D.new()
	wm.set_script(load("res://scripts/weapons/weapon_manager.gd"))
	player.add_child(wm)
	player._wm = wm

	var hud := StubHud.new()
	add_child(hud)
	await get_tree().physics_frame

	# --- 1) Las 8 armas del registry cargan --------------------------------------
	var registry: Array = wm.WEAPON_REGISTRY
	_check(registry.size() == 8, "registry tiene 8 armas (tiene %d)" % registry.size())
	for path in registry:
		var data = load(path)
		_check(data != null, "carga %s" % path)

	# --- 2) Evolucion via nucleo de jefe (FASE 12) -------------------------------
	# Ya no hay cartas: la evolucion la dispara WeaponManager.evolve_best_weapon(),
	# que valida nivel maximo + power-up requerido + tope por partida. El detalle
	# fino de esa logica vive en test_ground_loot; aqui solo se comprueba que el
	# arma inicial evoluciona de punta a punta.
	var pistol: Node2D = wm.get_weapon(&"cat_pistol")
	_check(pistol != null, "el arma inicial existe")
	while not pistol.is_max_level():
		wm.level_up_weapon(&"cat_pistol")
	_check(pistol.is_max_level(), "pistola a nivel maximo")

	player.owned_powerups.clear()
	_check(not wm.evolve_best_weapon(), "sin el power-up requerido no evoluciona")

	player.owned_powerups.append(&"extra_projectile")
	var count_before: int = wm.get_weapon_count()
	_check(wm.evolve_best_weapon(), "con el power-up requerido evoluciona")
	_check(wm.get_weapon_count() == count_before, "la evolucion conserva el numero de armas")
	_check(wm.has_weapon(&"gatling_meow"), "el arma evolucionada esta en juego")
	_check(not wm.has_weapon(&"cat_pistol"), "el arma base fue reemplazada")

	# El arma base evolucionada no se re-ofrece como "nueva".
	var reoffered: bool = false
	for data in wm.get_available_new_weapons():
		if data.id == &"cat_pistol":
			reoffered = true
	_check(not reoffered, "la base evolucionada no se re-ofrece como arma nueva")

	# --- 3) Laser en cadena (Rayo Prisma) ----------------------------------------
	wm.add_weapon(load("res://data/weapons/laser_pointer.tres"))
	var laser: Node2D = wm.get_weapon(&"laser_pointer")
	while not laser.is_max_level():
		wm.level_up_weapon(&"laser_pointer")
	# Evoluciona el laser directamente via WeaponManager y coloca 3 enemigos.
	var enemies: Array[Node2D] = []
	for i in 3:
		enemies.append(_spawn_enemy(player.global_position + Vector2(150 + i * 120, 0)))
	await get_tree().physics_frame
	_check(wm.evolve_weapon(&"laser_pointer"), "evolve_weapon del laser funciona")
	_check(wm.has_weapon(&"prism_beam"), "Rayo Prisma en juego")
	var prism: Node2D = wm.get_weapon(&"prism_beam")
	# Disparo sincrono (sin awaits): ningun otro arma puede interferir en la medida.
	var hp_before: Array[int] = []
	for e in enemies:
		hp_before.append(int(e.current_health))
	prism.call("_fire_laser")
	var hit_count: int = 0
	for i in enemies.size():
		if int(enemies[i].current_health) < hp_before[i]:
			hit_count += 1
	_check(hit_count >= 3, "el laser en cadena golpea a varios enemigos (%d/3)" % hit_count)

	# --- 5) Zona con atraccion (Ovillo Agujero Negro) ----------------------------
	var area := (load("res://scenes/weapons/CatnipArea.tscn") as PackedScene).instantiate() as Node2D
	add_child(area)
	var pull_enemy := _spawn_enemy(player.global_position + Vector2(0, 300))
	await get_tree().physics_frame
	area.global_position = pull_enemy.global_position + Vector2(80, 0)
	area.call("setup", 1, 150.0, 2.0, 0.3, Color.PURPLE, true)
	var x_before: float = pull_enemy.global_position.x
	await _wait(0.6)
	# El enemigo tiene speed 0: solo el knockback del pull puede moverlo, y debe
	# hacerlo HACIA el centro de la zona (x creciente).
	_check(pull_enemy.global_position.x > x_before + 2.0, "la zona con pull atrae hacia su centro")
	area.queue_free()

	# --- Resultado -----------------------------------------------------------------
	print("test_upgrades: %d checks, %d fallos" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("test_upgrades: OK")
	else:
		for f in _failures:
			print("  - ", f)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _spawn_enemy(pos: Vector2) -> Node2D:
	var enemy := (load("res://scenes/enemies/Enemy.tscn") as PackedScene).instantiate() as Node2D
	enemy.global_position = pos
	enemy.call("configure", load("res://data/enemies/normal_zombie_dog.tres"))
	add_child(enemy)
	enemy.set("speed", 0.0)
	enemy.set("max_health", 500)
	enemy.set("current_health", 500)
	return enemy
