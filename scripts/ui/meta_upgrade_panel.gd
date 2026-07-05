extends Control
## Panel de "Mejoras de la Colonia" (rediseño Fase 08.9). Layout minimalista de
## lista + detalle: a la izquierda una lista compacta (icono, nombre, nivel, costo);
## a la derecha el detalle de la mejora seleccionada (nivel, efecto actual, siguiente,
## costo) y un unico boton Comprar. Asi se evita repetir texto en cada tarjeta.
##
## Se abre con M cuando la partida termino (dentro del HUD) o desde el menu principal
## (MetaProgressionMenu, que fija `on_close` para volver al menu).

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")

const CATEGORY_ICON: Dictionary = {
	&"armas": "✦",
	&"jugador": "▲",
	&"economia": "◆",
	&"colonia": "✚",
}

## Callback opcional para el boton Cerrar (lo fija el menu para volver al menu).
var on_close: Callable = Callable()

var _meta: Node
var _save: Node
var _sardines_label: Label
var _message_label: Label
var _list_box: VBoxContainer
var _row_buttons: Array = []
var _selected_id: StringName = &""

# Nodos del panel de detalle.
var _detail_name: Label
var _detail_level: Label
var _detail_current: Label
var _detail_next: Label
var _detail_cost: Label
var _buy_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_meta = get_node_or_null("/root/MetaProgression")
	_save = get_node_or_null("/root/SaveManager")
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.07, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(880, 0)
	center.add_child(col)

	# Cabecera: titulo + Sardinas.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	col.add_child(header)
	var title := MenuTheme.make_title("Mejoras de la Colonia", 30, MenuTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_sardines_label = Label.new()
	_sardines_label.add_theme_font_size_override("font_size", 22)
	_sardines_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.34))
	_sardines_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_sardines_label)

	# Cuerpo: lista (izq) + detalle (der).
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	col.add_child(body)

	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(420, 420)
	MenuTheme.style_panel(list_panel, MenuTheme.CYAN, MenuTheme.PANEL_BG_SOFT)
	body.add_child(list_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	body.add_child(_build_detail_panel())

	# Pie: mensaje + Cerrar.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	col.add_child(footer)
	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", 16)
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_message_label)
	var close_btn := MenuTheme.make_button("Cerrar", MenuTheme.TEXT_DIM)
	close_btn.custom_minimum_size = Vector2(200, 44)
	close_btn.pressed.connect(_on_close_pressed)
	footer.add_child(close_btn)

	_build_rows()


func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 420)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuTheme.style_panel(panel, MenuTheme.ACCENT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 26)
	_detail_name.add_theme_color_override("font_color", MenuTheme.TEXT)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_name)

	_detail_level = Label.new()
	_detail_level.add_theme_font_size_override("font_size", 16)
	_detail_level.add_theme_color_override("font_color", MenuTheme.CYAN)
	v.add_child(_detail_level)

	v.add_child(_hsep())

	_detail_current = Label.new()
	_detail_current.add_theme_font_size_override("font_size", 17)
	_detail_current.add_theme_color_override("font_color", Color(0.74, 0.92, 1.0))
	_detail_current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_current)

	_detail_next = Label.new()
	_detail_next.add_theme_font_size_override("font_size", 17)
	_detail_next.add_theme_color_override("font_color", Color(0.66, 1.0, 0.72))
	_detail_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_next)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	_detail_cost = Label.new()
	_detail_cost.add_theme_font_size_override("font_size", 18)
	_detail_cost.add_theme_color_override("font_color", Color(0.95, 0.82, 0.34))
	_detail_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_detail_cost)

	_buy_button = MenuTheme.make_button("Comprar", MenuTheme.ZOMBIE)
	_buy_button.pressed.connect(_on_buy_pressed)
	v.add_child(_buy_button)
	return panel


func _build_rows() -> void:
	if _meta == null:
		return
	for up in _meta.get_upgrades():
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 52)
		row.focus_mode = Control.FOCUS_ALL
		row.clip_text = true
		_style_row(row, up.icon_color, false)
		row.pressed.connect(_on_row_selected.bind(up.id))
		row.pressed.connect(func() -> void: _play_ui(&"ui_click"))

		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.add_theme_constant_override("separation", 10)
		hb.offset_left = 10
		hb.offset_right = -10
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hb)

		var icon := Label.new()
		icon.text = CATEGORY_ICON.get(up.category, "●")
		icon.add_theme_font_size_override("font_size", 22)
		icon.add_theme_color_override("font_color", up.icon_color.lightened(0.2))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(icon)

		var name_label := Label.new()
		name_label.text = up.display_name
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", MenuTheme.TEXT)
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(name_label)

		var level_label := Label.new()
		level_label.add_theme_font_size_override("font_size", 15)
		level_label.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(level_label)

		var cost_label := Label.new()
		cost_label.add_theme_font_size_override("font_size", 15)
		cost_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.34))
		cost_label.custom_minimum_size = Vector2(70, 0)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(cost_label)

		_list_box.add_child(row)
		_row_buttons.append({
			"id": up.id,
			"button": row,
			"level_label": level_label,
			"cost_label": cost_label,
			"accent": up.icon_color,
		})
	if not _row_buttons.is_empty():
		_selected_id = _row_buttons[0]["id"]


func open() -> void:
	visible = true
	_message_label.text = ""
	if _selected_id == &"" and not _row_buttons.is_empty():
		_selected_id = _row_buttons[0]["id"]
	refresh()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _on_close_pressed() -> void:
	_play_ui(&"ui_click")
	if on_close.is_valid():
		on_close.call()
	else:
		close()


func _on_row_selected(id: StringName) -> void:
	_selected_id = id
	refresh()


func _on_buy_pressed() -> void:
	_play_ui(&"ui_click")
	if _meta == null or _selected_id == &"":
		return
	var up = _meta.get_upgrade_by_id(_selected_id)
	if up == null:
		return
	var level: int = _meta.get_level(_selected_id)
	var cost: int = _meta.get_next_cost(up)
	if cost < 0:
		_show_message("Mejora al maximo", Color(1.0, 0.82, 0.45))
		return
	if _save != null and _save.get_sardines() < cost:
		_show_message("No tienes suficientes Sardinas", Color(1.0, 0.58, 0.58))
		return
	if _meta.purchase(_selected_id):
		_show_message("%s mejorada a Nv. %d" % [up.display_name, level + 1], Color(0.6, 1.0, 0.7))
	else:
		_show_message("No se pudo comprar", Color(1.0, 0.58, 0.58))
	refresh()


func _show_message(text: String, color: Color) -> void:
	_message_label.add_theme_color_override("font_color", color)
	_message_label.text = text


func refresh() -> void:
	if _meta == null or _save == null:
		return
	var sardines: int = _save.get_sardines()
	_sardines_label.text = "Sardinas: %d" % sardines

	# Filas compactas. Las bloqueadas por historia se atenuan y muestran candado.
	for entry in _row_buttons:
		var up = _meta.get_upgrade_by_id(entry["id"])
		if up == null:
			continue
		var unlocked: bool = not _meta.has_method("is_upgrade_unlocked") or _meta.is_upgrade_unlocked(up)
		var level: int = _meta.get_level(up.id)
		if unlocked:
			entry["level_label"].text = "%d/%d" % [level, up.max_level]
			var cost: int = _meta.get_next_cost(up)
			entry["cost_label"].text = "MAX" if cost < 0 else str(cost)
			entry["button"].modulate = Color(1, 1, 1, 1)
		else:
			entry["level_label"].text = "🔒"
			entry["cost_label"].text = "Cap. %d" % up.unlock_story_chapter
			entry["button"].modulate = Color(0.62, 0.64, 0.7, 0.85)
		_style_row(entry["button"], entry["accent"] if unlocked else Color(0.3, 0.31, 0.36), entry["id"] == _selected_id)

	_refresh_detail(sardines)


func _refresh_detail(sardines: int) -> void:
	if _selected_id == &"":
		return
	var up = _meta.get_upgrade_by_id(_selected_id)
	if up == null:
		return
	var level: int = _meta.get_level(up.id)
	_detail_name.text = up.display_name
	_detail_level.text = "Nivel %d / %d   %s" % [level, up.max_level, _progress_bar(level, up.max_level)]
	_detail_current.text = "Actual: %s" % _meta.format_effect(up, level)
	# Mejora bloqueada por la historia: sin compra hasta completar el capitulo.
	if _meta.has_method("is_upgrade_unlocked") and not _meta.is_upgrade_unlocked(up):
		_detail_next.text = up.description
		_detail_cost.text = "🔒 Se desbloquea: Capitulo %d de la Historia" % up.unlock_story_chapter
		_buy_button.text = "Bloqueado"
		_buy_button.disabled = true
		return
	var cost: int = _meta.get_next_cost(up)
	if cost < 0:
		_detail_next.text = "Siguiente: —"
		_detail_cost.text = "Mejora al maximo"
		_buy_button.text = "MAX"
		_buy_button.disabled = true
	else:
		_detail_next.text = "Siguiente: %s" % _meta.format_effect(up, level + 1)
		_detail_cost.text = "Costo: %d Sardinas" % cost
		_buy_button.disabled = sardines < cost
		_buy_button.text = "Comprar" if sardines >= cost else "Sin Sardinas"


func _style_row(button: Button, accent: Color, selected: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.16, 0.17, 0.22, 0.98) if selected else Color(0.10, 0.11, 0.15, 0.96)
		if state == "hover":
			box.bg_color = Color(0.16, 0.17, 0.22, 0.98)
		box.border_color = accent if selected else Color(0.22, 0.24, 0.3)
		box.set_border_width_all(2 if selected else 1)
		box.set_corner_radius_all(8)
		box.set_content_margin_all(6)
		button.add_theme_stylebox_override(state, box)


func _progress_bar(level: int, max_level: int) -> String:
	var text: String = ""
	for i in max_level:
		text += "●" if i < level else "○"
	return text


func _hsep() -> Control:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.custom_minimum_size = Vector2(0, 2)
	return line


func _play_ui(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)
