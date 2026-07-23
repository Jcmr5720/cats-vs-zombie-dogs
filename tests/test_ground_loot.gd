extends Node2D
## Pruebas del loot en el suelo (FASE 12). Se ejecuta como ESCENA para contar con
## autoloads reales (Feedback, RunTelemetry, AudioManager):
##   godot --headless --path . res://tests/TestGroundLoot.tscn
##
## Cubre por ahora (Fase A): registro de power-ups contra el disco, aplicacion del
## efecto al recoger, guarda anti-doble-cobro de coop y tope de nodos vivos.

const PowerUpPickupScript := preload("res://scripts/loot/power_up_pickup.gd")
const GroundPickupScript := preload("res://scripts/loot/ground_pickup.gd")
const WeaponPickupScript := preload("res://scripts/loot/weapon_pickup.gd")

var _failures: Array[String] = []
var _checks: int = 0


## Jugador minimo con la interfaz que consume el pickup.
class StubPlayer:
	extends CharacterBody2D
	var player_id: int = 1
	var applied_upgrades: Array = []
	var owned_powerups: Array[StringName] = []
	var _wm: Node2D

	func _init() -> void:
		add_to_group("players")
		add_to_group("player")

	func is_active() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func get_last_facing_direction() -> Vector2:
		return Vector2.RIGHT

	func get_weapon_manager() -> Node:
		return _wm

	func get_pickup_radius() -> float:
		return 90.0

	func apply_upgrade(upgrade_id: StringName, _include_shared: bool = true) -> void:
		applied_upgrades.append(upgrade_id)
		if not owned_powerups.has(upgrade_id):
			owned_powerups.append(upgrade_id)


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		print("FALLO: ", label)


## Deja correr N frames de PROCESO. Los pickups actuan en _process, no en la
## fisica: esperar solo physics_frame deja el test a merced de la carga de la
## maquina y lo vuelve intermitente.
func _await_process_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _run() -> void:
	await get_tree().physics_frame

	var player := StubPlayer.new()
	# Lejos del origen: los pickups del test no deben auto-recogerse por iman
	# antes de que los comprobemos.
	player.global_position = Vector2(9000, 9000)
	add_child(player)
	await get_tree().physics_frame

	# --- 1) El registro coincide EXACTAMENTE con el disco -----------------------
	# Mismo criterio que test_story.gd con data/permanent_upgrades: un .tres suelto
	# que no este registrado (o al reves) es un bug silencioso en la tabla de drops.
	_check_registry_matches_disk("res://data/powerups/", PowerUpRegistry.POWERUP_PATHS, "powerups")
	_check_registry_matches_disk("res://data/powerups/mutations/", PowerUpRegistry.MUTATION_PATHS, "mutaciones")

	for path in PowerUpRegistry.POWERUP_PATHS + PowerUpRegistry.MUTATION_PATHS:
		var data: PowerUpData = load(path) as PowerUpData
		_check(data != null, "carga %s" % path)
		if data != null:
			_check(data.id != &"", "%s tiene id" % path)
			_check(data.effect_id() != &"", "%s resuelve effect_id" % path)
			_check(data.drop_weight > 0.0, "%s tiene drop_weight > 0" % path)

	var mutations: Array = PowerUpRegistry.load_mutations()
	_check(mutations.size() == 5, "hay 5 mutaciones (hay %d)" % mutations.size())
	for m in mutations:
		_check(m.is_mutation(), "%s es de categoria mutacion" % m.id)
		_check(m.max_stacks == 1, "%s tiene max_stacks 1" % m.id)

	# --- 2) Filtro de companero --------------------------------------------------
	var with_comp: Array = PowerUpRegistry.load_powerups(true)
	var without_comp: Array = PowerUpRegistry.load_powerups(false)
	_check(with_comp.size() == 13, "con companero hay 13 power-ups (hay %d)" % with_comp.size())
	_check(without_comp.size() == 7, "sin companero hay 7 power-ups (hay %d)" % without_comp.size())
	for p in without_comp:
		_check(not p.requires_companion, "%s no exige companero" % p.id)

	# --- 3) Recoger aplica el efecto UNA sola vez --------------------------------
	var damage_data: PowerUpData = load("res://data/powerups/weapon_damage.tres") as PowerUpData
	var pickup := PowerUpPickupScript.spawn(damage_data, self, Vector2(200, 200))
	await get_tree().physics_frame
	_check(is_instance_valid(pickup), "spawn crea el pickup")
	_check(pickup.is_in_group("pickups"), "el pickup entra en el grupo pickups")

	var collected: bool = pickup.collect(player)
	_check(collected, "collect devuelve true la primera vez")
	_check(player.applied_upgrades.size() == 1, "se aplico 1 mejora (se aplicaron %d)"
		% player.applied_upgrades.size())
	_check(player.applied_upgrades[0] == &"weapon_damage", "se aplico weapon_damage")
	_check(player.owned_powerups.has(&"weapon_damage"), "queda registrado en owned_powerups")

	# --- 4) Guarda anti-doble-cobro (coop) ---------------------------------------
	# Los dos jugadores pueden entrar en el area el mismo frame: el segundo cobro
	# debe rebotar sin aplicar nada.
	var second: bool = pickup.collect(player)
	_check(not second, "el segundo collect devuelve false")
	_check(player.applied_upgrades.size() == 1, "el segundo collect no aplica nada (total %d)"
		% player.applied_upgrades.size())
	_check(pickup.is_claimed(), "el pickup queda reclamado")

	# --- 5) Tope de pickups vivos ------------------------------------------------
	# Una racha de drops no debe acumular nodos sin limite.
	var budget_root := Node2D.new()
	add_child(budget_root)
	await get_tree().physics_frame
	for i in 40:
		PowerUpPickupScript.spawn(damage_data, budget_root, Vector2(i * 40, 700))
		await get_tree().physics_frame
	var alive: int = get_tree().get_node_count_in_group("pickups")
	_check(alive <= GroundPickupScript.MAX_PICKUPS,
		"tras 40 drops quedan <= %d vivos (quedan %d)" % [GroundPickupScript.MAX_PICKUPS, alive])
	budget_root.queue_free()
	await get_tree().physics_frame

	await _run_weapon_checks(player)
	_finish()


## Bloque de armas: WeaponManager (remove/replace/evolve) y el pickup de arma.
func _run_weapon_checks(player: StubPlayer) -> void:
	var wm := Node2D.new()
	wm.set_script(load("res://scripts/weapons/weapon_manager.gd"))
	player.add_child(wm)
	player._wm = wm
	await get_tree().physics_frame

	# El manager arranca con la pistola gatuna.
	_check(wm.get_weapon_count() == 1, "arranca con 1 arma (tiene %d)" % wm.get_weapon_count())
	_check(wm.has_weapon(&"cat_pistol"), "el arma inicial es la pistola gatuna")

	# --- 6) remove_weapon devuelve el WeaponData y respeta ids inexistentes ------
	var missing = wm.remove_weapon(&"no_existe")
	_check(missing == null, "remove_weapon de un id inexistente devuelve null")
	_check(wm.get_weapon_count() == 1, "remove_weapon fallido no toca el inventario")

	# --- 7) replace_weapon conserva el slot y devuelve la descartada -------------
	var boomerang: WeaponData = load("res://data/weapons/sardine_boomerang.tres") as WeaponData
	var laser: WeaponData = load("res://data/weapons/laser_pointer.tres") as WeaponData
	var yarn: WeaponData = load("res://data/weapons/yarn_bomb.tres") as WeaponData
	var spin: WeaponData = load("res://data/weapons/spin_scratcher.tres") as WeaponData
	wm.add_weapon(boomerang)
	wm.add_weapon(laser)
	wm.add_weapon(yarn)
	await get_tree().physics_frame
	_check(wm.get_weapon_count() == 4, "inventario lleno con 4 armas (tiene %d)"
		% wm.get_weapon_count())
	_check(not wm.can_add_weapon(), "con 4 armas ya no se puede anadir")

	var discarded = wm.replace_weapon(&"laser_pointer", spin)
	await get_tree().physics_frame
	_check(discarded != null and discarded.id == &"laser_pointer",
		"replace_weapon devuelve el WeaponData descartado")
	_check(wm.get_weapon_count() == 4, "replace_weapon conserva el conteo en 4 (es %d)"
		% wm.get_weapon_count())
	_check(wm.has_weapon(&"spin_scratcher"), "la nueva arma entro")
	_check(not wm.has_weapon(&"laser_pointer"), "la vieja salio")
	# El slot se conserva: la nueva ocupa el indice 2, no el final.
	var snapshots: Array = wm.get_weapon_snapshots()
	_check(snapshots.size() == 4, "hay 4 snapshots (hay %d)" % snapshots.size())
	_check(snapshots[2]["id"] == &"spin_scratcher",
		"la nueva arma conserva el slot 2 (esta %s)" % snapshots[2]["id"])

	# --- 8) get_swap_candidate elige la de MENOR nivel ---------------------------
	wm.level_up_weapon(&"cat_pistol")
	wm.level_up_weapon(&"cat_pistol")
	await get_tree().physics_frame
	var candidate = wm.get_swap_candidate()
	_check(candidate != null and candidate.data.id != &"cat_pistol",
		"el candidato a sacrificio no es el arma mas subida")

	# --- 9) evolve_best_weapon: requisito, exito y tope -------------------------
	# La pistola evoluciona a nivel maximo CON el power-up "extra_projectile".
	while not wm.get_weapon(&"cat_pistol").is_max_level():
		wm.level_up_weapon(&"cat_pistol")
	await get_tree().physics_frame
	_check(wm.get_evolution_ready_weapons().size() >= 1, "la pistola al maximo es elegible")

	player.owned_powerups.clear()
	_check(not wm.evolve_best_weapon(), "sin el power-up requerido NO evoluciona")
	_check(wm.has_weapon(&"cat_pistol"), "la pistola sigue sin evolucionar")

	player.owned_powerups.append(&"extra_projectile")
	_check(wm.evolve_best_weapon(), "con el power-up requerido SI evoluciona")
	await get_tree().physics_frame
	_check(not wm.has_weapon(&"cat_pistol"), "la pistola base desaparecio")
	_check(wm.has_weapon(&"gatling_meow"), "entro la evolucion gatling_meow")
	_check(wm.get_weapon_count() == 4, "la evolucion conserva el conteo (es %d)"
		% wm.get_weapon_count())

	# Tope por partida: forzado al maximo, no evoluciona nada mas.
	wm.set("_evolutions_done", wm.MAX_EVOLUTIONS_PER_RUN)
	while not wm.get_weapon(&"sardine_boomerang").is_max_level():
		wm.level_up_weapon(&"sardine_boomerang")
	player.owned_powerups.append(load("res://data/weapons/sardine_boomerang.tres").evolution_requirement)
	await get_tree().physics_frame
	_check(not wm.evolve_best_weapon(), "el tope de evoluciones por partida se respeta")

	# --- 10) El pickup de arma: hueco libre entra solo, lleno exige decision -----
	# Con hueco libre no hay nada que decidir, asi que se recoge al tocarla.
	wm.remove_weapon(&"yarn_bomb")
	wm.remove_weapon(&"spin_scratcher")
	await get_tree().physics_frame
	_check(wm.can_add_weapon(), "hay hueco tras quitar dos armas")

	var free_pickup = WeaponPickupScript.spawn(yarn, self, player.global_position)
	# La recogida ocurre en _process del pickup, no en la fisica: esperar
	# physics_frame no garantiza que haya corrido.
	await _await_process_frames(8)
	_check(wm.has_weapon(&"yarn_bomb"), "con hueco libre el arma se recoge sola al tocarla")
	_check(not is_instance_valid(free_pickup) or free_pickup.is_claimed(),
		"el pickup recogido queda reclamado")

	# Con el inventario lleno NO se recoge sola: espera al hold del jugador.
	wm.add_weapon(spin)
	await get_tree().physics_frame
	_check(not wm.can_add_weapon(), "inventario lleno de nuevo")
	var catnip: WeaponData = load("res://data/weapons/catnip_grenade.tres") as WeaponData
	var full_pickup = WeaponPickupScript.spawn(catnip, self, player.global_position)
	# Aqui se espera lo CONTRARIO (que no se recoja), asi que hay que dar tiempo
	# real a que el _process corra y demuestre que aun asi no la coge.
	await _await_process_frames(8)
	_check(is_instance_valid(full_pickup) and not full_pickup.is_claimed(),
		"con inventario lleno el arma NO se recoge sola")
	_check(not wm.has_weapon(&"catnip_grenade"), "el arma sigue en el suelo sin pulsar nada")
	# FASE 13: el prompt vive en la tarjeta de informacion (panel de comparacion).
	var card = full_pickup.get("_card")
	_check(card != null and bool(card.visible) and _card_contains(card, "cambiar"),
		"se muestra el panel de comparacion con el prompt de cambio")

	# El hold completo intercambia y devuelve la vieja al suelo.
	var sacrificed = wm.get_swap_candidate()
	var sacrificed_id: StringName = sacrificed.data.id
	full_pickup.set("_progress", full_pickup.HOLD_DURATION)
	var swapped = wm.replace_weapon(sacrificed_id, catnip)
	await get_tree().physics_frame
	_check(swapped != null and swapped.id == sacrificed_id,
		"el intercambio devuelve el arma sacrificada")
	_check(wm.has_weapon(&"catnip_grenade"), "tras el intercambio entro la nueva")
	_check(wm.get_weapon_count() == 4, "el intercambio conserva el conteo (es %d)"
		% wm.get_weapon_count())


## Compara un registro estatico contra el contenido real de su carpeta.
func _check_registry_matches_disk(dir_path: String, registered: Array, label: String) -> void:
	var disk: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_check(false, "existe la carpeta %s" % dir_path)
		return
	for file in dir.get_files():
		# Godot exporta los .tres como .remap; el nombre logico es el mismo.
		var name: String = file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			disk.append(dir_path + name)
	_check(registered.size() == disk.size(),
		"el registro de %s (%d) cubre todos los .tres del disco (%d)"
		% [label, registered.size(), disk.size()])
	for path in disk:
		_check(registered.has(path), "%s esta registrado" % path)


## Busca (recursivo) un Label cuyo texto contenga `needle` dentro de la tarjeta
## de informacion (FASE 13).
func _card_contains(root: Node, needle: String) -> bool:
	if root is Label and (root as Label).text.contains(needle):
		return true
	for child in root.get_children():
		if _card_contains(child, needle):
			return true
	return false


func _finish() -> void:
	print("test_ground_loot: %d checks, %d fallos" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("test_ground_loot: OK")
	else:
		for f in _failures:
			print("  - ", f)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0 if _failures.is_empty() else 1)
