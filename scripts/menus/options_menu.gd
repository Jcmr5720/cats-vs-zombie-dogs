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
## Accesibilidad: escala tipográfica global (UITheme.TEXT_SIZE_LEVELS).
const TEXT_SIZE_CHOICES: Array[Dictionary] = [
	{"id": "pequeno", "label": "Pequeño"}, {"id": "normal", "label": "Normal"},
	{"id": "grande", "label": "Grande"}, {"id": "muy_grande", "label": "Muy grande"},
]
const TABS: Array[Dictionary] = [
	{"id": &"video", "label": "Vídeo", "color": Color(0.45, 0.85, 1.0)},
	{"id": &"juego", "label": "Juego", "color": Color(1.0, 0.6, 0.2)},
	{"id": &"audio", "label": "Audio", "color": Color(0.62, 0.44, 0.88)},
	{"id": &"controles", "label": "Controles", "color": Color(0.48, 0.82, 0.42)},
	{"id": &"datos", "label": "Datos", "color": Color(0.95, 0.42, 0.42)},
]

## Acciones remapeables, agrupadas por jugador (Opciones → Controles).
const P1_BINDINGS: Array[Array] = [
	[&"move_up", "Arriba"], [&"move_down", "Abajo"],
	[&"move_left", "Izquierda"], [&"move_right", "Derecha"],
]
const P2_BINDINGS: Array[Array] = [
	[&"p2_move_up", "Arriba"], [&"p2_move_down", "Abajo"],
	[&"p2_move_left", "Izquierda"], [&"p2_move_right", "Derecha"],
]
const EXTRA_BINDINGS: Array[Array] = [
	[&"companion_regroup", "Reagrupar compañeros"],
	[&"restart", "Reintentar (fin de partida)"],
]
## Atajos fijos (no remapeables), mostrados como referencia compacta.
const FIXED_ROWS: Array[Array] = [
	["Pausa", "ESC"], ["Elegir carta", "Clic / Mando (P2)"], ["Rendimiento", "F8"],
]

var _settings: Node
var _save: Node
var _tab: StringName = &"video"
var _tab_row: HBoxContainer
var _content_box: VBoxContainer
var _reset_button: Button
var _reset_stage: int = 0
## Captura de tecla en curso: accion esperando pulsacion (o vacio).
var _capturing_action: StringName = &""
var _capturing_button: Button
var _binding_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings = get_node_or_null("/root/Settings")
	_save = get_node_or_null("/root/SaveManager")
	_build_ui()
	MenuTheme.add_fade_in(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _capturing_action != &"":
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return
		GameFlow.return_to_main_menu()


## Captura de tecla para el remapeo: el siguiente KeyDown fija la tecla de la
## accion en espera. ESC cancela (lo maneja _unhandled_input); se ignoran
## modificadores sueltos para no atrapar Shift/Ctrl por accidente.
func _input(event: InputEvent) -> void:
	if _capturing_action == &"" or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		return  # lo resuelve _unhandled_input como cancelacion
	if key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return
	get_viewport().set_input_as_handled()
	var code: int = int(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	var accepted: bool = _settings != null and _settings.has_method("set_input_override") \
		and _settings.set_input_override(_capturing_action, code)
	var button := _capturing_button
	_capturing_action = &""
	_capturing_button = null
	if accepted:
		_play_ui_sound(&"ui_click")
		_refresh_binding_buttons()
	else:
		# Tecla en conflicto con otra accion: avisar sin aplicar.
		_play_ui_sound(&"ui_error")
		if is_instance_valid(button):
			button.text = "Tecla en uso"
			var timer := get_tree().create_timer(0.9)
			timer.timeout.connect(func() -> void:
				if is_instance_valid(button) and _capturing_action == &"":
					_refresh_binding_buttons())


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
	# Cambiar de pestaña cancela cualquier captura de tecla pendiente.
	_capturing_action = &""
	_capturing_button = null
	_binding_buttons.clear()
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
			var hint := MenuTheme.make_label("Los cambios se aplican al instante.", MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM)
			_content_box.add_child(hint)
		&"juego":
			_content_box.add_child(MenuTheme.make_setting_toggle("Screen shake", "shake_enabled"))
			_content_box.add_child(_choice_row("Intensidad de shake", "shake_level", SHAKE_OPTIONS, "medio"))
			_content_box.add_child(MenuTheme.make_setting_toggle("Números de daño", "damage_numbers"))
			_content_box.add_child(MenuTheme.make_setting_toggle("Omitir cinemáticas", "skip_cinematics"))
			# Accesibilidad coop: elegir sola la carta resaltada tras 25 s de
			# inactividad (p.ej. mando compartido/soltado). Desactivado por defecto.
			_content_box.add_child(MenuTheme.make_setting_toggle("Carta automática por inactividad (coop)", "card_auto_pick"))
			# Accesibilidad: tamaño de texto global. Escala HUD, menús, tarjetas y
			# diálogos al instante (Theme global); el logo y los iconos no cambian.
			_content_box.add_child(_choice_row("Tamaño de texto", "text_size", TEXT_SIZE_CHOICES, "normal"))
			var size_hint := MenuTheme.make_text("El tamaño de texto se aplica a toda la interfaz al instante.", MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM)
			_content_box.add_child(size_hint)
		&"audio":
			_content_box.add_child(MenuTheme.make_setting_slider("Master", "audio_master", MenuTheme.PURPLE))
			_content_box.add_child(MenuTheme.make_setting_slider("Música", "audio_music", MenuTheme.PURPLE))
			_content_box.add_child(MenuTheme.make_setting_slider("Efectos", "audio_sfx", MenuTheme.PURPLE))
			_content_box.add_child(MenuTheme.make_setting_slider("UI", "audio_ui", MenuTheme.PURPLE))
			_content_box.add_child(MenuTheme.make_setting_toggle("Silenciar todo", "audio_mute"))
		&"controles":
			_build_controls_tab()
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


# --- Pestaña Controles: remapeo de teclado por jugador --------------------------

func _build_controls_tab() -> void:
	_capturing_action = &""
	_capturing_button = null
	_binding_buttons.clear()

	# Dos columnas: Jugador 1 y Jugador 2, cada una con sus 4 direcciones.
	var players_row := HBoxContainer.new()
	players_row.add_theme_constant_override("separation", MenuTheme.GAP_XL)
	_content_box.add_child(players_row)
	players_row.add_child(_player_bindings_column("Jugador 1", MenuTheme.CYAN, P1_BINDINGS))
	players_row.add_child(_player_bindings_column("Jugador 2 (coop)", MenuTheme.GOLD, P2_BINDINGS))

	_content_box.add_child(_spacer(MenuTheme.GAP_XS))
	_content_box.add_child(MenuTheme.make_section_header("Acciones", MenuTheme.PURPLE))
	for entry in EXTRA_BINDINGS:
		_content_box.add_child(_binding_row(entry[0], entry[1]))

	_content_box.add_child(_spacer(MenuTheme.GAP_XS))
	_content_box.add_child(MenuTheme.make_section_header("Atajos fijos", MenuTheme.TEXT_DIM))
	var fixed_row := HBoxContainer.new()
	fixed_row.add_theme_constant_override("separation", MenuTheme.GAP_M)
	for row in FIXED_ROWS:
		fixed_row.add_child(MenuTheme.make_chip("%s · %s" % [row[0], row[1]], MenuTheme.TEXT_DIM))
	_content_box.add_child(fixed_row)

	_content_box.add_child(_spacer(MenuTheme.GAP_S))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", MenuTheme.GAP_M)
	_content_box.add_child(footer)
	var hint := MenuTheme.make_label("Haz clic en una tecla y pulsa la nueva. El mando del J2 no cambia.", MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(hint)
	var reset := MenuTheme.make_button("Restaurar teclas", MenuTheme.TEXT_DIM, &"ghost")
	reset.custom_minimum_size = Vector2(190, 42)
	reset.pressed.connect(func() -> void:
		if _settings != null and _settings.has_method("clear_input_overrides"):
			_settings.clear_input_overrides()
		_play_ui_sound(&"ui_click")
		_refresh_binding_buttons())
	footer.add_child(reset)


## Columna de un jugador: panel con encabezado de color + 4 filas de direccion.
func _player_bindings_column(title: String, accent: Color, bindings: Array[Array]) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuTheme.style_panel(panel, accent, MenuTheme.PANEL_BG_SOFT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_S)
	panel.add_child(col)
	col.add_child(MenuTheme.make_section_header(title, accent))
	for entry in bindings:
		col.add_child(_binding_row(entry[0], entry[1]))
	return panel


## Fila accion: etiqueta + boton con la tecla actual (clic = capturar nueva).
func _binding_row(action: StringName, title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.GAP_M)
	var label := MenuTheme.make_label(title, MenuTheme.FS_BODY, MenuTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var button := MenuTheme.make_button(_key_label(action), MenuTheme.CYAN, &"secondary")
	button.custom_minimum_size = Vector2(190, 42)
	button.pressed.connect(_start_capture.bind(action, button))
	row.add_child(button)
	_binding_buttons[action] = button
	return row


func _start_capture(action: StringName, button: Button) -> void:
	_cancel_capture()
	_capturing_action = action
	_capturing_button = button
	button.text = "Pulsa una tecla…"
	_play_ui_sound(&"ui_click")


func _cancel_capture() -> void:
	if _capturing_action != &"" and is_instance_valid(_capturing_button):
		_capturing_button.text = _key_label(_capturing_action)
	_capturing_action = &""
	_capturing_button = null


func _refresh_binding_buttons() -> void:
	for action in _binding_buttons:
		var button: Button = _binding_buttons[action]
		if is_instance_valid(button):
			button.text = _key_label(action)


func _key_label(action: StringName) -> String:
	if _settings != null and _settings.has_method("get_action_key_label"):
		return str(_settings.get_action_key_label(action))
	return "—"


func _play_ui_sound(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)


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
