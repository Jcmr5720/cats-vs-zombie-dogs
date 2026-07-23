extends Node2D
## Valida la progresion de XP adaptada a partidas de 5 minutos y, desde FASE 12,
## que subir de nivel NUNCA pausa: la curva de XP sigue viva (primer nivel barato,
## ~6-8 subidas por partida) pero el poder llega por el loot del suelo.
##   godot --headless --path . res://tests/TestQuickRunXP.tscn

const LootDirectorScript := preload("res://scripts/systems/loot_director.gd")

var _failures: Array[String] = []
var _checks: int = 0


class StubHud:
	extends Node
	var messages: Array = []
	func show_event_message(text: String, _d: float = 1.8) -> void:
		messages.append(text)


class StubPlayer:
	extends Node
	signal level_up_requested(level: int)
	var applied: Array = []
	var owned_powerups: Array[StringName] = []

	func _init() -> void:
		# El LootDirector localiza al jugador por grupo para filtrar por max_stacks.
		add_to_group("player")

	func apply_upgrade(id: StringName, _shared: bool = true) -> void:
		applied.append(id)
		if not owned_powerups.has(id):
			owned_powerups.append(id)

	func get_weapon_manager() -> Node:
		return null


func _ready() -> void:
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

	# --- LootDirector + stubs -----------------------------------------------------
	var hud := StubHud.new()
	hud.name = "Hud"
	hud.add_to_group("hud")
	add_child(hud)
	var player := StubPlayer.new()
	player.name = "Player"
	add_child(player)
	var loot := Node.new()
	loot.name = "Loot"
	loot.set_script(LootDirectorScript)
	add_child(loot)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- FASE 12: subir de nivel NO abre nada ni pausa ----------------------------
	# La "puerta de la primera tarjeta" y toda la cadena de selecciones murieron con
	# el UpgradeManager. Lo que hay que sostener ahora es lo contrario: que ningun
	# camino del sistema de progresion vuelva a pausar la partida.
	player.level_up_requested.emit(2)
	await get_tree().process_frame
	_expect(not get_tree().paused, "subir de nivel NO pausa la partida")

	# --- La mutacion es un pickup del suelo, no un menu ----------------------------
	var mutation: PowerUpData = loot.call("roll_mutation")
	_expect(mutation != null, "el director sortea una mutacion")
	_expect(mutation.is_mutation() and mutation.rarity == &"legendary",
		"la mutacion es de categoria mutacion y rareza legendaria")

	var pickup = loot.call("drop_mutation", self, Vector2(500, 500))
	await get_tree().process_frame
	_expect(pickup != null and is_instance_valid(pickup), "la mutacion se suelta como pickup")
	_expect(not get_tree().paused, "soltar una mutacion no pausa la partida")

	pickup.call("collect", player)
	var got_mut := false
	for id in player.applied:
		if String(id).begins_with("mut_"):
			got_mut = true
	_expect(got_mut, "recoger la mutacion la aplica al jugador")
	_expect(not get_tree().paused, "recoger una mutacion no pausa la partida")

	# --- max_stacks: la misma mutacion no vuelve a salir --------------------------
	var repeated := false
	for _i in 12:
		var again: PowerUpData = loot.call("roll_mutation")
		if again != null and player.owned_powerups.has(again.effect_id()):
			repeated = true
	_expect(not repeated, "una mutacion ya recogida no vuelve a sortearse (max_stacks)")
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
