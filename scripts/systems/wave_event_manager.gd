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


# --- Eventos centrales de mapa (FASE 11) -------------------------------------
# El PhaseDirector dispara UNO por partida (elegido por la semilla via RunScript)
# en la ventana 110-155 s. Cada evento reutiliza sistemas existentes: spawner,
# zonas de peligro (HazardZone.try_spawn), obstaculos y ambiente.

const HAZARD_ZONE := preload("res://scripts/enemies/hazard_zone.gd")
const OBSTACLE_SCENE_PATH := "res://scenes/maps/Obstacle.tscn"
const BARRICADE_DATA_PATH := "res://data/obstacles/nb_barricade.tres"
## Cuanto duran las barricadas temporales del evento street_block.
const STREET_BLOCK_DURATION: float = 40.0
## Anticipacion de la barricada: se marca el sitio antes de levantar el muro,
## para que cerrar una calle nunca atrape a quien ya la estaba cruzando.
const BARRICADE_TELEGRAPH: float = 1.2


## Ejecuta un evento central por id. Ids no reconocidos no hacen nada (los mapas
## pueden definir pools nuevos sin romper builds viejas).
func trigger_map_event(id: StringName) -> void:
	match id:
		&"street_block":
			_event_street_block()
		&"stray_horde":
			_event_stray_horde()
		&"lake_fog":
			_event_lake_fog()
		&"carrier_bloom":
			_event_carrier_bloom()
		&"freight_train":
			_event_freight_train()
		&"steam_burst":
			_event_steam_burst()
		&"blackout":
			_event_blackout()
		_:
			return
	_play_event_audio()


func _event_player_pos() -> Vector2:
	var p: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p is Node2D:
		return (p as Node2D).global_position
	return Vector2.ZERO


## Semilla y bioma del mapa activo: los eventos centrales se anclan a la GEOMETRIA
## real (calles, orilla del lago, via de tren), no al punto donde este el jugador.
func _map_seed() -> int:
	var manager: Node = get_tree().get_first_node_in_group("map_manager")
	if is_instance_valid(manager) and manager.has_method("get_world_seed"):
		return manager.get_world_seed()
	return 0


func _map_biome() -> StringName:
	var manager: Node = get_tree().get_first_node_in_group("map_manager")
	if is_instance_valid(manager) and manager.has_method("get_active_map"):
		var map = manager.get_active_map()
		if map != null:
			return map.biome
	return &"neighborhood"


## Rng determinista del evento: mismo guion = mismo despliegue.
func _event_rng(tag: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("event:%d:%s" % [_map_seed(), tag])
	return rng


## Barrio: barricadas TEMPORALES cierran 2 calles (embudos nuevos durante 40 s).
func _event_street_block() -> void:
	_announce("¡Barricadas! Calles bloqueadas")
	var scene := load(OBSTACLE_SCENE_PATH) as PackedScene
	var data = load(BARRICADE_DATA_PATH)
	if scene == null or data == null:
		return
	var origin: Vector2 = _event_player_pos()
	var rng := _event_rng("street_block")
	# Las barricadas CIERRAN CALLES: se colocan atravesadas sobre el corredor de
	# vias reales cercanas, no en dos lineas arbitrarias alrededor del jugador.
	# Asi el evento cambia de verdad las rutas de movimiento del mapa.
	var world_seed: int = _map_seed()
	var biome: StringName = _map_biome()
	var roads := MapGeometry.roads_near(world_seed, biome, origin, 900.0)
	if roads.is_empty():
		return
	# Candidatas a BLOQUEAR: vias a distancia util, ni encima del jugador ni tan
	# lejos que el corte no se lea.
	var candidates: Array[Dictionary] = []
	for road in roads:
		var coord: float = float(road["coord"])
		var vertical: bool = road["axis"] == &"vertical"
		var along: float = origin.x if vertical else origin.y
		if absf(coord - along) < 240.0 or absf(coord - along) > 1100.0:
			continue
		candidates.append(road)
	# GARANTIA DE SALIDA. Las rutas de escape NO son solo las candidatas: cuentan
	# todas las vias del entorno, incluidas las que quedan fuera de la banda de
	# bloqueo (siguen siendo por donde salir). Se exige que tras bloquear queden
	# al menos 2 rutas libres.
	var total_routes: int = roads.size()
	var max_blocks: int = mini(2, maxi(0, total_routes - 2))
	max_blocks = mini(max_blocks, candidates.size())
	if max_blocks <= 0:
		# Entorno con muy pocas vias: bloquear aqui dejaria al jugador sin salida.
		# El evento degrada a manada callejera en vez de encerrar.
		RunTelemetry.count(&"street_block_downgraded")
		_event_stray_horde()
		return
	RunTelemetry.count(&"alternative_routes_left", total_routes - max_blocks)
	var blocked: int = 0
	for road in candidates:
		if blocked >= max_blocks:
			break
		var coord: float = float(road["coord"])
		var vertical: bool = road["axis"] == &"vertical"
		blocked += 1
		RunTelemetry.count(&"routes_blocked")
		# El corte va perpendicular a la via, a la altura del jugador en el otro eje.
		var across: Vector2 = Vector2(0.0, 1.0) if vertical else Vector2(1.0, 0.0)
		var center: Vector2 = Vector2(coord, origin.y) if vertical else Vector2(origin.x, coord)
		var half: float = float(road["half_width"])
		var count: int = maxi(3, int(ceilf(half * 2.0 / 72.0)))
		for i in count:
			var t: float = (float(i) / float(maxi(1, count - 1)) - 0.5) * 2.0
			var pos: Vector2 = center + across * t * half
			# No aplastar jefes, compañeros ni interactuables: una barricada
			# encima de ellos los dejaria inaccesibles o rotos.
			if not _barricade_spot_free(pos):
				continue
			# TELEGRAFO: la marca aparece antes que el muro. El jugador ve donde
			# se va a cerrar la calle y tiene tiempo de cruzarla.
			Feedback.hit_effect(pos, Color(1.0, 0.7, 0.25, 0.85), 0.5, 2.0)
			get_tree().create_timer(BARRICADE_TELEGRAPH).timeout.connect(
				_raise_barricade.bind(pos, scene, data, rng))
		RunTelemetry.count(&"barricades_created")
	Feedback.shake(0.2)


## true si el punto esta libre de jefes, compañeros e interactuables de mapa.
func _barricade_spot_free(pos: Vector2) -> bool:
	for group in [&"boss", &"companions", &"map_interactables", &"players"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or not (node is Node2D):
				continue
			if pos.distance_to((node as Node2D).global_position) < 110.0:
				return false
	return true


## Levanta una barricada ya telegrafiada (y programa su retirada).
func _raise_barricade(pos: Vector2, scene: PackedScene, data, rng: RandomNumberGenerator) -> void:
	if not is_inside_tree():
		return
	var obstacle := scene.instantiate() as Node2D
	if obstacle == null:
		return
	obstacle.global_position = pos
	get_parent().add_child(obstacle)
	if obstacle.has_method("configure"):
		obstacle.call("configure", data, rng)
	# Temporal: se libera sola (weakref: la escena puede reiniciarse antes de que
	# venza el temporizador).
	get_tree().create_timer(STREET_BLOCK_DURATION).timeout.connect(
		_free_temp_obstacle.bind(weakref(obstacle)))


func _free_temp_obstacle(ref: WeakRef) -> void:
	var obstacle = ref.get_ref()
	if obstacle != null and is_instance_valid(obstacle):
		obstacle.queue_free()


## Barrio: una manada callejera entra en tromba desde UN lado. Moderada: los
## eventos añaden PRESION, no una fuente extra de XP que abarate al jefe.
func _event_stray_horde() -> void:
	_announce("¡Manada callejera! Llegan en tromba")
	if is_instance_valid(_enemy_spawner):
		if _enemy_spawner.has_method("start_horde"):
			_enemy_spawner.start_horde(18.0, 2.0)
		# Entra por DOS bocas de calle distintas: la manada callejera se lee como
		# una caceria por rutas, no como un circulo que aparece alrededor.
		if _enemy_spawner.has_method("spawn_pack_urban"):
			_enemy_spawner.spawn_pack_urban(&"pack_zombie_dog", 6, 2)
		elif _enemy_spawner.has_method("spawn_pack"):
			_enemy_spawner.spawn_pack(&"pack_zombie_dog", 6)


## Parque: el lago libera niebla e infeccion en su orilla.
func _event_lake_fog() -> void:
	var origin: Vector2 = _event_player_pos()
	var rng := _event_rng("lake_fog")
	# El evento se ancla al LAGO real del plano: las esporas salen de su orilla y
	# contaminan un sector coherente del mapa. Antes sembraba zonas alrededor del
	# jugador aunque no hubiera agua a la vista.
	var lake := MapGeometry.lake_near(_map_seed(), origin, 2)
	if lake.is_empty():
		# Sin lago en este sector: el brote sale de los senderos (la otra
		# geometria del Parque). Nunca zonas flotando en mitad de la nada.
		_announce("¡Brote en los senderos!")
		var trail := MapGeometry.nearest_trail_point(_map_seed(), origin)
		if trail.is_empty():
			return
		var trail_pos: Vector2 = trail["pos"]
		var trail_dir: Vector2 = trail["dir"]
		for i in 3:
			HAZARD_ZONE.try_spawn(get_parent(), trail_pos + trail_dir * (float(i) - 1.0) * 200.0,
				{"kind": &"infection", "radius": 80.0, "duration": 25.0, "damage_per_tick": 4})
		return
	_announce("El lago libera esporas...")
	var center: Vector2 = lake["center"]
	var radius: float = float(lake["radius"])
	# Zonas repartidas por la ORILLA, en el arco que mira hacia el jugador: el
	# sector contaminado se lee como "viene del agua".
	var toward: float = (origin - center).angle()
	for i in 3:
		var angle: float = toward + (float(i) - 1.0) * 0.7 + rng.randf_range(-0.15, 0.15)
		var pos: Vector2 = center + Vector2.RIGHT.rotated(angle) * (radius + rng.randf_range(30.0, 90.0))
		HAZARD_ZONE.try_spawn(get_parent(), pos,
			{"kind": &"infection", "radius": 80.0, "duration": 25.0, "damage_per_tick": 4})


## Parque: florecen los portadores (mas presion infecciosa).
func _event_carrier_bloom() -> void:
	_announce("¡Brote de portadores!")
	if is_instance_valid(_enemy_spawner) and _enemy_spawner.has_method("spawn_pack"):
		_enemy_spawner.spawn_pack(&"infection_carrier_dog", 3)
		_enemy_spawner.spawn_pack(&"zombie_dog", 6)


## Industrial: un tren de carga cruza la via — DAÑA A AMBOS BANDOS. Telegrafo de
## 2 s (anillos intermitentes) antes de armarse.
func _event_freight_train() -> void:
	_announce("¡¡TREN DE CARGA!! Despeja la via")
	var origin: Vector2 = _event_player_pos()
	# El tren corre por la VIA del plano (una cada 3 filas de chunks), no por una
	# linea arbitraria cerca del jugador: el peligro es predecible y aprendible.
	var rail_y: float = MapGeometry.rail_y_near(_map_seed(), origin)
	if is_nan(rail_y):
		return
	for i in 7:
		var pos := Vector2(origin.x + (float(i) - 3.0) * 150.0, rail_y)
		HAZARD_ZONE.try_spawn(get_parent(), pos,
			{"kind": &"industrial", "faction": &"both", "radius": 78.0,
			"duration": 6.0, "arm_delay": 2.0, "damage_per_tick": 10})
	Feedback.shake(0.3)


## Industrial: bocas de vapor intermitentes (zonas duales persistentes).
func _event_steam_burst() -> void:
	_announce("¡Vapor a presion! Cuidado con las valvulas")
	var origin: Vector2 = _event_player_pos()
	for i in 4:
		var pos: Vector2 = origin + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(240.0, 480.0)
		HAZARD_ZONE.try_spawn(get_parent(), pos,
			{"kind": &"industrial", "faction": &"both", "radius": 64.0,
			"duration": 30.0, "arm_delay": 1.2, "damage_per_tick": 5,
			"color": Color(0.8, 0.85, 0.9, 1.0)})


## Mapas oscuros: apagon temporal (el ambiente se oscurece de verdad).
func _event_blackout() -> void:
	_announce("¡¡APAGON!! No pierdas de vista la horda")
	for ambient in get_tree().get_nodes_in_group("ambient_controller"):
		if ambient.has_method("pulse_darkness"):
			ambient.pulse_darkness(0.35, 10.0)
	Feedback.shake(0.25)


func _announce(text: String) -> void:
	if text == "":
		return
	if _hud != null and _hud.has_method("show_announcement"):
		_hud.show_announcement(text, 2.6)
	elif _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message(text, 2.6)


func _play_event_audio() -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"event_alert")
