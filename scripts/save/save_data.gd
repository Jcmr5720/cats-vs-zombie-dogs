class_name SaveData
extends RefCounted
## Esquema del guardado local (Fase 07). Centraliza la estructura por defecto y la
## normalizacion para que SaveManager nunca crashee con un archivo viejo, corrupto o
## incompleto: cualquier campo que falte se rellena con su valor por defecto.

## Version del esquema (para migraciones futuras).
const VERSION: int = 1

## Estructura por defecto de un save nuevo.
static func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"save_version": VERSION,
		"total_sardines": 0,
		"total_runs": 0,
		"total_victories": 0,
		"best_time_by_map": {},        # { map_id: segundos }
		"unlocked_maps": ["neighborhood"],
		"completed_maps": [],          # mapas asegurados al menos una vez
		"permanent_upgrades": {},      # { upgrade_id: nivel }
		"unlocked_features": [],
		"first_time_played": "",
		"last_played_at": "",
		# Estadisticas acumuladas (Fase 08). Se rellenan a 0 en saves antiguos.
		"lifetime_sardines_earned": 0,
		"total_kills": 0,
		"total_minibosses": 0,
		"total_bosses": 0,
		"total_cats_rescued": 0,
		"best_level": 0,
		# Modo Historia (Fase 09): capitulo mas alto completado y dificultad global.
		"story_chapters_cleared": 0,
		"story_difficulty": 1,
		# Refugio Felino (Fase 10): objetos comprados, niveles y colocacion.
		"shelter": {
			"purchased_items": [],
			"item_levels": {},
			"placed_slots": {},
			"seen_tutorial": false,
			"total_spent": 0,
		},
	}


## Devuelve un dato saneado: parte de los defaults y sobreescribe con lo valido del
## archivo. Tolera tipos raros sin romper.
static func sanitize(raw: Variant) -> Dictionary:
	var data: Dictionary = defaults()
	if typeof(raw) != TYPE_DICTIONARY:
		return data
	var source: Dictionary = raw
	data["version"] = _as_int(source.get("version", source.get("save_version", VERSION)))
	data["save_version"] = data["version"]

	data["total_sardines"] = maxi(0, _as_int(source.get("total_sardines", 0)))
	data["total_runs"] = maxi(0, _as_int(source.get("total_runs", 0)))
	data["total_victories"] = maxi(0, _as_int(source.get("total_victories", 0)))

	if typeof(source.get("best_time_by_map")) == TYPE_DICTIONARY:
		var best: Dictionary = {}
		for key in source["best_time_by_map"]:
			best[str(key)] = float(source["best_time_by_map"][key])
		data["best_time_by_map"] = best

	if typeof(source.get("unlocked_maps")) == TYPE_ARRAY:
		var maps: Array = []
		for m in source["unlocked_maps"]:
			maps.append(str(m))
		if not maps.has("neighborhood"):
			maps.append("neighborhood")
		data["unlocked_maps"] = maps

	if typeof(source.get("permanent_upgrades")) == TYPE_DICTIONARY:
		var ups: Dictionary = {}
		for key in source["permanent_upgrades"]:
			ups[str(key)] = maxi(0, _as_int(source["permanent_upgrades"][key]))
		data["permanent_upgrades"] = ups

	if typeof(source.get("unlocked_features")) == TYPE_ARRAY:
		data["unlocked_features"] = source["unlocked_features"].duplicate()

	if typeof(source.get("completed_maps")) == TYPE_ARRAY:
		var done: Array = []
		for m in source["completed_maps"]:
			done.append(str(m))
		data["completed_maps"] = done

	# Estadisticas acumuladas (Fase 08): saves antiguos quedan en 0 sin romperse.
	data["lifetime_sardines_earned"] = maxi(0, _as_int(source.get("lifetime_sardines_earned", 0)))
	data["total_kills"] = maxi(0, _as_int(source.get("total_kills", 0)))
	data["total_minibosses"] = maxi(0, _as_int(source.get("total_minibosses", 0)))
	data["total_bosses"] = maxi(0, _as_int(source.get("total_bosses", 0)))
	data["total_cats_rescued"] = maxi(0, _as_int(source.get("total_cats_rescued", 0)))
	data["best_level"] = maxi(0, _as_int(source.get("best_level", 0)))

	data["first_time_played"] = str(source.get("first_time_played", ""))
	data["last_played_at"] = str(source.get("last_played_at", ""))

	# Modo Historia (Fase 09).
	data["story_chapters_cleared"] = clampi(_as_int(source.get("story_chapters_cleared", 0)), 0, 6)
	data["story_difficulty"] = clampi(_as_int(source.get("story_difficulty", 1)), 0, 3)

	# Refugio Felino (Fase 10): estructura anidada saneada campo a campo.
	# Saves antiguos sin "shelter" conservan los defaults de arriba.
	if typeof(source.get("shelter")) == TYPE_DICTIONARY:
		var raw_shelter: Dictionary = source["shelter"]
		var shelter: Dictionary = data["shelter"]
		if typeof(raw_shelter.get("purchased_items")) == TYPE_ARRAY:
			var purchased: Array = []
			for item in raw_shelter["purchased_items"]:
				purchased.append(str(item))
			shelter["purchased_items"] = purchased
		if typeof(raw_shelter.get("item_levels")) == TYPE_DICTIONARY:
			var levels: Dictionary = {}
			for key in raw_shelter["item_levels"]:
				levels[str(key)] = maxi(1, _as_int(raw_shelter["item_levels"][key]))
			shelter["item_levels"] = levels
		if typeof(raw_shelter.get("placed_slots")) == TYPE_DICTIONARY:
			var placed: Dictionary = {}
			for key in raw_shelter["placed_slots"]:
				placed[str(key)] = str(raw_shelter["placed_slots"][key])
			shelter["placed_slots"] = placed
		shelter["seen_tutorial"] = bool(raw_shelter.get("seen_tutorial", false))
		shelter["total_spent"] = maxi(0, _as_int(raw_shelter.get("total_spent", 0)))
		data["shelter"] = shelter

	# Passthrough de claves dinamicas: todo lo escrito via SaveManager.set_value
	# (mission_stat_*, mission_done_*, plague_unlocked_*, story_clear_*) debe
	# sobrevivir al saneo. Solo tipos primitivos, para que un save manipulado no
	# pueda inyectar estructuras raras.
	for key in source:
		if data.has(key):
			continue
		if typeof(source[key]) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			data[key] = source[key]
	return data


static func _as_int(value: Variant) -> int:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING and value.is_valid_int():
		return value.to_int()
	return 0
