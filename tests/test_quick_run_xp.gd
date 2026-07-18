extends Node2D
## Valida la progresion de XP/cartas adaptada a partidas de 5 minutos:
## primera carta alcanzable antes de 0:20, ~6-8 elecciones estimadas, primera
## mano garantizada (ofensiva/defensiva/movilidad), Mutacion garantizada que NO
## consume nivel, encadenado de selecciones y ausencia de salto.
##   godot --headless --path . res://tests/TestQuickRunXP.tscn

const UpgradeManagerScript := preload("res://scripts/systems/upgrade_manager.gd")

var _failures: Array[String] = []
var _checks: int = 0


class StubHud:
	extends Node
	signal upgrade_card_selected(card_index: int)
	signal reroll_requested
	signal banish_requested(card_index: int)
	var shown: Array = []
	var actions: Array = []
	var hidden: int = 0
	func show_upgrade_selection(cards: Array[Dictionary]) -> void:
		shown.append(cards)
	func hide_upgrade_selection() -> void:
		hidden += 1
	func set_upgrade_actions(r: int, b: int) -> void:
		actions.append([r, b])


class StubPlayer:
	extends Node
	signal level_up_requested(level: int)
	var applied: Array = []
	func apply_upgrade(id: StringName, _shared: bool = true) -> void:
		applied.append(id)
	func get_weapon_manager() -> Node:
		return null


func _ready() -> void:
	# La seleccion de cartas pausa el arbol: este test debe seguir corriendo.
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	# --- Curva de XP adaptada a 5 minutos ---------------------------------------
	_expect(GameBalance.XP_FIRST_LEVEL <= 10,
		"primer nivel barato (%d XP)" % GameBalance.XP_FIRST_LEVEL)
	_expect(GameBalance.XP_GROWTH >= 1.45,
		"crecimiento empinado para partidas cortas (x%.2f)" % GameBalance.XP_GROWTH)
	# La manada inicial (8 mordedores x 3 XP = 24) cubre de sobra el primer nivel:
	# la primera carta es alcanzable ANTES de 0:20.
	var opening_xp: int = RunPhaseConfig.OPENING_PACK_MIN * 3
	_expect(opening_xp >= GameBalance.XP_FIRST_LEVEL,
		"la manada inicial (%d XP) cubre el primer nivel" % opening_xp)
	# Estimacion de elecciones con la XP tipica de una partida de 5 min
	# (~600 XP entre horda, mini-boss y jefe): objetivo 6-8 (tolerancia 5-9).
	var choices: int = _levels_for_xp(600)
	_expect(choices >= 5 and choices <= 9,
		"~%d elecciones estimadas con 600 XP (objetivo 6-8)" % choices)
	var choices_rich: int = _levels_for_xp(800)
	_expect(choices_rich <= 10, "con 800 XP sigue acotado (%d)" % choices_rich)

	# --- Manager + stubs ----------------------------------------------------------
	var hud := StubHud.new()
	hud.name = "Hud"
	add_child(hud)
	var player := StubPlayer.new()
	player.name = "Player"
	add_child(player)
	var manager := Node.new()
	manager.name = "Upgrades"
	manager.set_script(UpgradeManagerScript)
	manager.set("hud_path", NodePath("../Hud"))
	manager.set("player_path", NodePath("../Player"))
	add_child(manager)
	await get_tree().process_frame

	# --- Puerta temporal de la primera tarjeta (segundo 12) -----------------------
	# En la partida real la enciende el PhaseDirector; aqui se activa a mano.
	# Antes del segundo 12 la subida NO abre cartas (la XP no se pierde: queda
	# pendiente). Se simula el reloj con _run_time para no esperar 12 s reales.
	manager.call("set_first_card_gate", 12.0)
	manager.set("_run_time", 5.0)
	player.level_up_requested.emit(2)
	_expect(hud.shown.is_empty(), "antes de 0:12 la primera carta NO se abre (puerta)")
	_expect(not get_tree().paused, "la puerta no pausa la partida (XP encolada)")
	# Cruzada la puerta, la primera seleccion (que quedo pendiente) se muestra.
	manager.set("_run_time", 13.0)
	manager.call("_show_next_selection")

	# --- Primera seleccion garantizada: ofensiva / defensiva / movilidad ----------
	_expect(hud.shown.size() == 1, "cruzada la puerta, la subida pendiente abre seleccion")
	_expect(get_tree().paused, "la seleccion pausa la partida (sin salto posible)")
	if hud.shown.size() >= 1:
		var ids: Array = []
		for card in hud.shown[0]:
			ids.append(card.get("id"))
		_expect(ids == [&"weapon_damage", &"max_health", &"player_speed"],
			"primera mano garantizada: ofensiva+defensiva+movilidad (%s)" % str(ids))
	hud.upgrade_card_selected.emit(0)
	_expect(player.applied.back() == &"weapon_damage", "la carta elegida se aplica")
	_expect(not get_tree().paused, "resuelta la seleccion, la partida continua")

	# --- Mutacion garantizada (recompensa del mini-boss) ---------------------------
	manager.call("grant_mutation")
	_expect(hud.shown.size() == 2, "la Mutacion abre seleccion propia")
	if hud.shown.size() >= 2:
		var all_mut := true
		var all_legendary := true
		for card in hud.shown[1]:
			if card.get("card_type") != &"mutation":
				all_mut = false
			if card.get("rarity") != &"legendary":
				all_legendary = false
		_expect(hud.shown[1].size() == 3, "3 opciones de Mutacion")
		_expect(all_mut and all_legendary, "todas las opciones son Mutaciones legendarias")
	_expect(hud.actions.back() == [0, 0], "sin reroll/veto durante la Mutacion")
	hud.upgrade_card_selected.emit(1)
	var got_mut := false
	for id in player.applied:
		if String(id).begins_with("mut_"):
			got_mut = true
	_expect(got_mut, "la Mutacion elegida se aplica al jugador")
	_expect(not get_tree().paused, "tras la Mutacion la partida continua")

	# --- La Mutacion NO consume nivel: encadena con la subida pendiente -----------
	player.level_up_requested.emit(3)
	manager.call("grant_mutation")
	# En pantalla esta la seleccion del nivel; al resolverla debe encadenar la Mutacion.
	hud.upgrade_card_selected.emit(0)
	_expect(hud.shown.size() == 4, "las selecciones pendientes se encadenan")
	if hud.shown.size() >= 4:
		_expect(hud.shown[3][0].get("card_type") == &"mutation",
			"la Mutacion pendiente aparece tras la carta de nivel")
	hud.upgrade_card_selected.emit(0)
	_expect(not get_tree().paused, "cadena resuelta: sin pausas colgadas")

	# El nivel consumido fue UNO por carta normal (weapon_damage x2 + 2 mutaciones).
	var normal_cards: int = 0
	var mutation_cards: int = 0
	for id in player.applied:
		if String(id).begins_with("mut_"):
			mutation_cards += 1
		else:
			normal_cards += 1
	_expect(normal_cards == 2 and mutation_cards == 2,
		"2 cartas de nivel y 2 Mutaciones aplicadas (%d/%d)" % [normal_cards, mutation_cards])

	get_tree().paused = false
	print("")
	print("TestQuickRunXP: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)


## Niveles alcanzados con un total de XP segun la curva actual.
func _levels_for_xp(total: int) -> int:
	var needed: float = float(GameBalance.XP_FIRST_LEVEL)
	var levels: int = 0
	var xp: float = float(total)
	while xp >= needed and levels < 30:
		xp -= needed
		needed = ceil(needed * GameBalance.XP_GROWTH)
		levels += 1
	return levels


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", message)
	else:
		_failures.append(message)
		printerr("  FALLO  ", message)
