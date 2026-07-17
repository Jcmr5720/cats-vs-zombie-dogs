extends Node
## Telemetria de dificultad: corre una partida REAL acelerada (Engine.time_scale)
## y registra cada minuto de juego los multiplicadores y el estado del combate.
## Sirve para comparar la curva de dificultad antes/despues de un rebalanceo.
##   $env:TELEMETRY_MODE="solo:1"; godot --headless --path . res://tests/TestDifficultyTelemetry.tscn
## Variables de entorno:
##   TELEMETRY_MODE    "solo:0".."solo:3" | "coop:0".."coop:3" (modo:dificultad)
##   TELEMETRY_MINUTES minutos de juego a simular (defecto 20)
##   TELEMETRY_SCALE   Engine.time_scale (defecto 10)
##   TELEMETRY_OUT     nombre del archivo en user://telemetry/ (defecto por modo)
## El jugador queda practicamente inmortal (vida enorme re-llenada) y las cartas
## se eligen solas (carta 0) para que la progresion real de XP/armas siga viva.

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"

var _minutes_target: float = 20.0
var _mode: String = "solo"
var _tier: int = 1
var _out_name: String = ""
var _level_node: Node
var _elapsed: float = 0.0
var _next_sample_minute: int = 1
var _rows: Array = []
var _done: bool = false
var _damage_taken_minute: float = 0.0
var _kills_prev: int = 0
var _fps_min: float = 99999.0
var _fps_sum: float = 0.0
var _fps_samples: int = 0
var _started: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mode_env: String = OS.get_environment("TELEMETRY_MODE")
	if mode_env != "":
		var parts := mode_env.split(":")
		_mode = parts[0]
		_tier = int(parts[1]) if parts.size() > 1 else 1
	_minutes_target = float(OS.get_environment("TELEMETRY_MINUTES")) if OS.get_environment("TELEMETRY_MINUTES") != "" else 20.0
	var scale_env: String = OS.get_environment("TELEMETRY_SCALE")
	Engine.time_scale = float(scale_env) if scale_env != "" else 10.0
	_out_name = OS.get_environment("TELEMETRY_OUT")
	if _out_name == "":
		_out_name = "telemetry_%s_%d" % [_mode, _tier]

	var gf: Node = get_node_or_null("/root/GameFlow")
	gf.set("game_mode", "local_coop" if _mode == "coop" else "solo")
	if gf.has_method("set_free_play_difficulty"):
		gf.set_free_play_difficulty(_tier)
	_level_node = (load(MAIN_LEVEL) as PackedScene).instantiate()
	add_child(_level_node)
	_started = true
	print("TELEMETRY start mode=%s tier=%d minutes=%.0f scale=%.0f" % [_mode, _tier, _minutes_target, Engine.time_scale])


func _process(delta: float) -> void:
	if _done or not _started:
		return
	# delta ya viene escalado por time_scale: es tiempo DE JUEGO.
	if not get_tree().paused:
		_elapsed += delta
	_keep_players_alive()
	_auto_resolve_cards()
	_inject_progression()
	var fps: float = float(Engine.get_frames_per_second())
	if fps > 1.0:
		_fps_min = minf(_fps_min, fps)
		_fps_sum += fps
		_fps_samples += 1
	if _elapsed >= float(_next_sample_minute) * 60.0:
		_sample(_next_sample_minute)
		_next_sample_minute += 1
	if _elapsed >= _minutes_target * 60.0:
		_finish()


func _keep_players_alive() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		if int(p.get("max_health")) < 9000000:
			p.set("max_health", 9999999)
			if p.has_signal("damaged") and not p.damaged.is_connected(_on_player_damaged):
				p.damaged.connect(_on_player_damaged)
		p.set("current_health", 9999999)


func _on_player_damaged(amount: int) -> void:
	_damage_taken_minute += float(amount)


## Empuja la progresion hacia una curva de nivel tipica (~TELEMETRY_LEVEL_RATE
## niveles/min): el jugador estatico casi no recoge XP, asi que se inyecta XP real
## (dispara level_up y cartas REALES, auto-resueltas) para que la dificultad vea
## crecer nivel/armas/mejoras como en una partida normal.
func _inject_progression() -> void:
	if get_tree().paused:
		return
	var rate_env: String = OS.get_environment("TELEMETRY_LEVEL_RATE")
	var rate: float = float(rate_env) if rate_env != "" else 1.2
	var target_level: int = mini(26, 1 + int(_elapsed / 60.0 * rate))
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not p.has_method("add_experience"):
			continue
		if int(p.get("level")) < target_level:
			p.add_experience(int(p.get("experience_to_level")), true)
			return  # una subida por frame: deja que la seleccion se resuelva


## Elige siempre la carta 0 en cuanto aparece una seleccion (solo o coop).
func _auto_resolve_cards() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null:
		var panel = hud.get("upgrade_panel")
		if panel != null and (panel as CanvasItem).visible and hud.has_signal("upgrade_card_selected"):
			hud.emit_signal("upgrade_card_selected", 0)
	var coop_panel: Node = get_tree().get_first_node_in_group("coop_upgrade_panel")
	if coop_panel != null:
		for pid in [1, 2]:
			if bool(coop_panel.call("is_open", pid)):
				coop_panel.emit_signal("card_chosen", pid, 0)


func _spawner() -> Node:
	return get_tree().get_first_node_in_group("enemy_spawner")


func _sample(minute: int) -> void:
	var sp: Node = _spawner()
	if sp == null:
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	var elites: int = 0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var kind = e.get("_elite_kind")
		if kind != null and kind is StringName and kind != &"":
			elites += 1
	var level_max: int = 0
	var upgrades: int = 0
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p):
			level_max = maxi(level_max, int(p.get("level")))
			upgrades += int(p.get("upgrades_chosen"))
	var kills: int = int(sp.call("get_kills")) if sp.has_method("get_kills") else 0
	var timer = sp.get("_spawn_timer")
	var row := {
		"minute": minute,
		"score": snappedf(float(sp.call("get_difficulty_score")), 0.01),
		"health_mult": snappedf(float(sp.call("_health_multiplier")), 0.001),
		"damage_mult": snappedf(float(sp.call("_damage_multiplier")), 0.001),
		"speed_mult": snappedf(float(sp.call("_speed_multiplier")), 0.001),
		"spawn_interval": snappedf(float(timer.wait_time) if timer != null else -1.0, 0.001),
		"max_enemies": int(sp.call("_current_max_enemies")),
		"alive": enemies.size(),
		"elites": elites,
		"level": level_max,
		"upgrades": upgrades,
		"kills": kills,
		"kills_per_min": kills - _kills_prev,
		"damage_taken": int(_damage_taken_minute),
		"fps_min": int(_fps_min),
		"fps_avg": int(_fps_sum / maxf(1.0, float(_fps_samples))),
	}
	_kills_prev = kills
	_damage_taken_minute = 0.0
	_fps_min = 99999.0
	_fps_sum = 0.0
	_fps_samples = 0
	_rows.append(row)
	print("MIN %02d  score=%s hp=x%s dmg=x%s spd=x%s int=%ss cap=%s alive=%s elites=%s lvl=%s upg=%s kpm=%s dmg_in=%s" % [
		minute, row["score"], row["health_mult"], row["damage_mult"], row["speed_mult"],
		row["spawn_interval"], row["max_enemies"], row["alive"], row["elites"],
		row["level"], row["upgrades"], row["kills_per_min"], row["damage_taken"]])


func _finish() -> void:
	if _done:
		return
	_done = true
	DirAccess.make_dir_recursive_absolute("user://telemetry")
	var f := FileAccess.open("user://telemetry/%s.json" % _out_name, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"mode": _mode, "tier": _tier, "rows": _rows}, "  "))
		f.close()
	print("TELEMETRY done -> %s" % ProjectSettings.globalize_path("user://telemetry/%s.json" % _out_name))
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().quit(0)
