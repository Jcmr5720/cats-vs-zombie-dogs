extends Node
## Gestiona la seleccion de mejoras al subir de nivel. Desde Fase 04 las cartas son
## DINAMICAS y de varios tipos: arma nueva, mejora de arma, stat general y companero.
## El pool se arma cada nivel segun el estado real (armas que tienes, su nivel,
## companeros rescatados), respetando: maximo 4 armas y nivel maximo por arma.

const WeaponData = preload("res://scripts/weapons/weapon_data.gd")

@export var player_path: NodePath
@export var hud_path: NodePath

## Pesos de aparicion por rareza (mayor = mas frecuente).
const RARITY_WEIGHTS: Dictionary = {
	&"common": 1.0,
	&"rare": 0.42,
	&"epic": 0.16,
}

## Cartas de stat general (afectan a TODAS las armas o al jugador).
## `affects`: a quien impacta la carta, para que el HUD lo muestre claro.
const STAT_POOL: Array[Dictionary] = [
	{"id": &"weapon_damage", "name": "Garras afiladas", "description": "+10% dano de todas las armas.", "rarity": &"common", "affects": "Armas"},
	{"id": &"player_speed", "name": "Patas veloces", "description": "+6% velocidad de movimiento.", "rarity": &"common", "affects": "Jugador"},
	{"id": &"max_health", "name": "Aguante felino", "description": "+15 vida maxima y cura ese valor.", "rarity": &"common", "affects": "Jugador"},
	{"id": &"weapon_range", "name": "Vista aguda", "description": "+10% rango de armas.", "rarity": &"common", "affects": "Armas"},
	{"id": &"weapon_cooldown", "name": "Reflejos rapidos", "description": "-10% cooldown de armas.", "rarity": &"rare", "affects": "Armas"},
	{"id": &"pickup_range", "name": "Olfato de tesoros", "description": "+25% radio de recoleccion de XP.", "rarity": &"rare", "affects": "Jugador"},
	{"id": &"extra_projectile", "name": "Furia multiple", "description": "+1 proyectil a las armas de proyectil.", "rarity": &"epic", "affects": "Armas"},
]

## Cartas de companero (solo aparecen si ya rescataste alguno).
const COMPANION_POOL: Array[Dictionary] = [
	{"id": &"companion_damage", "name": "Garras coordinadas", "description": "+10% dano de companeros.", "rarity": &"common"},
	{"id": &"companion_cooldown", "name": "Formacion agresiva", "description": "Companeros atacan 10% mas rapido.", "rarity": &"rare"},
	{"id": &"medic_boost", "name": "Botiquin felino", "description": "El gato medico cura +2.", "rarity": &"rare"},
	{"id": &"colony_protection", "name": "Proteccion de colonia", "description": "Companeros reciben 10% menos dano.", "rarity": &"rare"},
	{"id": &"quick_revive", "name": "Rescate rapido", "description": "Revives companeros 20% mas rapido.", "rarity": &"rare"},
	{"id": &"colony_bond", "name": "Vinculo felino", "description": "Con 2+ companeros activos, +5% dano del jugador.", "rarity": &"rare"},
]

var _player: Node
var _hud: Node
var _pending_level_ups: int = 0
var _selection_active: bool = false
var _current_cards: Array[Dictionary] = []


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_hud = get_node_or_null(hud_path)

	if _player != null and _player.has_signal("level_up_requested"):
		_player.level_up_requested.connect(_on_player_level_up_requested)

	if _hud != null and _hud.has_signal("upgrade_card_selected"):
		_hud.upgrade_card_selected.connect(_on_upgrade_card_selected)


func _on_player_level_up_requested(_level: int) -> void:
	_pending_level_ups += 1
	if not _selection_active:
		_show_next_selection()


func _show_next_selection() -> void:
	if _pending_level_ups <= 0:
		return
	if _hud == null or not _hud.has_method("show_upgrade_selection"):
		return

	_selection_active = true
	_current_cards = _draw_cards(3)
	# Si por algun motivo no hay cartas, no bloquees la partida.
	if _current_cards.is_empty():
		_selection_active = false
		_pending_level_ups = max(_pending_level_ups - 1, 0)
		return

	# Enfasis al subir de nivel: un shake breve (la camara procesa en pausa).
	Feedback.shake(0.35)

	get_tree().paused = true
	_hud.show_upgrade_selection(_current_cards)


## Construye el pool de candidatos segun el estado y sortea N cartas distintas.
func _draw_cards(amount: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = _build_candidates()
	var result: Array[Dictionary] = []

	while result.size() < amount and not candidates.is_empty():
		var picked_index: int = _weighted_pick_index(candidates)
		result.append(candidates[picked_index])
		candidates.remove_at(picked_index)

	return result


func _build_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var weapon_manager: Node = _get_weapon_manager()

	# 1) Cartas de arma (nueva o mejora), si hay WeaponManager.
	if weapon_manager != null:
		for data in weapon_manager.get_available_new_weapons():
			candidates.append({
				"card_type": &"new_weapon",
				"name": "Nuevo: %s" % data.display_name,
				"description": data.description,
				"rarity": data.rarity,
				"type_label": "Arma nueva",
				"affects": "Arma",
				"weight": max(0.05, data.rarity_weight),
				"weapon_data": data,
			})
		for weapon in weapon_manager.get_upgradable_weapons():
			var snapshot: Dictionary = weapon.get_snapshot()
			candidates.append({
				"card_type": &"weapon_upgrade",
				"name": "%s Nv. %d" % [snapshot["display_name"], int(snapshot["level"]) + 1],
				"description": weapon.next_level_description(),
				"rarity": weapon.data.rarity,
				"type_label": "Mejora de arma",
				"affects": "Arma",
				# Las mejoras de arma salen algo mas que armas nuevas para premiar builds.
				"weight": max(0.05, RARITY_WEIGHTS.get(weapon.data.rarity, 0.5)) * 1.3,
				"weapon_id": snapshot["id"],
			})

	# 2) Cartas de stat general.
	for entry in STAT_POOL:
		candidates.append({
			"card_type": &"stat",
			"name": entry["name"],
			"description": entry["description"],
			"rarity": entry["rarity"],
			"type_label": "Stat",
			"affects": entry.get("affects", "Jugador"),
			"weight": _rarity_weight(entry),
			"id": entry["id"],
		})

	# 3) Cartas de companero, solo si ya rescataste alguno.
	if _has_any_companion():
		for entry in COMPANION_POOL:
			candidates.append({
				"card_type": &"companion",
				"name": entry["name"],
				"description": entry["description"],
				"rarity": entry["rarity"],
				"type_label": "Companero",
				"affects": "Companeros",
				"weight": _rarity_weight(entry),
				"id": entry["id"],
			})

	return candidates


func _weighted_pick_index(cards: Array[Dictionary]) -> int:
	var total_weight: float = 0.0
	for card in cards:
		total_weight += float(card.get("weight", 1.0))

	var roll: float = randf() * total_weight
	for index in cards.size():
		roll -= float(cards[index].get("weight", 1.0))
		if roll <= 0.0:
			return index

	return cards.size() - 1


var _shelter_rarity_cached: float = -1.0


func _rarity_weight(card: Dictionary) -> float:
	var rarity: StringName = card.get("rarity", &"common")
	var weight: float = RARITY_WEIGHTS.get(rarity, 1.0)
	# Refugio (Fase 10): la Caja de Suministros sube el peso de raras/epicas
	# (leve, tope +10% garantizado por el calculador). Se lee una vez por run.
	if rarity != &"common":
		weight *= 1.0 + _shelter_rarity_bonus()
	return weight


func _shelter_rarity_bonus() -> float:
	if _shelter_rarity_cached < 0.0:
		_shelter_rarity_cached = 0.0
		var shelter: Node = get_node_or_null("/root/Shelter")
		if shelter != null and shelter.has_method("get_bonus"):
			_shelter_rarity_cached = clampf(float(shelter.get_bonus("upgrade_rarity_bonus")), 0.0, 0.10)
	return _shelter_rarity_cached


func _on_upgrade_card_selected(card_index: int) -> void:
	if not _selection_active:
		return
	if card_index < 0 or card_index >= _current_cards.size():
		return

	var card: Dictionary = _current_cards[card_index]
	_apply_card(card)

	_pending_level_ups = max(_pending_level_ups - 1, 0)
	_selection_active = false
	_current_cards.clear()
	if _hud != null and _hud.has_method("hide_upgrade_selection"):
		_hud.hide_upgrade_selection()

	if _pending_level_ups > 0:
		_show_next_selection()
	else:
		get_tree().paused = false


func _apply_card(card: Dictionary) -> void:
	var weapon_manager: Node = _get_weapon_manager()
	match card.get("card_type", &"stat"):
		&"new_weapon":
			if weapon_manager != null:
				weapon_manager.add_weapon(card.get("weapon_data"))
			_note_upgrade(&"new_weapon")
		&"weapon_upgrade":
			if weapon_manager != null:
				weapon_manager.level_up_weapon(card.get("weapon_id", &""))
			_note_upgrade(&"weapon_upgrade")
		_:
			if _player != null and _player.has_method("apply_upgrade"):
				_player.apply_upgrade(card.get("id", &""))


func _note_upgrade(id: StringName) -> void:
	# Las cartas de arma tambien cuentan como mejora elegida (afecta dificultad).
	if _player != null and _player.has_method("apply_upgrade"):
		_player.apply_upgrade(id)


func _get_weapon_manager() -> Node:
	if _player != null and _player.has_method("get_weapon_manager"):
		return _player.get_weapon_manager()
	return null


func _has_any_companion() -> bool:
	var manager: Node = get_tree().get_first_node_in_group("companion_manager")
	return manager != null and manager.has_method("get_companion_count") and manager.get_companion_count() > 0
