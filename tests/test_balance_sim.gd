extends Node
## Simulacion ACELERADA, DETERMINISTA y reproducible del balance de dificultad
## (Fase correccion). Sin partidas reales: reproduce con matematica pura la
## formula ANTERIOR (auditada) y la NUEVA (GameBalance + integracion del spawner)
## sobre un modelo de progresion del jugador fijo, y valida las condiciones
## minimas de balance en los minutos 1, 3, 5, 10, 15 y 20.
##   godot --headless --path . res://tests/TestBalanceSim.tscn
##
## Configuraciones: solo facil/intermedio/dificil/extremo + coop intermedio/dificil.
## Salida: tabla por consola + user://telemetry/sim_before_after.json y codigo de
## salida 0/1 segun las condiciones minimas.
##
## Modelo de progresion (documentado; mismo para ambas formulas):
##   nivel(t)        = 1 + 1.35*t                     (tope 26)
##   armas(t)        = 1 + t/4                        (tope 4)
##   niveles_arma(t) = nivel(t) * 0.85                (tope 20)
##   companeros(t)   = t/3                            (tope 4)
##   kills(t)        = 220*(t-2.5) para t>2.5         (tope 4500)
##   cartas(t)       = nivel(t) - 1  (una carta por nivel: sin salto)
##   DPS jugador(t)  = 18 * (1 + 0.28*t)              (tope 320; pistola base 18)
## TTK usa vida normal 20 px y elite promedio x2.2 (veloz 1.4/blindado 3.0/gigante 2.2).

const StoryCampaign = preload("res://scripts/story/story_campaign.gd")

const MINUTES: Array = [1, 3, 5, 10, 15, 20]
const CONFIGS: Array = [
	["solo", 0], ["solo", 1], ["solo", 2], ["solo", 3], ["coop", 1], ["coop", 2],
]

# --- Constantes de la formula ANTERIOR (auditadas de enemy_spawner/map_manager) ---
const OLD := {
	"time_weight": 1.2, "level_weight": 0.9, "kills_divisor": 35.0,
	"upgrade_weight": 0.35, "companion_weight": 0.7, "weapon_weight": 0.7,
	"weapon_level_weight": 0.18, "coop_bonus": 3.0, "coop_pressure": 1.25,
	"coop_health": 1.45, "coop_damage": 1.15,
	"base_interval": 0.95, "interval_per_point": 0.05, "min_interval": 0.30,
	"base_max": 22.0, "per_point": 3.0, "coop_max_bonus": 25.0,
	"hp_per_point": 0.06, "hp_cap": 2.6, "dmg_per_point": 0.04, "dmg_cap": 2.2,
	"spd_per_point": 0.025, "spd_cap": 1.7,
	"elite_base": 0.015, "elite_per_point": 0.004, "elite_cap": 0.10,
	"boss_base_hp": 1200.0, "boss_diff_mult": 0.08, "boss_hp_cap": 9000.0,
	"boss_coop": 1.55,
}

var _failures: Array[String] = []
var _checks: int = 0
var _rows: Array = []


func _ready() -> void:
	call_deferred("_run")


# --- Modelo de progresion ------------------------------------------------------------

func _level(t: float) -> float:
	return minf(26.0, 1.0 + 1.35 * t)


func _weapons(t: float) -> float:
	return minf(4.0, 1.0 + t / 4.0)


func _weapon_levels(t: float) -> float:
	return minf(20.0, _level(t) * 0.85)


func _companions(t: float) -> float:
	return minf(4.0, t / 3.0)


## Kills acumulados: el ritmo sube en rampa (0 -> 220/min entre los minutos 2 y 6)
## y luego es constante. Integral por pasos de 0.1 min (determinista).
func _kills(t: float) -> float:
	var total: float = 0.0
	var clock: float = 0.0
	while clock < t:
		var rate: float = 220.0 * clampf((clock - 2.0) / 4.0, 0.0, 1.0)
		total += rate * 0.1
		clock += 0.1
	return minf(4500.0, total)


func _player_dps(t: float) -> float:
	return minf(320.0, 18.0 * (1.0 + 0.28 * t))


## Potencia cruda NUEVA en el minuto t (cada beneficio UNA vez).
func _raw_power(t: float, coop: bool) -> float:
	var mult: float = 1.6 if coop else 1.0  # equipo: niveles/armas de ambos (aprox)
	return _level(t) * GameBalance.LEVEL_WEIGHT \
		+ _weapons(t) * mult * GameBalance.WEAPON_WEIGHT \
		+ _weapon_levels(t) * mult * GameBalance.WEAPON_LEVEL_WEIGHT \
		+ _companions(t) * GameBalance.COMPANION_WEIGHT


## Potencia SUAVIZADA: integra la EMA real (paso 0.5 s, muestreo 2 s) desde 0.
func _smoothed_power(t: float, coop: bool) -> float:
	var smoothed: float = 0.0
	var raw: float = 0.0
	var clock: float = 0.0
	var poll: float = 0.0
	const STEP: float = 0.5
	while clock < t * 60.0:
		poll -= STEP
		if poll <= 0.0:
			poll = GameBalance.POWER_POLL_SECONDS
			raw = _raw_power(clock / 60.0, coop)
		smoothed = lerpf(smoothed, raw, 1.0 - exp(-STEP / GameBalance.POWER_SMOOTH_SECONDS))
		clock += STEP
	return smoothed


# --- Formula ANTERIOR ------------------------------------------------------------------

func _old_score(t: float, tier: Dictionary, coop: bool) -> float:
	# Baseline historico CONGELADO (no se toca): modelaba una carta por nivel. La
	# formula real —_raw_power— ya escala por niveles de arma, no por cartas, asi
	# que desde FASE 12 no necesita este termino.
	var upgrades: float = _level(t) - 1.0
	var mult: float = 1.6 if coop else 1.0
	var score: float = t * OLD["time_weight"] \
		+ _level(t) * OLD["level_weight"] \
		+ _kills(t) / OLD["kills_divisor"] \
		+ upgrades * mult * OLD["upgrade_weight"] \
		+ _companions(t) * OLD["companion_weight"] \
		+ _weapons(t) * mult * OLD["weapon_weight"] \
		+ _weapon_levels(t) * mult * OLD["weapon_level_weight"] \
		+ (OLD["coop_bonus"] if coop else 0.0)
	var pressure: float = float(tier["pressure"]) * (OLD["coop_pressure"] if coop else 1.0)
	return score * pressure  # mapa barrio = 1.0, plaga 1


func _old_row(t: float, tier: Dictionary, coop: bool) -> Dictionary:
	var score: float = _old_score(t, tier, coop)
	var hp: float = minf(OLD["hp_cap"], 1.0 + score * OLD["hp_per_point"]) \
		* float(tier["health"]) * (OLD["coop_health"] if coop else 1.0)
	var dmg: float = minf(OLD["dmg_cap"], 1.0 + score * OLD["dmg_per_point"]) \
		* float(tier["damage"]) * (OLD["coop_damage"] if coop else 1.0)
	var spd: float = minf(OLD["spd_cap"], 1.0 + score * OLD["spd_per_point"]) * float(tier["speed"])
	var interval: float = maxf(OLD["min_interval"], OLD["base_interval"] - score * OLD["interval_per_point"])
	var cap: float = minf(120.0 + (30.0 if coop else 0.0),
		OLD["base_max"] + (OLD["coop_max_bonus"] if coop else 0.0) + score * OLD["per_point"])
	var elite: float = clampf(OLD["elite_base"] + score * OLD["elite_per_point"], 0.0, OLD["elite_cap"])
	var boss: float = minf(OLD["boss_hp_cap"],
		OLD["boss_base_hp"] * (1.0 + score * OLD["boss_diff_mult"]) * (OLD["boss_coop"] if coop else 1.0))
	return {"score": score, "hp": hp, "dmg": dmg, "spd": spd, "interval": interval,
		"cap": cap, "elite": elite, "boss_hp": boss}


# --- Formula NUEVA (misma matematica que enemy_spawner + GameBalance) --------------------

func _new_row(t: float, tier: Dictionary, coop: bool) -> Dictionary:
	var power: float = _smoothed_power(t, coop)
	var score: float = t * GameBalance.TIME_WEIGHT \
		+ power \
		+ _kills(t) / GameBalance.KILLS_DIVISOR \
		+ (GameBalance.COOP_SCORE_BONUS * GameBalance.early_ramp(t) if coop else 0.0)
	score *= float(tier["pressure"]) * GameBalance.COOP_PRESSURE_MULT  # coop pressure = 1.0
	score = minf(score, GameBalance.SCORE_CAP)

	var hp: float = GameBalance.health_multiplier(score,
		float(tier["health"]) * (GameBalance.COOP_ENEMY_HEALTH_MULT if coop else 1.0))
	var dmg: float = GameBalance.damage_multiplier(score,
		float(tier["damage"]) * (GameBalance.COOP_ENEMY_DAMAGE_MULT if coop else 1.0))
	var spd: float = GameBalance.speed_multiplier(score, float(tier["speed"]))
	var interval: float = maxf(GameBalance.spawn_floor(t),
		GameBalance.BASE_SPAWN_INTERVAL - score * GameBalance.INTERVAL_PER_POINT)
	var cap: float = minf(120.0 + (30.0 if coop else 0.0),
		GameBalance.BASE_MAX_ENEMIES + (25.0 if coop else 0.0) + score * GameBalance.ENEMIES_PER_POINT)
	var elite: float = GameBalance.elite_chance(t, score)
	var boss: float = minf(OLD["boss_hp_cap"], OLD["boss_base_hp"] \
		* minf(GameBalance.BOSS_HEALTH_SCORE_FACTOR_CAP, 1.0 + score * OLD["boss_diff_mult"]) \
		* (GameBalance.BOSS_COOP_HEALTH_MULT if coop else 1.0))
	return {"score": score, "power": _raw_power(t, coop), "power_smooth": power,
		"hp": hp, "dmg": dmg, "spd": spd, "interval": interval, "cap": cap,
		"elite": elite, "boss_hp": boss}


# --- Ejecucion ---------------------------------------------------------------------------

func _run() -> void:
	for cfg in CONFIGS:
		var mode: String = cfg[0]
		var tier_index: int = cfg[1]
		var tier: Dictionary = StoryCampaign.get_difficulty(tier_index)
		var coop: bool = mode == "coop"
		print("\n===== %s tier %d (%s) — ANTES -> DESPUES =====" % [mode, tier_index, tier["name"]])
		print("min | score           | vida            | dano            | veloc           | intervalo       | tope   | elite          | jefe HP")
		for m in MINUTES:
			var t: float = float(m)
			var o: Dictionary = _old_row(t, tier, coop)
			var n: Dictionary = _new_row(t, tier, coop)
			print("%3d | %6.1f -> %5.1f | x%5.2f -> x%4.2f | x%5.2f -> x%4.2f | x%5.2f -> x%4.2f | %5.2fs -> %4.2fs | %3d->%3d | %4.1f%% -> %4.1f%% | %5d -> %5d" % [
				m, o["score"], n["score"], o["hp"], n["hp"], o["dmg"], n["dmg"],
				o["spd"], n["spd"], o["interval"], n["interval"], int(o["cap"]), int(n["cap"]),
				o["elite"] * 100.0, n["elite"] * 100.0, int(o["boss_hp"]), int(n["boss_hp"])])
			var dps: float = _player_dps(t)
			_rows.append({"mode": mode, "tier": tier_index, "minute": m,
				"old": o, "new": n,
				"level": int(_level(t)), "level_bonuses": int(_level(t)) - 1,
				"power_raw": n["power"], "power_smooth": n["power_smooth"],
				"ttk_normal_s": snappedf(20.0 * n["hp"] / dps, 0.01),
				"ttk_elite_s": snappedf(20.0 * 2.2 * n["hp"] / dps, 0.01),
				"pressure_index": snappedf(n["cap"] * n["dmg"], 0.1),
				"pressure_index_old": snappedf(o["cap"] * o["dmg"], 0.1)})
		_validate(mode, tier_index, tier, coop)

	_validate_cross()
	_save()
	print("\nTestBalanceSim: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)


## Condiciones minimas por configuracion.
func _validate(mode: String, tier_index: int, tier: Dictionary, coop: bool) -> void:
	var tag: String = "%s:%d" % [mode, tier_index]
	# 1) El suelo de spawn NO se alcanza en los primeros minutos.
	for m in [1, 2, 3, 4]:
		var n: Dictionary = _new_row(float(m), tier, coop)
		_expect(n["interval"] > 0.34, "%s: intervalo min%d por encima del suelo tardio (%.2fs)" % [tag, m, n["interval"]])
	# 2) Techos principales NO alcanzados antes del cierre de la run (5:00-5:30).
	# En coop el externo ELEGIDO ya es alto (dificil: tier 1.20 x coop 1.10 =
	# 1.32 de dano), asi que el techo TOTAL actua de red de seguridad hacia el
	# min 5 (el final de la run): alli el margen se exige a mitad (min 3).
	var n5: Dictionary = _new_row(5.0, tier, coop)
	if tier_index <= 2:
		_expect(n5["hp"] < GameBalance.HEALTH_TOTAL_CAP - 0.05, "%s: vida min5 sin tocar techo (x%.2f)" % [tag, n5["hp"]])
		if coop:
			var n3: Dictionary = _new_row(3.0, tier, coop)
			_expect(n3["dmg"] < GameBalance.DAMAGE_TOTAL_CAP - 0.05, "%s: dano min3 sin tocar techo (x%.2f)" % [tag, n3["dmg"]])
		else:
			_expect(n5["dmg"] < GameBalance.DAMAGE_TOTAL_CAP - 0.05, "%s: dano min5 sin tocar techo (x%.2f)" % [tag, n5["dmg"]])
	# 3) Sin saltos bruscos minuto a minuto. El umbral escala con la presion del
	# tier (Extremo sube mas rapido POR DISEÑO, pero de forma continua). En coop
	# la pendiente estable es algo mayor tambien POR DISEÑO: la potencia cuenta
	# el equipo de AMBOS jugadores (mult 1.6 en armas/niveles de arma), lo que
	# añade ~+0.14/min de score sobre la pendiente solo (~6.5/min con
	# TIME_WEIGHT 1.75 + kills 220/60 + potencia).
	var max_score_delta: float = (6.8 if coop else 6.5) * float(tier["pressure"])
	var prev: Dictionary = {}
	for m in range(1, 21):
		var n: Dictionary = _new_row(float(m), tier, coop)
		if not prev.is_empty():
			_expect(n["score"] - prev["score"] <= max_score_delta, "%s: salto de score min%d acotado (+%.1f <= %.1f)" % [tag, m, n["score"] - prev["score"], max_score_delta])
			_expect(n["hp"] - prev["hp"] <= 0.06 * max_score_delta + 0.06, "%s: salto de vida min%d acotado (+%.2f)" % [tag, m, n["hp"] - prev["hp"]])
		prev = n
	# 4) Velocidad con techo bajo SIEMPRE.
	var n20: Dictionary = _new_row(20.0, tier, coop)
	_expect(n20["spd"] <= GameBalance.SPEED_TOTAL_CAP + 0.001, "%s: velocidad min20 <= techo (x%.2f)" % [tag, n20["spd"]])
	# 5) Primeros minutos amables: la parte POR SCORE apenas sube en el minuto 1
	# (el suelo externo tier x coop es la dificultad ELEGIDA, no escalado) y el
	# dano total queda contenido en tiers <= dificil. Umbrales recalibrados tras
	# la Fase re-balance (TIME_WEIGHT 1.75 y bono coop rampando ya desde el min
	# 0-1.5): en coop dificil el score del min 1 llega a ~7 a proposito.
	var n1: Dictionary = _new_row(1.0, tier, coop)
	var hp_by_score_1: float = 1.0 + float(n1["score"]) * GameBalance.HEALTH_PER_POINT
	_expect(hp_by_score_1 <= 1.35, "%s: escalado de vida min1 casi plano (x%.2f por score)" % [tag, hp_by_score_1])
	if tier_index <= 2:
		_expect(n1["dmg"] <= 1.70, "%s: dano min1 contenido (x%.2f)" % [tag, n1["dmg"]])
	_expect(n1["elite"] == 0.0, "%s: sin elites en el minuto 1" % tag)
	# 6) Jugable al final: TTK de enemigo normal razonable con el DPS modelado.
	var ttk: float = 20.0 * n20["hp"] / _player_dps(20.0)
	_expect(ttk < 2.0, "%s: TTK normal min20 jugable (%.2fs)" % [tag, ttk])


## Condiciones cruzadas entre configuraciones.
func _validate_cross() -> void:
	var t10: float = 10.0
	# Separacion clara y monotona entre dificultades (vida al min 10).
	var hps: Array = []
	for tier_index in 4:
		hps.append(_new_row(t10, StoryCampaign.get_difficulty(tier_index), false)["hp"])
	for i in 3:
		_expect(hps[i] < hps[i + 1] - 0.03, "dificultades separadas: hp10 tier%d (x%.2f) < tier%d (x%.2f)" % [i, hps[i], i + 1, hps[i + 1]])
	# Facil nunca extremo.
	var easy20: Dictionary = _new_row(20.0, StoryCampaign.get_difficulty(0), false)
	_expect(easy20["hp"] <= 2.2, "facil min20: vida moderada (x%.2f)" % easy20["hp"])
	# Asintota de dano en facil = DAMAGE_SCORE_CAP (2.10) x tier 0.80 = x1.68,
	# aun por debajo de la formula antigua auditada (x1.76 en la misma celda).
	_expect(easy20["dmg"] <= 1.75, "facil min20: dano moderado (x%.2f)" % easy20["dmg"])
	# Coop = bono ADITIVO unico, no multiplicador de todo el score.
	var tier1: Dictionary = StoryCampaign.get_difficulty(1)
	var solo10: Dictionary = _new_row(t10, tier1, false)
	var coop10: Dictionary = _new_row(t10, tier1, true)
	var power_delta: float = coop10["power_smooth"] - solo10["power_smooth"]
	var extra: float = coop10["score"] - solo10["score"] - power_delta
	_expect(absf(extra - GameBalance.COOP_SCORE_BONUS) < 0.6,
		"coop suma un bono plano unico (+%.2f ~ %.1f), no un multiplicador" % [extra, GameBalance.COOP_SCORE_BONUS])
	# Extremo matematicamente jugable.
	var ext20: Dictionary = _new_row(20.0, StoryCampaign.get_difficulty(3), false)
	_expect(ext20["hp"] <= GameBalance.HEALTH_TOTAL_CAP and ext20["dmg"] <= GameBalance.DAMAGE_TOTAL_CAP \
		and ext20["spd"] <= GameBalance.SPEED_TOTAL_CAP,
		"extremo min20 dentro de TODOS los techos (hp x%.2f dmg x%.2f spd x%.2f)" % [ext20["hp"], ext20["dmg"], ext20["spd"]])


func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://telemetry")
	var f := FileAccess.open("user://telemetry/sim_before_after.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"rows": _rows}, "  "))
		f.close()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		pass
	else:
		_failures.append(message)
		printerr("  FALLO  ", message)
