extends Node
## Partida rapida COMPLETA acelerada (rendimiento + integracion): carga
## MainLevel real, mantiene vivo al jugador, auto-resuelve cartas y registra
## FPS, maximos por categoria, proyectiles, zonas, fases vistas, primera carta
## y desenlace. Valida que la partida SIEMPRE termina (limite absoluto).
##   godot --headless --path . res://tests/TestQuickRunSoak.tscn
## Variables de entorno:
##   SOAK_MODE  "solo" (defecto) | "coop"
##   SOAK_POWER "flow" (defecto) | "build"
##   SOAK_SCALE Engine.time_scale (defecto 8)
##
## Modos de potencia (ya NO existe el daño artificial x4/x40 del balance):
## - flow: prueba TECNICA pura, sin refuerzos. Ejercita el flujo completo
##   (fases, jefes, limite absoluto, caps, sin errores). El desenlace tipico es
##   DERROTA por tiempo (un jugador estatico sin punteria no derriba al jefe):
##   NO se afirma nada del balance con esto.
## - build: aproximacion a una BUILD NORMAL. Inyecta progresion de XP realista
##   (~6-8 cartas en 5 min: el arsenal crece solo con las cartas auto-elegidas) y
##   un factor de dano MODERADO que compensa que el jugador de prueba no se mueve
##   ni apunta. Sirve para comprobar que una build competente PUEDE ganar y recibe
##   la Mutacion; NO es una medida fina de balance (eso requiere prueba humana).

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"

var _failures: Array[String] = []
var _checks: int = 0

var _mode: String = "solo"
var _power: String = "normal"
var _elapsed: float = 0.0
var _done: bool = false
var _power_applied: bool = false

var _first_card_time: float = -1.0
var _phases_seen: Array[int] = []
var _fps_min: float = 999999.0
var _fps_sum: float = 0.0
var _fps_samples: int = 0
var _max_common: int = 0
var _max_special: int = 0
var _max_heavy: int = 0
var _max_minions: int = 0
var _max_projectiles: int = 0
var _max_zones: int = 0
var _max_enemies: int = 0
var _sample_timer: float = 0.0
var _mutations_seen: int = 0
var _level_node: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mode = OS.get_environment("SOAK_MODE")
	if _mode == "":
		_mode = "solo"
	_power = OS.get_environment("SOAK_POWER")
	if _power == "":
		_power = "flow"
	var scale_env: String = OS.get_environment("SOAK_SCALE")
	Engine.time_scale = float(scale_env) if scale_env != "" else 8.0

	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf != null:
		gf.set("game_mode", "local_coop" if _mode == "coop" else "solo")
	_level_node = (load(MAIN_LEVEL) as PackedScene).instantiate()
	add_child(_level_node)
	print("SOAK start mode=%s power=%s scale=%.0f" % [_mode, _power, Engine.time_scale])


func _process(delta: float) -> void:
	if _done:
		return
	if not get_tree().paused:
		_elapsed += delta
	_keep_players_alive()
	_collect_nearby_orbs()
	_auto_resolve_cards()
	if _power == "build":
		_inject_build_progression()
		_apply_build_damage_once()
	_track_phase()

	var fps: float = float(Engine.get_frames_per_second())
	if fps > 1.0:
		_fps_min = minf(_fps_min, fps)
		_fps_sum += fps
		_fps_samples += 1

	_sample_timer -= delta
	if _sample_timer <= 0.0:
		_sample_timer = 0.5
		_sample_counts()

	# Fin de partida real (victoria o derrota por tiempo).
	var mm: Node = get_tree().get_first_node_in_group("map_manager")
	if mm != null and mm.has_method("is_run_ended") and mm.is_run_ended():
		_finish()
		return
	# Cinturon de seguridad: si a los 6.5 min de juego nada termino, es un fallo
	# del limite absoluto.
	if _elapsed >= 390.0:
		_failures.append("la partida NO termino en 6.5 min (limite absoluto roto)")
		_finish()


func _keep_players_alive() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		if int(p.get("max_health")) < 9000000:
			p.set("max_health", 9999999)
		p.set("current_health", 9999999)


## El jugador del soak es estatico: simula el desplazamiento de un jugador real
## recogiendo los orbes que quedan a distancia de paseo (<300 px). Sin esto la
## progresion de XP no se ejercita (mismo enfoque que la telemetria).
func _collect_nearby_orbs() -> void:
	if get_tree().paused:
		return
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(player):
		return
	for orb in get_tree().get_nodes_in_group("xp_orbs"):
		if not is_instance_valid(orb) or not (orb is Node2D):
			continue
		if (orb as Node2D).global_position.distance_to(player.global_position) < 300.0 \
				and orb.has_method("collect"):
			orb.collect(player)


func _auto_resolve_cards() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null:
		var panel = hud.get("upgrade_panel")
		if panel != null and (panel as CanvasItem).visible and hud.has_signal("upgrade_card_selected"):
			if _first_card_time < 0.0:
				_first_card_time = _elapsed
			# Mutaciones vistas: la mano actual es de mutacion?
			var um: Node = _find_upgrade_manager()
			if um != null and bool(um.get("_mutation_active")):
				_mutations_seen += 1
			hud.emit_signal("upgrade_card_selected", 0)
	var coop_panel: Node = get_tree().get_first_node_in_group("coop_upgrade_panel")
	if coop_panel != null:
		for pid in [1, 2]:
			if bool(coop_panel.call("is_open", pid)):
				if _first_card_time < 0.0:
					_first_card_time = _elapsed
				coop_panel.emit_signal("card_chosen", pid, 0)


func _find_upgrade_manager() -> Node:
	if _level_node == null:
		return null
	return _level_node.get_node_or_null("UpgradeManager")


## Progresion realista de una BUILD NORMAL: se inyecta XP para que el jugador
## alcance ~6-8 niveles a lo largo de los 5 min (el arsenal crece SOLO con las
## cartas que se auto-eligen: armas nuevas, mejoras de arma, stats). Es la MISMA
## tecnica que la telemetria; el balance no se declara con esto.
func _inject_build_progression() -> void:
	if get_tree().paused:
		return
	# ~1.5 niveles/min -> ~7 niveles al minuto 5 (dentro del objetivo 6-8 cartas).
	var target_level: int = mini(12, 1 + int(_elapsed / 60.0 * 1.5))
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not p.has_method("add_experience"):
			continue
		if int(p.get("level")) < target_level:
			p.add_experience(int(p.get("experience_to_level")), true)
			return  # una subida por frame: deja que la seleccion se resuelva


## Factor de dano MODERADO (una vez) que compensa que el jugador de prueba no se
## mueve ni apunta: un jugador real acorrala a la horda, kitea y focaliza al jefe,
## logrando bastante mas DPS efectivo que uno estatico. Es una APROXIMACION (x3,
## no god-mode: el x40 se elimino), no una medida de balance. Por jugador, asi que
## en coop el equipo suma ~2x este proxy (dos arsenales), como es de esperar.
const BUILD_DAMAGE_PROXY: float = 3.0


func _apply_build_damage_once() -> void:
	if _power_applied or _elapsed < 1.0:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not p.has_method("get_weapon_manager"):
			continue
		var wm: Node = p.get_weapon_manager()
		if wm != null and wm.has_method("multiply_damage"):
			wm.multiply_damage(BUILD_DAMAGE_PROXY)
			_power_applied = true


func _track_phase() -> void:
	var director: Node = get_tree().get_first_node_in_group("phase_director")
	if director == null or not director.has_method("get_phase"):
		return
	var phase: int = int(director.get_phase())
	if _phases_seen.is_empty() or _phases_seen.back() != phase:
		_phases_seen.append(phase)


func _sample_counts() -> void:
	var common: int = 0
	var special: int = 0
	var heavy: int = 0
	var enemies: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		enemies += 1
		var data = e.get("enemy_data")
		if data == null:
			continue
		match data.get("tier"):
			&"special":
				special += 1
			&"heavy":
				heavy += 1
			_:
				common += 1
	_max_common = maxi(_max_common, common)
	_max_special = maxi(_max_special, special)
	_max_heavy = maxi(_max_heavy, heavy)
	_max_enemies = maxi(_max_enemies, enemies)
	_max_minions = maxi(_max_minions, get_tree().get_node_count_in_group("boss_minions"))
	_max_projectiles = maxi(_max_projectiles, get_tree().get_node_count_in_group("enemy_projectiles"))
	_max_zones = maxi(_max_zones, get_tree().get_node_count_in_group("hazard_zones"))


func _finish() -> void:
	if _done:
		return
	_done = true

	var director: Node = get_tree().get_first_node_in_group("phase_director")
	var final_phase: int = int(director.get_phase()) if director != null else -1

	# --- Comprobaciones ----------------------------------------------------------
	# Puerta temporal: la primera carta no se abre antes del segundo 12 aunque la
	# XP este completa; se muestra idealmente entre 12 y 18 (tolerancia hasta 20).
	_expect(_first_card_time >= 11.5 and _first_card_time <= 20.0,
		"primera carta entre 0:12 y 0:20 (t=%.1fs)" % _first_card_time)
	_expect(_elapsed <= 345.0, "la partida termino dentro del limite (%.0fs)" % _elapsed)
	# Orden de fases estrictamente creciente hasta el desenlace.
	var ordered := true
	for i in range(1, _phases_seen.size()):
		if _phases_seen[i] < _phases_seen[i - 1] \
				and _phases_seen[i] < RunPhaseConfig.Phase.VICTORY:
			ordered = false
	_expect(ordered, "fases en orden: %s" % str(_phases_seen))
	_expect(_phases_seen.has(RunPhaseConfig.Phase.MINIBOSS), "hubo fase de mini-boss")
	_expect(_phases_seen.has(RunPhaseConfig.Phase.BOSS), "hubo fase de boss")
	_expect(final_phase == RunPhaseConfig.Phase.VICTORY or final_phase == RunPhaseConfig.Phase.DEFEAT,
		"desenlace claro (fase final %d)" % final_phase)
	# flow: prueba tecnica; el desenlace tipico es DERROTA por tiempo (valida el
	# limite absoluto y el camino de derrota) — no se afirma nada del balance.
	if _power == "flow":
		_expect(final_phase == RunPhaseConfig.Phase.DEFEAT,
			"flow: sin refuerzos el jefe sobrevive -> DERROTA por limite (valida 5:30)")
	# build: una build competente PUEDE ganar y recibe la Mutacion del mini-boss.
	if _power == "build":
		_expect(final_phase == RunPhaseConfig.Phase.VICTORY,
			"build normal: el jefe elite cae -> VICTORIA")
		_expect(_mutations_seen >= 1 or _mode == "coop",
			"Mutacion ofrecida al caer el mini-boss (%d)" % _mutations_seen)
	_expect(_max_projectiles <= RunPhaseConfig.MAX_ENEMY_PROJECTILES,
		"proyectiles enemigos bajo el limite (%d)" % _max_projectiles)
	_expect(_max_zones <= RunPhaseConfig.MAX_HAZARD_ZONES,
		"zonas peligrosas bajo el limite (%d)" % _max_zones)
	_expect(_max_enemies <= 220, "enemigos vivos bajo el techo (%d)" % _max_enemies)

	# Nodos huerfanos (monitor nativo; el autoload Performance hace sombra).
	var orphans: int = 0
	var perf = Engine.get_singleton(&"Performance")
	if perf != null:
		orphans = int(perf.get_monitor(3))
	_expect(orphans < 50, "sin fuga de nodos huerfanos (%d)" % orphans)

	# --- Informe -------------------------------------------------------------------
	var fps_avg: int = int(_fps_sum / maxf(1.0, float(_fps_samples)))
	print("")
	print("SOAK %s/%s  t=%.0fs  fase_final=%d" % [_mode, _power, _elapsed, final_phase])
	print("  fps_min=%d fps_avg=%d" % [int(_fps_min), fps_avg])
	print("  max comunes=%d especiales=%d pesados=%d esbirros=%d" % [_max_common, _max_special, _max_heavy, _max_minions])
	print("  max proyectiles_enemigos=%d zonas=%d enemigos_totales=%d" % [_max_projectiles, _max_zones, _max_enemies])
	print("  primera_carta=%.1fs mutaciones=%d fases=%s" % [_first_card_time, _mutations_seen, str(_phases_seen)])
	print("TestQuickRunSoak: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", message)
	else:
		_failures.append(message)
		printerr("  FALLO  ", message)
