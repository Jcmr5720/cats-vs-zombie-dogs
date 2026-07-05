extends SceneTree
## Test headless del Modo Historia (correr con: godot --headless -s tests/test_story.gd).
## Valida la capa de datos de la campaña, la tabla de dificultad, las tablas de
## recompensa y el passthrough del saneo del save (claves dinamicas).


func _init() -> void:
	_test_sanitize_passthrough()
	_test_chapters()
	_test_difficulty_table()
	_test_reward_tables()
	_test_story_upgrades()
	print("test_story: OK")
	quit(0)


## Las 3 mejoras de historia existen, tienen capitulo de desbloqueo y los .tres
## de mejoras cargan completos (10 en total).
func _test_story_upgrades() -> void:
	var meta := load("res://scripts/meta/permanent_upgrade_manager.gd")
	assert(meta.UPGRADE_PATHS.size() == 10, "10 mejoras permanentes registradas")
	var locked_ids := {}
	for path in meta.UPGRADE_PATHS:
		var up = load(path)
		assert(up != null, "mejora carga: %s" % path)
		if int(up.unlock_story_chapter) > 0:
			locked_ids[up.id] = up.unlock_story_chapter
	assert(locked_ids.size() == 3, "3 mejoras bloqueadas por historia")
	assert(int(locked_ids.get(&"bigotes_radar", 0)) == 2, "bigotes_radar -> cap 2")
	assert(int(locked_ids.get(&"pelaje_erizado", 0)) == 4, "pelaje_erizado -> cap 4")
	assert(int(locked_ids.get(&"corazon_de_leon", 0)) == 6, "corazon_de_leon -> cap 6")
	print("  mejoras de historia: 3 bloqueadas por capitulo")


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
	assert(int(data["total_sardines"]) == 123, "clave conocida saneada")
	assert(int(data["mission_stat_kills"]) == 55, "stat de mision sobrevive al saneo")
	assert(bool(data["mission_done_kills_1"]), "flag de mision sobrevive al saneo")
	assert(int(data["plague_unlocked_neighborhood"]) == 3, "plaga desbloqueada sobrevive")
	assert(bool(data["story_clear_ch1_d1"]), "first-clear de historia sobrevive")
	assert(int(data["story_chapters_cleared"]) == 4, "capitulos completados saneados")
	assert(int(data["story_difficulty"]) == 2, "dificultad de historia saneada")
	assert(not data.has("inyeccion_rara"), "estructuras no primitivas se descartan")
	print("  sanitize: passthrough OK")


func _test_chapters() -> void:
	var campaign := load("res://scripts/story/story_campaign.gd")
	var chapters: Array = campaign.load_chapters()
	assert(chapters.size() == 6, "la campaña tiene 6 capitulos")
	var seen_numbers := {}
	for i in chapters.size():
		var ch = chapters[i]
		assert(ch.number == i + 1, "capitulo %d en orden" % (i + 1))
		assert(not seen_numbers.has(ch.number), "numeros unicos")
		seen_numbers[ch.number] = true
		assert(ch.map != null, "capitulo %s tiene mapa" % ch.id)
		assert(ch.title != "" and ch.tagline != "", "capitulo %s con titulo y tagline" % ch.id)
		assert(ch.first_clear_reward > 0, "recompensa positiva en %s" % ch.id)
		assert(not ch.cinematic_panels.is_empty(), "capitulo %s con cinematica" % ch.id)
		for panel in ch.cinematic_panels:
			assert(panel.has("title") and panel.has("body") and panel.has("kind"),
				"panel completo en %s" % ch.id)
	var last = chapters[5]
	assert(not last.ending_panels.is_empty(), "el capitulo 6 tiene paneles de final")
	# Los 3 mapas nuevos generan mundo correctamente (chunks + obstaculos).
	for i in [3, 4, 5]:
		var mgr := Node2D.new()
		mgr.set_script(load("res://scripts/maps/map_chunk_manager.gd"))
		root.add_child(mgr)
		mgr.obstacle_scene = load("res://scenes/maps/Obstacle.tscn")
		mgr.world_seed = 424242424
		mgr.generate(chapters[i].map, Vector2.ZERO)
		assert(mgr.get_active_obstacle_count() > 0, "mapa del capitulo %d genera obstaculos" % (i + 1))
		mgr.queue_free()
	print("  capitulos: 6 validos, mapas nuevos generan mundo")


func _test_difficulty_table() -> void:
	var campaign := load("res://scripts/story/story_campaign.gd")
	assert(campaign.DIFFICULTIES.size() == 4, "4 dificultades")
	var last_reward: float = 0.0
	for tier in 4:
		var d: Dictionary = campaign.get_difficulty(tier)
		for key in ["pressure", "health", "speed", "damage", "reward"]:
			assert(float(d[key]) > 0.0, "multiplicador %s positivo en tier %d" % [key, tier])
		assert(float(d["reward"]) >= last_reward, "la recompensa nunca baja con la dificultad")
		last_reward = float(d["reward"])
	# Clamp fuera de rango.
	assert(campaign.get_difficulty(-5)["id"] == &"facil", "clamp inferior")
	assert(campaign.get_difficulty(99)["id"] == &"extremo", "clamp superior")
	print("  dificultad: tabla valida")


func _test_reward_tables() -> void:
	var meta := load("res://scripts/meta/permanent_upgrade_manager.gd")
	for map_id in ["neighborhood_dark", "park_dark", "factory"]:
		assert(meta.VICTORY_BONUS.has(map_id), "%s en VICTORY_BONUS" % map_id)
		assert(meta.MAP_BASE_REWARD.has(map_id), "%s en MAP_BASE_REWARD" % map_id)
		assert(meta.MAP_REWARD_MULT.has(map_id), "%s en MAP_REWARD_MULT" % map_id)
	print("  recompensas: tablas con los mapas de historia")
