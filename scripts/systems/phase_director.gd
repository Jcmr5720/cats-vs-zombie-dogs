extends Node
## Director de fases (Partidas rapidas): convierte cada mapa en una partida
## corta e intensa de ~5 minutos con progresion por fases:
##   INTRO -> COMMON -> SPECIAL -> HEAVY -> MINIBOSS -> BOSS -> ELITE_BOSS
## y cierre garantizado: furia final a los 5:00 y derrota al limite absoluto
## (~5:30) si el jefe sigue vivo. Los tiempos por defecto y las composiciones
## viven CENTRALIZADOS en RunPhaseConfig; aqui solo esta la orquestacion.
##
## Reutiliza los sistemas existentes: EnemySpawner (spawn + presupuesto),
## BossSpawner (jefes + barra del HUD + musica), MapManager (victoria/derrota y
## recompensas) y UpgradeManager (Mutacion al caer el mini-boss). El calendario
## clasico del WaveEventManager queda suspendido (set_external_director).
##
## El reloj se detiene solo con la pausa del arbol (cartas, menu), igual que el
## WaveEventManager clasico: process_mode heredado.

signal phase_changed(phase: int)

@export var hud_path: NodePath
@export var enemy_spawner_path: NodePath
@export var boss_spawner_path: NodePath
@export var wave_event_manager_path: NodePath
@export var map_manager_path: NodePath
@export var upgrade_manager_path: NodePath

@export_group("Tiempos de fase (segundos; defaults en RunPhaseConfig)")
@export var common_start: float = RunPhaseConfig.COMMON_START
@export var special_start: float = RunPhaseConfig.SPECIAL_START
@export var heavy_start: float = RunPhaseConfig.HEAVY_START
@export var miniboss_start: float = RunPhaseConfig.MINIBOSS_START
@export var boss_start: float = RunPhaseConfig.BOSS_START
@export var elite_start: float = RunPhaseConfig.ELITE_START
@export var final_fury_start: float = RunPhaseConfig.FINAL_FURY_START
@export var absolute_limit: float = RunPhaseConfig.ABSOLUTE_LIMIT

var _hud: Node
var _spawner: Node
var _boss_spawner: Node
var _wave_events: Node
var _map_manager: Node
var _upgrade_manager: Node

var _elapsed: float = 0.0
var _phase: int = RunPhaseConfig.Phase.INTRO
var _run_over: bool = false
var _opening_runners_done: bool = false
var _fury_started: bool = false
var _hud_tick: float = 0.0
## Jefe activo (para la transformacion elite y la furia final).
var _boss_node: Node2D


func _ready() -> void:
	add_to_group("phase_director")
	_hud = get_node_or_null(hud_path)
	_spawner = get_node_or_null(enemy_spawner_path)
	_boss_spawner = get_node_or_null(boss_spawner_path)
	_wave_events = get_node_or_null(wave_event_manager_path)
	_map_manager = get_node_or_null(map_manager_path)
	_upgrade_manager = get_node_or_null(upgrade_manager_path)

	# El director asume el calendario completo: sin hordas/jefes del sistema clasico.
	if is_instance_valid(_wave_events) and _wave_events.has_method("set_external_director"):
		_wave_events.set_external_director(true)

	if is_instance_valid(_boss_spawner):
		if _boss_spawner.has_signal("miniboss_defeated"):
			_boss_spawner.connect("miniboss_defeated", Callable(self, "_on_miniboss_defeated"))
		if _boss_spawner.has_signal("boss_defeated"):
			_boss_spawner.connect("boss_defeated", Callable(self, "_on_boss_defeated"))

	# Diferido: todos los sistemas (incluido MapManager con el mapa activo) deben
	# haber corrido su _ready antes de aplicar el primer perfil y la manada inicial.
	call_deferred("_start_run")


func _start_run() -> void:
	_apply_phase(RunPhaseConfig.Phase.INTRO)
	# Segundo 0: manada inicial de comunes debiles, fuera de camara, con ruta de
	# escape (spawn_pack entra por un arco, no rodea al jugador).
	if is_instance_valid(_spawner) and _spawner.has_method("spawn_pack"):
		var count: int = randi_range(RunPhaseConfig.OPENING_PACK_MIN, RunPhaseConfig.OPENING_PACK_MAX)
		_spawner.spawn_pack(&"zombie_dog", count)
	_announce("¡La horda llega! Resiste hasta el jefe")


func _process(delta: float) -> void:
	if _run_over:
		return
	if is_instance_valid(_map_manager) and _map_manager.has_method("is_run_ended") \
			and _map_manager.is_run_ended():
		_run_over = true
		return
	_elapsed += delta

	# Segundo ~8: entra una variedad rapida (la horda no es homogenea).
	if not _opening_runners_done and _elapsed >= RunPhaseConfig.OPENING_RUNNERS_TIME:
		_opening_runners_done = true
		if is_instance_valid(_spawner) and _spawner.has_method("spawn_pack"):
			_spawner.spawn_pack(&"runner_zombie_dog", RunPhaseConfig.OPENING_RUNNERS_COUNT)

	var target: int = _phase_for_time(_elapsed)
	if target != _phase:
		_apply_phase(target)

	# 5:00 — se detienen los spawns comunes y arranca la furia final.
	if not _fury_started and _elapsed >= final_fury_start:
		_start_final_fury()

	# Limite absoluto (~5:30): si el jefe sigue vivo, derrota. Sin partidas infinitas.
	if _elapsed >= absolute_limit:
		_time_out_defeat()
		return

	_hud_tick -= delta
	if _hud_tick <= 0.0:
		_hud_tick = 0.25
		_update_hud_phase()


## Fase que corresponde al reloj usando los tiempos CONFIGURADOS del nodo.
func _phase_for_time(seconds: float) -> int:
	if seconds < common_start:
		return RunPhaseConfig.Phase.INTRO
	if seconds < special_start:
		return RunPhaseConfig.Phase.COMMON_ENEMIES
	if seconds < heavy_start:
		return RunPhaseConfig.Phase.SPECIAL_ENEMIES
	if seconds < miniboss_start:
		return RunPhaseConfig.Phase.HEAVY_ENEMIES
	if seconds < boss_start:
		return RunPhaseConfig.Phase.MINIBOSS
	if seconds < elite_start:
		return RunPhaseConfig.Phase.BOSS
	return RunPhaseConfig.Phase.ELITE_BOSS


func _apply_phase(phase: int) -> void:
	_phase = phase
	# Perfil de spawn de la fase, con la identidad del mapa mezclada encima.
	var profile: Dictionary = RunPhaseConfig.phase_profile(phase).duplicate(true)
	_merge_map_weights(profile)
	if is_instance_valid(_spawner) and _spawner.has_method("set_phase_profile"):
		_spawner.set_phase_profile(profile)

	match phase:
		RunPhaseConfig.Phase.COMMON_ENEMIES:
			_announce("La horda crece...")
		RunPhaseConfig.Phase.SPECIAL_ENEMIES:
			_announce("¡Enemigos especiales detectados!")
		RunPhaseConfig.Phase.HEAVY_ENEMIES:
			_announce("¡Amenazas pesadas en camino!")
		RunPhaseConfig.Phase.MINIBOSS:
			# El BossSpawner ya anuncia con nombre, barra propia, shake y sfx.
			if is_instance_valid(_boss_spawner) and _boss_spawner.has_method("spawn_miniboss"):
				_boss_spawner.spawn_miniboss()
		RunPhaseConfig.Phase.BOSS:
			# Anuncio, barra del HUD y musica de jefe los pone el BossSpawner.
			if is_instance_valid(_boss_spawner) and _boss_spawner.has_method("spawn_boss"):
				_boss_node = _boss_spawner.spawn_boss()
		RunPhaseConfig.Phase.ELITE_BOSS:
			_transform_boss_elite()
	phase_changed.emit(phase)


## 4:15 — el jefe actual SE TRANSFORMA en su version elite (no se crea otro).
func _transform_boss_elite() -> void:
	if not is_instance_valid(_boss_node):
		# Si el jugador ya mato al jefe, la victoria la gestiono MapManager.
		return
	if _boss_node.has_method("transform_elite"):
		_boss_node.transform_elite()
		# La barra del HUD se actualiza con el nombre elite.
		if is_instance_valid(_hud) and _hud.has_method("show_boss_bar"):
			var elite_name: String = "Jefe elite"
			var data = _boss_node.get("data")
			if data != null:
				elite_name = data.elite_name if data.elite_name != "" else "%s ELITE" % data.display_name
			_hud.show_boss_bar(elite_name, int(_boss_node.get("max_health")))
		_announce("¡¡El jefe se transforma!!")
		# Refuerzo musical: reinicia el tema de jefe (no hay pista elite propia).
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio != null and audio.has_method("play_music"):
			audio.play_music(&"boss")


## 5:00 — furia final: paran los spawns comunes y el jefe se acelera (evitable).
func _start_final_fury() -> void:
	_fury_started = true
	if is_instance_valid(_spawner) and _spawner.has_method("set_phase_profile"):
		var empty: Dictionary = RunPhaseConfig.phase_profile(RunPhaseConfig.Phase.VICTORY)
		_spawner.set_phase_profile(empty)
	if is_instance_valid(_boss_node) and _boss_node.has_method("enrage"):
		_boss_node.enrage()
	_announce("¡¡FURIA FINAL!! Derrota al jefe YA")
	Feedback.shake(0.3)


## Limite absoluto alcanzado con el jefe vivo: derrota (via flujo unificado).
func _time_out_defeat() -> void:
	if _run_over:
		return
	_run_over = true
	_phase = RunPhaseConfig.Phase.DEFEAT
	phase_changed.emit(_phase)
	_announce("El jefe sigue en pie... la colonia cae")
	if is_instance_valid(_map_manager) and _map_manager.has_method("force_run_end"):
		_map_manager.force_run_end(false)


func _on_miniboss_defeated(_data) -> void:
	# Recompensa GARANTIZADA: una Mutacion (mas fuerte que una carta normal).
	if is_instance_valid(_upgrade_manager) and _upgrade_manager.has_method("grant_mutation"):
		_upgrade_manager.grant_mutation()


func _on_boss_defeated(_data) -> void:
	# La victoria (recompensas, panel, guardado) la orquesta MapManager con sus
	# objetivos; aqui solo se refleja el estado para HUD/tests.
	_run_over = true
	_phase = RunPhaseConfig.Phase.VICTORY
	phase_changed.emit(_phase)


## Mezcla la identidad del mapa: multiplica pesos de la fase por los overrides
## del MapData (phase_weight_overrides: id -> multiplicador).
func _merge_map_weights(profile: Dictionary) -> void:
	if not is_instance_valid(_map_manager) or not _map_manager.has_method("get_active_map"):
		return
	var map = _map_manager.get_active_map()
	if map == null:
		return
	var overrides = map.get("phase_weight_overrides")
	if not (overrides is Dictionary) or overrides.is_empty():
		return
	var weights: Dictionary = profile.get("weights", {})
	for id in overrides:
		if weights.has(id):
			weights[id] = float(weights[id]) * float(overrides[id])


func _update_hud_phase() -> void:
	if not is_instance_valid(_hud) or not _hud.has_method("set_phase_info"):
		return
	var label: String
	var remaining: float
	if _fury_started:
		label = "Furia final"
		remaining = maxf(0.0, absolute_limit - _elapsed)
	else:
		label = RunPhaseConfig.phase_name(_phase)
		remaining = maxf(0.0, final_fury_start - _elapsed)
	var total: int = int(ceil(remaining))
	@warning_ignore("integer_division")
	_hud.set_phase_info("%s · %d:%02d" % [label, total / 60, total % 60])


func _announce(text: String) -> void:
	if is_instance_valid(_hud) and _hud.has_method("show_event_message"):
		_hud.show_event_message(text, 2.4)


# --- API de consulta / tests ----------------------------------------------------

func get_phase() -> int:
	return _phase


func get_elapsed() -> float:
	return _elapsed


func is_final_fury() -> bool:
	return _fury_started


## Salta el reloj (tests/debug). Las transiciones se aplican en el proximo frame.
func debug_set_time(seconds: float) -> void:
	_elapsed = seconds
