extends Node
## Gestiona las mejoras permanentes (Fase 07). Autoload "MetaProgression": carga los
## PermanentUpgradeData, calcula costos, valida y aplica compras (gastando Sardinas via
## SaveManager) y expone los efectos acumulados a los sistemas (Player, WeaponManager,
## RescueSpawner, calculo de recompensa y dificultad).
##
## Desacoplado: los sistemas piden `get_effect_total(tipo)` sin conocer las mejoras
## concretas. Agregar una mejora = soltar un .tres en data/permanent_upgrades y, si es
## un efecto nuevo, leerlo donde corresponda.

@warning_ignore("shadowed_global_identifier")
const PermanentUpgradeData = preload("res://scripts/meta/permanent_upgrade_data.gd")

const UPGRADE_PATHS: Array[String] = [
	"res://data/permanent_upgrades/sharp_claws.tres",
	"res://data/permanent_upgrades/light_paws.tres",
	"res://data/permanent_upgrades/nine_lives.tres",
	"res://data/permanent_upgrades/feline_instinct.tres",
	"res://data/permanent_upgrades/sardine_bag.tres",
	"res://data/permanent_upgrades/colony_call.tres",
	"res://data/permanent_upgrades/feline_mechanics.tres",
	# Mejoras desbloqueables por hitos del Modo Historia (Fase 09).
	"res://data/permanent_upgrades/bigotes_radar.tres",
	"res://data/permanent_upgrades/pelaje_erizado.tres",
	"res://data/permanent_upgrades/corazon_de_leon.tres",
	# Agencia en el level-up (Rework de adictividad): rerolls/vetos extra por run.
	"res://data/permanent_upgrades/lucky_paw.tres",
	"res://data/permanent_upgrades/picky_eater.tres",
]

## Bonus de Sardinas por asegurar cada mapa (victoria).
const VICTORY_BONUS: Dictionary = {
	"neighborhood": 50,
	"park": 70,
	"industrial_alley": 90,
	# Mapas del Modo Historia (Fase 09): pagan mas que sus versiones base.
	"neighborhood_dark": 100,
	"park_dark": 110,
	"factory": 140,
}

const MAP_BASE_REWARD: Dictionary = {
	"neighborhood": 6,
	"park": 8,
	"industrial_alley": 10,
	"neighborhood_dark": 11,
	"park_dark": 12,
	"factory": 14,
}

const MAP_REWARD_MULT: Dictionary = {
	"neighborhood": 1.0,
	"park": 1.15,
	"industrial_alley": 1.30,
	"neighborhood_dark": 1.35,
	"park_dark": 1.40,
	"factory": 1.50,
}

signal upgrades_changed()

var _upgrades: Array[PermanentUpgradeData] = []


func _ready() -> void:
	for path in UPGRADE_PATHS:
		var data: PermanentUpgradeData = load(path)
		if data != null:
			_upgrades.append(data)


# --- Consulta ----------------------------------------------------------------

func get_upgrades() -> Array:
	return _upgrades


func _save_manager() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("SaveManager")


func get_level(id: StringName) -> int:
	var sm := _save_manager()
	if sm == null:
		return 0
	return sm.get_upgrade_level(id)


func get_upgrade_by_id(id: StringName) -> PermanentUpgradeData:
	for up in _upgrades:
		if up.id == id:
			return up
	return null


## True si la mejora esta disponible (0 = siempre; N = requiere haber completado
## el capitulo N del Modo Historia).
func is_upgrade_unlocked(up: PermanentUpgradeData) -> bool:
	if up == null:
		return false
	if up.unlock_story_chapter <= 0:
		return true
	var sm := _save_manager()
	if sm == null or not sm.has_method("get_value"):
		return false
	return int(sm.get_value("story_chapters_cleared", 0)) >= up.unlock_story_chapter


## Multiplicador del radio de recogida de XP (Bigotes Radar).
func pickup_range_mult() -> float:
	return 1.0 + get_effect_total(&"pickup_range_pct")


## Reduccion permanente de daño recibido, con tope sano (Pelaje Erizado).
func permanent_damage_reduction() -> float:
	return clampf(get_effect_total(&"damage_reduction_pct"), 0.0, 0.25)


## Multiplicador de daño de los compañeros (Corazon de Leon).
func companion_damage_mult() -> float:
	return 1.0 + get_effect_total(&"companion_damage_pct")


## Costo del SIGUIENTE nivel; -1 si ya esta al maximo.
func get_next_cost(up: PermanentUpgradeData) -> int:
	var level: int = get_level(up.id)
	if level >= up.max_level:
		return -1
	return int(round(up.base_cost * pow(up.cost_growth, level)))


## Suma del efecto de un tipo sobre todas las mejoras (valor * nivel).
func get_effect_total(effect_type: StringName) -> float:
	var total: float = 0.0
	for up in _upgrades:
		if up.effect_type == effect_type:
			total += up.effect_value_per_level * float(get_level(up.id))
	return total


## Suma de niveles permanentes (lo usa la dificultad: builds permanentes = mas presion).
func get_permanent_power_score() -> float:
	var total: float = 0.0
	for up in _upgrades:
		var weight: float = 1.0
		match up.effect_type:
			&"player_damage_pct", &"max_health_flat":
				weight = 1.15
			&"sardine_pct":
				weight = 0.75
			&"first_rescue_seconds":
				weight = 0.65
		total += float(get_level(up.id)) * weight
	return total


# --- Compra ------------------------------------------------------------------

## Intenta comprar un nivel. Devuelve true si se compro. Si falla el guardado,
## revierte la compra para no perder Sardinas.
func purchase(id: StringName) -> bool:
	var up := get_upgrade_by_id(id)
	var sm := _save_manager()
	if up == null or sm == null or not is_upgrade_unlocked(up):
		return false
	var level: int = get_level(id)
	if level >= up.max_level:
		return false
	var cost: int = get_next_cost(up)
	if sm.get_sardines() < cost:
		return false
	if not sm.spend_sardines(cost):
		return false

	sm.set_upgrade_level(id, level + 1)
	if not sm.save():
		# Guardado fallo: revierte para no quedar inconsistente.
		sm.set_upgrade_level(id, level)
		sm.add_sardines(cost)
		return false
	upgrades_changed.emit()
	return true


func can_purchase(id: StringName) -> bool:
	var up := get_upgrade_by_id(id)
	var sm := _save_manager()
	if up == null or sm == null or not is_upgrade_unlocked(up):
		return false
	var cost: int = get_next_cost(up)
	return cost >= 0 and sm.get_sardines() >= cost


# --- Recompensa de Sardinas --------------------------------------------------

## Calcula las Sardinas ganadas en una partida segun su resumen (Dictionary).
## Aplica el bonus permanente de "Mochila de Sardinas". Nunca devuelve menos de 1.
func compute_sardines(summary: Dictionary) -> int:
	return int(compute_sardine_breakdown(summary).get("total", 1))


func compute_sardine_breakdown(summary: Dictionary) -> Dictionary:
	var map_id: String = str(summary.get("map_id", ""))
	var victory: bool = bool(summary.get("victory", false))
	var time_value: int = int(floor(float(summary.get("time", 0.0)) / 12.0))
	var kill_value: int = int(round(float(summary.get("kills", 0)) * 0.15))
	var cats_value: int = int(summary.get("cats", 0)) * 8
	var active_value: int = int(summary.get("active_companions", 0)) * 5
	var miniboss_value: int = int(summary.get("minibosses", 0)) * 18
	var boss_value: int = int(summary.get("bosses", 0)) * 45
	var objective_value: int = _objective_bonus(summary)
	var victory_value: int = int(VICTORY_BONUS.get(map_id, 50)) if victory else 0
	var base_map_value: int = int(MAP_BASE_REWARD.get(map_id, 5))

	var subtotal: float = float(base_map_value + time_value + kill_value + cats_value + active_value + miniboss_value + boss_value + objective_value + victory_value)
	var map_mult: float = float(MAP_REWARD_MULT.get(map_id, 1.0))
	var sardine_mult: float = 1.0 + get_effect_total(&"sardine_pct")
	var total: int = int(round(subtotal * map_mult * sardine_mult))
	if float(summary.get("time", 0.0)) < 30.0 and not victory:
		total = min(total, 8)
	if float(summary.get("time", 0.0)) >= 60.0:
		total = max(total, 12)
	total = maxi(1, total)

	return {
		"base_map": base_map_value,
		"time": time_value,
		"kills": kill_value,
		"cats": cats_value,
		"active_companions": active_value,
		"minibosses": miniboss_value,
		"bosses": boss_value,
		"objective": objective_value,
		"victory": victory_value,
		"map_multiplier": map_mult,
		"sardine_multiplier": sardine_mult,
		"subtotal": subtotal,
		"total": total,
	}


func _objective_bonus(summary: Dictionary) -> int:
	if bool(summary.get("victory", false)):
		return 20
	var value: int = 0
	if int(summary.get("cats", 0)) > 0:
		value += 4
	if int(summary.get("minibosses", 0)) > 0:
		value += 6
	if int(summary.get("bosses", 0)) > 0:
		value += 10
	return value


# --- Aplicacion de efectos al inicio de partida ------------------------------
# Helpers semanticos para que los sistemas no repitan los StringName.

func player_damage_mult() -> float:
	return 1.0 + get_effect_total(&"player_damage_pct")


func player_speed_mult() -> float:
	return 1.0 + get_effect_total(&"player_speed_pct")


func max_health_bonus() -> int:
	return int(round(get_effect_total(&"max_health_flat")))


func xp_mult() -> float:
	return 1.0 + get_effect_total(&"xp_pct")


func weapon_cooldown_mult() -> float:
	# Reduccion: -% => multiplicador < 1.
	return clampf(1.0 - get_effect_total(&"weapon_cooldown_pct"), 0.7, 1.0)


func first_rescue_seconds_reduction() -> float:
	return min(20.0, get_effect_total(&"first_rescue_seconds"))


func format_effect(up: PermanentUpgradeData, level: int) -> String:
	var value: float = up.effect_value_per_level * float(level)
	match up.effect_type:
		&"player_damage_pct":
			return "+%d%% dano inicial" % int(round(value * 100.0))
		&"player_speed_pct":
			return "+%d%% velocidad inicial" % int(round(value * 100.0))
		&"max_health_flat":
			return "+%d vida maxima" % int(round(value))
		&"xp_pct":
			return "+%d%% experiencia ganada" % int(round(value * 100.0))
		&"sardine_pct":
			return "+%d%% Sardinas ganadas" % int(round(value * 100.0))
		&"first_rescue_seconds":
			return "Primer rescate %.0fs antes" % min(20.0, value)
		&"weapon_cooldown_pct":
			return "-%d%% cooldown inicial" % int(round(value * 100.0))
		&"pickup_range_pct":
			return "+%d%% radio de recogida" % int(round(value * 100.0))
		&"damage_reduction_pct":
			return "-%d%% daño recibido" % int(round(minf(value, 0.25) * 100.0))
		&"companion_damage_pct":
			return "+%d%% daño de compañeros" % int(round(value * 100.0))
		&"reroll_per_run":
			return "+%d re-tiradas por partida" % int(round(value))
		&"banish_per_run":
			return "+%d vetos por partida" % int(round(value))
	return up.description
