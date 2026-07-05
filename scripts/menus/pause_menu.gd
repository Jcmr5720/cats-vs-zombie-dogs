extends Control
## Pausa durante la partida (Fase 08). ESC pausa/reanuda y muestra Continuar, Opciones
## (ajustes rapidos) y Volver al menu (con confirmacion). Se instancia dentro del HUD.
## No se activa si la partida ya termino (lo maneja MapManager) ni durante la seleccion
## de cartas de mejora.

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const SHAKE_ORDER: Array[String] = ["bajo", "medio", "alto"]

var _settings: Node
var _root_box: VBoxContainer
var _options_box: VBoxContainer
var _confirm_box: VBoxContainer
var _info_label: Label
var _is_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_settings = get_node_or_null("/root/Settings")
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Si la partida termino, deja que el MapManager maneje ESC (volver al menu).
	var mm: Node = get_tree().get_first_node_in_group("map_manager")
	if mm != null and mm.has_method("is_run_ended") and mm.is_run_ended():
		return
	# No interferir con la seleccion de cartas (el arbol ya esta en pausa por eso).
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("is_selecting_upgrade") and hud.is_selecting_upgrade():
		return

	if _is_open:
		# Si hay un sub-panel abierto, ESC vuelve al panel raiz; si no, reanuda.
		if _options_box.visible or _confirm_box.visible:
			_show_root()
		else:
			_resume()
	else:
		_open()
	get_viewport().set_input_as_handled()


func _open() -> void:
	_is_open = true
	visible = true
	_play_ui(&"ui_open")
	get_tree().paused = true
	_refresh_info()
	_show_root()


## Centro de informacion: vuelca el detalle de la run (que el HUD ya no muestra).
func _refresh_info() -> void:
	if _info_label == null:
		return
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("get_run_info"):
		_info_label.text = ""
		return
	var info: Dictionary = hud.get_run_info()
	var total: int = int(info.get("time", 0.0))
	var lines: Array[String] = [
		"%s  ·  %s" % [info.get("map_name", "Mapa"), info.get("objective", "Sobrevive")],
		"Tiempo %02d:%02d   Nivel %d   Eliminados %d" % [total / 60, total % 60, int(info.get("level", 1)), int(info.get("kills", 0))],
		"Gatos rescatados: %d/%d   Intensidad: %s" % [int(info.get("cats", 0)), int(info.get("max_cats", 4)), _intensity_tier(float(info.get("difficulty", 0.0)))],
	]
	var mm: Node = get_tree().get_first_node_in_group("map_manager")
	if mm != null and mm.has_method("get_world_seed"):
		var seed_value: int = int(mm.get_world_seed())
		if seed_value != 0:
			lines.append("Semilla del mundo: %d" % seed_value)
	var weapons: Array = info.get("weapons", [])
	if not weapons.is_empty():
		var parts: Array[String] = []
		for w in weapons:
			parts.append("%s Nv.%d" % [w.get("display_name", "Arma"), int(w.get("level", 1))])
		lines.append("Armas: %s" % ", ".join(parts))
	var synergies: Array = info.get("synergies", [])
	var active_syn: Array[String] = []
	for s in synergies:
		if bool(s.get("active", false)):
			active_syn.append(str(s.get("name", "")))
	if not active_syn.is_empty():
		lines.append("Sinergias activas: %s" % ", ".join(active_syn))
	var companions: Array = info.get("companions", [])
	if not companions.is_empty():
		var cparts: Array[String] = []
		for c in companions:
			cparts.append(str(c.get("display_name", "Companero")))
		lines.append("Companeros: %s" % ", ".join(cparts))
	_info_label.text = "\n".join(lines)


func _intensity_tier(difficulty: float) -> String:
	if difficulty < 3.0:
		return "Tranquilo"
	if difficulty < 7.0:
		return "Calentando"
	if difficulty < 12.0:
		return "Medio"
	if difficulty < 18.0:
		return "Peligroso"
	return "Caotico"


func _resume() -> void:
	_is_open = false
	visible = false
	_play_ui(&"ui_close")
	get_tree().paused = false


func _show_root() -> void:
	_root_box.visible = true
	_options_box.visible = false
	_confirm_box.visible = false


# --- Construccion ------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var stack := VBoxContainer.new()
	center.add_child(stack)

	_root_box = _build_root()
	stack.add_child(_root_box)
	_options_box = _build_options()
	stack.add_child(_options_box)
	_confirm_box = _build_confirm()
	stack.add_child(_confirm_box)


func _build_root() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(MenuTheme.make_title("Pausa", 44, MenuTheme.CYAN))

	# Centro de informacion: detalle de la run que el HUD mantiene oculto.
	var info_panel := PanelContainer.new()
	MenuTheme.style_panel(info_panel, MenuTheme.CYAN, MenuTheme.PANEL_BG_SOFT)
	info_panel.custom_minimum_size = Vector2(520, 0)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 15)
	_info_label.add_theme_color_override("font_color", MenuTheme.TEXT)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_panel.add_child(_info_label)
	v.add_child(info_panel)
	v.add_child(_spacer(4))

	var cont := MenuTheme.make_button("Continuar", MenuTheme.ZOMBIE)
	cont.pressed.connect(_resume)
	v.add_child(cont)

	var opt := MenuTheme.make_button("Opciones", MenuTheme.PURPLE)
	opt.pressed.connect(func() -> void:
		_root_box.visible = false
		_options_box.visible = true)
	v.add_child(opt)

	var menu := MenuTheme.make_button("Volver al menu principal", Color(0.85, 0.45, 0.45))
	menu.pressed.connect(func() -> void:
		_root_box.visible = false
		_confirm_box.visible = true)
	v.add_child(menu)
	return v


func _build_options() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.visible = false
	v.add_child(MenuTheme.make_title("Opciones rapidas", 28, MenuTheme.PURPLE))
	v.add_child(_toggle_row("Pantalla completa", "fullscreen"))
	v.add_child(_toggle_row("Screen shake", "shake_enabled"))
	v.add_child(_shake_row())
	v.add_child(_toggle_row("Numeros de dano", "damage_numbers"))
	v.add_child(_toggle_row("Mostrar FPS", "show_fps"))
	v.add_child(_volume_row("Master", "audio_master"))
	v.add_child(_volume_row("Musica", "audio_music"))
	v.add_child(_volume_row("Efectos", "audio_sfx"))
	v.add_child(_volume_row("UI", "audio_ui"))
	v.add_child(_toggle_row("Silenciar todo", "audio_mute"))
	var back := MenuTheme.make_button("Atras", MenuTheme.TEXT_DIM)
	back.pressed.connect(_show_root)
	v.add_child(back)
	return v


func _build_confirm() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.visible = false
	v.add_child(MenuTheme.make_title("Perderas el progreso de esta partida. Salir?", 22, Color(1.0, 0.7, 0.5)))
	v.add_child(_spacer(6))
	var yes := MenuTheme.make_button("Si, volver al menu", Color(0.85, 0.45, 0.45))
	yes.pressed.connect(func() -> void: GameFlow.return_to_main_menu())
	v.add_child(yes)
	var no := MenuTheme.make_button("No, seguir jugando", MenuTheme.ZOMBIE)
	no.pressed.connect(_show_root)
	v.add_child(no)
	return v


func _toggle_row(title: String, key: String) -> Control:
	var hb := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", MenuTheme.TEXT)
	label.custom_minimum_size = Vector2(260, 0)
	hb.add_child(label)
	var button := MenuTheme.make_button(_on_off(key), MenuTheme.CYAN)
	button.custom_minimum_size = Vector2(120, 40)
	button.pressed.connect(func() -> void:
		_settings.set_value(key, not bool(_settings.get_value(key, false)))
		button.text = _on_off(key))
	hb.add_child(button)
	return hb


func _shake_row() -> Control:
	var hb := HBoxContainer.new()
	var label := Label.new()
	label.text = "Intensidad de shake"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", MenuTheme.TEXT)
	label.custom_minimum_size = Vector2(260, 0)
	hb.add_child(label)
	var button := MenuTheme.make_button(_shake_label(), MenuTheme.ACCENT)
	button.custom_minimum_size = Vector2(120, 40)
	button.pressed.connect(func() -> void:
		var idx: int = SHAKE_ORDER.find(str(_settings.get_value("shake_level", "medio")))
		idx = (idx + 1) % SHAKE_ORDER.size()
		_settings.set_value("shake_level", SHAKE_ORDER[idx])
		button.text = _shake_label())
	hb.add_child(button)
	return hb


func _volume_row(title: String, key: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", MenuTheme.TEXT)
	label.custom_minimum_size = Vector2(160, 0)
	hb.add_child(label)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	hb.add_child(value_label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(190, 32)
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


func _on_off(key: String) -> String:
	return "Si" if bool(_settings.get_value(key, false)) else "No"


func _shake_label() -> String:
	return str(_settings.get_value("shake_level", "medio")).capitalize()


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _play_ui(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)
