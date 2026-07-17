extends Control
## Pausa durante la partida (rediseño Steam). ESC pausa/reanuda y muestra Continuar,
## Opciones rápidas y Volver al menú (con confirmación). La info de la run se muestra
## como chips/tarjetas en vez de un bloque de texto. Se instancia dentro del HUD.
## No se activa si la partida ya terminó (lo maneja MapManager) ni durante la
## selección de cartas de mejora.

@warning_ignore("shadowed_global_identifier")
const MenuTheme = preload("res://scripts/menus/menu_theme.gd")

var _settings: Node
var _root_box: VBoxContainer
var _options_box: VBoxContainer
var _confirm_box: VBoxContainer
var _info_header: Label
var _info_chips: HFlowContainer
var _is_open: bool = false
## Primer boton (Continuar): recibe el foco al abrir para navegar con gamepad (P2).
var _continue_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_settings = get_node_or_null("/root/Settings")
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	# ESC (P1) o Start/Options del gamepad (P2) abren/cierran la pausa.
	if not (event.is_action_pressed("ui_cancel") or event.is_action_pressed("p2_pause")):
		return
	# Si la partida terminó, deja que el MapManager maneje ESC (volver al menú).
	var mm: Node = get_tree().get_first_node_in_group("map_manager")
	if mm != null and mm.has_method("is_run_ended") and mm.is_run_ended():
		return
	# No interferir con la selección de cartas (el árbol ya está en pausa por eso).
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("is_selecting_upgrade") and hud.is_selecting_upgrade():
		return

	if _is_open:
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
	# Foco al primer boton para que el P2 navegue la pausa con el gamepad.
	if is_instance_valid(_continue_button):
		_continue_button.call_deferred("grab_focus")


## Centro de información: vuelca el detalle de la run como chips en vez de texto.
func _refresh_info() -> void:
	if _info_chips == null:
		return
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("get_run_info"):
		_info_header.text = ""
		return
	var info: Dictionary = hud.get_run_info()
	_info_header.text = "%s  ·  %s" % [info.get("map_name", "Mapa"), info.get("objective", "Sobrevive")]
	for child in _info_chips.get_children():
		child.queue_free()
	var total: int = int(info.get("time", 0.0))
	@warning_ignore("integer_division")
	_info_chips.add_child(MenuTheme.make_chip("%02d:%02d" % [total / 60, total % 60], MenuTheme.CYAN, &"clock"))
	_info_chips.add_child(MenuTheme.make_chip("Nivel %d" % int(info.get("level", 1)), MenuTheme.CYAN, &"upgrade"))
	_info_chips.add_child(MenuTheme.make_chip("%d bajas" % int(info.get("kills", 0)), MenuTheme.DANGER, &"boss"))
	_info_chips.add_child(MenuTheme.make_chip("%d/%d" % [int(info.get("cats", 0)), int(info.get("max_cats", 4))], MenuTheme.PURPLE, &"companion"))
	_info_chips.add_child(MenuTheme.make_chip(_intensity_tier(float(info.get("difficulty", 0.0))), MenuTheme.ACCENT, &"shield"))
	var mm: Node = get_tree().get_first_node_in_group("map_manager")
	if mm != null and mm.has_method("get_world_seed"):
		var seed_value: int = int(mm.get_world_seed())
		if seed_value != 0:
			_info_chips.add_child(MenuTheme.make_chip("Semilla %d" % seed_value, MenuTheme.TEXT_DIM, &"map"))
	for w in info.get("weapons", []):
		_info_chips.add_child(MenuTheme.make_chip("%s Nv.%d" % [w.get("display_name", "Arma"), int(w.get("level", 1))], MenuTheme.ACCENT, &"upgrade"))
	for s in info.get("synergies", []):
		if bool(s.get("active", false)):
			_info_chips.add_child(MenuTheme.make_chip(str(s.get("name", "")), MenuTheme.ZOMBIE, &"star"))
	for c in info.get("companions", []):
		_info_chips.add_child(MenuTheme.make_chip(str(c.get("display_name", "Compañero")), MenuTheme.PURPLE, &"companion"))


func _intensity_tier(difficulty: float) -> String:
	if difficulty < 3.0:
		return "Tranquilo"
	if difficulty < 7.0:
		return "Calentando"
	if difficulty < 12.0:
		return "Medio"
	if difficulty < 18.0:
		return "Peligroso"
	return "Caótico"


func _resume() -> void:
	_is_open = false
	visible = false
	_play_ui(&"ui_close")
	get_tree().paused = false


func _show_root() -> void:
	_root_box.visible = true
	_options_box.visible = false
	_confirm_box.visible = false


# --- Construcción ------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 0.86)
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
	v.add_theme_constant_override("separation", MenuTheme.GAP_M)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(MenuTheme.make_title("Pausa", MenuTheme.FS_H1 + 6, MenuTheme.CYAN))

	# Centro de información: cabecera + chips de la run.
	var info_panel := PanelContainer.new()
	MenuTheme.style_panel(info_panel, MenuTheme.CYAN, MenuTheme.PANEL_BG_SOFT)
	info_panel.custom_minimum_size = Vector2(560, 0)
	var info_col := VBoxContainer.new()
	info_col.add_theme_constant_override("separation", MenuTheme.GAP_S)
	info_panel.add_child(info_col)
	_info_header = MenuTheme.make_label("", MenuTheme.FS_H3, MenuTheme.TEXT)
	_info_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_col.add_child(_info_header)
	_info_chips = HFlowContainer.new()
	_info_chips.add_theme_constant_override("h_separation", MenuTheme.GAP_S)
	_info_chips.add_theme_constant_override("v_separation", MenuTheme.GAP_S)
	info_col.add_child(_info_chips)
	v.add_child(info_panel)
	v.add_child(_spacer(MenuTheme.GAP_XS))

	var cont := MenuTheme.make_button("Continuar", MenuTheme.ZOMBIE, &"primary")
	cont.custom_minimum_size = Vector2(360, 52)
	cont.focus_mode = Control.FOCUS_ALL
	cont.pressed.connect(_resume)
	v.add_child(cont)
	_continue_button = cont

	var opt := MenuTheme.make_button("Opciones", MenuTheme.PURPLE, &"secondary")
	opt.custom_minimum_size = Vector2(360, 46)
	opt.pressed.connect(func() -> void:
		_root_box.visible = false
		_options_box.visible = true)
	v.add_child(opt)

	var menu := MenuTheme.make_button("Volver al menú principal", MenuTheme.DANGER, &"ghost")
	menu.custom_minimum_size = Vector2(360, 44)
	menu.pressed.connect(func() -> void:
		_root_box.visible = false
		_confirm_box.visible = true)
	v.add_child(menu)
	return v


func _build_options() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", MenuTheme.GAP_M)
	v.visible = false
	v.custom_minimum_size = Vector2(460, 0)
	v.add_child(MenuTheme.make_title("Opciones rápidas", MenuTheme.FS_H2, MenuTheme.PURPLE))
	v.add_child(MenuTheme.make_setting_toggle("Pantalla completa", "fullscreen"))
	v.add_child(MenuTheme.make_setting_toggle("Screen shake", "shake_enabled"))
	v.add_child(MenuTheme.make_setting_toggle("Números de daño", "damage_numbers"))
	v.add_child(MenuTheme.make_setting_toggle("Mostrar FPS", "show_fps"))
	v.add_child(MenuTheme.make_setting_slider("Master", "audio_master", MenuTheme.PURPLE))
	v.add_child(MenuTheme.make_setting_slider("Música", "audio_music", MenuTheme.PURPLE))
	v.add_child(MenuTheme.make_setting_slider("Efectos", "audio_sfx", MenuTheme.PURPLE))
	v.add_child(MenuTheme.make_setting_slider("UI", "audio_ui", MenuTheme.PURPLE))
	v.add_child(MenuTheme.make_setting_toggle("Silenciar todo", "audio_mute"))
	var back := MenuTheme.make_button("Atrás", MenuTheme.TEXT_DIM, &"ghost")
	back.pressed.connect(_show_root)
	v.add_child(back)
	return v


func _build_confirm() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", MenuTheme.GAP_M)
	v.visible = false
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var warn := MenuTheme.make_title("Perderás el progreso de esta partida. ¿Salir?", MenuTheme.FS_H2, Color(1.0, 0.7, 0.5))
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(460, 0)
	v.add_child(warn)
	v.add_child(_spacer(MenuTheme.GAP_XS))
	var yes := MenuTheme.make_button("Sí, volver al menú", MenuTheme.DANGER, &"danger")
	yes.custom_minimum_size = Vector2(360, 48)
	yes.pressed.connect(func() -> void: GameFlow.return_to_main_menu())
	v.add_child(yes)
	var no := MenuTheme.make_button("No, seguir jugando", MenuTheme.ZOMBIE, &"primary")
	no.custom_minimum_size = Vector2(360, 48)
	no.pressed.connect(_show_root)
	v.add_child(no)
	return v


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _play_ui(sound_name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(sound_name)
