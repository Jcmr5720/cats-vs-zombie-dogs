class_name FreePlayScore
extends RefCounted
## Puntuacion de Partida libre (Fase Arcade). Partida libre no da Sardinas: es un modo
## competitivo puro. En su lugar produce una PUNTUACION por partida y un RECORD local
## por mapa + dificultad, para "superarte o superar a tu amigo en la misma maquina".
##
## Sin estado: todo estatico, como StoryCampaign. La fuente de verdad del record vive
## en el save (clave generica best_score_<map>_d<tier>, sin cambios de esquema).

const StoryCampaign = preload("res://scripts/story/story_campaign.gd")

## Pesos base de la puntuacion (editables). Premian jugar agresivo y llegar lejos.
const KILL_POINTS: int = 10
const LEVEL_POINTS: int = 50
const CAT_POINTS: int = 100
const MINIBOSS_POINTS: int = 150
const BOSS_POINTS: int = 400
const TIME_POINTS_PER_SECOND: int = 2
const VICTORY_BONUS: int = 500


## Calcula la puntuacion final. `summary` es RunSummary.to_dict(); `tier` 0-3;
## `plague` 1-5. Devuelve {total: int, breakdown: Dictionary}.
static func compute(summary: Dictionary, tier: int, plague: int) -> Dictionary:
	var kills: int = int(summary.get("kills", 0))
	var level: int = int(summary.get("level", 1))
	var cats: int = int(summary.get("cats", 0))
	var minibosses: int = int(summary.get("minibosses", 0))
	var bosses: int = int(summary.get("bosses", 0))
	var seconds: int = int(floor(float(summary.get("time", 0.0))))
	var victory: bool = bool(summary.get("victory", false))

	var breakdown: Dictionary = {
		"kills": kills * KILL_POINTS,
		"level": level * LEVEL_POINTS,
		"cats": cats * CAT_POINTS,
		"minibosses": minibosses * MINIBOSS_POINTS,
		"bosses": bosses * BOSS_POINTS,
		"time": seconds * TIME_POINTS_PER_SECOND,
		"victory": VICTORY_BONUS if victory else 0,
	}
	var subtotal: int = 0
	for key in breakdown:
		subtotal += int(breakdown[key])

	# Multiplicadores de reto: dificultad elegida (como Historia) y Nivel de Plaga.
	var difficulty_mult: float = float(StoryCampaign.get_difficulty(tier)["reward"])
	var plague_mult: float = 1.0 + 0.5 * float(max(0, plague - 1))
	var total: int = int(round(float(subtotal) * difficulty_mult * plague_mult))

	breakdown["subtotal"] = subtotal
	breakdown["difficulty_mult"] = difficulty_mult
	breakdown["plague_mult"] = plague_mult
	breakdown["total"] = total
	return {"total": total, "breakdown": breakdown}


## Clave de save del record por mapa + dificultad (tier 0-3).
static func record_key(map_id: StringName, tier: int) -> String:
	return "best_score_%s_d%d" % [str(map_id), clampi(tier, 0, 3)]


## Mejor puntuacion guardada de un mapa en una dificultad (0 si no hay).
static func get_best(save: Node, map_id: StringName, tier: int) -> int:
	if save == null or not save.has_method("get_value"):
		return 0
	return int(save.get_value(record_key(map_id, tier), 0))


## Mejor puntuacion de un mapa entre TODAS las dificultades. Devuelve {score, tier};
## score 0 si no hay ningun record.
static func get_best_any(save: Node, map_id: StringName) -> Dictionary:
	var best_score: int = 0
	var best_tier: int = 0
	for tier in StoryCampaign.DIFFICULTIES.size():
		var s: int = get_best(save, map_id, tier)
		if s > best_score:
			best_score = s
			best_tier = tier
	return {"score": best_score, "tier": best_tier}
