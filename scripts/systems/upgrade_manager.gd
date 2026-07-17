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

## Agencia en el level-up (Rework de adictividad): rerolls y banishes base por
## partida. Las mejoras permanentes "Pata de la Suerte" / "Paladar Exigente"
## suman mas (solo Modo Historia, como el resto de la meta-progresion).
const BASE_REROLLS: int = 1
const BASE_BANISHES: int = 1
## Tope de evoluciones de arma por partida (no trivializar jefes).
const MAX_EVOLUTIONS_PER_RUN: int = 2

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

## MUTACIONES (Partidas rapidas): recompensa GARANTIZADA al derrotar al
## mini-boss. Mas poderosas que una carta normal, rareza legendaria, y NO
## consumen nivel (son un premio aparte). Efectos en player.apply_upgrade.
const MUTATION_POOL: Array[Dictionary] = [
	{"id": &"mut_split_shots", "name": "MUTACION: Proyectiles divididos", "description": "+2 proyectiles a las armas de proyectil."},
	{"id": &"mut_savage_power", "name": "MUTACION: Garra salvaje", "description": "+35% daño de todas las armas."},
	{"id": &"mut_frenzy", "name": "MUTACION: Frenesi felino", "description": "-30% cooldown de todas las armas."},
	{"id": &"mut_iron_hide", "name": "MUTACION: Pelaje de hierro", "description": "+40 vida maxima y +10% reduccion de daño."},
	{"id": &"mut_wind_paws", "name": "MUTACION: Patas de viento", "description": "+15% velocidad y +50% radio de recoleccion."},
]

## Primera seleccion de la partida GARANTIZADA (antes de 0:20): una opcion
## ofensiva, una defensiva y una de movilidad, en ese orden.
const FIRST_HAND_IDS: Array[StringName] = [&"weapon_damage", &"max_health", &"player_speed"]

const COOP_PANEL_SCRIPT := preload("res://scripts/ui/coop_upgrade_panel.gd")

var _player: Node
var _hud: Node
var _pending_level_ups: int = 0
var _selection_active: bool = false
var _current_cards: Array[Dictionary] = []
## Mutaciones pendientes (solo) y si la seleccion en pantalla es una mutacion.
var _pending_mutations: int = 0
var _mutation_active: bool = false
## Primera seleccion garantizada ya mostrada (solo clasico).
var _first_selection_done: bool = false

# --- Estado coop (Rework Coop: cartas INDEPENDIENTES por jugador) ---
var _coop: bool = false
var _coop_panel: Control
var _coop_bound: Array = []              # jugadores ya conectados a level_up
var _coop_players: Dictionary = {}       # player_id -> Node
var _coop_pending: Dictionary = {}       # player_id -> subidas sin resolver
var _coop_cards: Dictionary = {}         # player_id -> cartas en pantalla
var _coop_chosen_stats: Dictionary = {}  # player_id -> stats elegidos (evoluciones)
var _coop_evolutions: Dictionary = {}    # player_id -> evoluciones hechas
var _coop_mutations_pending: Dictionary = {}  # player_id -> mutaciones sin elegir
var _coop_mutation_active: Dictionary = {}    # player_id -> seleccion actual es mutacion
var _coop_first_done: Dictionary = {}         # player_id -> primera mano ya mostrada

# --- Agencia en el level-up (estado por partida; la escena se recarga por run) ---
var _rerolls_left: int = BASE_REROLLS
var _banishes_left: int = BASE_BANISHES
## Ids vetados por el jugador: no vuelven a aparecer el resto de la partida.
var _banished_ids: Array[StringName] = []
## Stats elegidos en la run (requisitos de evolucion de armas).
var _chosen_stat_ids: Array[StringName] = []
var _evolutions_done: int = 0


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_hud = get_node_or_null(hud_path)

	# Coop (Rework): cada jugador tiene SU nivel y SUS cartas. El flujo solo
	# clasico se desvia por completo al panel coop (dos columnas simultaneas).
	var gf: Node = get_node_or_null("/root/GameFlow")
	_coop = gf != null and gf.has_method("is_coop") and gf.is_coop()
	if _coop:
		# El P2 spawnea diferido (PlayerManager): se vinculan jugadores por polling
		# en _process hasta tener a los dos.
		set_process(true)
	elif _player != null and _player.has_signal("level_up_requested"):
		_player.level_up_requested.connect(_on_player_level_up_requested)

	if _hud != null and _hud.has_signal("upgrade_card_selected"):
		_hud.upgrade_card_selected.connect(_on_upgrade_card_selected)
	if _hud != null and _hud.has_signal("reroll_requested"):
		_hud.reroll_requested.connect(request_reroll)
	if _hud != null and _hud.has_signal("banish_requested"):
		_hud.banish_requested.connect(request_banish)

	# Mejoras permanentes de agencia (solo Modo Historia, como el Refugio).
	if _is_story_run():
		var mp: Node = get_node_or_null("/root/MetaProgression")
		if mp != null and mp.has_method("get_effect_total"):
			_rerolls_left += int(round(float(mp.get_effect_total(&"reroll_per_run"))))
			_banishes_left += int(round(float(mp.get_effect_total(&"banish_per_run"))))


func _on_player_level_up_requested(_level: int) -> void:
	_pending_level_ups += 1
	if not _selection_active:
		_show_next_selection()


func _show_next_selection() -> void:
	# Las mutaciones pendientes tienen prioridad y NO consumen nivel.
	var mutation: bool = _pending_mutations > 0
	if _pending_level_ups <= 0 and not mutation:
		return
	if _hud == null or not _hud.has_method("show_upgrade_selection"):
		return

	_selection_active = true
	_mutation_active = mutation
	if mutation:
		_current_cards = _mutation_cards()
	elif not _first_selection_done:
		# Primera seleccion de la run: mano garantizada ofensiva/defensiva/movilidad.
		_first_selection_done = true
		_current_cards = _first_selection_cards()
	else:
		_current_cards = _draw_cards(3)
	# Salvaguarda EXTREMA (pools agotados, en la practica inalcanzable con el
	# STAT_POOL siempre disponible): consume el nivel SIN recompensa alguna para
	# no congelar la partida. Nunca otorga XP/cura: no es una via de salto.
	if _current_cards.is_empty():
		push_warning("UpgradeManager: sin cartas que ofrecer; nivel consumido sin mejora")
		_selection_active = false
		_mutation_active = false
		_pending_level_ups = max(_pending_level_ups - 1, 0)
		return

	# Enfasis al subir de nivel: un shake breve (la camara procesa en pausa).
	Feedback.shake(0.35)

	get_tree().paused = true
	if _hud.has_method("set_upgrade_actions"):
		# Una mutacion no admite reroll/veto: es el premio del mini-boss.
		if mutation:
			_hud.set_upgrade_actions(0, 0)
		else:
			_hud.set_upgrade_actions(_rerolls_left, _banishes_left)
	_hud.show_upgrade_selection(_current_cards)


## Mano de mutaciones: 3 opciones al azar del pool (todas legendarias).
func _mutation_cards() -> Array[Dictionary]:
	var pool: Array = MUTATION_POOL.duplicate()
	pool.shuffle()
	var result: Array[Dictionary] = []
	for entry in pool.slice(0, 3):
		result.append({
			"card_type": &"mutation",
			"name": entry["name"],
			"description": entry["description"],
			"rarity": &"legendary",
			"type_label": "Mutacion",
			"affects": "Jugador",
			"weight": 1.0,
			"id": entry["id"],
		})
	return result


## Primera mano de la partida: ofensiva + defensiva + movilidad, garantizadas.
func _first_selection_cards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in FIRST_HAND_IDS:
		for entry in STAT_POOL:
			if entry["id"] == id:
				result.append({
					"card_type": &"stat",
					"name": entry["name"],
					"description": entry["description"],
					"rarity": entry["rarity"],
					"type_label": "Stat",
					"affects": entry.get("affects", "Jugador"),
					"weight": 1.0,
					"id": entry["id"],
				})
				break
	return result


## Recompensa del mini-boss (la llama PhaseDirector): Mutacion GARANTIZADA.
## En coop cada jugador elige la suya (selecciones independientes).
func grant_mutation() -> void:
	if _coop:
		for pid in _coop_players:
			_coop_mutations_pending[pid] = int(_coop_mutations_pending.get(pid, 0)) + 1
			_ensure_coop_panel()
			if not _coop_panel.is_open(pid):
				_coop_show_selection(pid)
		return
	_pending_mutations += 1
	if not _selection_active:
		_show_next_selection()


# --- Agencia: reroll / banish (SIN salto: elegir carta es obligatorio) -------------

## Re-sortea las 3 cartas sin consumir la subida de nivel. Limitado por partida.
## Si el re-sorteo no produce cartas (pools agotados), se conserva la mano actual
## y se devuelve el reroll: nunca se convierte en un salto.
func request_reroll() -> void:
	if not _selection_active or _rerolls_left <= 0 or _mutation_active:
		return
	var new_cards: Array[Dictionary] = _draw_cards(3)
	if new_cards.is_empty():
		return
	_rerolls_left -= 1
	_current_cards = new_cards
	if _hud != null and _hud.has_method("set_upgrade_actions"):
		_hud.set_upgrade_actions(_rerolls_left, _banishes_left)
	if _hud != null and _hud.has_method("show_upgrade_selection"):
		_hud.show_upgrade_selection(_current_cards)


## Veta una carta: su id no vuelve a aparecer el resto de la partida y la mano
## se re-sortea. Las cartas de evolucion no se pueden vetar (son el premio gordo).
## Si tras el veto no quedan cartas que sortear, se revierte el veto y se
## conserva la mano: el veto tampoco puede convertirse en un salto.
func request_banish(card_index: int) -> void:
	if not _selection_active or _banishes_left <= 0 or _mutation_active:
		return
	if card_index < 0 or card_index >= _current_cards.size():
		return
	var card: Dictionary = _current_cards[card_index]
	if card.get("card_type", &"stat") == &"weapon_evolution":
		return
	var banish_id: StringName = _card_ban_id(card)
	if banish_id == &"":
		return
	var already: bool = _banished_ids.has(banish_id)
	if not already:
		_banished_ids.append(banish_id)
	var new_cards: Array[Dictionary] = _draw_cards(3)
	if new_cards.is_empty():
		if not already:
			_banished_ids.erase(banish_id)
		return
	_banishes_left -= 1
	_current_cards = new_cards
	if _hud != null and _hud.has_method("set_upgrade_actions"):
		_hud.set_upgrade_actions(_rerolls_left, _banishes_left)
	if _hud != null and _hud.has_method("show_upgrade_selection"):
		_hud.show_upgrade_selection(_current_cards)


## Id con el que se veta una carta (stats/companeros usan `id`; armas su weapon id).
func _card_ban_id(card: Dictionary) -> StringName:
	match card.get("card_type", &"stat"):
		&"new_weapon":
			var data = card.get("weapon_data")
			return data.id if data != null else &""
		&"weapon_upgrade":
			return card.get("weapon_id", &"")
		_:
			return card.get("id", &"")


## Construye el pool de candidatos segun el estado y sortea N cartas distintas.
func _draw_cards(amount: int) -> Array[Dictionary]:
	return _draw_cards_from(_get_weapon_manager(), _chosen_stat_ids, _evolutions_done, amount)


## Version parametrizada (coop): sortea cartas para el CONTEXTO de un jugador
## concreto (su WeaponManager, sus stats elegidos y sus evoluciones hechas).
func _draw_cards_from(weapon_manager: Node, chosen_stats: Array, evolutions_done: int, amount: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = _build_candidates(weapon_manager, chosen_stats, evolutions_done)
	var result: Array[Dictionary] = []

	while result.size() < amount and not candidates.is_empty():
		var picked_index: int = _weighted_pick_index(candidates)
		result.append(candidates[picked_index])
		candidates.remove_at(picked_index)

	return result


## Sin argumentos usa el contexto SOLO clasico (P1); en coop se pasa el contexto
## del jugador que sube de nivel. Los defaults centinela mantienen compatible la
## llamada sin argumentos (tests y flujo solo).
func _build_candidates(weapon_manager: Node = null, chosen_stats: Variant = null, evolutions_done: int = -1) -> Array[Dictionary]:
	if weapon_manager == null:
		weapon_manager = _get_weapon_manager()
	var chosen: Array = chosen_stats if chosen_stats is Array else _chosen_stat_ids
	if evolutions_done < 0:
		evolutions_done = _evolutions_done
	var candidates: Array[Dictionary] = []

	# 0) Cartas de EVOLUCION: arma a nivel maximo + stat requisito elegido en la
	# run. Peso alto forzado: si esta disponible, practicamente garantizada.
	if weapon_manager != null and evolutions_done < MAX_EVOLUTIONS_PER_RUN \
			and weapon_manager.has_method("get_evolution_ready_weapons"):
		for weapon in weapon_manager.get_evolution_ready_weapons():
			var req: StringName = weapon.data.evolution_requirement
			if req != &"" and not chosen.has(req):
				continue
			var evolved = weapon.data.evolution
			candidates.append({
				"card_type": &"weapon_evolution",
				"name": "EVOLUCION: %s" % evolved.display_name,
				"description": evolved.description,
				"rarity": &"legendary",
				"type_label": "Evolucion",
				"affects": "Arma",
				"weight": 60.0,
				"weapon_id": weapon.data.id,
			})

	# 1) Cartas de arma (nueva o mejora), si hay WeaponManager.
	if weapon_manager != null:
		for data in weapon_manager.get_available_new_weapons():
			if _banished_ids.has(data.id):
				continue
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
			if _banished_ids.has(snapshot["id"]):
				continue
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
		if _banished_ids.has(entry["id"]):
			continue
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
			if _banished_ids.has(entry["id"]):
				continue
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
	# El Refugio solo mejora la rareza de cartas en Modo Historia (Partida libre = puro).
	if not _is_story_run():
		return 0.0
	if _shelter_rarity_cached < 0.0:
		_shelter_rarity_cached = 0.0
		var shelter: Node = get_node_or_null("/root/Shelter")
		if shelter != null and shelter.has_method("get_bonus"):
			_shelter_rarity_cached = clampf(float(shelter.get_bonus("upgrade_rarity_bonus")), 0.0, 0.10)
	return _shelter_rarity_cached


## True solo en Modo Historia (donde aplican mejoras permanentes y Refugio).
func _is_story_run() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_story_run") and gf.is_story_run()


func _on_upgrade_card_selected(card_index: int) -> void:
	if not _selection_active:
		return
	if card_index < 0 or card_index >= _current_cards.size():
		return

	var card: Dictionary = _current_cards[card_index]
	_apply_card(card)

	# Una mutacion consume SU contador (premio del mini-boss); una carta normal
	# consume el nivel pendiente. Las selecciones pendientes se encadenan.
	if _mutation_active:
		_pending_mutations = max(_pending_mutations - 1, 0)
		_mutation_active = false
	else:
		_pending_level_ups = max(_pending_level_ups - 1, 0)
	_selection_active = false
	_current_cards.clear()
	if _hud != null and _hud.has_method("hide_upgrade_selection"):
		_hud.hide_upgrade_selection()

	if _pending_level_ups > 0 or _pending_mutations > 0:
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
		&"weapon_evolution":
			_evolutions_done += 1
			if weapon_manager != null and weapon_manager.has_method("evolve_weapon"):
				weapon_manager.evolve_weapon(card.get("weapon_id", &""))
			_note_upgrade(&"weapon_upgrade")
		&"weapon_upgrade":
			if weapon_manager != null:
				weapon_manager.level_up_weapon(card.get("weapon_id", &""))
			_note_upgrade(&"weapon_upgrade")
		_:
			var stat_id: StringName = card.get("id", &"")
			# Registro para requisitos de evolucion de armas.
			if card.get("card_type", &"stat") == &"stat" and stat_id != &"" \
					and not _chosen_stat_ids.has(stat_id):
				_chosen_stat_ids.append(stat_id)
			if _player != null and _player.has_method("apply_upgrade"):
				_player.apply_upgrade(stat_id)


func _note_upgrade(id: StringName) -> void:
	# Las cartas de arma tambien cuentan como mejora elegida (afecta dificultad).
	if _player != null and _player.has_method("apply_upgrade"):
		_player.apply_upgrade(id)


func _get_weapon_manager() -> Node:
	if _player != null and _player.has_method("get_weapon_manager"):
		return _player.get_weapon_manager()
	return null


# --- Flujo coop (Rework Coop): cartas simultaneas e independientes ---------------
# Cada jugador sube SU nivel y elige SUS cartas con SUS controles en su mitad de
# la pantalla (CoopUpgradePanel). Las cartas de arma/stat aplican SOLO a quien las
# elige; las de companero afectan al CompanionManager (compartido) porque ese
# jugador decidio invertir su carta en el equipo. Sin reroll/veto en coop: la
# seleccion simultanea debe ser rapida y legible.

func _process(_delta: float) -> void:
	if not _coop:
		set_process(false)
		return
	_coop_bind_new_players()
	if _coop_bound.size() >= 2:
		set_process(false)


func _coop_bind_new_players() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or p in _coop_bound:
			continue
		if not p.has_signal("level_up_requested"):
			continue
		p.level_up_requested.connect(_on_coop_level_up.bind(p))
		_coop_bound.append(p)
		var pid: int = maxi(1, int(p.get("player_id")))
		# Un jugador derribado no abre cartas (Fase 9): quedan pendientes y se
		# ofrecen al revivir.
		if p.has_signal("revived") and not p.revived.is_connected(_on_coop_player_revived):
			p.revived.connect(_on_coop_player_revived)
		_coop_players[pid] = p
		_coop_pending[pid] = int(_coop_pending.get(pid, 0))
		_coop_chosen_stats[pid] = _coop_chosen_stats.get(pid, [])
		_coop_evolutions[pid] = int(_coop_evolutions.get(pid, 0))


func _ensure_coop_panel() -> void:
	if is_instance_valid(_coop_panel):
		return
	var panel := Control.new()
	panel.set_script(COOP_PANEL_SCRIPT)
	panel.name = "CoopUpgradePanel"
	var host: Node = _hud if _hud != null else self
	host.add_child(panel)
	panel.connect("card_chosen", _on_coop_card_chosen)
	_coop_panel = panel


func _on_coop_level_up(_level: int, player: Node) -> void:
	var pid: int = maxi(1, int(player.get("player_id")))
	_coop_pending[pid] = int(_coop_pending.get(pid, 0)) + 1
	_ensure_coop_panel()
	if not _coop_panel.is_open(pid):
		_coop_show_selection(pid)


func _coop_show_selection(pid: int) -> void:
	var mutation: bool = int(_coop_mutations_pending.get(pid, 0)) > 0
	if int(_coop_pending.get(pid, 0)) <= 0 and not mutation:
		return
	var player: Node = _coop_players.get(pid)
	if player == null or not is_instance_valid(player):
		return
	# Derribado: no abre cartas. La subida queda PENDIENTE (no se pierde) y se
	# ofrece al revivir (_on_coop_player_revived). No bloquea la pausa: la pausa
	# solo depende de paneles ABIERTOS.
	if player.has_method("is_downed") and player.is_downed():
		if is_instance_valid(_coop_panel):
			_coop_panel.close_for(pid)
		_coop_maybe_unpause()
		return
	var wm: Node = player.get_weapon_manager() if player.has_method("get_weapon_manager") else null
	var cards: Array[Dictionary]
	if mutation:
		# Mutacion del mini-boss: cada jugador elige la SUYA.
		cards = _mutation_cards()
		_coop_mutation_active[pid] = true
	elif not bool(_coop_first_done.get(pid, false)):
		# Primera seleccion del jugador: mano garantizada (ofensiva/defensa/movilidad).
		_coop_first_done[pid] = true
		cards = _first_selection_cards()
	else:
		cards = _draw_cards_from(
			wm, _coop_chosen_stats.get(pid, []), int(_coop_evolutions.get(pid, 0)), 3)
	if cards.is_empty():
		# Salvaguarda extrema (pools agotados): consume el nivel SIN recompensa
		# para no congelar la partida. Nunca otorga XP/cura: no es un salto.
		push_warning("UpgradeManager: sin cartas coop para J%d; nivel consumido sin mejora" % pid)
		_coop_pending[pid] = maxi(0, int(_coop_pending.get(pid, 0)) - 1)
		_coop_maybe_unpause()
		return
	_coop_cards[pid] = cards
	_ensure_coop_panel()
	Feedback.shake(0.3)
	_coop_set_selection_active(true)
	_coop_panel.open_for(pid, cards)


## Reanuda las cartas pendientes de un jugador que acaba de revivir.
func _on_coop_player_revived(pid: int) -> void:
	if int(_coop_pending.get(pid, 0)) > 0 or int(_coop_mutations_pending.get(pid, 0)) > 0:
		_ensure_coop_panel()
		if not _coop_panel.is_open(pid):
			_coop_show_selection(pid)


## Detiene (o ralentiza, segun CoopConfig.CARD_SLOWDOWN_ENABLED) la partida
## mientras hay una seleccion activa. Centralizado para poder cambiar el modo
## pausa <-> camara lenta sin tocar el resto del flujo.
func _coop_set_selection_active(active: bool) -> void:
	if CoopConfig.CARD_SLOWDOWN_ENABLED:
		Engine.time_scale = CoopConfig.CARD_SLOWDOWN_SCALE if active else 1.0
	else:
		get_tree().paused = active


func _on_coop_card_chosen(pid: int, card_index: int) -> void:
	var cards: Array = _coop_cards.get(pid, [])
	if card_index < 0 or card_index >= cards.size():
		return
	var player: Node = _coop_players.get(pid)
	if player != null and is_instance_valid(player):
		_coop_apply_card(pid, player, cards[card_index])
	_coop_resolve_choice(pid)


## Cierra o refresca el lado del jugador y despausa si ya no queda nadie eligiendo.
func _coop_resolve_choice(pid: int) -> void:
	if bool(_coop_mutation_active.get(pid, false)):
		_coop_mutation_active[pid] = false
		_coop_mutations_pending[pid] = maxi(0, int(_coop_mutations_pending.get(pid, 0)) - 1)
	else:
		_coop_pending[pid] = maxi(0, int(_coop_pending.get(pid, 0)) - 1)
	_coop_cards.erase(pid)
	if int(_coop_pending.get(pid, 0)) > 0 or int(_coop_mutations_pending.get(pid, 0)) > 0:
		_coop_show_selection(pid)
	else:
		if is_instance_valid(_coop_panel):
			_coop_panel.close_for(pid)
		_coop_maybe_unpause()


func _coop_maybe_unpause() -> void:
	# La pausa depende SOLO de paneles abiertos: un pendiente diferido (jugador
	# derribado) no debe congelar la partida sin panel en pantalla.
	if is_instance_valid(_coop_panel) and (_coop_panel.is_open(1) or _coop_panel.is_open(2)):
		return
	_coop_set_selection_active(false)


## Aplica la carta SOLO al jugador que la eligio (armas y stats propios; las de
## companero tocan el CompanionManager compartido: fue su eleccion de equipo).
func _coop_apply_card(pid: int, player: Node, card: Dictionary) -> void:
	var wm: Node = player.get_weapon_manager() if player.has_method("get_weapon_manager") else null
	match card.get("card_type", &"stat"):
		&"new_weapon":
			if wm != null:
				wm.add_weapon(card.get("weapon_data"))
			_coop_note_upgrade(player, &"new_weapon")
		&"weapon_evolution":
			_coop_evolutions[pid] = int(_coop_evolutions.get(pid, 0)) + 1
			if wm != null and wm.has_method("evolve_weapon"):
				wm.evolve_weapon(card.get("weapon_id", &""))
			_coop_note_upgrade(player, &"weapon_upgrade")
		&"weapon_upgrade":
			if wm != null:
				wm.level_up_weapon(card.get("weapon_id", &""))
			_coop_note_upgrade(player, &"weapon_upgrade")
		_:
			var stat_id: StringName = card.get("id", &"")
			if card.get("card_type", &"stat") == &"stat" and stat_id != &"":
				var chosen: Array = _coop_chosen_stats.get(pid, [])
				if not chosen.has(stat_id):
					chosen.append(stat_id)
					_coop_chosen_stats[pid] = chosen
			if player.has_method("apply_upgrade"):
				player.apply_upgrade(stat_id)


func _coop_note_upgrade(player: Node, id: StringName) -> void:
	if player.has_method("apply_upgrade"):
		player.apply_upgrade(id)


func _has_any_companion() -> bool:
	var manager: Node = get_tree().get_first_node_in_group("companion_manager")
	return manager != null and manager.has_method("get_companion_count") and manager.get_companion_count() > 0
