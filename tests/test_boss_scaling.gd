extends Node2D
## Prueba de jefe (Fase correccion): instancia el Boss y el MiniBoss REALES y
## valida el escalado de vida con los techos centralizados de GameBalance.
##   godot --headless --path . res://tests/TestBossScaling.tscn

const BossData = preload("res://scripts/bosses/boss_data.gd")

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Jugador minimo para que la IA del jefe resuelva su objetivo.
	var player := CharacterBody2D.new()
	player.add_to_group("players")
	player.add_to_group("player")
	add_child(player)

	var boss_data: BossData = load("res://data/bosses/rottweiler_charger.tres")
	var mini_data: BossData = load("res://data/bosses/bulldog_brute.tres")
	var gf: Node = get_node_or_null("/root/GameFlow")

	# --- SOLO, score maximo (70): el factor por score queda acotado ---
	gf.set("game_mode", "solo")
	var boss := (load("res://scenes/bosses/Boss.tscn") as PackedScene).instantiate()
	add_child(boss)
	boss.call("configure", boss_data, GameBalance.SCORE_CAP)
	var expected: int = int(round(boss_data.max_health * minf(GameBalance.BOSS_HEALTH_SCORE_FACTOR_CAP,
		1.0 + GameBalance.SCORE_CAP * boss_data.difficulty_multiplier)))
	expected = clampi(expected, boss_data.max_health, 9000)
	_expect(int(boss.get("max_health")) == expected,
		"jefe solo score 70: vida %d == esperada %d (factor acotado)" % [int(boss.get("max_health")), expected])
	_expect(int(boss.get("max_health")) <= 9000, "jefe: bajo el techo absoluto de px")

	# Score bajo (min 1 aprox): jefe cercano a su base.
	boss.call("configure", boss_data, 3.0)
	_expect(float(boss.get("max_health")) <= boss_data.max_health * 1.3,
		"jefe con score 3: vida cercana a la base (%d)" % int(boss.get("max_health")))

	# --- COOP: multiplicador UNA sola vez (GameBalance.BOSS_COOP_HEALTH_MULT) ---
	gf.set("game_mode", "local_coop")
	boss.call("configure", boss_data, GameBalance.SCORE_CAP)
	var expected_coop: int = clampi(int(round(expected * GameBalance.BOSS_COOP_HEALTH_MULT)), boss_data.max_health, 9000)
	_expect(int(boss.get("max_health")) == expected_coop,
		"jefe coop: vida %d == esperada %d (x%.2f una sola vez)" % [int(boss.get("max_health")), expected_coop, GameBalance.BOSS_COOP_HEALTH_MULT])

	# --- MiniBoss: mismo esquema con su techo propio ---
	gf.set("game_mode", "solo")
	var mini := (load("res://scenes/bosses/MiniBoss.tscn") as PackedScene).instantiate()
	add_child(mini)
	mini.call("configure", mini_data, GameBalance.SCORE_CAP)
	var mini_expected: int = clampi(int(round(mini_data.max_health * minf(GameBalance.MINIBOSS_HEALTH_SCORE_FACTOR_CAP,
		1.0 + GameBalance.SCORE_CAP * mini_data.difficulty_multiplier))), mini_data.max_health, 4000)
	_expect(int(mini.get("max_health")) == mini_expected,
		"mini-jefe score 70: vida %d == esperada %d" % [int(mini.get("max_health")), mini_expected])

	# El dano de jefe NO escala con el score (fijo por BossData).
	_expect(boss.get("data").contact_damage == boss_data.contact_damage,
		"jefe: dano de contacto fijo (%d), sin escalado dinamico" % boss_data.contact_damage)

	gf.set("game_mode", "solo")
	print("")
	print("TestBossScaling: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", message)
	else:
		_failures.append(message)
		printerr("  FALLO  ", message)
