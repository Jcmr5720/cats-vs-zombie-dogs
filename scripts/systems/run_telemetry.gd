class_name RunTelemetry
extends RefCounted
## Telemetria de partida (FASE 11). Sirve para DEMOSTRAR con numeros que dos
## mapas producen partidas distintas, en vez de afirmarlo por diseño.
##
## Esta APAGADA por defecto. Se enciende con la variable de entorno
## `RUN_TELEMETRY=1` (mismo patron que `BOSS_DEBUG`). Con la bandera apagada cada
## llamada es una comparacion de bool contra una `static var` ya resuelta y un
## return: no toca diccionarios, no formatea texto y no reserva memoria, asi que
## no altera el rendimiento normal del juego.
##
## Uso:
##   RunTelemetry.count(&"flanks_executed")
##   RunTelemetry.add_time(&"time_in_hazard", delta)
##   RunTelemetry.note(&"central_event", "lake_fog")
##   print(RunTelemetry.report())

## Resuelta UNA vez al cargar la clase: el coste en runtime es leer un bool.
static var enabled: bool = OS.has_environment("RUN_TELEMETRY")

static var _counters: Dictionary = {}
static var _times: Dictionary = {}
static var _notes: Dictionary = {}


## Suma a un contador entero (zonas creadas, flanqueos, marcas destruidas...).
static func count(key: StringName, amount: int = 1) -> void:
	if not enabled:
		return
	_counters[key] = int(_counters.get(key, 0)) + amount


## Acumula segundos (tiempo dentro de zonas peligrosas, tiempo en persecucion...).
static func add_time(key: StringName, seconds: float) -> void:
	if not enabled:
		return
	_times[key] = float(_times.get(key, 0.0)) + seconds


## Registra un valor unico de la partida (evento elegido, mutacion dominante...).
static func note(key: StringName, value: Variant) -> void:
	if not enabled:
		return
	_notes[key] = value


static func get_count(key: StringName) -> int:
	return int(_counters.get(key, 0))


static func get_time(key: StringName) -> float:
	return float(_times.get(key, 0.0))


static func get_note(key: StringName, fallback: Variant = null) -> Variant:
	return _notes.get(key, fallback)


## Limpia todo. Lo llama el arranque de partida: reiniciar no debe arrastrar los
## numeros de la run anterior.
static func reset() -> void:
	_counters.clear()
	_times.clear()
	_notes.clear()


## Resumen legible de la partida. Vacio si la telemetria esta apagada.
static func report() -> String:
	if not enabled:
		return ""
	var lines: PackedStringArray = ["--- RUN TELEMETRY ---"]
	var note_keys: Array = _notes.keys()
	note_keys.sort()
	for key in note_keys:
		lines.append("  %-24s %s" % [key, str(_notes[key])])
	var count_keys: Array = _counters.keys()
	count_keys.sort()
	for key in count_keys:
		lines.append("  %-24s %d" % [key, int(_counters[key])])
	var time_keys: Array = _times.keys()
	time_keys.sort()
	for key in time_keys:
		lines.append("  %-24s %.2f s" % [key, float(_times[key])])
	lines.append("--- END TELEMETRY ---")
	return "\n".join(lines)


## Volcado en una linea, apto para comparar dos partidas con diff/grep.
static func report_line() -> String:
	if not enabled:
		return ""
	var parts: PackedStringArray = []
	for key in _notes.keys():
		parts.append("%s=%s" % [key, str(_notes[key])])
	for key in _counters.keys():
		parts.append("%s=%d" % [key, int(_counters[key])])
	for key in _times.keys():
		parts.append("%s=%.2f" % [key, float(_times[key])])
	parts.sort()
	return "TELEMETRY " + " ".join(parts)
