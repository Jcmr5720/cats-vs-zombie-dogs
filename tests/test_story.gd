extends SceneTree
## Test headless del Modo Historia (correr con: godot --headless -s tests/test_story.gd).
## Valida la capa de datos de la campaña, la tabla de dificultad, las tablas de
## recompensa y el passthrough del saneo del save (claves dinamicas).
##
## No usa assert(): en headless un assert fallido aborta solo la funcion donde
## ocurre y el script seguia imprimiendo "OK" y saliendo con 0. El helper
## _expect acumula fallos y quit() devuelve 1 si hubo alguno.

const UPGRADE_DIR := "res://data/permanent_upgrades"

var _failures: Array[String] = []
var _checks: int = 0


func _init() -> void:
	_test_sanitize_passthrough()
	_test_chapters()
	_test_difficulty_table()
	_test_reward_tables()
	_test_story_upgrades()
	print("")
	print("test_story: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	if _failures.is_empty():
		print("test_story: OK")
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("  FALLO  ", message)


## UPGRADE_PATHS registra exactamente los .tres presentes en data/permanent_upgrades
## (el conteo se deriva de la carpeta, no de un numero fijo), todos cargan, y las
## 3 mejoras de historia tienen su capitulo de desbloqueo.
func _test_story_upgrades() -> void:
	var meta := load("res://scripts/meta/permanent_upgrade_manager.gd")
	var disk_paths := {}
	var dir := DirAccess.open(UPGRADE_DIR)
	_expect(dir != null, "carpeta de mejoras accesible: %s" % UPGRADE_DIR)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				disk_paths["%s/%s" % [UPGRADE_DIR, file]] = true
	_expect(meta.UPGRADE_PATHS.size() == disk_paths.size(),
		"UPGRADE_PATHS (%d) registra todos los .tres de la carpeta (%d)"
		% [meta.UPGRADE_PATHS.size(), disk_paths.size()])
	var locked_ids := {}
	for path in meta.UPGRADE_PATHS:
		_expect(disk_paths.has(path), "ruta registrada existe en disco: %s" % path)
		var up = load(path)
		_expect(up != null, "mejora carga: %s" % path)
		if up != null and int(up.unlock_story_chapter) > 0:
			locked_ids[up.id] = up.unlock_story_chapter
	_expect(locked_ids.size() == 3, "3 mejoras bloqueadas por historia")
	_expect(int(locked_ids.get(&"bigotes_radar", 0)) == 2, "bigotes_radar -> cap 2")
	_expect(int(locked_ids.get(&"pelaje_erizado", 0)) == 4, "pelaje_erizado -> cap 4")
	_expect(int(locked_ids.get(&"corazon_de_leon", 0)) == 6, "corazon_de_leon -> cap 6")
	print("  mejoras: %d registradas, 3 bloqueadas por capitulo" % meta.UPGRADE_PATHS.size())


## El fix de Fase 0: las claves dinamicas (misiones, plagas, historia) deben
## sobrevivir a SaveData.sanitize, y las estructuras raras deben descartarse.
func _test_sanitize_passthrough() -> void:
	var save_data := load("res://scripts/save/save_data.gd")
	var raw := {
		"total_sardines": 123,
		"mission_stat_kills": 55,
		"mission_done_kills_1": true,
		"plague_unlocked_neighborhood": 3,
		"story_clear_ch1_d1": true,
		"story_chapters_cleared": 4,
		"story_difficulty": 2,
		"inyeccion_rara": {"no": "deberia pasar"},
	}
	var data: Dictionary = save_data.sanitize(raw)
	_expect(int(data.get("total_sardines", -1)) == 123, "clave conocida saneada")
	_expect(int(data.get("mission_stat_kills", -1)) == 55, "stat de mision sobrevive al saneo")
	_expect(bool(data.get("mission_done_kills_1", false)), "flag de mision sobrevive al saneo")
	_expect(int(data.get("plague_unlocked_neighborhood", -1)) == 3, "plaga desbloqueada sobrevive")
	_expect(bool(data.get("story_clear_ch1_d1", false)), "first-clear de historia sobrevive")
	_expect(int(data.get("story_chapters_cleared", -1)) == 4, "capitulos completados saneados")
	_expect(int(data.get("story_difficulty", -1)) == 2, "dificultad de historia saneada")
	_expect(not data.has("inyeccion_rara"), "estructuras no primitivas se descartan")
	print("  sanitize: passthrough OK")


func _test_chapters() -> void:
	var campaign := load("res://scripts/story/story_campaign.gd")
	var chapters: Array = campaign.load_chapters()
	_expect(chapters.size() == 6, "la campaña tiene 6 capitulos")
	var seen_numbers := {}
	for i in chapters.size():
		var ch = chapters[i]
		_expect(ch.number == i + 1, "capitulo %d en orden" % (i + 1))
		_expect(not seen_numbers.has(ch.number), "numeros unicos")
		seen_numbers[ch.number] = true
		_expect(ch.map != null, "capitulo %s tiene mapa" % ch.id)
		_expect(ch.title != "" and ch.tagline != "", "capitulo %s con titulo y tagline" % ch.id)
		_expect(ch.first_clear_reward > 0, "recompensa positiva en %s" % ch.id)
		_expect(not ch.cinematic_panels.is_empty(), "capitulo %s con cinematica" % ch.id)
		for panel in ch.cinematic_panels:
			_expect(panel.has("title") and panel.has("body") and panel.has("kind"),
				"panel completo en %s" % ch.id)
	if chapters.size() == 6:
		var last = chapters[5]
		_expect(not last.ending_panels.is_empty(), "el capitulo 6 tiene paneles de final")
		# Los 3 mapas nuevos generan mundo correctamente (chunks + obstaculos).
		for i in [3, 4, 5]:
			var mgr := Node2D.new()
			mgr.set_script(load("res://scripts/maps/map_chunk_manager.gd"))
			root.add_child(mgr)
			mgr.obstacle_scene = load("res://scenes/maps/Obstacle.tscn")
			mgr.world_seed = 424242424
			mgr.generate(chapters[i].map, Vector2.ZERO)
			_expect(mgr.get_active_obstacle_count() > 0,
				"mapa del capitulo %d genera obstaculos" % (i + 1))
			mgr.queue_free()
	print("  capitulos: 6 validos, mapas nuevos generan mundo")


func _test_difficulty_table() -> void:
	var campaign := load("res://scripts/story/story_campaign.gd")
	_expect(campaign.DIFFICULTIES.size() == 4, "4 dificultades")
	var last_reward: float = 0.0
	for tier in 4:
		var d: Dictionary = campaign.get_difficulty(tier)
		for key in ["pressure", "health", "speed", "damage", "reward"]:
			_expect(float(d.get(key, 0.0)) > 0.0, "multiplicador %s positivo en tier %d" % [key, tier])
		_expect(float(d.get("reward", 0.0)) >= last_reward, "la recompensa nunca baja con la dificultad")
		last_reward = float(d.get("reward", 0.0))
	# Clamp fuera de rango.
	_expect(campaign.get_difficulty(-5)["id"] == &"facil", "clamp inferior")
	_expect(campaign.get_difficulty(99)["id"] == &"extremo", "clamp superior")
	print("  dificultad: tabla valida")


func _test_reward_tables() -> void:
	var meta := load("res://scripts/meta/permanent_upgrade_manager.gd")
	for map_id in ["neighborhood_dark", "park_dark", "factory"]:
		_expect(meta.VICTORY_BONUS.has(map_id), "%s en VICTORY_BONUS" % map_id)
		_expect(meta.MAP_BASE_REWARD.has(map_id), "%s en MAP_BASE_REWARD" % map_id)
		_expect(meta.MAP_REWARD_MULT.has(map_id), "%s en MAP_REWARD_MULT" % map_id)
	print("  recompensas: tablas con los mapas de historia")
