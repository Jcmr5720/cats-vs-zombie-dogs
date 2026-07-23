extends Node
## Flujo de juego fuera de partida (Fase 08). Autoload "GameFlow": guarda el mapa
## seleccionado y centraliza la navegacion entre menus y la partida, para que ninguna
## escena tenga que conocer rutas de otras. Cambia de escena de forma segura
## (despausando antes) y nunca duplica managers (SaveManager/MetaProgression son
## autoloads aparte; aqui solo vive el estado de navegacion).

const MAIN_MENU := "res://scenes/menus/MainMenu.tscn"
const MAP_SELECT := "res://scenes/menus/MapSelectMenu.tscn"
const META_MENU := "res://scenes/menus/MetaProgressionMenu.tscn"
const STATS_MENU := "res://scenes/menus/StatsMenu.tscn"
const OPTIONS_MENU := "res://scenes/menus/OptionsMenu.tscn"
const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"
const STORY_MENU := "res://scenes/menus/StoryMenu.tscn"
const STORY_CINEMATIC := "res://scenes/story/StoryCinematic.tscn"
const SHELTER_MENU := "res://scenes/shelter/ShelterMenu.tscn"

## MapData de la partida actual/seleccionada. La lee MapManager al iniciar MainLevel.
var selected_map: Resource = null

## --- Modo de juego (Fase Coop Local) ---
## "solo" (por defecto, comportamiento clasico) o "local_coop" (2 jugadores en la
## misma pantalla). Lo elige el jugador en el selector de mapas y lo leen MainLevel,
## PlayerManager, la camara, el HUD y la dificultad. NUNCA se activa en historia.
const MODE_SOLO := "solo"
const MODE_LOCAL_COOP := "local_coop"
var game_mode: String = MODE_SOLO


func is_coop() -> bool:
	return game_mode == MODE_LOCAL_COOP


func get_game_mode() -> String:
	return game_mode


func set_game_mode(mode: String) -> void:
	game_mode = MODE_LOCAL_COOP if mode == MODE_LOCAL_COOP else MODE_SOLO


## --- Regulador de dificultad de Partida libre (Coop 1.5) ---
## Tier 0-3 (Facil/Intermedio/Dificil/Extremo), analogo al de Historia. Multiplica
## presion/vida/velocidad/dano de los enemigos y la recompensa de sardinas. Se elige
## en el selector de mapas y persiste en el save. Es independiente del Nivel de Plaga
## (que sigue siendo el eje de rejugabilidad/desbloqueo).
var free_play_difficulty: int = 1


func get_free_play_difficulty() -> int:
	return clampi(free_play_difficulty, 0, 3)


func set_free_play_difficulty(tier: int) -> void:
	free_play_difficulty = clampi(tier, 0, 3)
	var save: Node = get_node_or_null("/root/SaveManager")
	if save != null and save.has_method("set_value"):
		save.set_value("free_play_difficulty", free_play_difficulty)


func _ready() -> void:
	# Carga la ultima dificultad de Partida libre elegida (SaveManager ya esta listo:
	# va antes que GameFlow en el orden de autoloads).
	var save: Node = get_node_or_null("/root/SaveManager")
	if save != null and save.has_method("get_value"):
		free_play_difficulty = clampi(int(save.get_value("free_play_difficulty", 1)), 0, 3)

## Semilla del mundo de la partida actual (estilo Minecraft): se genera nueva en cada
## start_run/restart_run y todo el mundo procedural deriva de ella. Nunca 0 (0 significa
## "sin seed" y activa el fallback determinista de WorldSeedManager).
var run_seed: int = 0

## Nivel de Plaga (1-5) de la partida actual: multiplica dificultad y sardinas.
## Se elige en el selector de mapas; ganar un nivel desbloquea el siguiente.
var plague_level: int = 1

## --- Modo Historia (Fase 09) ---
## Capitulo en curso (null = partida libre). La dificultad global (tier 0-3) se
## congela al iniciar la run para que cambiarla en el menu no desincronice nada.
var story_chapter: Resource = null
var story_tier: int = 1
## Paneles pendientes para la escena de cinematica y a donde ir al terminar.
var pending_panels: Array = []
var pending_accent: Color = Color(1.0, 0.6, 0.2)
var pending_next_scene: String = ""
## Al completar el capitulo 6 por primera vez se encola la cinematica final.
var story_ending_pending: bool = false


func get_selected_map() -> Resource:
	return selected_map


func get_plague_level() -> int:
	return clampi(plague_level, 1, 5)


func is_story_run() -> bool:
	return story_chapter != null


func get_story_chapter() -> Resource:
	return story_chapter


func get_story_tier() -> int:
	return clampi(story_tier, 0, 3)


func open_story() -> void:
	story_chapter = null
	_change_scene(STORY_MENU)


func open_shelter() -> void:
	story_chapter = null
	_change_scene(SHELTER_MENU)


## Lanza un capitulo: fija el mapa, congela la dificultad global del save y pasa
## por la cinematica de entrada (si tiene) antes del nivel.
func start_story_chapter(chapter: Resource, tier: int = -1) -> void:
	if chapter == null or chapter.map == null:
		return
	game_mode = MODE_SOLO  # el Modo Historia siempre es de un jugador
	story_chapter = chapter
	var save: Node = get_node_or_null("/root/SaveManager")
	var resolved_tier: int = tier
	if resolved_tier < 0:
		resolved_tier = int(save.get_value("story_difficulty", 1)) if save != null else 1
	story_tier = clampi(resolved_tier, 0, 3)
	if save != null and save.has_method("set_value"):
		save.set_value("story_difficulty", story_tier)
	selected_map = chapter.map
	plague_level = 1
	run_seed = _new_seed()
	if not _skip_cinematics() and not chapter.cinematic_panels.is_empty():
		play_cinematic(chapter.cinematic_panels, chapter.accent_color, MAIN_LEVEL)
	else:
		_change_scene(MAIN_LEVEL)


## Encola paneles y navega a la escena de cinematica reutilizable.
func play_cinematic(panels: Array, accent: Color, next_scene: String) -> void:
	pending_panels = panels.duplicate()
	pending_accent = accent
	pending_next_scene = next_scene
	_change_scene(STORY_CINEMATIC)


## La llama StoryCinematic al terminar/saltarse.
func on_cinematic_finished() -> void:
	var next: String = pending_next_scene if pending_next_scene != "" else MAIN_MENU
	pending_panels = []
	pending_next_scene = ""
	_change_scene(next)


## Salida de una run de historia terminada (ESC en el panel de fin de partida):
## si acaba de caer el capitulo 6 por primera vez, primero la cinematica final.
func exit_story_run() -> void:
	var chapter: Resource = story_chapter
	story_chapter = null
	if story_ending_pending and chapter != null and not chapter.ending_panels.is_empty():
		story_ending_pending = false
		play_cinematic(chapter.ending_panels, chapter.accent_color, STORY_MENU)
		return
	_change_scene(STORY_MENU)


## Semilla de la run actual. Si aun no existe (p.ej. MainLevel lanzado directo con F6),
## se genera una al vuelo para que entrar al mapa siempre produzca un mundo nuevo.
func get_run_seed() -> int:
	if run_seed == 0:
		run_seed = _new_seed()
	return run_seed


## Inicia una partida con el MapData dado (lo aplica MapManager al cargar MainLevel).
## seed_override permite rejugar/compartir una semilla concreta.
func start_run(map_data: Resource, seed_override: int = 0, plague: int = 1) -> void:
	if map_data != null:
		selected_map = map_data
	story_chapter = null  # partida libre: nunca hereda contexto de historia
	plague_level = clampi(plague, 1, 5)
	run_seed = abs(seed_override) if seed_override != 0 else _new_seed()
	_change_scene(MAIN_LEVEL)


## Reinicia la partida actual con el mismo mapa (R desde el fin de partida).
## Por defecto genera mundo nuevo; con new_seed=false repite la misma semilla.
func restart_run(new_seed: bool = true) -> void:
	if new_seed or run_seed == 0:
		run_seed = _new_seed()
	_change_scene(MAIN_LEVEL)


func _new_seed() -> int:
	# Tests/repro (FASE 11): RUN_SEED en el entorno fija la semilla de la run
	# (mundo + guion procedural identicos, estilo "compartir semilla").
	if OS.has_environment("RUN_SEED"):
		return maxi(1, abs(int(OS.get_environment("RUN_SEED"))))
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("%d:%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]))
	# Rango legible para mostrar/compartir (9 digitos), nunca 0.
	return rng.randi_range(100_000_000, 999_999_999)


func _skip_cinematics() -> bool:
	var settings: Node = get_node_or_null("/root/Settings")
	return settings != null and settings.has_method("get_value") and bool(settings.get_value("skip_cinematics", false))


func return_to_main_menu() -> void:
	story_chapter = null
	_change_scene(MAIN_MENU)


func open_map_select() -> void:
	_change_scene(MAP_SELECT)


func open_meta_progression() -> void:
	_change_scene(META_MENU)


func open_stats() -> void:
	_change_scene(STATS_MENU)


func open_options() -> void:
	_change_scene(OPTIONS_MENU)


func quit_game() -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		if audio.has_method("shutdown"):
			audio.shutdown()
		elif audio.has_method("reset_for_scene_change"):
			audio.reset_for_scene_change()
	get_tree().quit()


func _change_scene(path: String) -> void:
	# Despausar antes de cambiar para no arrastrar el estado de pausa de la partida.
	if get_tree() != null:
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio != null:
			if audio.has_method("reset_for_scene_change"):
				audio.reset_for_scene_change()
			if audio.has_method("play_music"):
				var music_name: StringName = &"menu"
				if path == MAIN_LEVEL:
					music_name = &"gameplay"
				elif path == SHELTER_MENU:
					music_name = &"shelter"
				audio.play_music(music_name)
		get_tree().paused = false
		get_tree().change_scene_to_file(path)
