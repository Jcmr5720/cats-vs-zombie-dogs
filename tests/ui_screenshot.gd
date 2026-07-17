extends Node
## Herramienta de QA visual: instancia cada pantalla de menu, espera unos frames
## y guarda un PNG en user://ui_shots/. Se ejecuta con render real (NO --headless):
##   godot --path . res://tests/UIScreenshot.tscn
## No forma parte del juego; solo sirve para revisar la UI sin clics manuales.

const SCREENS: Array[Dictionary] = [
	{"name": "main_menu", "scene": "res://scenes/menus/MainMenu.tscn"},
	{"name": "story_menu", "scene": "res://scenes/menus/StoryMenu.tscn"},
	{"name": "map_select", "scene": "res://scenes/menus/MapSelectMenu.tscn"},
	{"name": "options_video", "scene": "res://scenes/menus/OptionsMenu.tscn", "tab": &"video"},
	{"name": "options_juego", "scene": "res://scenes/menus/OptionsMenu.tscn", "tab": &"juego"},
	{"name": "options_audio", "scene": "res://scenes/menus/OptionsMenu.tscn", "tab": &"audio"},
	{"name": "options_controles", "scene": "res://scenes/menus/OptionsMenu.tscn", "tab": &"controles"},
	{"name": "options_datos", "scene": "res://scenes/menus/OptionsMenu.tscn", "tab": &"datos"},
	{"name": "stats_menu", "scene": "res://scenes/menus/StatsMenu.tscn"},
	{"name": "meta_menu", "scene": "res://scenes/menus/MetaProgressionMenu.tscn"},
	{"name": "shelter_menu", "scene": "res://scenes/shelter/ShelterMenu.tscn"},
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	for entry in SCREENS:
		var packed: PackedScene = load(entry["scene"])
		if packed == null:
			print("ui_screenshot: no carga ", entry["scene"])
			continue
		var screen: Node = packed.instantiate()
		add_child(screen)
		# Pestaña concreta (opciones) si aplica.
		if entry.has("tab") and screen.has_method("_on_tab_selected"):
			await get_tree().process_frame
			screen._on_tab_selected(entry["tab"])
		for _i in 14:
			await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png("user://ui_shots/%s.png" % entry["name"])
		print("ui_screenshot: %s listo" % entry["name"])
		screen.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("ui_screenshot: FIN — %s" % ProjectSettings.globalize_path("user://ui_shots"))
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0)
