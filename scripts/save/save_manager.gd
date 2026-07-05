extends Node
## Guardado local en JSON (Fase 07). Autoload "SaveManager": persiste entre partidas
## y entre sesiones. Carga al iniciar, crea save nuevo si no existe, y es robusto
## ante archivos corruptos (hace backup y arranca uno limpio en vez de crashear).
##
## Archivo: user://cats_vs_zombie_dogs_save.json
## (en Windows: %APPDATA%/Godot/app_userdata/CatsVsZombieDogs/)
##
## No usa servidor, ni Supabase, ni Steam Cloud. Solo disco local.

const SaveData = preload("res://scripts/save/save_data.gd")

const SAVE_PATH: String = "user://cats_vs_zombie_dogs_save.json"
const BACKUP_PATH: String = "user://cats_vs_zombie_dogs_save_corrupt_backup.json"

@export var debug_add_sardines_amount: int = 500
@export var debug_enable_save_reset: bool = false
@export var debug_print_save_data: bool = false

signal sardines_changed(total: int)

var _data: Dictionary = {}


func _ready() -> void:
	load_save()


# --- Carga / guardado --------------------------------------------------------

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_data = SaveData.defaults()
		_data["first_time_played"] = Time.get_datetime_string_from_system()
		save()
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_data = SaveData.defaults()
		return
	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		# Archivo corrupto: respalda y arranca limpio (sin crashear).
		push_warning("SaveManager: save corrupto, creando uno nuevo (backup en .bak).")
		_backup_corrupt(text)
		_data = SaveData.defaults()
		save()
		return

	_data = SaveData.sanitize(parsed)
	if debug_print_save_data:
		print("SaveManager data: ", JSON.stringify(_data))


func save() -> bool:
	_data["last_played_at"] = Time.get_datetime_string_from_system()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: no se pudo abrir el save para escribir.")
		return false
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
	return true


func _backup_corrupt(text: String) -> void:
	var file := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


## Solo para desarrollo: borra el progreso y arranca un save limpio.
func reset_save() -> void:
	if not debug_enable_save_reset:
		push_warning("SaveManager: reset_save bloqueado; activa debug_enable_save_reset para desarrollo.")
		return
	_data = SaveData.defaults()
	_data["first_time_played"] = Time.get_datetime_string_from_system()
	save()
	sardines_changed.emit(get_sardines())


func force_reset_save_for_tests() -> void:
	_data = SaveData.defaults()
	_data["first_time_played"] = Time.get_datetime_string_from_system()
	save()
	sardines_changed.emit(get_sardines())


## Borrado de progreso iniciado por el jugador desde Opciones (con doble confirmacion
## en la UI). A diferencia de reset_save(), no esta detras del flag de debug.
func reset_progress() -> void:
	_data = SaveData.defaults()
	_data["first_time_played"] = Time.get_datetime_string_from_system()
	save()
	sardines_changed.emit(get_sardines())


## Reinicia solo la campana de Historia. Mantiene sardinas, mejoras y refugio, pero
## borra capitulos completados, first-clears por dificultad y desbloqueos derivados
## de mapas/plaga de partida libre para que el avance vuelva a depender de Historia.
func abandon_story_campaign() -> void:
	_data["story_chapters_cleared"] = 0
	_data["story_difficulty"] = 1
	var keys_to_remove: Array[String] = []
	for key in _data.keys():
		var text: String = str(key)
		if text.begins_with("story_clear_") or text.begins_with("plague_unlocked_"):
			keys_to_remove.append(text)
	for key in keys_to_remove:
		_data.erase(key)
	_data["unlocked_maps"] = ["neighborhood"]
	_data["completed_maps"] = []
	save()


func debug_add_sardines() -> void:
	add_sardines(debug_add_sardines_amount)
	save()


# --- Sardinas ----------------------------------------------------------------

func get_sardines() -> int:
	return int(_data.get("total_sardines", 0))


func get_data() -> Dictionary:
	return _data.duplicate(true)


func add_sardines(amount: int) -> void:
	if amount <= 0:
		return
	_data["total_sardines"] = get_sardines() + amount
	sardines_changed.emit(get_sardines())


func spend_sardines(amount: int) -> bool:
	if amount <= 0 or get_sardines() < amount:
		return false
	_data["total_sardines"] = get_sardines() - amount
	sardines_changed.emit(get_sardines())
	return true


# --- Mejoras permanentes -----------------------------------------------------

func get_upgrade_level(id: StringName) -> int:
	var ups: Dictionary = _data.get("permanent_upgrades", {})
	return int(ups.get(str(id), 0))


func set_upgrade_level(id: StringName, level: int) -> void:
	if not _data.has("permanent_upgrades"):
		_data["permanent_upgrades"] = {}
	_data["permanent_upgrades"][str(id)] = maxi(0, level)


# --- Mapas -------------------------------------------------------------------

func is_map_unlocked(map_id: StringName) -> bool:
	var maps: Array = _data.get("unlocked_maps", [])
	return maps.has(str(map_id))


func unlock_map(map_id: StringName) -> void:
	var maps: Array = _data.get("unlocked_maps", [])
	if not maps.has(str(map_id)):
		maps.append(str(map_id))
		_data["unlocked_maps"] = maps


# --- Registro de partida -----------------------------------------------------

## Registra el fin de una partida: suma sardinas, cuenta runs/victorias, mejor
## tiempo del mapa y desbloqueos. Persiste al disco.
func record_run(map_id: StringName, victory: bool, time_survived: float, sardines_earned: int, summary: Dictionary = {}) -> void:
	_data["total_runs"] = int(_data.get("total_runs", 0)) + 1
	if victory:
		_data["total_victories"] = int(_data.get("total_victories", 0)) + 1
	add_sardines(sardines_earned)
	_data["lifetime_sardines_earned"] = int(_data.get("lifetime_sardines_earned", 0)) + max(0, sardines_earned)

	var best: Dictionary = _data.get("best_time_by_map", {})
	var key: String = str(map_id)
	if not best.has(key) or time_survived > float(best[key]):
		best[key] = time_survived
	_data["best_time_by_map"] = best

	# Mapa completado (asegurado) al menos una vez.
	if victory:
		var done: Array = _data.get("completed_maps", [])
		if not done.has(key):
			done.append(key)
			_data["completed_maps"] = done

	# Estadisticas acumuladas (Fase 08), si llega el resumen de la partida.
	if not summary.is_empty():
		_data["total_kills"] = int(_data.get("total_kills", 0)) + int(summary.get("kills", 0))
		_data["total_minibosses"] = int(_data.get("total_minibosses", 0)) + int(summary.get("minibosses", 0))
		_data["total_bosses"] = int(_data.get("total_bosses", 0)) + int(summary.get("bosses", 0))
		_data["total_cats_rescued"] = int(_data.get("total_cats_rescued", 0)) + int(summary.get("cats", 0))
		_data["best_level"] = maxi(int(_data.get("best_level", 0)), int(summary.get("level", 0)))

	save()


func is_map_completed(map_id: StringName) -> bool:
	return Array(_data.get("completed_maps", [])).has(str(map_id))


func get_best_time(map_id: StringName) -> float:
	var best: Dictionary = _data.get("best_time_by_map", {})
	return float(best.get(str(map_id), 0.0))


# --- Acceso general ----------------------------------------------------------

func get_value(key: String, default_value: Variant) -> Variant:
	return _data.get(key, default_value)


func set_value(key: String, value: Variant, persist: bool = true) -> void:
	_data[key] = value
	if persist:
		save()


func get_data_copy() -> Dictionary:
	return _data.duplicate(true)
