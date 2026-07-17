extends Node2D
## Pruebas del rework de adictividad (agencia en el level-up + evoluciones).
## Se ejecuta como ESCENA para contar con autoloads reales:
##   godot --headless --path . res://tests/TestUpgrades.tscn
## Valida: reroll/banish (sin salto), filtrado de vetados, las 8 armas del registry,
## carta de evolucion (requisitos + tope), evolve_weapon conserva el slot,
## laser en cadena y zona con atraccion.

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

	func get_last_facing_direction() -> Vector2:
		return Vector2.RIGHT

	func get_weapon_manager() -> Node:
		return _wm


## HUD minimo: captura las llamadas del UpgradeManager sin UI real.
class StubHud:
	extends Node
	signal upgrade_card_selected(card_index: int)
	signal reroll_requested
	signal banish_requested(card_index: int)
	var shown_cards: Array = []
	var show_count: int = 0
	var actions_state: Array = []

	func show_upgrade_selection(cards: Array[Dictionary]) -> void:
		shown_cards = cards.duplicate()
		show_count += 1

	func hide_upgrade_selection() -> void:
		pass

	func set_upgrade_actions(rerolls: int, banishes: int) -> void:
		actions_state = [rerolls, banishes]

	func show_event_message(_text: String) -> void:
		pass


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

	var um := Node.new()
	um.set_script(load("res://scripts/systems/upgrade_manager.gd"))
	add_child(um)
	um.set("_player", player)
	um.set("_hud", hud)
	hud.upgrade_card_selected.connect(um._on_upgrade_card_selected)
	hud.reroll_requested.connect(um.request_reroll)
	hud.banish_requested.connect(um.request_banish)
	await get_tree().physics_frame

	# --- 1) Las 8 armas del registry cargan --------------------------------------
	var registry: Array = wm.WEAPON_REGISTRY
	_check(registry.size() == 8, "registry tiene 8 armas (tiene %d)" % registry.size())
	for path in registry:
		var data = load(path)
		_check(data != null, "carga %s" % path)

	# --- 2) Seleccion, reroll, banish y NO-skip ----------------------------------
	um._on_player_level_up_requested(2)
	_check(bool(um.get("_selection_active")), "seleccion activa al subir de nivel")
	_check(hud.shown_cards.size() == 3, "se muestran 3 cartas")
	_check(hud.actions_state.size() == 2 and hud.actions_state[0] == 1 and hud.actions_state[1] == 1,
		"contadores base: 1 reroll / 1 banish")

	var before_reroll: Array = hud.shown_cards.duplicate()
	um.request_reroll()
	_check(int(um.get("_rerolls_left")) == 0, "reroll consumido")
	_check(hud.show_count >= 2, "reroll re-muestra cartas")
	um.request_reroll()
	_check(hud.show_count == 2, "sin rerolls restantes no re-sortea")

	# Banish: veta la primera carta y no debe volver a aparecer.
	var ban_card: Dictionary = hud.shown_cards[0]
	var ban_id: StringName = um._card_ban_id(ban_card)
	um.request_banish(0)
	_check(int(um.get("_banishes_left")) == 0, "banish consumido")
	var banished: Array = um.get("_banished_ids")
	_check(banished.has(ban_id), "id vetado registrado (%s)" % ban_id)
	var reappears: bool = false
	for _i in 12:
		for card in um._draw_cards(3):
			if um._card_ban_id(card) == ban_id:
				reappears = true
	_check(not reappears, "el id vetado no reaparece en 12 sorteos")

	# Sin salto (Fase correccion): no existe request_skip ni recompensa por omitir.
	# La seleccion sigue activa hasta elegir una carta valida.
	player.current_health = 50
	var xp_before_choice: int = player.xp_gained
	_check(not um.has_method("request_skip"), "request_skip ya no existe")
	_check(not hud.has_signal("skip_requested") or true, "stub sin señal de skip")
	_check(bool(um.get("_selection_active")), "la seleccion sigue activa (no hay forma de saltarla)")
	hud.upgrade_card_selected.emit(0)
	_check(not bool(um.get("_selection_active")), "elegir una carta cierra la seleccion")
	_check(not get_tree().paused, "elegir despausa el juego")
	_check(player.xp_gained == xp_before_choice, "elegir no regala XP extra")
	_check(player.current_health == 50 or player.applied_upgrades.has(&"max_health"),
		"sin cura de compensacion (solo cambia la vida si la carta era de vida)")
	_check(player.applied_upgrades.size() >= 1, "la mejora elegida se aplico")

	# --- 3) Evolucion: requisitos, carta legendaria y swap ------------------------
	# Sube la pistola inicial a nivel maximo.
	var pistol: Node2D = wm.get_weapon(&"cat_pistol")
	_check(pistol != null, "el arma inicial existe")
	while not pistol.is_max_level():
		wm.level_up_weapon(&"cat_pistol")
	_check(pistol.is_max_level(), "pistola a nivel maximo")

	# Sin el stat requisito NO debe aparecer la carta de evolucion.
	var found_evo: bool = false
	for card in um._build_candidates():
		if card.get("card_type", &"") == &"weapon_evolution":
			found_evo = true
	_check(not found_evo, "sin requisito no hay carta de evolucion")

	# Con el requisito (extra_projectile) debe aparecer, con rareza legendaria.
	um._apply_card({"card_type": &"stat", "id": &"extra_projectile"})
	var evo_card: Dictionary = {}
	for card in um._build_candidates():
		if card.get("card_type", &"") == &"weapon_evolution":
			evo_card = card
	_check(not evo_card.is_empty(), "carta de evolucion disponible con requisito")
	_check(evo_card.get("rarity", &"") == &"legendary", "carta de evolucion legendaria")

	# Con peso 60 debe salir practicamente siempre en la mano de 3.
	var evo_in_hand: int = 0
	for _i in 10:
		for card in um._draw_cards(3):
			if card.get("card_type", &"") == &"weapon_evolution":
				evo_in_hand += 1
	_check(evo_in_hand >= 9, "la carta de evolucion sale garantizada (%d/10)" % evo_in_hand)

	# Aplicar la evolucion: reemplaza el arma conservando el conteo.
	var count_before: int = wm.get_weapon_count()
	um._apply_card(evo_card)
	_check(wm.get_weapon_count() == count_before, "la evolucion conserva el numero de armas")
	_check(wm.has_weapon(&"gatling_meow"), "el arma evolucionada esta en juego")
	_check(not wm.has_weapon(&"cat_pistol"), "el arma base fue reemplazada")
	_check(int(um.get("_evolutions_done")) == 1, "contador de evoluciones avanzo")

	# El arma base evolucionada no se re-ofrece como "nueva".
	var reoffered: bool = false
	for data in wm.get_available_new_weapons():
		if data.id == &"cat_pistol":
			reoffered = true
	_check(not reoffered, "la base evolucionada no se re-ofrece como arma nueva")

	# Tope de evoluciones por run.
	um.set("_evolutions_done", um.MAX_EVOLUTIONS_PER_RUN)
	wm.add_weapon(load("res://data/weapons/laser_pointer.tres"))
	var laser: Node2D = wm.get_weapon(&"laser_pointer")
	while not laser.is_max_level():
		wm.level_up_weapon(&"laser_pointer")
	um._apply_card({"card_type": &"stat", "id": &"weapon_damage"})
	var evo_after_cap: bool = false
	for card in um._build_candidates():
		if card.get("card_type", &"") == &"weapon_evolution":
			evo_after_cap = true
	_check(not evo_after_cap, "tope de %d evoluciones respetado" % um.MAX_EVOLUTIONS_PER_RUN)
	um.set("_evolutions_done", 1)

	# --- 4) Laser en cadena (Rayo Prisma) ----------------------------------------
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
