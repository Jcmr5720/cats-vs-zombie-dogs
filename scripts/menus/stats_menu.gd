extends Control
## Pantalla de estadisticas/progreso (Fase 08). Muestra los datos guardados en el
## SaveManager. Tolera saves antiguos: los campos nuevos aparecen en 0.

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")

const MAP_NAMES: Dictionary = {
	"neighborhood": "Barrio Gatuno",
	"park": "Parque Abandonado",
	"industrial_alley": "Callejon Industrial",
}

var _save: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(640, 0)
	center.add_child(col)

	col.add_child(MenuTheme.make_title("Progreso", 40, MenuTheme.CYAN))

	# Tarjetas grandes con los datos clave.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)
	grid.add_child(_stat_card("Partidas", str(_get_stat("total_runs", 0)), MenuTheme.CYAN))
	grid.add_child(_stat_card("Victorias", str(_get_stat("total_victories", 0)), MenuTheme.ZOMBIE))
	grid.add_child(_stat_card("Sardinas", str(_get_stat("total_sardines", 0)), MenuTheme.ACCENT))
	grid.add_child(_stat_card("Enemigos", str(_get_stat("total_kills", 0)), Color(0.85, 0.5, 0.5)))
	grid.add_child(_stat_card("Gatos", str(_get_stat("total_cats_rescued", 0)), MenuTheme.PURPLE))
	grid.add_child(_stat_card("Jefes", str(_get_stat("total_bosses", 0)), Color(0.9, 0.6, 0.4)))
	grid.add_child(_stat_card("Mejor nivel", str(_get_stat("best_level", 0)), MenuTheme.CYAN))
	grid.add_child(_stat_card("Mini-jefes", str(_get_stat("total_minibosses", 0)), MenuTheme.TEXT_DIM))

	# Misiones persistentes con recompensa de sardinas.
	col.add_child(MenuTheme.make_title("Misiones", 20, Color(1.0, 0.78, 0.25)))
	col.add_child(_build_missions_list())

	# Detalle por mapa en seccion secundaria.
	col.add_child(MenuTheme.make_title("Mejores tiempos por mapa", 20, MenuTheme.ACCENT))
	var best: Dictionary = _get_stat("best_time_by_map", {})
	var unlocked: Array = _get_stat("unlocked_maps", [])
	var completed: Array = _get_stat("completed_maps", [])
	for map_id in MAP_NAMES:
		var name: String = MAP_NAMES[map_id]
		var state: String = "Bloqueado"
		if completed.has(map_id):
			state = "Completado"
		elif unlocked.has(map_id):
			state = "Desbloqueado"
		var time_text: String = _format_time(float(best.get(map_id, 0.0))) if best.has(map_id) else "--:--"
		col.add_child(_row(name, "%s   ·   %s" % [time_text, state]))

	col.add_child(_spacer(8))
	var back := MenuTheme.make_button("Volver  (ESC)", MenuTheme.TEXT_DIM)
	back.pressed.connect(func() -> void: GameFlow.return_to_main_menu())
	col.add_child(back)


## Lista scrolleable de misiones: nombre + descripcion a la izquierda, progreso o
## check con recompensa a la derecha.
func _build_missions_list() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	var missions: Node = get_node_or_null("/root/Missions")
	if missions == null or not missions.has_method("get_missions_view"):
		return scroll
	for m in missions.get_missions_view():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 0)
		var name_label := Label.new()
		name_label.text = str(m["name"])
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", MenuTheme.ZOMBIE if m["done"] else MenuTheme.TEXT)
		left.add_child(name_label)
		var desc := Label.new()
		desc.text = str(m["desc"])
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		left.add_child(desc)
		row.add_child(left)
		var status := Label.new()
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status.add_theme_font_size_override("font_size", 14)
		if m["done"]:
			status.text = "✓  +%d 🐟" % int(m["reward"])
			status.add_theme_color_override("font_color", MenuTheme.ZOMBIE)
		else:
			status.text = "%d / %d   (+%d 🐟)" % [int(m["progress"]), int(m["target"]), int(m["reward"])]
			status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		row.add_child(status)
		list.add_child(row)
	return scroll


## Tarjeta grande con un dato clave.
func _stat_card(title: String, value: String, accent: Color) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(146, 92)
	MenuTheme.style_panel(panel, accent, MenuTheme.PANEL_BG_SOFT)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var val := Label.new()
	val.text = value
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", 30)
	val.add_theme_color_override("font_color", accent.lightened(0.15))
	v.add_child(val)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	v.add_child(t)
	return panel


func _get_stat(key: String, default_value: Variant) -> Variant:
	if _save != null and _save.has_method("get_value"):
		return _save.get_value(key, default_value)
	return default_value


func _row(title: String, value: String) -> Control:
	var hb := HBoxContainer.new()
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", MenuTheme.TEXT)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(val)
	return hb


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
