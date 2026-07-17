extends Node
## Orquesta la estructura temporal de la partida (Fase 05): hordas, manadas de
## runners, mini-jefes y el jefe principal. Mantiene un reloj propio (avanza solo
## cuando el juego NO esta en pausa, por lo que las cartas de upgrade tambien
## pausan los eventos) y dispara cada WaveEventData cuando llega su `time`.
##
## No spawnea enemigos directamente: delega en EnemySpawner (hordas/runners) y en
## BossSpawner (jefes), manteniendo el sistema modular y desacoplado.

const WaveEventData = preload("res://scripts/systems/wave_event_data.gd")

@export var hud_path: NodePath
@export var enemy_spawner_path: NodePath
@export var boss_spawner_path: NodePath

@export_group("Tiempos de eventos (segundos)")
## Primera horda a los 75 s: da al jugador nuevo un primer minuto de aprendizaje.
@export var horde_first_time: float = 75.0
@export var horde_repeat: float = 90.0
@export var horde_duration: float = 20.0
@export var horde_intensity: float = 2.0
@export var runner_first_time: float = 120.0
@export var runner_repeat: float = 120.0
@export var runner_duration: float = 15.0
@export var miniboss_first_time: float = 180.0
@export var miniboss_second_time: float = 420.0
@export var boss_time: float = 600.0

@export_group("Debug / prueba rapida")
## Si es true, el jefe principal aparece en `debug_boss_spawn_time` (no en boss_time).
@export var debug_spawn_boss_early: bool = false
@export var debug_boss_spawn_time: float = 20.0
## Si es true, aparece un mini-jefe temprano (a los 12 s) para probar sin esperar.
@export var debug_spawn_miniboss_early: bool = false
@export var debug_miniboss_spawn_time: float = 12.0

var _hud: Node
var _enemy_spawner: Node
var _boss_spawner: Node
var _elapsed: float = 0.0
var _events: Array[WaveEventData] = []
var _boss_spawned: bool = false

# --- Tiempos del mapa activo (Fase 06). Si estan definidos, mandan sobre los @export. ---
var _map_boss_time: float = -1.0
var _map_miniboss_times: PackedFloat32Array = PackedFloat32Array()
var _map_applied: bool = false


## Partidas rapidas por fases: un director externo (PhaseDirector) asume el
## calendario COMPLETO (hordas, mini-jefes y jefe). Con esto activo, este nodo
## no dispara ningun evento propio (y las reprogramaciones quedan bloqueadas).
var _external_director: bool = false


func set_external_director(active: bool) -> void:
	_external_director = active
	if active:
		_events.clear()


## La llama MapManager: fija los tiempos de jefe/mini-jefes del mapa y reprograma.
func apply_map_schedule(boss_time: float, miniboss_times: PackedFloat32Array) -> void:
	_map_boss_time = boss_time
	_map_miniboss_times = miniboss_times
	_map_applied = true
	_build_schedule()


func _ready() -> void:
	add_to_group("wave_event_manager")
	_hud = get_node_or_null(hud_path)
	_enemy_spawner = get_node_or_null(enemy_spawner_path)
	_boss_spawner = get_node_or_null(boss_spawner_path)
	_build_schedule()


## Construye la lista de eventos por tiempo. Editable via los @export de arriba.
func _build_schedule() -> void:
	_events.clear()
	if _external_director:
		return
	_add_event(&"horde", horde_first_time, horde_duration, horde_intensity,
		"¡Horda entrante!", horde_repeat)
	_add_event(&"runner_pack", runner_first_time, runner_duration, 1.0,
		"¡Manada rápida detectada!", runner_repeat)

	if debug_spawn_miniboss_early:
		_add_event(&"miniboss", debug_miniboss_spawn_time, 0.0, 1.0, "", 0.0)
	elif _map_applied and not _map_miniboss_times.is_empty():
		# Tiempos de mini-jefes del mapa activo.
		for t in _map_miniboss_times:
			_add_event(&"miniboss", float(t), 0.0, 1.0, "", 0.0)
	else:
		_add_event(&"miniboss", miniboss_first_time, 0.0, 1.0, "", 0.0)
		_add_event(&"miniboss", miniboss_second_time, 0.0, 1.0, "", 0.0)

	var base_boss_time: float = _map_boss_time if _map_applied and _map_boss_time > 0.0 else boss_time
	var boss_at: float = debug_boss_spawn_time if debug_spawn_boss_early else base_boss_time
	if base_boss_time > 0.0 or debug_spawn_boss_early:
		_add_event(&"boss", boss_at, 0.0, 1.0, "", 0.0)


func _add_event(type: StringName, time: float, duration: float, intensity: float,
		label: String, repeat_interval: float) -> void:
	var event := WaveEventData.new()
	event.type = type
	event.time = time
	event.duration = duration
	event.intensity = intensity
	event.label = label
	event.repeat_interval = repeat_interval
	_events.append(event)


func _process(delta: float) -> void:
	_elapsed += delta
	# Dispara todos los eventos cuyo tiempo ya llego.
	for index in range(_events.size() - 1, -1, -1):
		var event: WaveEventData = _events[index]
		if _elapsed >= event.time:
			_fire(event)
			if event.repeat_interval > 0.0:
				event.time += event.repeat_interval  # se reprograma
			else:
				_events.remove_at(index)


func _fire(event: WaveEventData) -> void:
	match event.type:
		&"horde":
			if is_instance_valid(_enemy_spawner) and _enemy_spawner.has_method("start_horde"):
				_enemy_spawner.start_horde(event.duration, event.intensity)
			_play_event_audio()
			_announce(event.label)
		&"runner_pack":
			if is_instance_valid(_enemy_spawner) and _enemy_spawner.has_method("start_runner_pack"):
				_enemy_spawner.start_runner_pack(event.duration)
			_play_event_audio()
			_announce(event.label)
		&"miniboss":
			if is_instance_valid(_boss_spawner) and _boss_spawner.has_method("spawn_miniboss"):
				_boss_spawner.spawn_miniboss()
		&"boss":
			if _boss_spawned:
				return
			if is_instance_valid(_boss_spawner) and _boss_spawner.has_method("spawn_boss"):
				_boss_spawner.spawn_boss()
				_boss_spawned = true
		&"xp_bonus":
			_announce(event.label)
		_:
			pass


func _announce(text: String) -> void:
	if text == "":
		return
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message(text, 2.6)


func _play_event_audio() -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"event_alert")
