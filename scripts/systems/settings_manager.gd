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

## Acciones remapeables desde Opciones → Controles. SOLO se sustituyen sus
## eventos de TECLADO; los de mando (P2) se conservan intactos.
const REMAP_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"p2_move_left", &"p2_move_right", &"p2_move_up", &"p2_move_down",
	&"companion_regroup", &"restart",
]

var _data: Dictionary = {}
var _fps_layer: CanvasLayer
var _fps_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build_fps_overlay()
	apply_all()
	apply_input_overrides()


func defaults() -> Dictionary:
	return {
		"fullscreen": false,
		"shake_enabled": true,
		"shake_level": "medio",
		"damage_numbers": true,
		"visual_quality": "media",
		"visual_effects": true,
		"shadows": true,
		"dynamic_lights": true,
		"vignette": true,
		"fog": true,
		"show_fps": false,
		"skip_cinematics": false,
		"audio_master": 0.80,
		"audio_music": 0.60,
		"audio_sfx": 0.75,
		"audio_ui": 0.70,
		"audio_mute": false,
		# Remapeo de teclado: accion (String) -> physical_keycode (int).
		"input_overrides": {},
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
			bool(_data.get("shadows", true)),
			bool(_data.get("dynamic_lights", true)),
			bool(_data.get("vignette", true)),
			bool(_data.get("fog", true))
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


# --- Remapeo de teclado (Opciones → Controles) --------------------------------

## Aplica los overrides guardados sobre el InputMap en runtime. Para cada accion
## remapeada se eliminan SOLO los InputEventKey (el joypad del P2 se conserva) y
## se añade la tecla elegida. Sin override, la accion queda como en project.godot.
func apply_input_overrides() -> void:
	var overrides: Dictionary = _data.get("input_overrides", {})
	for action in REMAP_ACTIONS:
		if not InputMap.has_action(action):
			continue
		if not overrides.has(String(action)):
			continue
		var keycode: int = int(overrides[String(action)])
		if keycode <= 0:
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		var key := InputEventKey.new()
		key.physical_keycode = keycode as Key
		InputMap.action_add_event(action, key)


## Fija la tecla de una accion. Devuelve false si la tecla ya la usa otra accion
## remapeable (conflicto); no aplica nada en ese caso.
func set_input_override(action: StringName, physical_keycode: int) -> bool:
	if physical_keycode <= 0 or not REMAP_ACTIONS.has(action):
		return false
	for other in REMAP_ACTIONS:
		if other != action and get_action_keycode(other) == physical_keycode:
			return false
	var overrides: Dictionary = _data.get("input_overrides", {})
	overrides[String(action)] = physical_keycode
	_data["input_overrides"] = overrides
	_save()
	apply_input_overrides()
	settings_changed.emit()
	return true


## Borra todos los overrides y restaura el InputMap de project.godot.
func clear_input_overrides() -> void:
	_data["input_overrides"] = {}
	_save()
	InputMap.load_from_project_settings()
	settings_changed.emit()


## Tecla (physical keycode) actualmente activa para una accion, o 0 si su
## entrada de teclado es la por defecto con varias teclas / no tiene teclado.
func get_action_keycode(action: StringName) -> int:
	if not InputMap.has_action(action):
		return 0
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			return int(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	return 0


## Etiqueta legible de las teclas de una accion (para la UI de Controles).
func get_action_key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "—"
	var parts: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			parts.append(OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code)))
	if parts.is_empty():
		return "—"
	return " / ".join(parts)


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
