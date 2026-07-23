class_name RunScript
extends RefCounted
## Guion procedural de la partida (FASE 11). La semilla de la run no solo decide
## geometria: tambien elige de forma DETERMINISTA el evento central del mapa, la
## mutacion elite dominante, el modificador del jefe y la variante de apertura.
## Misma semilla + mismo mapa = mismo guion; semillas distintas cambian tanto el
## layout como la historia mecanica de la partida.
##
## Cada eleccion usa un hash con salt PROPIO (estilo WorldSeedManager): añadir o
## quitar un pool no desplaza las demas decisiones.

## Evento central (ventana 110-155 s). &"" = el mapa no define pool.
var central_event: StringName = &""
## Mutacion elite dominante: pesa el doble en el sorteo de elites.
var dominant_mutation: StringName = &""
## Modificador del jefe de esta partida (boss.gd::apply_run_modifier).
var boss_modifier: StringName = &""
## Variante de apertura (0 = base, 1 = alternativa del MapData).
var opening_variant: int = 0


## Construye el guion desde el MapData y la seed de la run. Determinista y puro.
static func generate(map_data, world_seed: int) -> RunScript:
	var rs := RunScript.new()
	if map_data == null:
		return rs
	var map_id: String = str(map_data.id)
	rs.central_event = _pick(map_data.dynamic_event_pool, world_seed, map_id, "event")
	rs.dominant_mutation = _pick(map_data.biome_mutations, world_seed, map_id, "mutation")
	rs.boss_modifier = _pick(map_data.boss_modifier_pool, world_seed, map_id, "boss")
	rs.opening_variant = _hash01(world_seed, map_id, "opening") % 2
	return rs


## Eleccion determinista de un pool (vacio-seguro).
static func _pick(pool: Array, world_seed: int, map_id: String, salt: String) -> StringName:
	if pool == null or pool.is_empty():
		return &""
	return pool[_hash01(world_seed, map_id, salt) % pool.size()]


static func _hash01(world_seed: int, map_id: String, salt: String) -> int:
	# `hash()` reparte bien EN CONJUNTO, pero sus bits BAJOS quedan correlacionados
	# entre cadenas parecidas: como todos los pools se indexan con `% size` (casi
	# siempre % 2), evento, mutacion y apertura salian encadenados y el Barrio
	# solo producia 2 guiones reales en vez de todas las combinaciones.
	# Se mezcla con un avalanche estilo splitmix64 para que cada decision use
	# bits realmente independientes.
	# Se pasa el hash por un RandomNumberGenerator (mismo idioma que
	# `CityPlan.hash01`): su salida SI reparte bien los bits bajos, que son los
	# que consumen los `% pool.size()`.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("runscript:%d:%s:%s" % [world_seed, map_id, salt])
	return absi(rng.randi())


## Resumen legible del guion (pausa/debug/tests).
func describe() -> String:
	var parts: PackedStringArray = []
	if central_event != &"":
		parts.append("Evento: %s" % central_event)
	if dominant_mutation != &"":
		parts.append("Mutación: %s" % dominant_mutation)
	if boss_modifier != &"":
		parts.append("Jefe: %s" % boss_modifier)
	if parts.is_empty():
		return "Sin guion"
	return " · ".join(parts)
