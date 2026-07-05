class_name ShelterBonusCalculator
extends RefCounted
## Calcula las bonificaciones activas del Refugio (Fase 10) a partir de los
## objetos COLOCADOS y sus niveles. Funciones puras + topes de balance: el
## refugio ayuda, nunca rompe el juego. Los sistemas leen el diccionario
## resultante al iniciar la run (via el autoload Shelter).

## Topes de balance por clave del diccionario de bonus.
const CAPS: Dictionary = {
	"player_damage_bonus": 0.15,
	"player_speed_bonus": 0.10,
	"player_max_health_bonus": 25.0,
	"companion_health_bonus": 25.0,
	"companion_police_damage_bonus": 0.25,
	"companion_engineer_damage_bonus": 0.25,
	"medic_heal_bonus": 5.0,
	"sardines_reward_bonus": 0.25,
	"rescue_first_spawn_reduction": 15.0,
	"rescue_distance_modifier": 0.15,
	"damage_reduction_bonus": 0.10,
	"upgrade_rarity_bonus": 0.10,
}

## Traduce el effect_type del objeto a la clave del diccionario de bonus.
const EFFECT_TO_KEY: Dictionary = {
	&"player_damage_pct": "player_damage_bonus",
	&"player_speed_pct": "player_speed_bonus",
	&"player_health_flat": "player_max_health_bonus",
	&"companion_health_flat": "companion_health_bonus",
	&"police_damage_pct": "companion_police_damage_bonus",
	&"engineer_damage_pct": "companion_engineer_damage_bonus",
	&"medic_heal_flat": "medic_heal_bonus",
	&"sardine_pct": "sardines_reward_bonus",
	&"rescue_first_seconds": "rescue_first_spawn_reduction",
	&"rescue_distance_pct": "rescue_distance_modifier",
	&"damage_reduction_pct": "damage_reduction_bonus",
	&"upgrade_rarity_pct": "upgrade_rarity_bonus",
}


static func empty_bonuses() -> Dictionary:
	var out: Dictionary = {}
	for key in CAPS:
		out[key] = 0.0
	return out


## Suma los efectos de los objetos colocados (items_by_id: id -> ShelterItemData,
## levels: id -> int, placed_slots: slot_id -> item_id) y aplica los topes.
static func compute(items_by_id: Dictionary, levels: Dictionary, placed_slots: Dictionary) -> Dictionary:
	var out: Dictionary = empty_bonuses()
	for slot_id in placed_slots:
		var item_id: String = str(placed_slots[slot_id])
		var item = items_by_id.get(item_id)
		if item == null:
			continue
		var key: String = str(EFFECT_TO_KEY.get(item.effect_type, ""))
		if key == "":
			continue
		var level: int = maxi(1, int(levels.get(item_id, 1)))
		out[key] = float(out[key]) + item.effect_value_per_level * float(level)
	for key in out:
		out[key] = clampf(float(out[key]), 0.0, float(CAPS[key]))
	return out


## Nombre legible de cada clave de bonus (para el panel "Bonificaciones activas").
const KEY_LABELS: Dictionary = {
	"player_damage_bonus": "Daño inicial",
	"player_speed_bonus": "Velocidad",
	"player_max_health_bonus": "Vida maxima",
	"companion_health_bonus": "Vida compañeros",
	"companion_police_damage_bonus": "Daño Gato Policia",
	"companion_engineer_damage_bonus": "Daño Gato Ingeniero",
	"medic_heal_bonus": "Cura Gato Medico",
	"sardines_reward_bonus": "Sardinas ganadas",
	"rescue_first_spawn_reduction": "Primer rescate",
	"rescue_distance_modifier": "Distancia de rescates",
	"damage_reduction_bonus": "Reduccion de daño",
	"upgrade_rarity_bonus": "Rareza de cartas",
}


## Linea legible de un bonus agregado ("Daño inicial: +6%"). "" si es cero.
static func format_key(key: String, value: float) -> String:
	if value <= 0.0:
		return ""
	var label: String = str(KEY_LABELS.get(key, key))
	match key:
		"player_max_health_bonus", "companion_health_bonus", "medic_heal_bonus":
			return "%s: +%d" % [label, int(round(value))]
		"rescue_first_spawn_reduction":
			return "%s: -%ds" % [label, int(round(value))]
		"rescue_distance_modifier":
			return "%s: -%d%%" % [label, int(round(value * 100.0))]
		"damage_reduction_bonus":
			return "%s: -%d%% daño" % [label, int(round(value * 100.0))]
		_:
			return "%s: +%d%%" % [label, int(round(value * 100.0))]


## Texto del efecto de UN objeto a un nivel dado ("+3% daño inicial" x nivel).
static func format_effect(effect_type: StringName, value_per_level: float, level: int) -> String:
	var key: String = str(EFFECT_TO_KEY.get(effect_type, ""))
	if key == "":
		return ""
	return format_key(key, value_per_level * float(maxi(0, level)))


## Poder del refugio para la dificultad dinamica: suma ponderada de niveles de
## los objetos COLOCADOS (los de economia/rescate pesan menos: no dan combate).
static func power_score(items_by_id: Dictionary, levels: Dictionary, placed_slots: Dictionary) -> float:
	var total: float = 0.0
	for slot_id in placed_slots:
		var item_id: String = str(placed_slots[slot_id])
		var item = items_by_id.get(item_id)
		if item == null:
			continue
		var weight: float = 1.0
		if item.category in [&"economia", &"rescate"]:
			weight = 0.5
		total += float(maxi(1, int(levels.get(item_id, 1)))) * weight
	return total
