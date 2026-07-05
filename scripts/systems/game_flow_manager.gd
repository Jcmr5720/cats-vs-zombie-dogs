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
func start_story_chapter(chapter: Resource) -> void:
	if chapter == null or chapter.map == null:
		return
	story_chapter = chapter
	var save: Node = get_node_or_null("/root/SaveManager")
	story_tier = clampi(int(save.get_value("story_difficulty", 1)) if save != null else 1, 0, 3)
	selected_map = chapter.map
	plague_level = 1
	run_seed = _new_seed()
	if not chapter.cinematic_panels.is_empty():
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
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("%d:%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]))
	# Rango legible para mostrar/compartir (9 digitos), nunca 0.
	return rng.randi_range(100_000_000, 999_999_999)


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
