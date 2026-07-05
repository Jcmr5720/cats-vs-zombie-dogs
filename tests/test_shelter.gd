extends SceneTree
## Test headless del Refugio Felino (correr con: godot --headless -s tests/test_shelter.gd).
## Valida los 12 objetos, el calculador de bonus con topes, el poder del refugio
## y el saneo del bloque "shelter" del save (compatibilidad con saves antiguos).


func _init() -> void:
	_test_items()
	_test_bonus_caps()
	_test_power_score()
	_test_save_sanitize()
	print("test_shelter: OK")
	quit(0)


func _load_items() -> Dictionary:
	var manager := load("res://scripts/shelter/shelter_manager.gd")
	var by_id: Dictionary = {}
	for path in manager.ITEM_PATHS:
		var item = load(path)
		assert(item != null, "objeto carga: %s" % path)
		by_id[str(item.id)] = item
	return by_id


func _test_items() -> void:
	var calculator := load("res://scripts/shelter/shelter_bonus_calculator.gd")
	var by_id := _load_items()
	assert(by_id.size() == 12, "12 objetos del refugio")
	var categories := {}
	for item_id in by_id:
		var item = by_id[item_id]
		assert(item.price > 0 and item.max_level == 5, "%s: precio y nivel max validos" % item_id)
		assert(item.upgrade_base_cost > 0 and item.upgrade_cost_growth > 1.0, "%s: costos de mejora" % item_id)
		assert(calculator.EFFECT_TO_KEY.has(item.effect_type), "%s: effect_type reconocido" % item_id)
		categories[item.category] = true
	assert(categories.size() == 5, "5 categorias cubiertas")
	print("  objetos: 12 validos en 5 categorias")


func _test_bonus_caps() -> void:
	var calculator := load("res://scripts/shelter/shelter_bonus_calculator.gd")
	var by_id := _load_items()
	# Todo colocado a nivel 5 (imposible en juego por slots, pero prueba topes).
	var levels := {}
	var placed := {}
	var i: int = 0
	for item_id in by_id:
		levels[item_id] = 5
		placed["slot_%d" % i] = item_id
		i += 1
	var bonuses: Dictionary = calculator.compute(by_id, levels, placed)
	for key in calculator.CAPS:
		assert(float(bonuses[key]) <= float(calculator.CAPS[key]) + 0.001,
			"tope respetado en %s (%f)" % [key, float(bonuses[key])])
	assert(absf(float(bonuses["player_damage_bonus"]) - 0.15) < 0.001, "daño jugador topa en 15%")
	assert(absf(float(bonuses["rescue_first_spawn_reduction"]) - 15.0) < 0.001, "primer rescate topa en 15s")
	# Sin colocar = sin bonus (comprar no basta).
	var none: Dictionary = calculator.compute(by_id, levels, {})
	for key in none:
		assert(float(none[key]) == 0.0, "sin colocar no hay bonus (%s)" % key)
	print("  bonus: topes OK y solo objetos colocados aportan")


func _test_power_score() -> void:
	var calculator := load("res://scripts/shelter/shelter_bonus_calculator.gd")
	var by_id := _load_items()
	var levels := {"combat_scratcher": 4, "sardine_storage": 4}
	var placed := {"training_1": "combat_scratcher", "economy_1": "sardine_storage"}
	# Combate pesa 1.0; economia 0.5 -> 4*1 + 4*0.5 = 6.
	var score: float = calculator.power_score(by_id, levels, placed)
	assert(absf(score - 6.0) < 0.001, "poder ponderado del refugio (%f)" % score)
	assert(calculator.power_score(by_id, levels, {}) == 0.0, "sin colocar, poder 0")
	print("  poder: ponderado por categoria OK")


func _test_save_sanitize() -> void:
	var save_data := load("res://scripts/save/save_data.gd")
	# Save antiguo SIN bloque shelter: defaults completos, sin crash.
	var old: Dictionary = save_data.sanitize({"total_sardines": 50})
	assert(typeof(old.get("shelter")) == TYPE_DICTIONARY, "save antiguo recibe shelter por defecto")
	assert(Array(old["shelter"]["purchased_items"]).is_empty(), "shelter default vacio")
	# Save con shelter valido + basura: se sanea campo a campo.
	var dirty: Dictionary = save_data.sanitize({
		"shelter": {
			"purchased_items": ["combat_scratcher", 42],
			"item_levels": {"combat_scratcher": "3"},
			"placed_slots": {"training_1": "combat_scratcher"},
			"seen_tutorial": 1,
			"total_spent": -5,
			"campo_raro": {"x": 1},
		}
	})
	var shelter: Dictionary = dirty["shelter"]
	assert(Array(shelter["purchased_items"]).has("combat_scratcher"), "compra sobrevive")
	assert(int(shelter["item_levels"]["combat_scratcher"]) == 3, "nivel saneado desde string")
	assert(str(shelter["placed_slots"]["training_1"]) == "combat_scratcher", "colocacion sobrevive")
	assert(int(shelter["total_spent"]) == 0, "total_spent nunca negativo")
	assert(not shelter.has("campo_raro"), "campos desconocidos del bloque se descartan")
	print("  save: bloque shelter compatible con saves antiguos")
