extends Node2D
## Valida el PhaseDirector (Partidas rapidas): orden de fases, tiempos
## configurables, mini-boss/boss/elite en su momento, Mutacion garantizada,
## furia final, derrota por limite absoluto (5:30) y victoria al caer el jefe.
##   godot --headless --path . res://tests/TestPhaseDirector.tscn

const PhaseDirectorScript := preload("res://scripts/systems/phase_director.gd")
const BossDataRes := preload("res://data/bosses/rottweiler_charger.tres")

var _failures: Array[String] = []
var _checks: int = 0


class StubSpawner:
	extends Node
	var profiles: Array = []
	var packs: Array = []
	func set_phase_profile(p: Dictionary) -> void:
		profiles.append(p)
	func get_phase_profile() -> Dictionary:
		return profiles.back() if not profiles.is_empty() else {}
	func spawn_pack(id: StringName, count: int) -> int:
		packs.append([id, count])
		return count


class StubBoss:
	extends Node2D
	var data = null
	var max_health: int = 1400
	var elite_calls: int = 0
	var enrage_calls: int = 0
	func request_elite_transform() -> void:
		elite_calls += 1
	func enrage() -> void:
		enrage_calls += 1


class StubBossSpawner:
	extends Node2D
	signal boss_defeated(data)
	signal miniboss_defeated(data)
	var miniboss_calls: int = 0
	var boss_calls: int = 0
	var boss_node: Node2D
	func spawn_miniboss(_d = null) -> Node2D:
		miniboss_calls += 1
		return null
	func spawn_boss(_d = null) -> Node2D:
		boss_calls += 1
		return boss_node


class StubHud:
	extends Node
	var phase_texts: Array = []
	var messages: Array = []
	var boss_bars: Array = []
	func set_phase_info(t: String) -> void:
		phase_texts.append(t)
	func show_event_message(t: String, _d: float = 1.8) -> void:
		messages.append(t)
	func show_boss_bar(n: String, m: int) -> void:
		boss_bars.append([n, m])


class StubMapManager:
	extends Node
	var ended: bool = false
	var end_calls: Array = []
	func is_run_ended() -> bool:
		return ended
	func force_run_end(victory: bool) -> void:
		ended = true
		end_calls.append(victory)
	func get_active_map():
		return null


## FASE 12: el director ya NO reparte recompensas de jefe (las suelta el propio
## jefe via LootDirector). El stub solo existe para cablear `loot_director_path` y
## poder comprobar que el director no lo usa para premiar.
class StubLoot:
	extends Node
	var drops: int = 0
	func drop_mutation(_parent: Node, _pos: Vector2) -> Node2D:
		drops += 1
		return null
	func drop_evolution_core(_parent: Node, _pos: Vector2) -> Node2D:
		drops += 1
		return null


func _ready() -> void:
	call_deferred("_run")


func _build_rig(suffix: String) -> Dictionary:
	var rig := {}
	var spawner := StubSpawner.new()
	spawner.name = "Spawner" + suffix
	add_child(spawner)
	var boss := StubBoss.new()
	boss.data = BossDataRes
	var boss_spawner := StubBossSpawner.new()
	boss_spawner.name = "BossSpawner" + suffix
	boss_spawner.boss_node = boss
	boss_spawner.add_child(boss)
	add_child(boss_spawner)
	var hud := StubHud.new()
	hud.name = "Hud" + suffix
	add_child(hud)
	var map_mgr := StubMapManager.new()
	map_mgr.name = "MapMgr" + suffix
	add_child(map_mgr)
	var loot := StubLoot.new()
	loot.name = "Loot" + suffix
	add_child(loot)

	var director := Node.new()
	director.name = "Director" + suffix
	director.set_script(PhaseDirectorScript)
	director.set("hud_path", NodePath("../Hud" + suffix))
	director.set("enemy_spawner_path", NodePath("../Spawner" + suffix))
	director.set("boss_spawner_path", NodePath("../BossSpawner" + suffix))
	director.set("map_manager_path", NodePath("../MapMgr" + suffix))
	director.set("loot_director_path", NodePath("../Loot" + suffix))
	add_child(director)

	rig["spawner"] = spawner
	rig["boss"] = boss
	rig["boss_spawner"] = boss_spawner
	rig["hud"] = hud
	rig["map"] = map_mgr
	rig["loot"] = loot
	rig["director"] = director
	return rig


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# ============ RIG A: recorrido completo hasta la derrota por tiempo ============
	var a := _build_rig("A")
	var dir: Node = a["director"]
	var spawner: StubSpawner = a["spawner"]
	await get_tree().process_frame
	await get_tree().process_frame

	# Arranque: fase INTRO + manada inicial de comunes debiles (8-12).
	_expect(int(dir.call("get_phase")) == RunPhaseConfig.Phase.INTRO, "arranca en INTRO")
	_expect(spawner.packs.size() >= 1 and spawner.packs[0][0] == &"zombie_dog",
		"manada inicial de mordedores en el segundo 0")
	if spawner.packs.size() >= 1:
		var n: int = spawner.packs[0][1]
		_expect(n >= RunPhaseConfig.OPENING_PACK_MIN and n <= RunPhaseConfig.OPENING_PACK_MAX,
			"manada inicial de %d enemigos (8-12)" % n)
	var intro_profile: Dictionary = spawner.get_phase_profile()
	_expect(int(intro_profile.get("tier_caps", {}).get(&"special", -1)) == 0,
		"INTRO sin especiales (cap 0)")
	_expect(int(intro_profile.get("tier_caps", {}).get(&"heavy", -1)) == 0,
		"INTRO sin pesados (cap 0)")

	# Segundo ~8: variedad rapida (corredores).
	dir.call("debug_set_time", 8.5)
	await get_tree().process_frame
	var has_runner_pack := false
	for p in spawner.packs:
		if p[0] == &"runner_zombie_dog":
			has_runner_pack = true
	_expect(has_runner_pack, "corredores introducidos hacia el segundo 8")

	# Orden completo de fases por tiempo.
	var seq: Array = [
		[21.0, RunPhaseConfig.Phase.COMMON_ENEMIES, "COMMON a los 0:21"],
		[61.0, RunPhaseConfig.Phase.SPECIAL_ENEMIES, "SPECIAL a los 1:01"],
		[111.0, RunPhaseConfig.Phase.HEAVY_ENEMIES, "HEAVY a los 1:51"],
		[156.0, RunPhaseConfig.Phase.MINIBOSS, "MINIBOSS a los 2:36"],
		[201.0, RunPhaseConfig.Phase.BOSS, "BOSS a los 3:21"],
		[256.0, RunPhaseConfig.Phase.ELITE_BOSS, "ELITE_BOSS a los 4:16"],
	]
	for step in seq:
		dir.call("debug_set_time", step[0])
		await get_tree().process_frame
		_expect(int(dir.call("get_phase")) == step[1], step[2])

	var bs: StubBossSpawner = a["boss_spawner"]
	_expect(bs.miniboss_calls == 1, "mini-boss invocado UNA vez (2:35)")
	_expect(bs.boss_calls == 1, "boss invocado UNA vez (3:20)")
	var boss: StubBoss = a["boss"]
	# El director PIDE la transformacion elite a 4:15 (el jefe decide cuando es
	# seguro y abre su segunda barra; eso se valida a fondo en TestBossElite).
	_expect(boss.elite_calls == 1, "transformacion elite pedida al jefe (4:15)")
	var hud: StubHud = a["hud"]

	# FASE 12: la recompensa del mini-jefe ya NO la reparte el director, la suelta
	# el propio mini-jefe al morir (mini_boss._drop_reward -> LootDirector). Que el
	# director no toque el loot es justo lo que hay que sostener aqui: si alguien
	# vuelve a cablearlo, salen dos premios por un solo mini-jefe.
	bs.miniboss_defeated.emit(null)
	_expect((a["loot"] as StubLoot).drops == 0,
		"el director NO reparte recompensas de jefe (lo hace el propio jefe)")

	# Perfil del mini-boss reduce la horda (intervalo mayor que la fase pesada).
	var heavy_i: float = float(RunPhaseConfig.phase_profile(RunPhaseConfig.Phase.HEAVY_ENEMIES)["interval"])
	var mb_i: float = float(RunPhaseConfig.phase_profile(RunPhaseConfig.Phase.MINIBOSS)["interval"])
	_expect(mb_i >= heavy_i * 1.3, "el mini-boss reduce 30-40%% la aparicion de comunes")

	# 5:00 furia final: sin spawns comunes + enrage del jefe.
	dir.call("debug_set_time", 301.0)
	await get_tree().process_frame
	_expect(bool(dir.call("is_final_fury")), "furia final activa a los 5:00")
	_expect(boss.enrage_calls == 1, "el jefe entra en furia")
	_expect((spawner.get_phase_profile().get("weights", {}) as Dictionary).is_empty(),
		"spawns comunes DETENIDOS en la furia final")

	# 5:30 limite absoluto: derrota via MapManager.
	dir.call("debug_set_time", 331.0)
	await get_tree().process_frame
	var map_a: StubMapManager = a["map"]
	_expect(map_a.end_calls == [false], "derrota forzada al limite absoluto (5:30)")
	_expect(int(dir.call("get_phase")) == RunPhaseConfig.Phase.DEFEAT, "fase DEFEAT tras el limite")

	# ============ RIG B: victoria al caer el jefe ============
	var b := _build_rig("B")
	await get_tree().process_frame
	await get_tree().process_frame
	var dir_b: Node = b["director"]
	dir_b.call("debug_set_time", 201.0)
	await get_tree().process_frame
	(b["boss_spawner"] as StubBossSpawner).boss_defeated.emit(null)
	_expect(int(dir_b.call("get_phase")) == RunPhaseConfig.Phase.VICTORY, "fase VICTORY al caer el jefe")

	# ============ RIG C: tiempos CONFIGURABLES ============
	var c := _build_rig("C")
	var dir_c: Node = c["director"]
	dir_c.set("common_start", 1.0)
	dir_c.set("special_start", 2.0)
	dir_c.set("heavy_start", 3.0)
	dir_c.set("miniboss_start", 4.0)
	dir_c.set("boss_start", 5.0)
	dir_c.set("elite_start", 6.0)
	dir_c.set("final_fury_start", 7.0)
	dir_c.set("absolute_limit", 8.0)
	await get_tree().process_frame
	await get_tree().process_frame
	dir_c.call("debug_set_time", 5.2)
	await get_tree().process_frame
	_expect(int(dir_c.call("get_phase")) == RunPhaseConfig.Phase.BOSS,
		"tiempos configurables: BOSS a los 5.2s con boss_start=5")
	dir_c.call("debug_set_time", 8.2)
	await get_tree().process_frame
	_expect((c["map"] as StubMapManager).end_calls == [false],
		"tiempos configurables: limite absoluto en 8s")

	# El HUD recibe fase + tiempo restante.
	_expect(hud.phase_texts.size() > 0, "el HUD recibe el rotulo de fase")

	print("")
	print("TestPhaseDirector: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", message)
	else:
		_failures.append(message)
		printerr("  FALLO  ", message)
