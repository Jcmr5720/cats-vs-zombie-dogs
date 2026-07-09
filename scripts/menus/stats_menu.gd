extends Control
## Pantalla de estadísticas/progreso (rediseño Steam). Barra superior con retorno,
## contenido en scroll (nunca se recorta), tarjetas de dato con icono, misiones con
## barra de progreso + badge de recompensa y mapas como mini-tarjetas con estado.
## Tolera saves antiguos: los campos nuevos aparecen en 0.

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const StoryCampaign = preload("res://scripts/story/story_campaign.gd")
const FreePlayScore = preload("res://scripts/systems/free_play_score.gd")

const MAP_NAMES: Dictionary = {
	"neighborhood": "Barrio Gatuno",
	"park": "Parque Abandonado",
	"industrial_alley": "Callejón Industrial",
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

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", MenuTheme.GAP_XL + 12)
	margin.add_theme_constant_override("margin_right", MenuTheme.GAP_XL + 12)
	margin.add_theme_constant_override("margin_top", MenuTheme.GAP_L)
	margin.add_theme_constant_override("margin_bottom", MenuTheme.GAP_L)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", MenuTheme.GAP_L)
	margin.add_child(outer)
	outer.add_child(MenuTheme.make_top_bar("Progreso", func() -> void: GameFlow.return_to_main_menu(), MenuTheme.CYAN))

	# Contenido en scroll: nunca se recorta.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_L)
	var scroll := MenuTheme.wrap_scrollable(col)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	# Tarjetas grandes con los datos clave.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", MenuTheme.GAP_M)
	grid.add_theme_constant_override("v_separation", MenuTheme.GAP_M)
	col.add_child(grid)
	grid.add_child(MenuTheme.make_stat_card(str(_get_stat("total_runs", 0)), "Partidas", MenuTheme.CYAN, &"map"))
	grid.add_child(MenuTheme.make_stat_card(str(_get_stat("total_victories", 0)), "Victorias", MenuTheme.ZOMBIE, &"check"))
	grid.add_child(MenuTheme.make_stat_card(str(_get_stat("total_sardines", 0)), "Sardinas", MenuTheme.GOLD, &"sardine"))
	grid.add_child(MenuTheme.make_stat_card(str(_get_stat("total_kills", 0)), "Enemigos", MenuTheme.DANGER, &"boss"))
	grid.add_child(MenuTheme.make_stat_card(str(_get_stat("total_cats_rescued", 0)), "Gatos", MenuTheme.PURPLE, &"companion"))
	grid.add_child(MenuTheme.make_stat_card(str(_get_stat("total_bosses", 0)), "Jefes", Color(0.9, 0.6, 0.4), &"boss"))
	grid.add_child(MenuTheme.make_stat_card(str(_get_stat("best_level", 0)), "Mejor nivel", MenuTheme.CYAN, &"upgrade"))
	grid.add_child(MenuTheme.make_stat_card(str(_get_stat("total_minibosses", 0)), "Mini-jefes", MenuTheme.TEXT_DIM, &"shield"))

	# Misiones con recompensa de sardinas.
	col.add_child(MenuTheme.make_section_header("Misiones", MenuTheme.GOLD))
	col.add_child(_build_missions_list())

	# Mapas como mini-tarjetas con estado.
	col.add_child(MenuTheme.make_section_header("Zonas y mejores tiempos", MenuTheme.ACCENT))
	col.add_child(_build_maps_grid())


func _build_missions_list() -> Control:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", MenuTheme.GAP_S)
	var missions: Node = get_node_or_null("/root/Missions")
	if missions == null or not missions.has_method("get_missions_view"):
		return list
	for m in missions.get_missions_view():
		list.add_child(_mission_row(m))
	return list


func _mission_row(m: Dictionary) -> Control:
	var done: bool = bool(m["done"])
	var panel := PanelContainer.new()
	MenuTheme.style_panel(panel, MenuTheme.ZOMBIE if done else MenuTheme.GOLD, MenuTheme.PANEL_BG_SOFT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.GAP_M)
	panel.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", MenuTheme.GAP_XS)
	row.add_child(left)
	left.add_child(MenuTheme.make_label(str(m["name"]), MenuTheme.FS_H3, MenuTheme.ZOMBIE if done else MenuTheme.TEXT))
	left.add_child(MenuTheme.make_label(str(m["desc"]), MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM))
	if not done:
		var bar := MenuTheme.make_progress_bar(float(m["progress"]), float(m["target"]), MenuTheme.GOLD, 240, 8)
		left.add_child(bar)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	if done:
		var check := IconDrawer.new()
		check.icon_type = &"check"
		check.accent = MenuTheme.ZOMBIE
		check.custom_minimum_size = Vector2(24, 24)
		check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		right.add_child(check)
	else:
		var progress := MenuTheme.make_label("%d / %d" % [int(m["progress"]), int(m["target"])], MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM)
		progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(progress)
	right.add_child(MenuTheme.make_chip("+%d" % int(m["reward"]), MenuTheme.GOLD, &"sardine"))
	return panel


func _build_maps_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", MenuTheme.GAP_M)
	grid.add_theme_constant_override("v_separation", MenuTheme.GAP_M)
	var best: Dictionary = _get_stat("best_time_by_map", {})
	var unlocked: Array = _get_stat("unlocked_maps", [])
	var completed: Array = _get_stat("completed_maps", [])
	for map_id in MAP_NAMES:
		var state_text: String = "Bloqueado"
		var state_color: Color = MenuTheme.TEXT_DIM
		var state_icon: StringName = &"lock"
		if completed.has(map_id):
			state_text = "Completado"
			state_color = MenuTheme.ZOMBIE
			state_icon = &"check"
		elif unlocked.has(map_id):
			state_text = "Disponible"
			state_color = MenuTheme.CYAN
			state_icon = &"map"
		var time_text: String = _format_time(float(best.get(map_id, 0.0))) if best.has(map_id) else "--:--"
		# Mejor puntuación de Partida libre (máximo entre las 4 dificultades).
		var rec: Dictionary = FreePlayScore.get_best_any(_save, map_id)
		var record_text: String = "--"
		if int(rec.get("score", 0)) > 0:
			record_text = "%d (%s)" % [int(rec["score"]), str(StoryCampaign.get_difficulty(int(rec["tier"]))["name"])]
		grid.add_child(_map_card(MAP_NAMES[map_id], state_text, state_color, state_icon, time_text, record_text))
	return grid


func _map_card(map_name: String, state_text: String, state_color: Color, state_icon: StringName, time_text: String, record_text: String = "--") -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuTheme.style_panel(panel, state_color, MenuTheme.PANEL_BG_SOFT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", MenuTheme.GAP_S)
	panel.add_child(v)
	v.add_child(MenuTheme.make_label(map_name, MenuTheme.FS_H3, MenuTheme.TEXT))
	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", MenuTheme.GAP_S)
	v.add_child(state_row)
	state_row.add_child(MenuTheme.make_chip(state_text, state_color, state_icon))
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", MenuTheme.GAP_XS + 1)
	v.add_child(time_row)
	var clock := IconDrawer.new()
	clock.icon_type = &"clock"
	clock.accent = MenuTheme.TEXT_DIM
	clock.custom_minimum_size = Vector2(16, 16)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_row.add_child(clock)
	time_row.add_child(MenuTheme.make_label(time_text, MenuTheme.FS_BODY, MenuTheme.TEXT_DIM))
	# Mejor puntuación de Partida libre.
	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", MenuTheme.GAP_XS + 1)
	v.add_child(score_row)
	var star := IconDrawer.new()
	star.icon_type = &"star"
	star.accent = MenuTheme.GOLD
	star.custom_minimum_size = Vector2(16, 16)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_row.add_child(star)
	score_row.add_child(MenuTheme.make_label("Récord: %s" % record_text, MenuTheme.FS_BODY, MenuTheme.GOLD))
	return panel


func _get_stat(key: String, default_value: Variant) -> Variant:
	if _save != null and _save.has_method("get_value"):
		return _save.get_value(key, default_value)
	return default_value


func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
