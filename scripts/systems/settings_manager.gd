extends Node
## Opciones del juego (Fase 08). Autoload "Settings": carga/guarda en un archivo
## propio (user://cats_vs_zombie_dogs_settings.json) y aplica los ajustes globales:
## pantalla completa, screen shake (on/off + intensidad), numeros de dano, FPS
## y volumen de audio.
##
## Mantiene su propio overlay de FPS (CanvasLayer) para que funcione en cualquier
## escena sin tocar cada HUD.

const SETTINGS_PATH: String = "user://cats_vs_zombie_dogs_settings.json"

## Niveles de intensidad de shake (texto -> multiplicador).
const SHAKE_LEVELS: Dictionary = {
	"bajo": 0.6,
	"medio": 1.0,
	"alto": 1.5,
}

signal settings_changed()

var _data: Dictionary = {}
var _fps_layer: CanvasLayer
var _fps_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build_fps_overlay()
	apply_all()


func defaults() -> Dictionary:
	return {
		"fullscreen": false,
		"shake_enabled": true,
		"shake_level": "medio",
		"damage_numbers": true,
		"visual_quality": "media",
		"visual_effects": true,
		"shadows": true,
		"show_fps": false,
		"audio_master": 0.80,
		"audio_music": 0.60,
		"audio_sfx": 0.75,
		"audio_ui": 0.70,
		"audio_mute": false,
	}


# --- Carga / guardado --------------------------------------------------------

func _load() -> void:
	_data = defaults()
	if not FileAccess.file_exists(SETTINGS_PATH):
		_save()
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		for key in parsed:
			if _data.has(key):
				_data[key] = parsed[key]


func _save() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()


# --- Acceso ------------------------------------------------------------------

func get_value(key: String, default_value: Variant = null) -> Variant:
	return _data.get(key, default_value)


func set_value(key: String, value: Variant) -> void:
	_data[key] = value
	_save()
	apply_all()
	settings_changed.emit()


# --- Aplicacion --------------------------------------------------------------

func apply_all() -> void:
	_apply_fullscreen()
	_apply_feedback()
	_apply_audio()
	_apply_fps()


func _apply_fullscreen() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(_data.get("fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func _apply_feedback() -> void:
	var fb: Node = get_node_or_null("/root/Feedback")
	if fb == null:
		return
	var scale: float = 0.0
	if bool(_data.get("shake_enabled", true)):
		scale = float(SHAKE_LEVELS.get(str(_data.get("shake_level", "medio")), 1.0))
	fb.set("shake_scale", scale)
	fb.set("damage_numbers_enabled", bool(_data.get("damage_numbers", true)))
	if fb.has_method("apply_visual_quality"):
		fb.apply_visual_quality(
			StringName(str(_data.get("visual_quality", "media"))),
			bool(_data.get("visual_effects", true)),
			bool(_data.get("shadows", true))
		)


func _apply_audio() -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	if audio.has_method("set_master_volume"):
		audio.set_master_volume(float(_data.get("audio_master", 0.80)))
	if audio.has_method("set_music_volume"):
		audio.set_music_volume(float(_data.get("audio_music", 0.60)))
	if audio.has_method("set_sfx_volume"):
		audio.set_sfx_volume(float(_data.get("audio_sfx", 0.75)))
	if audio.has_method("set_ui_volume"):
		audio.set_ui_volume(float(_data.get("audio_ui", 0.70)))
	if audio.has_method("mute_all"):
		audio.mute_all(bool(_data.get("audio_mute", false)))


func _apply_fps() -> void:
	if is_instance_valid(_fps_layer):
		_fps_layer.visible = bool(_data.get("show_fps", false))


func _build_fps_overlay() -> void:
	_fps_layer = CanvasLayer.new()
	_fps_layer.layer = 100
	add_child(_fps_layer)
	_fps_label = Label.new()
	_fps_label.position = Vector2(8, 8)
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_fps_layer.add_child(_fps_label)
	_fps_layer.visible = false


func _process(_delta: float) -> void:
	if is_instance_valid(_fps_label) and _fps_layer.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
