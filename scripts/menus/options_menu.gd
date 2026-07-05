extends Control
## Pantalla de opciones basicas (Fase 08). Lee y escribe en el autoload Settings
## (pantalla completa, screen shake + intensidad, numeros de dano, FPS y audio) y
## permite resetear el progreso con DOBLE confirmacion.

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const SHAKE_ORDER: Array[String] = ["bajo", "medio", "alto"]
const QUALITY_ORDER: Array[String] = ["baja", "media", "alta"]

var _settings: Node
var _save: Node
var _reset_button: Button
var _reset_stage: int = 0  # 0 normal, 1 esperando confirmacion final


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings = get_node_or_null("/root/Settings")
	_save = get_node_or_null("/root/SaveManager")
	_build_ui()
	MenuTheme.add_fade_in(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameFlow.return_to_main_menu()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = MenuTheme.BG_BOTTOM
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(520, 0)
	scroll.add_child(col)

	col.add_child(MenuTheme.make_title("Opciones", 40, MenuTheme.PURPLE))
	col.add_child(_spacer(8))

	col.add_child(_toggle_row("Pantalla completa", "fullscreen"))
	col.add_child(_toggle_row("Screen shake", "shake_enabled"))
	col.add_child(_shake_level_row())
	col.add_child(_toggle_row("Numeros de dano", "damage_numbers"))
	col.add_child(_quality_row())
	col.add_child(_toggle_row("Efectos intensos", "visual_effects"))
	col.add_child(_toggle_row("Sombras", "shadows"))
	col.add_child(_toggle_row("Mostrar FPS", "show_fps"))
	col.add_child(_toggle_row("Omitir cinematicas", "skip_cinematics"))
	col.add_child(_spacer(8))
	col.add_child(MenuTheme.make_title("Audio", 24, MenuTheme.CYAN))
	col.add_child(_volume_row("Master", "audio_master"))
	col.add_child(_volume_row("Musica", "audio_music"))
	col.add_child(_volume_row("Efectos", "audio_sfx"))
	col.add_child(_volume_row("UI", "audio_ui"))
	col.add_child(_toggle_row("Silenciar todo", "audio_mute"))

	col.add_child(_spacer(14))
	_reset_button = MenuTheme.make_button("Resetear progreso", Color(0.85, 0.35, 0.35))
	_reset_button.pressed.connect(_on_reset_pressed)
	col.add_child(_reset_button)

	col.add_child(_spacer(6))
	var back := MenuTheme.make_button("Volver  (ESC)", MenuTheme.TEXT_DIM)
	back.pressed.connect(func() -> void: GameFlow.return_to_main_menu())
	col.add_child(back)


## Fila con etiqueta + boton que alterna un booleano de Settings.
func _toggle_row(title: String, key: String) -> Control:
	var hb := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", MenuTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(label)

	var button := MenuTheme.make_button(_on_off(key), MenuTheme.CYAN)
	button.custom_minimum_size = Vector2(140, 42)
	button.pressed.connect(func() -> void:
		var current: bool = bool(_settings.get_value(key, false))
		_settings.set_value(key, not current)
		button.text = _on_off(key))
	hb.add_child(button)
	return hb


func _shake_level_row() -> Control:
	var hb := HBoxContainer.new()
	var label := Label.new()
	label.text = "Intensidad de shake"
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", MenuTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(label)

	var button := MenuTheme.make_button(_shake_label(), MenuTheme.ACCENT)
	button.custom_minimum_size = Vector2(140, 42)
	button.pressed.connect(func() -> void:
		var current: String = str(_settings.get_value("shake_level", "medio"))
		var idx: int = SHAKE_ORDER.find(current)
		idx = (idx + 1) % SHAKE_ORDER.size()
		_settings.set_value("shake_level", SHAKE_ORDER[idx])
		button.text = _shake_label())
	hb.add_child(button)
	return hb


func _quality_row() -> Control:
	var hb := HBoxContainer.new()
	var label := Label.new()
	label.text = "Calidad visual"
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", MenuTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(label)

	var button := MenuTheme.make_button(_quality_label(), MenuTheme.PURPLE)
	button.custom_minimum_size = Vector2(140, 42)
	button.pressed.connect(func() -> void:
		var current: String = str(_settings.get_value("visual_quality", "media"))
		var idx: int = QUALITY_ORDER.find(current)
		idx = (idx + 1) % QUALITY_ORDER.size()
		_settings.set_value("visual_quality", QUALITY_ORDER[idx])
		button.text = _quality_label())
	hb.add_child(button)
	return hb


func _volume_row(title: String, key: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", MenuTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(54, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 17)
	value_label.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	hb.add_child(value_label)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(210, 34)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(_settings.get_value(key, 0.75))
	value_label.text = "%d%%" % int(round(slider.value * 100.0))
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d%%" % int(round(value * 100.0))
		_settings.set_value(key, value))
	hb.add_child(slider)
	return hb


func _on_reset_pressed() -> void:
	# Doble confirmacion para no borrar progreso por accidente.
	_reset_stage += 1
	match _reset_stage:
		1:
			var audio_warn: Node = get_node_or_null("/root/AudioManager")
			if audio_warn != null and audio_warn.has_method("play_ui"):
				audio_warn.play_ui(&"ui_error")
			_reset_button.text = "Esto borrara todo tu progreso. Confirmar borrado definitivo"
			_reset_button.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
		_:
			if _save != null and _save.has_method("reset_progress"):
				_save.reset_progress()
			var audio_done: Node = get_node_or_null("/root/AudioManager")
			if audio_done != null and audio_done.has_method("play_ui"):
				audio_done.play_ui(&"ui_buy")
			_reset_button.text = "Progreso borrado"
			_reset_button.add_theme_color_override("font_color", MenuTheme.ZOMBIE)
			_reset_button.disabled = true
			_reset_stage = 0


func _on_off(key: String) -> String:
	return "Si" if bool(_settings.get_value(key, false)) else "No"


func _shake_label() -> String:
	return str(_settings.get_value("shake_level", "medio")).capitalize()


func _quality_label() -> String:
	return str(_settings.get_value("visual_quality", "media")).capitalize()


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s
