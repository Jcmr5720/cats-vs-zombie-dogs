extends Node2D
## Controla la aparicion de gatos rescatables y alimenta el HUD/indicador.

const CompanionData = preload("res://scripts/companions/companion_data.gd")

@export var player_path: NodePath
@export var companion_manager_path: NodePath
@export var hud_path: NodePath
@export var rescue_point_scene: PackedScene
@export var companion_pool: Array[CompanionData] = []

@export_group("Ventanas de spawn")
@export var first_spawn_min: float = 25.0
@export var first_spawn_max: float = 35.0
@export var second_spawn_min: float = 75.0
@export var second_spawn_max: float = 95.0
@export var third_spawn_min: float = 140.0
@export var third_spawn_max: float = 170.0
@export var repeat_spawn_min: float = 90.0
@export var repeat_spawn_max: float = 120.0

@export_group("Posicionamiento")
@export var min_spawn_distance: float = 340.0
@export var max_spawn_distance: float = 520.0
@export var safe_enemy_radius: float = 130.0

var _player: Node2D
var _companion_manager: Node
var _hud: Node
var _elapsed_time: float = 0.0
var _next_spawn_time: float = 0.0
var _spawned_points: int = 0
var _active_point: Node2D

# --- Modificadores de mapa (Fase 06): los fija MapManager.set_map_modifiers. ---
## <1 = rescates mas frecuentes, >1 = menos frecuentes.
var _interval_mult: float = 1.0
## Distancia extra de aparicion (mapas peligrosos).
var _distance_bonus: float = 0.0


## Ajusta la frecuencia y distancia de los rescates segun el mapa activo.
func set_map_modifiers(interval_mult: float, distance_bonus: float) -> void:
	_interval_mult = max(0.2, interval_mult)
	_distance_bonus = max(0.0, distance_bonus)


## Reduccion del tiempo del PRIMER rescate por "Llamado de la Colonia" (Fase 07.5).
var _first_rescue_seconds_reduction: float = 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_companion_manager = get_node_or_null(companion_manager_path)
	_hud = get_node_or_null(hud_path)
	# Mejoras permanentes y Refugio SOLO en Modo Historia (Partida libre = reto puro).
	if _is_story_run():
		var mp: Node = get_node_or_null("/root/MetaProgression")
		if mp != null and mp.has_method("first_rescue_seconds_reduction"):
			_first_rescue_seconds_reduction = float(mp.first_rescue_seconds_reduction())
		# Refugio Felino (Fase 10): Radio de Maullidos (primer rescate antes; el piso
		# de 15 s ya lo garantiza _schedule_next_spawn) y Mapa de Refugios (mas cerca).
		var shelter: Node = get_node_or_null("/root/Shelter")
		if shelter != null and shelter.has_method("get_bonuses"):
			var bonuses: Dictionary = shelter.get_bonuses()
			_first_rescue_seconds_reduction += float(bonuses.get("rescue_first_spawn_reduction", 0.0))
			var closer: float = clampf(float(bonuses.get("rescue_distance_modifier", 0.0)), 0.0, 0.15)
			if closer > 0.0:
				min_spawn_distance = maxf(220.0, min_spawn_distance * (1.0 - closer))
				max_spawn_distance = maxf(min_spawn_distance + 60.0, max_spawn_distance * (1.0 - closer))
	_schedule_next_spawn()


## True solo en Modo Historia (donde aplican mejoras permanentes y Refugio).
func _is_story_run() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_story_run") and gf.is_story_run()


func _process(delta: float) -> void:
	_elapsed_time += delta
	_update_hud_tracking()
	if is_instance_valid(_active_point):
		return
	if not is_instance_valid(_companion_manager) or not _companion_manager.has_method("can_add_companion"):
		return
	if not _companion_manager.can_add_companion():
		_set_rescue_notice(false)
		return
	if _elapsed_time >= _next_spawn_time:
		_spawn_rescue_point()


func _spawn_rescue_point() -> void:
	if rescue_point_scene == null or companion_pool.is_empty():
		return
	if not is_instance_valid(_player):
		_player = get_node_or_null(player_path)
		if not is_instance_valid(_player):
			return

	var point := rescue_point_scene.instantiate() as Node2D
	if point == null:
		return
	var data: CompanionData = _pick_companion_data()
	point.global_position = _find_spawn_position()
	point.call("setup", data)
	point.connect("rescue_completed", Callable(self, "_on_rescue_completed"))
	point.connect("rescue_progress_started", Callable(self, "_on_rescue_progress_started"))
	point.connect("rescue_progress_cancelled", Callable(self, "_on_rescue_progress_cancelled"))
	get_parent().add_child(point)
	_active_point = point
	_spawned_points += 1

	_set_rescue_notice(true)
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("Gato cercano")


func _on_rescue_completed(data: CompanionData) -> void:
	if is_instance_valid(_companion_manager) and _companion_manager.has_method("rescue_companion"):
		_companion_manager.rescue_companion(data)
	_active_point = null
	_set_rescue_notice(false)
	_schedule_next_spawn()


func _on_rescue_progress_started() -> void:
	if _hud != null and _hud.has_method("set_rescue_status"):
		_hud.set_rescue_status("Rescatando...", true)


func _on_rescue_progress_cancelled() -> void:
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("Rescate cancelado", 1.6)
	_set_rescue_notice(true)


func _schedule_next_spawn() -> void:
	match _spawned_points:
		0:
			_next_spawn_time = max(15.0, randf_range(first_spawn_min, first_spawn_max) * _interval_mult - _first_rescue_seconds_reduction)
		1:
			_next_spawn_time = randf_range(second_spawn_min, second_spawn_max) * _interval_mult
		2:
			_next_spawn_time = randf_range(third_spawn_min, third_spawn_max) * _interval_mult
		_:
			_next_spawn_time = _elapsed_time + randf_range(repeat_spawn_min, repeat_spawn_max) * _interval_mult


func _find_spawn_position() -> Vector2:
	var min_dist: float = min_spawn_distance + _distance_bonus
	var max_dist: float = max_spawn_distance + _distance_bonus
	var fallback: Vector2 = _player.global_position + Vector2.RIGHT.rotated(randf() * TAU) * min_dist
	for _attempt in 10:
		var angle: float = randf() * TAU
		var distance: float = randf_range(min_dist, max_dist)
		var candidate: Vector2 = _player.global_position + Vector2.RIGHT.rotated(angle) * distance
		if _is_safe_from_enemies(candidate) and _is_clear_of_obstacles(candidate):
			return candidate
	return fallback


## Evita que un rescate aparezca encima o pegado a un obstaculo (quedaria encerrado).
func _is_clear_of_obstacles(candidate: Vector2) -> bool:
	for o in get_tree().get_nodes_in_group("obstacles"):
		if not is_instance_valid(o) or not (o is Node2D):
			continue
		var radius: float = 40.0
		if o.has_method("get_block_radius"):
			radius = float(o.get_block_radius())
		if candidate.distance_to((o as Node2D).global_position) < radius + 70.0:
			return false
	return true


func _is_safe_from_enemies(candidate: Vector2) -> bool:
	var safe_radius_sq: float = safe_enemy_radius * safe_enemy_radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if candidate.distance_squared_to(enemy.global_position) < safe_radius_sq:
			return false
	return true


func _pick_companion_data() -> CompanionData:
	var total_weight: float = 0.0
	for data in companion_pool:
		if data != null:
			total_weight += max(0.01, data.spawn_weight)
	var roll: float = randf() * total_weight
	for data in companion_pool:
		if data == null:
			continue
		roll -= max(0.01, data.spawn_weight)
		if roll <= 0.0:
			return data
	return companion_pool[0]


func _set_rescue_notice(active: bool) -> void:
	if _hud == null:
		return
	if _hud.has_method("set_rescue_status"):
		_hud.set_rescue_status("Rescate disponible" if active else "", active)
	if _hud.has_method("set_rescue_target"):
		var target_position: Vector2 = _active_point.global_position if active and is_instance_valid(_active_point) else Vector2.ZERO
		_hud.set_rescue_target(active, target_position)


func _update_hud_tracking() -> void:
	if _hud != null and _hud.has_method("set_rescue_target"):
		if is_instance_valid(_active_point):
			_hud.set_rescue_target(true, _active_point.global_position)
		else:
			_hud.set_rescue_target(false, Vector2.ZERO)
