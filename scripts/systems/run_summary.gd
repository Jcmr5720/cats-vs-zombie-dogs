class_name RunSummary
extends RefCounted
## Resumen de una partida (Fase 07). Estructura unica que recoge el estado al terminar
## (por victoria o derrota) y se convierte en Dictionary para el HUD, el calculo de
## Sardinas (MetaProgression) y el registro en SaveManager.

var map_id: StringName = &""
var map_name: String = ""
var victory: bool = false
var victory_message: String = "ZONA ASEGURADA"
var time_survived: float = 0.0
var enemies_killed: int = 0
var cats_rescued: int = 0
var active_companions: int = 0
var downed_companions: int = 0
var level_reached: int = 1
var weapons_used: int = 0
var weapons_levels: int = 0
var mini_bosses_defeated: int = 0
var bosses_defeated: int = 0
var sardines_earned: int = 0
var sardines_total_after: int = 0
var sardine_breakdown: Dictionary = {}
## Semilla del mundo de la run (para mostrar/rejugar mundos concretos).
var world_seed: int = 0
## Puntuacion de Partida libre (Fase Arcade). -1 = no aplica (Modo Historia), y el HUD
## muestra Sardinas en su lugar. En Partida libre es >= 0 y sustituye a las Sardinas.
var score: int = -1
var score_breakdown: Dictionary = {}
var best_score: int = 0
var is_new_record: bool = false


func to_dict() -> Dictionary:
	return {
		"map_id": map_id,
		"map_name": map_name,
		"victory": victory,
		"victory_message": victory_message,
		"time": time_survived,
		"kills": enemies_killed,
		"cats": cats_rescued,
		"active_companions": active_companions,
		"downed_companions": downed_companions,
		"level": level_reached,
		"weapons": weapons_used,
		"weapons_levels": weapons_levels,
		"minibosses": mini_bosses_defeated,
		"bosses": bosses_defeated,
		"sardines_earned": sardines_earned,
		"total_sardines": sardines_total_after,
		"sardine_breakdown": sardine_breakdown,
		"world_seed": world_seed,
		"score": score,
		"score_breakdown": score_breakdown,
		"best_score": best_score,
		"is_new_record": is_new_record,
	}
