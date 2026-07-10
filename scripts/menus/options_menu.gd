extends Control
## Pantalla de opciones (rediseño Steam). Reorganizada en pestañas por grupo
## (Vídeo · Juego · Audio · Datos) con barra superior de retorno y contenido en
## scroll para que nunca se recorte. Interruptores y sliders reales desde la
## fábrica de MenuTheme. Lee/escribe el autoload Settings; el reset conserva la
## doble confirmación.

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const SHAKE_OPTIONS: Array[Dictionary] = [
	{"id": "bajo", "label": "Bajo"}, {"id": "medio", "label": "Medio"}, {"id": "alto", "label": "Alto"},
]
const QUALITY_OPTIONS: Array[Dictionary] = [
	{"id": "baja", "label": "Baja"}, {"id": "media", "label": "Media"}, {"id": "alta", "label": "Alta"},
]
const TABS: Array[Dictionary] = [
	{"id": &"video", "label": "Vídeo", "color": Color(0.45, 0.85, 1.0)},
	{"id": &"juego", "label": "Juego", "color": Color(1.0, 0.6, 0.2)},
	{"id": &"audio", "label": "Audio", "color": Color(0.62, 0.44, 0.88)},
	{"id": &"controles", "label": "Controles", "color": Color(0.48, 0.82, 0.42)},
	{"id": &"datos", "label": "Datos", "color": Color(0.95, 0.42, 0.42)},
]

## Referencia de controles (solo lectura; el remapeo queda para otra fase).
const CONTROL_ROWS: Array[Array] = [
	["Jugador 1 — mover", "WASD  /  Flechas"],
	["Jugador 2 — mover (coop)", "Stick izq. del mando  /  IJKL"],
	["Pausa", "ESC"],
	["Elegir carta de mejora", "Clic  /  Mando (P2)"],
	["Reintentar (fin de partida)", "R"],
	["Mejoras permanentes (fin de partida)", "M"],
	["Cambiar zona (pruebas)", "F1 · F2 · F3"],
	["Panel de rendimiento", "F8"],
]

var _settings: Node
var _save: Node
var _tab: StringName = &"video"
var _tab_row: HBoxContainer
var _content_box: VBoxContainer
var _reset_button: Button
var _reset_stage: int = 0


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

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", MenuTheme.GAP_XL + 12)
	margin.add_theme_constant_override("margin_right", MenuTheme.GAP_XL + 12)
	margin.add_theme_constant_override("margin_top", MenuTheme.GAP_L)
	margin.add_theme_constant_override("margin_bottom", MenuTheme.GAP_L)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_L)
	margin.add_child(col)

	col.add_child(MenuTheme.make_top_bar("Opciones", func() -> void: GameFlow.return_to_main_menu(), MenuTheme.PURPLE))

	_tab_row = MenuTheme.make_segmented(TABS, _tab, _on_tab_selected, MenuTheme.PURPLE)
	col.add_child(_tab_row)

	# Panel de contenido, envuelto en scroll para no recortar nunca.
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	MenuTheme.style_panel(panel, MenuTheme.PURPLE, MenuTheme.PANEL_BG_SOFT)
	col.add_child(panel)
	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", MenuTheme.GAP_M)
	panel.add_child(MenuTheme.wrap_scrollable(_content_box))

	_rebuild_content()


func _on_tab_selected(id: Variant) -> void:
	_tab = id
	MenuTheme.refresh_segmented(_tab_row, _tab)
	_rebuild_content()


func _rebuild_content() -> void:
	_reset_stage = 0
	for child in _content_box.get_children():
		child.queue_free()
	_focus_first_control.call_deferred()
	match _tab:
		&"video":
			_content_box.add_child(MenuTheme.make_setting_toggle("Pantalla completa", "fullscreen"))
			_content_box.add_child(_choice_row("Calidad visual", "visual_quality", QUALITY_OPTIONS, "media"))
			# FASE VISUAL 2.5: toggles de la capa de iluminacion/atmosfera. La calidad
			# Baja los apaga todos aunque esten activos (preset manda sobre toggle).
			_content_box.add_child(MenuTheme.make_setting_toggle("Luces dinámicas", "dynamic_lights"))
			_content_box.add_child(MenuTheme.make_setting_toggle("Viñeta de cámara", "vignette"))
			_content_box.add_child(MenuTheme.make_setting_toggle("Niebla de ambiente", "fog"))
			_content_box.add_child(MenuTheme.make_setting_toggle("Efectos intensos", "visual_effects"))
			_content_box.add_child(MenuTheme.make_setting_toggle("Sombras", "shadows"))
			_content_box.add_child(MenuTheme.make_setting_toggle("Mostrar FPS", "show_fps"))
			var hint := MenuTheme.make_label("Luces y niebla nuevas se aplican al instante; las luces ya encendidas se apagan/encienden en vivo.", MenuTheme.FS_BODY, MenuTheme.TEXT_DIM)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_content_box.add_child(hint)
		&"juego":
			_content_box.add_child(MenuTheme.make_setting_toggle("Screen shake", "shake_enabled"))
			_content_box.add_child(_choice_row("Intensidad de shake", "shake_level", SHAKE_OPTIONS, "medio"))
			_content_box.add_child(MenuTheme.make_setting_toggle("Números de daño", "damage_numbers"))
			_content_box.add_child(MenuTheme.make_setting_toggle("Omitir cinemáticas", "skip_cinematics"))
		&"audio":
			_content_box.add_child(MenuTheme.make_setting_slider("Master", "audio_master", MenuTheme.PURPLE))
			_content_box.add_child(MenuTheme.make_setting_slider("Música", "audio_music", MenuTheme.PURPLE))
			_content_box.add_child(MenuTheme.make_setting_slider("Efectos", "audio_sfx", MenuTheme.PURPLE))
			_content_box.add_child(MenuTheme.make_setting_slider("UI", "audio_ui", MenuTheme.PURPLE))
			_content_box.add_child(MenuTheme.make_setting_toggle("Silenciar todo", "audio_mute"))
		&"controles":
			# Referencia de controles en pares titulo/valor (FASE VISUAL 3).
			for row in CONTROL_ROWS:
				_content_box.add_child(MenuTheme.make_info_pair(row[0], row[1]))
			_content_box.add_child(_spacer(MenuTheme.GAP_S))
			var note := MenuTheme.make_label("El remapeo de teclas llegará en una fase futura.", MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_content_box.add_child(note)
		&"datos":
			var warn := MenuTheme.make_label("El reinicio borra partidas, sardinas y desbloqueos. No se puede deshacer.", MenuTheme.FS_BODY, MenuTheme.TEXT_DIM)
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_content_box.add_child(warn)
			_content_box.add_child(_spacer(MenuTheme.GAP_S))
			_reset_button = MenuTheme.make_button("Resetear progreso", MenuTheme.DANGER, &"danger")
			_reset_button.custom_minimum_size = Vector2(280, 48)
			_reset_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_reset_button.pressed.connect(_on_reset_pressed)
			_content_box.add_child(_reset_button)


## Fila etiqueta + control segmentado ligado a una clave de texto de Settings.
func _choice_row(title: String, key: String, options: Array, default_value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.GAP_M)
	var label := MenuTheme.make_label(title, MenuTheme.FS_H3, MenuTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var current: String = str(_settings.get_value(key, default_value)) if _settings != null else default_value
	# holder guarda la referencia al segmentado para refrescarlo desde el callback
	# (las lambdas de GDScript capturan los locales por valor al crearse).
	var holder: Array = []
	var seg := MenuTheme.make_segmented(options, current, func(id: Variant) -> void:
		if _settings != null and _settings.has_method("set_value"):
			_settings.set_value(key, id)
		if not holder.is_empty():
			MenuTheme.refresh_segmented(holder[0], id), MenuTheme.PURPLE)
	holder.append(seg)
	seg.custom_minimum_size = Vector2(240, 0)
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(seg)
	return row


func _on_reset_pressed() -> void:
	# Doble confirmación para no borrar el progreso por accidente.
	_reset_stage += 1
	match _reset_stage:
		1:
			var audio_warn: Node = get_node_or_null("/root/AudioManager")
			if audio_warn != null and audio_warn.has_method("play_ui"):
				audio_warn.play_ui(&"ui_error")
			_reset_button.text = "Confirmar borrado definitivo"
		_:
			if _save != null and _save.has_method("reset_progress"):
				_save.reset_progress()
			var audio_done: Node = get_node_or_null("/root/AudioManager")
			if audio_done != null and audio_done.has_method("play_ui"):
				audio_done.play_ui(&"ui_buy")
			_reset_button.text = "Progreso borrado"
			MenuTheme.style_button(_reset_button, MenuTheme.ZOMBIE, &"secondary")
			_reset_button.disabled = true
			_reset_stage = 0


## Foco inicial para teclado/gamepad (FASE VISUAL 3): primer boton util de la
## pestaña activa. Ignora los nodos viejos pendientes de liberarse.
func _focus_first_control() -> void:
	var stack: Array = _content_box.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n.is_queued_for_deletion():
			continue
		if n is Button and not (n as Button).disabled and (n as Button).focus_mode != Control.FOCUS_NONE:
			(n as Button).grab_focus()
			return
		stack.append_array(n.get_children())


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s
