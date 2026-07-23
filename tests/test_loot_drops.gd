extends Node2D
## Valida el CABLEADO del loot en el suelo (FASE 12) en ejecucion real:
##   godot --headless --path . res://tests/TestLootDrops.tscn
##
## Complementa a test_ground_loot (que prueba las piezas en aislamiento): aqui se
## comprueba que el PhaseDirector planta las cajas en su horario, que romperlas
## suelta botin, y que la misma semilla produce el mismo guion de cajas.
##
## Usa el `debug_set_time()` del director en vez de esperar 225 s de reloj.

const PhaseDirectorScript := preload("res://scripts/systems/phase_director.gd")
const LootDirectorScript := preload("res://scripts/systems/loot_director.gd")
const MapInteractableScript := preload("res://scripts/maps/map_interactable.gd")
const NEIGHBORHOOD := preload("res://data/maps/neighborhood_map.tres")

var _failures: Array[String] = []
var _checks: int = 0


class StubSpawner:
	extends Node
	func set_phase_profile(_p: Dictionary) -> void:
		pass
	func spawn_pack(_id: StringName, count: int) -> int:
		return count
	func start_horde(_d: float, _i: float) -> void:
		pass


class StubBossSpawner:
	extends Node2D
	signal boss_defeated(data)
	signal miniboss_defeated(data)
	func spawn_miniboss(_d = null) -> Node2D:
		return null
	func spawn_boss(_d = null) -> Node2D:
		return null


class StubHud:
	extends Node
	var messages: Array = []
	func set_phase_info(_t: String) -> void:
		pass
	func show_event_message(t: String, _d: float = 1.8) -> void:
		messages.append(t)
	func show_announcement(t: String, _d: float = 1.8) -> void:
		messages.append(t)
	func show_boss_bar(_n: String, _m: int) -> void:
		pass


class StubWaveEvents:
	extends Node
	func set_external_director(_a: bool) -> void:
		pass
	func trigger_map_event(_id: StringName) -> void:
		pass


class StubMapManager:
	extends Node
	var map_data = null
	var world_seed: int = 0
	var script_obj: RunScript
	func is_run_ended() -> bool:
		return false
	func force_run_end(_v: bool) -> void:
		pass
	func get_active_map():
		return map_data
	func get_world_seed() -> int:
		return world_seed
	func get_run_script() -> RunScript:
		return script_obj


class StubUpgrades:
	extends Node
	func grant_mutation() -> void:
		pass
	func set_first_card_gate() -> void:
		pass


## Jugador minimo con WeaponManager real: el LootDirector consulta el inventario
## para decidir que arma mete en la caja.
class StubPlayer:
	extends CharacterBody2D
	var player_id: int = 1
	var owned_powerups: Array[StringName] = []
	var applied_upgrades: Array = []
	var _wm: Node2D

	func _init() -> void:
		add_to_group("players")
		add_to_group("player")

	func is_active() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func get_pickup_radius() -> float:
		return 90.0

	func get_last_facing_direction() -> Vector2:
		return Vector2.RIGHT

	func get_weapon_manager() -> Node:
		return _wm

	func apply_upgrade(upgrade_id: StringName, _shared: bool = true) -> void:
		applied_upgrades.append(upgrade_id)
		if not owned_powerups.has(upgrade_id):
			owned_powerups.append(upgrade_id)


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("FALLO: ", message)


func _build_rig(suffix: String, world_seed: int) -> Dictionary:
	var spawner := StubSpawner.new()
	spawner.name = "Spawner" + suffix
	add_child(spawner)
	var boss_spawner := StubBossSpawner.new()
	boss_spawner.name = "BossSpawner" + suffix
	add_child(boss_spawner)
	var hud := StubHud.new()
	hud.name = "Hud" + suffix
	add_child(hud)
	var events := StubWaveEvents.new()
	events.name = "Events" + suffix
	add_child(events)
	var map_mgr := StubMapManager.new()
	map_mgr.name = "MapMgr" + suffix
	map_mgr.map_data = NEIGHBORHOOD
	map_mgr.world_seed = world_seed
	map_mgr.script_obj = RunScript.generate(NEIGHBORHOOD, world_seed)
	add_child(map_mgr)
	var upgrades := StubUpgrades.new()
	upgrades.name = "Upgrades" + suffix
	add_child(upgrades)

	var director := Node.new()
	director.name = "Director" + suffix
	director.set_script(PhaseDirectorScript)
	director.set("hud_path", NodePath("../Hud" + suffix))
	director.set("enemy_spawner_path", NodePath("../Spawner" + suffix))
	director.set("boss_spawner_path", NodePath("../BossSpawner" + suffix))
	director.set("wave_event_manager_path", NodePath("../Events" + suffix))
	director.set("map_manager_path", NodePath("../MapMgr" + suffix))
	director.set("upgrade_manager_path", NodePath("../Upgrades" + suffix))
	add_child(director)

	return {"director": director, "hud": hud}


func _run() -> void:
	await get_tree().physics_frame

	var player := StubPlayer.new()
	player.global_position = Vector2(400, 400)
	add_child(player)
	var wm := Node2D.new()
	wm.set_script(load("res://scripts/weapons/weapon_manager.gd"))
	player.add_child(wm)
	player._wm = wm

	var loot := Node.new()
	loot.set_script(LootDirectorScript)
	add_child(loot)
	await get_tree().physics_frame

	await _test_crates_appear_on_schedule()
	await _test_breaking_a_crate_drops_loot(loot, wm)
	await _test_bosses_drop_rewards()
	_test_same_seed_same_crates()
	_test_crates_ignore_howl_budget()

	_finish()


## Las cajas salen en su horario, no antes, y en TODOS los mapas (no dependen de
## MapData.interactable_kind como los interactables de identidad).
func _test_crates_appear_on_schedule() -> void:
	var rig := _build_rig("A", 424242)
	var director: Node = rig["director"]
	var before: int = _count_role(&"weapon_crate")

	# Justo antes de la primera caja: nada.
	director.debug_set_time(RunPhaseConfig.WEAPON_CRATE_TIMES[0] - 3.0)
	director._process(0.1)
	await get_tree().physics_frame
	_check(_count_role(&"weapon_crate") == before,
		"no hay caja de armas ANTES de su horario")

	# Pasado el tiempo: aparece exactamente una.
	director.debug_set_time(RunPhaseConfig.WEAPON_CRATE_TIMES[0] + 1.0)
	director._process(0.1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_count_role(&"weapon_crate") == before + 1,
		"aparece 1 caja de armas tras su horario (hay %d)" % _count_role(&"weapon_crate"))

	# Un segundo _process no duplica la caja: el slot ya se consumio.
	director._process(0.1)
	await get_tree().physics_frame
	_check(_count_role(&"weapon_crate") == before + 1,
		"el slot consumido no vuelve a plantar (hay %d)" % _count_role(&"weapon_crate"))

	# Y la de suministros llega en SU horario, no con la de armas.
	director.debug_set_time(RunPhaseConfig.SUPPLY_CRATE_TIMES[0] + 1.0)
	director._process(0.1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_count_role(&"supply_crate") >= 1,
		"aparece la caja de suministros en su horario (hay %d)" % _count_role(&"supply_crate"))
	_cleanup_crates()


## Romper una caja de armas suelta un pickup de arma; una de suministros, un power-up.
func _test_breaking_a_crate_drops_loot(loot: Node, wm: Node) -> void:
	_cleanup_crates()
	await get_tree().physics_frame

	var crate := MapInteractableScript.spawn(&"weapon_crate", self, Vector2(1500, 1500))
	await get_tree().physics_frame
	_check(is_instance_valid(crate), "se puede crear una caja de armas")
	_check(crate.is_in_group("enemies"),
		"la caja vive en el grupo enemies (todas las armas la danan)")

	var weapons_before: int = get_tree().get_node_count_in_group("weapon_pickups")
	crate.take_damage(9999)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(get_tree().get_node_count_in_group("weapon_pickups") == weapons_before + 1,
		"romper la caja de armas suelta 1 pickup de arma (solto %d)"
		% (get_tree().get_node_count_in_group("weapon_pickups") - weapons_before))

	var supply := MapInteractableScript.spawn(&"supply_crate", self, Vector2(1800, 1800))
	await get_tree().physics_frame
	var powerups_before: int = get_tree().get_node_count_in_group("pickups")
	supply.take_damage(9999)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(get_tree().get_node_count_in_group("pickups") == powerups_before + 1,
		"romper la caja de suministros suelta 1 power-up (solto %d)"
		% (get_tree().get_node_count_in_group("pickups") - powerups_before))

	# El nucleo de evolucion cae a mutacion si ningun arma es elegible todavia.
	var core = loot.drop_evolution_core(self, Vector2(2100, 2100))
	await get_tree().physics_frame
	_check(core != null, "el nucleo de evolucion siempre suelta algo aunque no haya arma elegible")

	_cleanup_pickups()


## El premio de jefe lo suelta el JEFE, no el PhaseDirector (FASE 12). Se llama
## directamente a _drop_reward para no tener que matar un jefe real.
func _test_bosses_drop_rewards() -> void:
	_cleanup_pickups()
	await get_tree().physics_frame

	var mini := (load("res://scenes/bosses/MiniBoss.tscn") as PackedScene).instantiate() as Node2D
	mini.global_position = Vector2(2500, 2500)
	add_child(mini)
	mini.call("configure", load("res://data/bosses/bulldog_brute.tres"), 1.0)
	await get_tree().physics_frame

	var before: int = get_tree().get_node_count_in_group("pickups")
	mini.call("_drop_reward")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(get_tree().get_node_count_in_group("pickups") > before,
		"el mini-jefe suelta su premio (nucleo o mutacion)")
	mini.queue_free()
	_cleanup_pickups()


## Misma semilla = mismo guion de cajas. El contenido forma parte de la partida.
func _test_same_seed_same_crates() -> void:
	var a: Array = _crate_plan(777)
	var b: Array = _crate_plan(777)
	var c: Array = _crate_plan(778)
	_check(a == b, "la misma semilla da el mismo guion de cajas")
	_check(a != c, "semillas distintas dan guiones de cajas distintos")


## Reproduce el sorteo de posicion del director para una semilla dada.
func _crate_plan(world_seed: int) -> Array:
	var plan: Array = []
	for slot in RunPhaseConfig.WEAPON_CRATE_TIMES.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("crate:%d:%s:%d" % [world_seed, &"weapon_crate", slot])
		plan.append([rng.randf(), rng.randi() % 1000])
	return plan


## Las cajas NO consumen el presupuesto de marcas de aullido del Barrio.
func _test_crates_ignore_howl_budget() -> void:
	var before: int = get_tree().get_node_count_in_group("howl_posts")
	for i in 5:
		MapInteractableScript.spawn(&"weapon_crate", self, Vector2(3000 + i * 60, 3000))
	_check(get_tree().get_node_count_in_group("howl_posts") == before,
		"las cajas no cuentan contra el presupuesto de marcas de aullido")


func _count_role(role: StringName) -> int:
	var total: int = 0
	for node in get_tree().get_nodes_in_group("map_interactables"):
		if is_instance_valid(node) and node.get("role") == role:
			total += 1
	return total


func _cleanup_crates() -> void:
	for node in get_tree().get_nodes_in_group("map_interactables"):
		if is_instance_valid(node):
			node.queue_free()


func _cleanup_pickups() -> void:
	for group in ["pickups", "weapon_pickups"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node):
				node.queue_free()


func _finish() -> void:
	print("TestLootDrops: %d checks, %d fallos" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("TestLootDrops: OK")
	else:
		for f in _failures:
			print("  - ", f)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0 if _failures.is_empty() else 1)
