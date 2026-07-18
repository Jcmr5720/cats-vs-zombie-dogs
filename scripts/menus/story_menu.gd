extends Control
## Pantalla del Modo Historia (rediseño Steam). Tres zonas claras: barra superior
## con retorno + progreso, camino de capítulos como tarjetas limpias (estado por
## color/icono, sin texto apretado) y un panel de detalle con una acción primaria
## "Jugar". La dificultad se elige en un overlay centrado al pulsar Jugar. Toda la
## lógica de StoryCampaign (desbloqueos, tiers, recompensas, abandono) se conserva.

@warning_ignore("shadowed_global_identifier")
const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
@warning_ignore("shadowed_global_identifier")
const StoryCampaign = preload("res://scripts/story/story_campaign.gd")

var _save: Node
var _chapters: Array[ChapterData] = []
var _selected: ChapterData
var _anim_time: float = 0.0

var _chapter_row: HBoxContainer
var _detail_panel: PanelContainer
var _detail_title: Label
var _detail_tagline: Label
var _detail_objective: Control
var _detail_reward: Label
var _detail_stars: HBoxContainer
var _play_button: Button
var _cinematic_button: Button
var _chips_box: HBoxContainer
var _abandon_button: Button
var _abandon_stage: int = 0
var _difficulty_panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_save = get_node_or_null("/root/SaveManager")
	_chapters = StoryCampaign.load_chapters()
	_build_ui()
	# Selección inicial: el capítulo que toca continuar (Jugar = continuar historia).
	var pending: ChapterData = StoryCampaign.first_pending_chapter(_save, _chapters, _current_tier())
	_select_chapter(pending if pending != null else _chapters[0])
	MenuTheme.add_fade_in(self)


func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(_difficulty_panel):
			MenuTheme.close_overlay(_difficulty_panel)
			return
		GameFlow.return_to_main_menu()


func _current_tier() -> int:
	return StoryCampaign.get_story_difficulty(_save)


## Fondo: degradado + luna + tejados con gatos (ambiente narrativo). Identidad.
func _draw() -> void:
	var s: Vector2 = get_viewport_rect().size
	for i in 20:
		var t: float = float(i) / 19.0
		draw_rect(Rect2(0, s.y * t, s.x, s.y / 20.0 + 1.0), MenuTheme.BG_TOP.lerp(MenuTheme.BG_BOTTOM, t), true)
	draw_circle(Vector2(s.x * 0.88, s.y * 0.12), 40.0, Color(0.92, 0.94, 0.85, 0.55))
	draw_circle(Vector2(s.x * 0.88, s.y * 0.12), 56.0, Color(0.92, 0.94, 0.85, 0.07))
	for i in 10:
		var w: float = s.x / 10.0
		var h: float = s.y * (0.05 + 0.045 * abs(sin(float(i) * 2.9)))
		draw_rect(Rect2(float(i) * w, s.y * 0.2 - h, w - 4, h), Color(0.05, 0.055, 0.09, 0.8), true)
	for i in 8:
		var bx: float = s.x * (0.08 + float(i) * 0.12)
		var by: float = s.y * 0.94 + sin(_anim_time * 0.5 + float(i) * 1.3) * 8.0
		var a: float = 0.04 + 0.02 * sin(_anim_time * 0.8 + float(i))
		draw_circle(Vector2(bx, by), 6.0, Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, a))


func _build_ui() -> void:
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

	# --- Barra superior: retorno + título + chips de progreso ---
	var top := MenuTheme.make_top_bar("Historia", func() -> void: GameFlow.return_to_main_menu())
	col.add_child(top)
	_chips_box = top.get_node("Actions")
	_refresh_chips()

	# --- Camino de capítulos ---
	col.add_child(MenuTheme.make_section_header("Capítulos", MenuTheme.ACCENT))
	_chapter_row = HBoxContainer.new()
	_chapter_row.add_theme_constant_override("separation", MenuTheme.GAP_M)
	_chapter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_chapter_row)
	_build_chapter_nodes()

	# --- Panel de detalle del capítulo seleccionado ---
	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	MenuTheme.style_panel(_detail_panel, MenuTheme.ACCENT, MenuTheme.PANEL_BG_SOFT)
	col.add_child(_detail_panel)
	var detail := HBoxContainer.new()
	detail.add_theme_constant_override("separation", MenuTheme.GAP_XL)
	_detail_panel.add_child(detail)

	# Columna izquierda: información del capítulo.
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", MenuTheme.GAP_S)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(info)
	_detail_title = MenuTheme.make_title("", MenuTheme.FS_H2, MenuTheme.TEXT)
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(_detail_title)
	_detail_tagline = MenuTheme.make_label("", MenuTheme.FS_BODY, MenuTheme.TEXT_DIM)
	_detail_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_detail_tagline)
	_detail_objective = HBoxContainer.new()
	(_detail_objective as HBoxContainer).add_theme_constant_override("separation", MenuTheme.GAP_S)
	info.add_child(_detail_objective)
	var stars_row := HBoxContainer.new()
	stars_row.add_theme_constant_override("separation", MenuTheme.GAP_S)
	info.add_child(stars_row)
	stars_row.add_child(MenuTheme.make_label("Dificultades:", MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM))
	_detail_stars = HBoxContainer.new()
	_detail_stars.add_theme_constant_override("separation", MenuTheme.GAP_XS)
	_detail_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stars_row.add_child(_detail_stars)
	_detail_reward = MenuTheme.make_label("", MenuTheme.FS_BODY, MenuTheme.GOLD)
	info.add_child(_detail_reward)

	# Columna derecha: acción primaria + secundaria.
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", MenuTheme.GAP_S)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	detail.add_child(actions)
	_play_button = MenuTheme.make_button("Jugar", MenuTheme.ACCENT, &"primary")
	_play_button.custom_minimum_size = Vector2(230, 54)
	_play_button.add_theme_font_size_override("font_size", UIFonts.scaled(MenuTheme.FS_H2))
	_play_button.pressed.connect(_on_play_pressed)
	actions.add_child(_play_button)
	_cinematic_button = MenuTheme.make_button("Cinemática", MenuTheme.CYAN, &"secondary")
	_cinematic_button.custom_minimum_size = Vector2(230, 44)
	_cinematic_button.pressed.connect(_on_cinematic_pressed)
	actions.add_child(_cinematic_button)

	# --- Pie discreto: omitir cinemáticas + abandonar campaña ---
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", MenuTheme.GAP_M)
	col.add_child(footer)
	var skip := MenuTheme.make_setting_toggle("Omitir cinemáticas", "skip_cinematics")
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(skip)
	_abandon_button = MenuTheme.make_button("Abandonar campaña", MenuTheme.DANGER, &"ghost")
	_abandon_button.custom_minimum_size = Vector2(210, 42)
	_abandon_button.tooltip_text = "Reinicia capítulos, first-clears y desbloqueos de campaña."
	_abandon_button.pressed.connect(_on_abandon_pressed)
	footer.add_child(_abandon_button)


func _refresh_chips() -> void:
	for child in _chips_box.get_children():
		child.queue_free()
	var sardines: String = str(_save.get_sardines()) if _save != null and _save.has_method("get_sardines") else "0"
	_chips_box.add_child(MenuTheme.make_chip("%s/%d" % [StoryCampaign.chapters_cleared(_save), StoryCampaign.TOTAL_CHAPTERS], MenuTheme.ZOMBIE, &"check"))
	_chips_box.add_child(MenuTheme.make_chip(sardines, MenuTheme.GOLD, &"sardine"))
	if StoryCampaign.is_campaign_completed(_save):
		_chips_box.add_child(MenuTheme.make_chip("Completa", MenuTheme.GOLD, &"star"))


## Nodo-tarjeta por capítulo: número grande + título + estado (candado / estrellas
## por dificultad superada). Sin texto multilínea apretado.
func _build_chapter_nodes() -> void:
	for child in _chapter_row.get_children():
		child.queue_free()
	var tier: int = _current_tier()
	for chapter in _chapters:
		_chapter_row.add_child(_make_chapter_node(chapter, tier))


func _make_chapter_node(chapter: ChapterData, tier: int) -> Button:
	var unlocked: bool = StoryCampaign.is_chapter_unlocked(_save, chapter.number)
	var accent: Color = chapter.accent_color if unlocked else Color(0.30, 0.31, 0.36)
	var selected: bool = _selected == chapter
	var node := Button.new()
	node.custom_minimum_size = Vector2(132, 150)
	node.disabled = not unlocked
	node.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = accent.lerp(Color(0.08, 0.09, 0.13), 0.86 if not selected else 0.72)
		if state == "hover" and unlocked:
			box.bg_color = accent.lerp(Color(0.08, 0.09, 0.13), 0.66)
		box.border_color = accent if unlocked else Color(0.25, 0.26, 0.30)
		box.set_border_width_all(3 if selected else 1)
		box.set_corner_radius_all(MenuTheme.RADIUS + 2)
		box.set_content_margin_all(MenuTheme.GAP_S)
		node.add_theme_stylebox_override(state, box)
	node.tooltip_text = chapter.tagline if unlocked else "Completa el capítulo %d para desbloquear" % (chapter.number - 1)
	if unlocked:
		node.pressed.connect(_select_chapter.bind(chapter))

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", MenuTheme.GAP_XS)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(v)

	var num := MenuTheme.make_label(str(chapter.number), MenuTheme.FS_H1, accent if unlocked else MenuTheme.TEXT_DIM)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(num)

	if not unlocked:
		var lock := IconDrawer.new()
		lock.icon_type = &"lock"
		lock.accent = MenuTheme.TEXT_DIM
		lock.custom_minimum_size = Vector2(26, 26)
		lock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(lock)
		return node

	var title := MenuTheme.make_label(chapter.title, MenuTheme.FS_MICRO, MenuTheme.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)

	# Estrellas por dificultad superada (pips dorados), o check si toca este tier.
	var cleared: int = 0
	for t in StoryCampaign.DIFFICULTIES.size():
		if StoryCampaign.is_tier_cleared(_save, chapter.id, t):
			cleared += 1
	var pips := MenuTheme.make_progress_pips(cleared, StoryCampaign.DIFFICULTIES.size(), MenuTheme.GOLD, 9)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pips)
	if StoryCampaign.is_tier_cleared(_save, chapter.id, tier):
		var check := IconDrawer.new()
		check.icon_type = &"check"
		check.accent = MenuTheme.ZOMBIE
		check.custom_minimum_size = Vector2(20, 20)
		check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(check)
	return node


func _select_chapter(chapter: ChapterData) -> void:
	_selected = chapter
	_build_chapter_nodes()
	_update_detail()


func _update_detail() -> void:
	if _selected == null:
		return
	var tier: int = _current_tier()
	var d: Dictionary = StoryCampaign.get_difficulty(tier)
	_detail_title.text = "Capítulo %d — %s" % [_selected.number, _selected.title]
	_detail_title.add_theme_color_override("font_color", _selected.accent_color)
	_detail_tagline.text = "«%s»" % _selected.tagline

	# Objetivo y zona como chips en vez de una línea larga.
	for child in _detail_objective.get_children():
		child.queue_free()
	var objective: String = _selected.map.objective_description if _selected.map != null else ""
	if objective != "":
		_detail_objective.add_child(MenuTheme.make_chip(objective, MenuTheme.CYAN, &"check"))
	if _selected.map != null:
		_detail_objective.add_child(MenuTheme.make_chip(_selected.map.display_name, MenuTheme.PURPLE, &"map"))

	# Estrellas por dificultad para este capítulo.
	for child in _detail_stars.get_children():
		child.queue_free()
	for t in StoryCampaign.DIFFICULTIES.size():
		var star := IconDrawer.new()
		star.icon_type = &"star"
		star.accent = MenuTheme.GOLD
		star.dimmed = not StoryCampaign.is_tier_cleared(_save, _selected.id, t)
		star.custom_minimum_size = Vector2(18, 18)
		_detail_stars.add_child(star)

	if StoryCampaign.is_tier_cleared(_save, _selected.id, tier):
		_detail_reward.text = "Completado en %s · rejuega por sardinas x%.1f" % [str(d["name"]), float(d["reward"])]
		_detail_reward.add_theme_color_override("font_color", MenuTheme.ZOMBIE)
	else:
		_detail_reward.text = "Primera vez en %s: +%d sardinas" % [str(d["name"]), int(round(_selected.first_clear_reward * float(d["reward"])))]
		_detail_reward.add_theme_color_override("font_color", MenuTheme.GOLD)

	_cinematic_button.visible = not _selected.cinematic_panels.is_empty()


func _on_play_pressed() -> void:
	if _selected != null:
		_show_difficulty_prompt(_selected)


func _on_cinematic_pressed() -> void:
	if _selected != null and not _selected.cinematic_panels.is_empty():
		GameFlow.play_cinematic(_selected.cinematic_panels, _selected.accent_color, GameFlow.STORY_MENU)


## Overlay centrado (responsive) para elegir dificultad antes de jugar.
func _show_difficulty_prompt(chapter: ChapterData) -> void:
	if chapter == null:
		return
	if is_instance_valid(_difficulty_panel):
		MenuTheme.close_overlay(_difficulty_panel)
	_difficulty_panel = MenuTheme.make_overlay(self, chapter.accent_color, Vector2(620, 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_M)
	_difficulty_panel.add_child(col)
	var title := MenuTheme.make_title("Capítulo %d: %s" % [chapter.number, chapter.title], MenuTheme.FS_H2, chapter.accent_color)
	col.add_child(title)
	col.add_child(MenuTheme.make_label("Elige la dificultad para esta partida.", MenuTheme.FS_BODY, MenuTheme.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", MenuTheme.GAP_M)
	grid.add_theme_constant_override("v_separation", MenuTheme.GAP_M)
	col.add_child(grid)
	for tier in StoryCampaign.DIFFICULTIES.size():
		grid.add_child(_difficulty_start_button(chapter, tier))
	var cancel := MenuTheme.make_button("Cancelar", MenuTheme.TEXT_DIM, &"ghost")
	cancel.custom_minimum_size = Vector2(180, 42)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func() -> void: MenuTheme.close_overlay(_difficulty_panel))
	col.add_child(cancel)


func _difficulty_start_button(chapter: ChapterData, tier: int) -> Button:
	var d: Dictionary = StoryCampaign.get_difficulty(tier)
	var button := MenuTheme.make_button(str(d["name"]), d["color"], &"primary")
	button.custom_minimum_size = Vector2(285, 56)
	var reward: int = int(round(chapter.first_clear_reward * float(d["reward"])))
	button.tooltip_text = "Presión x%.2f · Vida x%.2f · Daño x%.2f · First-clear: %d sardinas" % [
		float(d["pressure"]), float(d["health"]), float(d["damage"]), reward]
	button.pressed.connect(func() -> void:
		MenuTheme.close_overlay(_difficulty_panel)
		GameFlow.start_story_chapter(chapter, tier))
	return button


func _on_abandon_pressed() -> void:
	if _save == null or not _save.has_method("abandon_story_campaign"):
		return
	_abandon_stage += 1
	if _abandon_stage == 1:
		_abandon_button.text = "Confirmar abandono"
		MenuTheme.style_button(_abandon_button, MenuTheme.DANGER, &"danger")
		var audio_warn: Node = get_node_or_null("/root/AudioManager")
		if audio_warn != null and audio_warn.has_method("play_ui"):
			audio_warn.play_ui(&"ui_error")
		return
	_save.abandon_story_campaign()
	_abandon_stage = 0
	_abandon_button.text = "Campaña reiniciada"
	_abandon_button.disabled = true
	_refresh_chips()
	_build_chapter_nodes()
	if not _chapters.is_empty():
		_select_chapter(_chapters[0])
