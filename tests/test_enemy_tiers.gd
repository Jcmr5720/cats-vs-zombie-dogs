extends Node2D
## Valida la clasificacion de enemigos (comunes/especiales/pesados/esbirros),
## los costes de amenaza, los limites por tipo y categoria y el presupuesto del
## EnemySpawner en modo fases.
##   godot --headless --path . res://tests/TestEnemyTiers.tscn

const SpawnerScript := preload("res://scripts/enemies/enemy_spawner.gd")
const ENEMY_SCENE := preload("res://scenes/enemies/Enemy.tscn")

var _failures: Array[String] = []
var _checks: int = 0

## id -> [tier, threat_cost, behavior] segun el diseño (seccion 7).
const EXPECTED: Dictionary = {
	&"zombie_dog": [&"common", 1.0, &""],
	&"pup_zombie_dog": [&"common", 1.0, &""],
	&"runner_zombie_dog": [&"common", 1.0, &""],
	&"pack_zombie_dog": [&"common", 1.5, &"pack"],
	&"flanker_zombie_dog": [&"special", 2.0, &"flanker"],
	&"howler_zombie_dog": [&"special", 3.0, &"howler"],
	&"spitter_zombie_dog": [&"special", 3.0, &"spitter"],
	&"infection_carrier_dog": [&"special", 3.0, &"infection_carrier"],
	&"tank_zombie_dog": [&"heavy", 5.0, &"armored"],
	&"splitter_zombie_dog": [&"heavy", 5.0, &"splitter"],
	&"charger_zombie_dog": [&"heavy", 6.0, &"charger"],
	&"hunter_zombie_dog": [&"heavy", 6.0, &"hunter"],
	&"boss_guardian": [&"special", 6.0, &"boss_guardian"],
	&"boss_healer": [&"special", 4.0, &"boss_healer"],
	&"boss_exploder": [&"special", 4.0, &"boss_exploder"],
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# --- Clasificacion y costes -------------------------------------------------
	for id in EXPECTED:
		var data = RunPhaseConfig.load_enemy_data(id)
		_expect(data != null, "existe EnemyData de %s" % id)
		if data == null:
			continue
		var exp: Array = EXPECTED[id]
		_expect(data.tier == exp[0], "%s: tier %s" % [id, exp[0]])
		_expect(is_equal_approx(data.threat_cost, exp[1]), "%s: coste de amenaza %.1f" % [id, exp[1]])
		_expect(data.behavior == exp[2], "%s: comportamiento '%s'" % [id, exp[2]])
		# Terminologia: la palabra inglesa "minion" no aparece en la interfaz.
		_expect(not data.display_name.to_lower().contains("minion"),
			"%s: el nombre visible no usa 'minion'" % id)
	# Solo los invocados por el jefe son esbirros (role boss_minion).
	for id in EXPECTED:
		var data = RunPhaseConfig.load_enemy_data(id)
		if data == null:
			continue
		var is_minion: bool = String(id).begins_with("boss_")
		_expect((data.role == &"boss_minion") == is_minion,
			"%s: role boss_minion=%s" % [id, str(is_minion)])
	# Esbirros dentro del rango de coste 4-7 del diseño.
	for id in [&"boss_guardian", &"boss_healer", &"boss_exploder"]:
		var data = RunPhaseConfig.load_enemy_data(id)
		_expect(data.threat_cost >= 4.0 and data.threat_cost <= 7.0,
			"%s: coste de esbirro en 4-7" % id)

	# --- Perfiles de fase: composicion y limites -------------------------------
	var intro: Dictionary = RunPhaseConfig.phase_profile(RunPhaseConfig.Phase.INTRO)
	_expect(int(intro["tier_caps"].get(&"special", -1)) == 0 and int(intro["tier_caps"].get(&"heavy", -1)) == 0,
		"INTRO: sin especiales ni pesados")
	var special: Dictionary = RunPhaseConfig.phase_profile(RunPhaseConfig.Phase.SPECIAL_ENEMIES)
	_expect(int(special["type_caps"].get(&"howler_zombie_dog", 99)) == 1,
		"SPECIAL: nunca dos aulladores a la vez")
	var heavy: Dictionary = RunPhaseConfig.phase_profile(RunPhaseConfig.Phase.HEAVY_ENEMIES)
	_expect(int(heavy["tier_caps"].get(&"heavy", 99)) <= 4,
		"HEAVY: pesados en cantidades limitadas (cap %d)" % int(heavy["tier_caps"].get(&"heavy", 99)))
	var boss_p: Dictionary = RunPhaseConfig.phase_profile(RunPhaseConfig.Phase.BOSS)
	_expect(int(boss_p["tier_caps"].get(&"special", 99)) == 0 and int(boss_p["tier_caps"].get(&"heavy", 99)) == 0,
		"BOSS: horda reducida a comunes")
	_expect((RunPhaseConfig.phase_profile(RunPhaseConfig.Phase.VICTORY)["weights"] as Dictionary).is_empty(),
		"furia final/cierre: sin spawns comunes")

	# --- Spawner en modo fases: presupuesto y limites en vivo -------------------
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.add_to_group("players")
	add_child(player)

	var spawner := Node2D.new()
	spawner.set_script(SpawnerScript)
	spawner.set("enemy_scene", ENEMY_SCENE)
	add_child(spawner)

	# Limite por TIPO: solo un aullador aunque se pidan tres.
	spawner.call("set_phase_profile", {
		"weights": {&"howler_zombie_dog": 1.0},
		"interval": 30.0, "budget": 30.0, "max_alive": 30,
		"tier_caps": {&"special": 2}, "type_caps": {&"howler_zombie_dog": 1},
	})
	var spawned: int = spawner.call("spawn_pack", &"howler_zombie_dog", 3)
	_expect(spawned == 1, "limite por tipo: 1 de 3 aulladores generados (%d)" % spawned)
	_expect(int(spawner.call("get_alive_count_for", &"howler_zombie_dog")) == 1,
		"conteo de vivos por id correcto")

	# Limite por CATEGORIA: con cap especial 2 y un aullador vivo, entra solo
	# 1 escupidor mas aunque se pidan dos.
	spawner.call("set_phase_profile", {
		"weights": {&"spitter_zombie_dog": 1.0},
		"interval": 30.0, "budget": 30.0, "max_alive": 30,
		"tier_caps": {&"special": 2}, "type_caps": {},
	})
	spawned = spawner.call("spawn_pack", &"spitter_zombie_dog", 2)
	_expect(spawned == 1, "limite por categoria: especiales cap 2 (entro %d)" % spawned)

	# PRESUPUESTO: amenaza activa = 3 (aullador) + 3 (escupidor) = 6. Con budget
	# 10 un pesado de coste 5 NO cabe; un comun de coste 1 si.
	spawner.call("set_phase_profile", {
		"weights": {&"tank_zombie_dog": 1.0},
		"interval": 30.0, "budget": 10.0, "max_alive": 30,
		"tier_caps": {}, "type_caps": {},
	})
	_expect(absf(float(spawner.call("get_active_threat")) - 6.0) < 0.01,
		"amenaza activa acumulada = 6.0")
	spawned = spawner.call("spawn_pack", &"tank_zombie_dog", 1)
	_expect(spawned == 0, "presupuesto: el Blindado (5) no cabe con 6/10 usados")
	spawned = spawner.call("spawn_pack", &"zombie_dog", 1)
	_expect(spawned == 1, "presupuesto: un Mordedor (1) si cabe")

	# El presupuesto SE RECUPERA al morir/salir enemigos (ventana de respiro).
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(float(spawner.call("get_active_threat")) < 0.01,
		"la amenaza activa vuelve a 0 al vaciarse el campo")
	spawned = spawner.call("spawn_pack", &"tank_zombie_dog", 1)
	_expect(spawned == 1, "recuperado el presupuesto, el Blindado ya cabe")

	# Aparicion FUERA de la vista: lejos del jugador (borde de camara + margen).
	var min_dist: float = INF
	for e in get_tree().get_nodes_in_group("enemies"):
		min_dist = minf(min_dist, (e as Node2D).global_position.distance_to(player.global_position))
	_expect(min_dist >= 400.0, "los spawns entran lejos del jugador (%.0f px)" % min_dist)

	print("")
	print("TestEnemyTiers: %d checks, %d fallos" % [_checks, _failures.size()])
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
