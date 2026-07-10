extends Node
## Orquesta el mapa/bioma activo (Fase 06). Carga un MapData y lo reparte a los
## sistemas: pinta el fondo y la decoracion, pasa modificadores al EnemySpawner y al
## RescueSpawner, fija los tiempos de eventos del WaveEventManager y el jefe del
## BossSpawner, muestra nombre/objetivo en el HUD y controla la condicion de victoria.
##
## Cambio de mapa para pruebas (F1/F2/F3): guarda el indice elegido en una static var
## que sobrevive al reload de escena y reinicia la partida en el mapa nuevo, de modo
## que todo (decoracion, objetivos, eventos, jefes) queda limpio sin codigo extra.

const MapData = preload("res://scripts/maps/map_data.gd")
const WorldSeedManager = preload("res://scripts/maps/world_seed_manager.gd")
const RunSummary = preload("res://scripts/systems/run_summary.gd")
const StoryCampaign = preload("res://scripts/story/story_campaign.gd")
const FreePlayScore = preload("res://scripts/systems/free_play_score.gd")

## Mapa que se desbloquea al asegurar cada zona (progresion simple, Fase 07).
const NEXT_MAP_UNLOCK: Dictionary = {
	&"neighborhood": &"park",
	&"park": &"industrial_alley",
}

## Indice de mapa elegido por debug; persiste entre reinicios de escena.
static var _selected_map_index: int = -1

@export var current_map_data: MapData
## Mapas seleccionables con F1/F2/F3 (en orden).
@export var map_pool: Array[MapData] = []

@export var background_grid_path: NodePath
@export var decoration_path: NodePath
@export var hud_path: NodePath
@export var player_path: NodePath
@export var enemy_spawner_path: NodePath
@export var rescue_spawner_path: NodePath
@export var wave_event_manager_path: NodePath
@export var boss_spawner_path: NodePath
@export var companion_manager_path: NodePath
@export var obstacle_spawner_path: NodePath

@export_group("Balance coop (Fase Coop 1.5)")
## Multiplicadores aplicados a los enemigos en coop local (partida libre).
@export var coop_pressure_multiplier: float = 1.25
@export var coop_enemy_health_multiplier: float = 1.45
@export var coop_enemy_damage_multiplier: float = 1.15

var _map: MapData
## Semilla efectiva del mundo de esta run (de GameFlow o fallback determinista).
var _world_seed: int = 0
var _grid: Node
var _decoration: Node
var _hud: Node
var _enemy_spawner: Node
var _rescue_spawner: Node
var _wave_event_manager: Node
var _boss_spawner: Node
var _companion_manager: Node
var _obstacle_spawner: Node

var _elapsed: float = 0.0
var _bosses_defeated: int = 0
var _minibosses_defeated: int = 0
var _victory_active: bool = false
## La partida ya termino (victoria o derrota): habilita R/M y bloquea re-disparos.
var _run_ended: bool = false
var _run_rewards_claimed: bool = false


func _ready() -> void:
	add_to_group("map_manager")
	process_mode = Node.PROCESS_MODE_ALWAYS  # para capturar R aun en pausa de victoria
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_music"):
		audio.play_music(&"gameplay")
	_grid = get_node_or_null(background_grid_path)
	_decoration = get_node_or_null(decoration_path)
	_hud = get_node_or_null(hud_path)
	_enemy_spawner = get_node_or_null(enemy_spawner_path)
	_rescue_spawner = get_node_or_null(rescue_spawner_path)
	_wave_event_manager = get_node_or_null(wave_event_manager_path)
	_boss_spawner = get_node_or_null(boss_spawner_path)
	_companion_manager = get_node_or_null(companion_manager_path)
	_obstacle_spawner = get_node_or_null(obstacle_spawner_path)

	_map = _resolve_active_map()
	_connect_objective_signals()
	# Se aplica diferido para que todos los sistemas hayan corrido su _ready.
	call_deferred("_apply_active_map")


func _resolve_active_map() -> MapData:
	# 1) Mapa elegido desde el menu (Fase 08).
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf != null and gf.has_method("get_selected_map"):
		var selected = gf.get_selected_map()
		if selected != null:
			return selected
	# 2) Selector debug F1/F2/F3 (persiste en static).
	if _selected_map_index >= 0 and _selected_map_index < map_pool.size():
		return map_pool[_selected_map_index]
	# 3) Fallback para probar MainLevel directo (F6).
	return current_map_data


func is_run_ended() -> bool:
	return _run_ended


func get_world_seed() -> int:
	return _world_seed


func _resolve_world_seed() -> int:
	# Seed de la run (nueva por partida, estilo Minecraft) via GameFlow.
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf != null and gf.has_method("get_run_seed"):
		var s: int = int(gf.get_run_seed())
		if s != 0:
			return s
	# Fallback determinista (tests/headless sin GameFlow).
	return WorldSeedManager.resolve_seed(_map)


func _apply_active_map() -> void:
	if _map == null:
		return
	_world_seed = _resolve_world_seed()
	_apply_visuals()
	_apply_obstacles()
	_apply_spawner_modifiers()
	_apply_rescue_modifiers()
	_apply_event_schedule()
	_update_hud_objective()


## Genera los obstaculos del mapa alrededor del punto de inicio del jugador.
func _apply_obstacles() -> void:
	if not is_instance_valid(_obstacle_spawner) or not _obstacle_spawner.has_method("generate"):
		return
	var player: Node = get_node_or_null(player_path)
	var origin: Vector2 = (player as Node2D).global_position if is_instance_valid(player) and player is Node2D else Vector2.ZERO
	_obstacle_spawner.set("world_seed", _world_seed)
	_obstacle_spawner.generate(_map, origin)


# --- Aplicacion del mapa -----------------------------------------------------

func _apply_visuals() -> void:
	# Fondo de cuadricula: base + lineas derivadas del grid_color.
	if is_instance_valid(_grid):
		_grid.set("world_seed", _world_seed)
		_grid.set("base_color", _map.background_color)
		_grid.set("secondary_color", _map.secondary_color)
		_grid.set("line_color", _map.grid_color.darkened(0.15))
		_grid.set("major_line_color", _map.grid_color)
		_grid.set("dot_color", _map.grid_color.lightened(0.15))
		_grid.set("accent_color", _map.accent_color)
		_grid.set("hazard_color", _map.hazard_color)
		_grid.set("pattern_type", _map.pattern_type)
		_grid.set("pattern_strength", _map.pattern_strength)
		_grid.set("road_line_enabled", _map.road_line_enabled)
		_grid.set("hazard_line_enabled", _map.hazard_line_enabled)
	if is_instance_valid(_decoration) and _decoration.has_method("configure"):
		_decoration.set("world_seed", _world_seed)
		_decoration.configure(_map)
	# FASE VISUAL 2: ambiente global (CanvasModulate + niebla) y vignette de camara.
	# Se buscan por grupo para no acoplar rutas; si no existen, no pasa nada.
	for ambient in get_tree().get_nodes_in_group("ambient_controller"):
		if ambient.has_method("configure"):
			ambient.configure(_map)
	for overlay in get_tree().get_nodes_in_group("camera_overlay"):
		if overlay.has_method("configure"):
			overlay.configure(_map)


func _apply_spawner_modifiers() -> void:
	if not is_instance_valid(_enemy_spawner) or not _enemy_spawner.has_method("set_map_modifiers"):
		return
	if _is_story_run():
		# Modo Historia: la dificultad global (Facil..Extremo) sustituye a la Plaga.
		var tier: Dictionary = StoryCampaign.get_difficulty(_story_tier())
		_enemy_spawner.set_map_modifiers(
			_map.difficulty_modifier * float(tier["pressure"]),
			_map.runner_probability_modifier,
			_map.enemy_health_modifier * float(tier["health"]),
			_map.enemy_speed_modifier * float(tier["speed"]),
			float(tier["damage"])
		)
		return
	# Partida libre: Nivel de Plaga (1-5) suma presion, vida y algo de velocidad.
	var plague: int = _plague_level()
	var plague_pressure: float = 1.0 + 0.35 * float(plague - 1)
	var plague_health: float = 1.0 + 0.15 * float(plague - 1)
	var plague_speed: float = 1.0 + 0.05 * float(plague - 1)
	# Coop local (Fase Coop 1.5): mas vida/dano/presion para compensar 2 jugadores.
	var coop: bool = _is_coop()
	var coop_pressure: float = coop_pressure_multiplier if coop else 1.0
	var coop_health: float = coop_enemy_health_multiplier if coop else 1.0
	var coop_damage: float = coop_enemy_damage_multiplier if coop else 1.0
	# Regulador de dificultad de Partida libre (Coop 1.5): Facil..Extremo, como Historia.
	var diff: Dictionary = StoryCampaign.get_difficulty(_free_play_difficulty())
	_enemy_spawner.set_map_modifiers(
		_map.difficulty_modifier * plague_pressure * coop_pressure * float(diff["pressure"]),
		_map.runner_probability_modifier,
		_map.enemy_health_modifier * plague_health * coop_health * float(diff["health"]),
		_map.enemy_speed_modifier * plague_speed * float(diff["speed"]),
		coop_damage * float(diff["damage"])
	)


## Nivel de Plaga de la run actual (1 si no hay GameFlow, p.ej. F6 directo).
func _plague_level() -> int:
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf != null and gf.has_method("get_plague_level"):
		return int(gf.get_plague_level())
	return 1


# --- Modo Historia (Fase 09) ---------------------------------------------------

func _game_flow() -> Node:
	return get_node_or_null("/root/GameFlow")


func _is_story_run() -> bool:
	var gf: Node = _game_flow()
	return gf != null and gf.has_method("is_story_run") and gf.is_story_run()


func _is_coop() -> bool:
	var gf: Node = _game_flow()
	return gf != null and gf.has_method("is_coop") and gf.is_coop()


func _free_play_difficulty() -> int:
	var gf: Node = _game_flow()
	return int(gf.get_free_play_difficulty()) if gf != null and gf.has_method("get_free_play_difficulty") else 1


func _story_chapter() -> Resource:
	var gf: Node = _game_flow()
	return gf.get_story_chapter() if gf != null and gf.has_method("get_story_chapter") else null


func _story_tier() -> int:
	var gf: Node = _game_flow()
	return int(gf.get_story_tier()) if gf != null and gf.has_method("get_story_tier") else 1


func _apply_rescue_modifiers() -> void:
	if is_instance_valid(_rescue_spawner) and _rescue_spawner.has_method("set_map_modifiers"):
		_rescue_spawner.set_map_modifiers(_map.rescue_spawn_modifier, _map.rescue_distance_bonus)


func _apply_event_schedule() -> void:
	if is_instance_valid(_wave_event_manager) and _wave_event_manager.has_method("apply_map_schedule"):
		_wave_event_manager.apply_map_schedule(_map.boss_spawn_time, _map.miniboss_times)
	# Jefe especifico del mapa (si lo define).
	if is_instance_valid(_boss_spawner) and _map.boss_data != null:
		_boss_spawner.set("default_boss_data", _map.boss_data)


# --- Objetivos y victoria ----------------------------------------------------

func _connect_objective_signals() -> void:
	if is_instance_valid(_boss_spawner):
		if _boss_spawner.has_signal("boss_defeated"):
			_boss_spawner.connect("boss_defeated", Callable(self, "_on_boss_defeated"))
		if _boss_spawner.has_signal("miniboss_defeated"):
			_boss_spawner.connect("miniboss_defeated", Callable(self, "_on_miniboss_defeated"))
	if is_instance_valid(_companion_manager) and _companion_manager.has_signal("companion_rescued"):
		_companion_manager.connect("companion_rescued", Callable(self, "_on_companion_rescued"))
	# Derrota: el fin de partida tambien lo orquesta el MapManager (Fase 07).
	var player: Node = get_node_or_null(player_path)
	if is_instance_valid(player) and player.has_signal("died"):
		player.died.connect(_on_player_defeated)


func _on_boss_defeated(_data) -> void:
	_bosses_defeated += 1
	_show_objective_event("Jefe derrotado")
	_update_hud_objective()


func _on_miniboss_defeated(_data) -> void:
	_minibosses_defeated += 1
	_show_objective_event("Mini-jefe derrotado %d/%d" % [_minibosses_defeated, max(1, _map.defeat_minibosses_required)])
	_update_hud_objective()


func _on_companion_rescued(_data) -> void:
	if _map != null and _map.rescue_cats_required > 0:
		_show_objective_event("Gato rescatado %d/%d" % [_cats_rescued(), _map.rescue_cats_required])
	var missions: Node = get_node_or_null("/root/Missions")
	if missions != null:
		missions.add(&"cats_rescued")
	_update_hud_objective()


func _process(delta: float) -> void:
	if _run_ended or _map == null:
		return
	if get_tree().paused:
		return
	_elapsed += delta
	_update_hud_objective()
	if _objectives_complete():
		_trigger_victory()


func _cats_rescued() -> int:
	if is_instance_valid(_companion_manager) and _companion_manager.has_method("get_companion_count"):
		return int(_companion_manager.get_companion_count())
	return 0


func _objectives_complete() -> bool:
	if _map.survive_seconds > 0.0 and _elapsed < _map.survive_seconds:
		return false
	if _map.require_defeat_boss and _bosses_defeated <= 0:
		return false
	if _map.rescue_cats_required > 0 and _cats_rescued() < _map.rescue_cats_required:
		return false
	if _map.defeat_minibosses_required > 0 and _minibosses_defeated < _map.defeat_minibosses_required:
		return false
	return true


func _trigger_victory() -> void:
	if _run_ended:
		return
	_victory_active = true
	_finish_run(true)


func _on_player_defeated() -> void:
	if _run_ended:
		return
	_finish_run(false)


## Fin de partida unificado (Fase 07): construye el resumen, calcula y registra las
## Sardinas, desbloquea el siguiente mapa si fue victoria, pausa y muestra el panel.
func _finish_run(victory: bool) -> void:
	if _run_ended:
		return
	_run_ended = true
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		if audio.has_method("play_sfx"):
			audio.play_sfx(&"victory" if victory else &"defeat")
		if audio.has_method("play_music"):
			audio.play_music(&"gameplay")

	var summary := _build_run_summary(victory)
	var meta: Node = get_node_or_null("/root/MetaProgression")
	var save: Node = get_node_or_null("/root/SaveManager")

	var dict: Dictionary = summary.to_dict()
	var earned: int = 0
	var breakdown: Dictionary = {}
	var plague: int = _plague_level()

	if _is_story_run():
		# --- HISTORIA: economia de Sardinas (mejoras permanentes + Refugio) ---
		if meta != null and meta.has_method("compute_sardine_breakdown"):
			breakdown = meta.compute_sardine_breakdown(dict)
			earned = int(breakdown.get("total", 0))
		elif meta != null and meta.has_method("compute_sardines"):
			earned = int(meta.compute_sardines(dict))
		# Refugio Felino: Almacen de Sardinas (+% sobre lo ganado). Solo colocados.
		var shelter: Node = get_node_or_null("/root/Shelter")
		if shelter != null and shelter.has_method("get_bonus") and earned > 0:
			var shelter_pct: float = float(shelter.get_bonus("sardines_reward_bonus"))
			if shelter_pct > 0.0:
				var shelter_bonus: int = int(round(earned * shelter_pct))
				earned += shelter_bonus
				if not breakdown.is_empty():
					breakdown["refugio"] = shelter_bonus
					breakdown["total"] = earned
		# Historia con victoria: multiplicador de dificultad + first-clear por tier.
		# En derrota no se aplica el mult (evita farmear derrotas en Extremo).
		if victory:
			var tier_index: int = _story_tier()
			var tier: Dictionary = StoryCampaign.get_difficulty(tier_index)
			var reward_mult: float = float(tier["reward"])
			if earned > 0 and reward_mult != 1.0:
				var diff_bonus: int = int(round(earned * reward_mult)) - earned
				earned += diff_bonus
				if not breakdown.is_empty():
					breakdown["dificultad"] = diff_bonus
			var chapter: Resource = _story_chapter()
			if chapter != null and save != null:
				var key: String = StoryCampaign.clear_key(chapter.id, tier_index)
				if not bool(save.get_value(key, false)):
					var clear_bonus: int = int(round(chapter.first_clear_reward * reward_mult))
					earned += clear_bonus
					if not breakdown.is_empty():
						breakdown["historia"] = clear_bonus
					save.set_value(key, true, false)
				# Progreso de campaña: capitulo mas alto completado.
				var cleared: int = int(save.get_value("story_chapters_cleared", 0))
				if chapter.number > cleared:
					save.set_value("story_chapters_cleared", chapter.number, false)
					# Primer clear del capitulo final: encolar la cinematica de cierre.
					if chapter.number == StoryCampaign.TOTAL_CHAPTERS:
						var gf: Node = _game_flow()
						if gf != null:
							gf.story_ending_pending = true
			if not breakdown.is_empty():
				breakdown["total"] = earned
		summary.sardines_earned = earned
		summary.sardine_breakdown = breakdown
	else:
		# --- PARTIDA LIBRE: sin Sardinas. Puntuacion arcade + record local ---
		# El reto es puro (sin bonos de mejoras/refugio); la motivacion es superar
		# tu propio record (o el de un amigo) en el mismo mapa y dificultad.
		summary.sardines_earned = 0
		summary.sardine_breakdown = {}
		var fp_tier: int = _free_play_difficulty()
		var result: Dictionary = FreePlayScore.compute(dict, fp_tier, plague)
		summary.score = int(result["total"])
		summary.score_breakdown = result["breakdown"]
		var prev_best: int = FreePlayScore.get_best(save, _map.id, fp_tier)
		summary.best_score = maxi(prev_best, summary.score)
		summary.is_new_record = save != null and summary.score > prev_best
		if summary.is_new_record and save != null and save.has_method("set_value"):
			save.set_value(FreePlayScore.record_key(_map.id, fp_tier), summary.score)

	dict = summary.to_dict()

	# Misiones persistentes: victorias, mayor Plaga y progreso de la campaña.
	var missions: Node = get_node_or_null("/root/Missions")
	if missions != null and victory:
		missions.add(&"victories")
		if _is_story_run():
			var mission_chapter: Resource = _story_chapter()
			if mission_chapter != null:
				missions.report_peak(&"story_chapter_peak", mission_chapter.number)
			if _story_tier() >= 3:
				missions.report_peak(&"story_extreme", 1)
		else:
			missions.report_peak(&"plague_peak", plague)

	if save != null and not _run_rewards_claimed:
		_run_rewards_claimed = true
		save.record_run(_map.id, victory, _elapsed, earned, dict)
		if victory and not _is_story_run():
			# Desbloqueos de partida libre (mapas y plagas): no aplican en historia.
			var next_map: StringName = NEXT_MAP_UNLOCK.get(_map.id, &"")
			if next_map != &"":
				save.unlock_map(next_map)
			if save.has_method("get_value") and save.has_method("set_value"):
				var unlocked: int = int(save.get_value("plague_unlocked_%s" % _map.id, 1))
				if plague >= unlocked and plague < 5:
					save.set_value("plague_unlocked_%s" % _map.id, plague + 1)
			save.save()
		elif victory:
			save.save()
		summary.sardines_total_after = int(save.get_sardines())
		dict = summary.to_dict()

	get_tree().paused = true
	if _hud != null and _hud.has_method("show_run_end"):
		_hud.show_run_end(dict)


func _build_run_summary(victory: bool) -> RunSummary:
	var summary := RunSummary.new()
	summary.map_id = _map.id
	summary.map_name = _map.display_name
	summary.victory = victory
	summary.victory_message = _map.victory_message if victory else (_map.game_over_message if _map.game_over_message != "" else "COLONIA PERDIDA")
	summary.time_survived = _elapsed
	summary.enemies_killed = _get_kills()
	summary.cats_rescued = _cats_rescued()
	summary.active_companions = _active_companions()
	summary.downed_companions = _downed_companions()
	summary.level_reached = _get_player_level()
	summary.weapons_used = _get_weapon_count()
	summary.weapons_levels = _get_total_weapon_levels()
	summary.mini_bosses_defeated = _minibosses_defeated
	summary.bosses_defeated = _bosses_defeated
	summary.world_seed = _world_seed
	return summary


# --- HUD ---------------------------------------------------------------------

func _update_hud_objective() -> void:
	if _hud == null:
		return
	if _hud.has_method("set_map_name"):
		_hud.set_map_name(_map.display_name)
	if _hud.has_method("set_objective_text"):
		# HUD minimalista: objetivo corto (la pausa muestra el progreso completo).
		# Historia: "Cap. N"; partida libre con Plaga > 1: "☠ Plaga N".
		var prefix: String = ""
		if _is_story_run():
			var chapter: Resource = _story_chapter()
			var skull: String = "☠ " if _story_tier() >= 3 else ""
			prefix = "%sCap. %d · " % [skull, chapter.number if chapter != null else 0]
		else:
			var plague: int = _plague_level()
			if plague > 1:
				prefix = "☠ Plaga %d · " % plague
		_hud.set_objective_text(prefix + _objective_short())
	if _hud.has_method("set_game_over_title"):
		_hud.set_game_over_title(_map.game_over_message)


## Construye el texto del objetivo con el progreso actual.
func _objective_text() -> String:
	var lines: Array[String] = []
	lines.append("Objetivo: %s" % _objective_title())
	if _map.survive_seconds > 0.0:
		lines.append("Tiempo: %s / %s" % [_format_time(min(_elapsed, _map.survive_seconds)), _format_time(_map.survive_seconds)])
	if _map.require_defeat_boss:
		lines.append("Jefe: %s" % ("Derrotado" if _bosses_defeated > 0 else "Pendiente"))
	if _map.rescue_cats_required > 0:
		lines.append("Gatos: %d / %d" % [_cats_rescued(), _map.rescue_cats_required])
	if _map.defeat_minibosses_required > 0:
		lines.append("Mini-jefes: %d / %d" % [_minibosses_defeated, _map.defeat_minibosses_required])
	return "\n".join(lines)


## Objetivo corto para el HUD (max ~4 palabras).
func _objective_short() -> String:
	if _map.require_defeat_boss:
		return "Derrota al jefe"
	if _map.rescue_cats_required > 0:
		return "Rescata %d gatos" % _map.rescue_cats_required
	if _map.defeat_minibosses_required > 0:
		return "Derrota mini-jefes"
	return "Sobrevive"


func _objective_title() -> String:
	if _map.objective_description != "":
		return _map.objective_description
	if _map.require_defeat_boss:
		return "Sobrevive y derrota al jefe"
	if _map.rescue_cats_required > 0:
		return "Rescata gatos y sobrevive"
	if _map.defeat_minibosses_required > 0:
		return "Derrota mini-jefes"
	return "Sobrevive hasta asegurar la zona"


func _show_objective_event(text: String) -> void:
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message(text)


func _format_time(seconds: float) -> String:
	var total: int = int(ceil(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


# --- Cambio de mapa (debug F1/F2/F3) ----------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Tras terminar la partida: R reinicia, M abre/cierra el panel de mejoras.
	if _run_ended:
		if event.is_action_pressed("restart"):
			var audio_r: Node = get_node_or_null("/root/AudioManager")
			if audio_r != null and audio_r.has_method("reset_for_scene_change"):
				audio_r.reset_for_scene_change()
			# R reinicia el MISMO mapa (vuelve a cargar MainLevel via GameFlow).
			var gf_r: Node = get_node_or_null("/root/GameFlow")
			if gf_r != null and gf_r.has_method("restart_run"):
				gf_r.restart_run()
			else:
				get_tree().paused = false
				get_tree().reload_current_scene()
			return
		if event.is_action_pressed("ui_cancel"):
			# ESC tras terminar: en historia vuelve a la pantalla de Historia (con
			# cinematica final si acaba de caer el capitulo 6); si no, al menu.
			var gf: Node = get_node_or_null("/root/GameFlow")
			if gf != null and gf.has_method("is_story_run") and gf.is_story_run():
				get_tree().paused = false
				gf.exit_story_run()
			elif gf != null and gf.has_method("return_to_main_menu"):
				gf.return_to_main_menu()
			return
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
			if _hud != null and _hud.has_method("toggle_meta_panel"):
				_hud.toggle_meta_panel()
			return

	if event is InputEventKey and event.pressed and not event.echo:
		# Selector de mapa por debug (F1/F2/F3): respeta el desbloqueo guardado.
		var index: int = -1
		match event.keycode:
			KEY_F1:
				index = 0
			KEY_F2:
				index = 1
			KEY_F3:
				index = 2
		if index >= 0 and index < map_pool.size():
			var target: MapData = map_pool[index]
			var save: Node = get_node_or_null("/root/SaveManager")
			if save != null and save.has_method("is_map_unlocked") and not save.is_map_unlocked(target.id):
				var audio: Node = get_node_or_null("/root/AudioManager")
				if audio != null and audio.has_method("play_ui"):
					audio.play_ui(&"ui_error")
				if _hud != null and _hud.has_method("show_event_message"):
					_hud.show_event_message("Zona bloqueada", 1.6)
				return
			_selected_map_index = index
			get_tree().paused = false
			get_tree().reload_current_scene()


# --- Getters auxiliares ------------------------------------------------------

func _get_kills() -> int:
	if is_instance_valid(_enemy_spawner) and _enemy_spawner.has_method("get_kills"):
		return int(_enemy_spawner.get_kills())
	return 0


func _get_weapon_count() -> int:
	var player: Node = get_node_or_null(player_path)
	if is_instance_valid(player) and player.has_method("get_weapon_manager"):
		var wm = player.get_weapon_manager()
		if wm != null and wm.has_method("get_weapon_count"):
			return int(wm.get_weapon_count())
	return 0


func _active_companions() -> int:
	if is_instance_valid(_companion_manager) and _companion_manager.has_method("get_active_companion_count"):
		return int(_companion_manager.get_active_companion_count())
	return 0


func _downed_companions() -> int:
	if is_instance_valid(_companion_manager) and _companion_manager.has_method("get_downed_companion_count"):
		return int(_companion_manager.get_downed_companion_count())
	return 0


func _get_total_weapon_levels() -> int:
	var player: Node = get_node_or_null(player_path)
	if is_instance_valid(player) and player.has_method("get_weapon_manager"):
		var wm = player.get_weapon_manager()
		if wm != null and wm.has_method("get_total_weapon_levels"):
			return int(wm.get_total_weapon_levels())
	return 0


func _get_player_level() -> int:
	var player: Node = get_node_or_null(player_path)
	if is_instance_valid(player):
		return int(player.get("level"))
	return 1
