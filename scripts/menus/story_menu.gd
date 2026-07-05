extends Control
## Pantalla del Modo Historia (Fase 09): selector de dificultad global de la
## campaña, camino de 6 capitulos (bloqueado/disponible/completado con estrellas
## por dificultad superada) y panel de detalle con "Jugar capitulo" y "Ver
## cinematica". Todo procedural con MenuTheme, sin assets.

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const StoryCampaign = preload("res://scripts/story/story_campaign.gd")

var _save: Node
var _chapters: Array[ChapterData] = []
var _selected: ChapterData
var _anim_time: float = 0.0

var _difficulty_row: HBoxContainer
var _chapter_row: HBoxContainer
var _detail_panel: PanelContainer
var _detail_title: Label
var _detail_tagline: Label
var _detail_objective: Label
var _detail_reward: Label
var _play_button: Button
var _cinematic_button: Button
var _chips_box: HBoxContainer
var _skip_cinematics_button: CheckBox
var _difficulty_overlay: Control
var _abandon_button: Button
var _abandon_stage: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_save = get_node_or_null("/root/SaveManager")
	_chapters = StoryCampaign.load_chapters()
	_build_ui()
	# Seleccion inicial: el capitulo que toca continuar.
	var pending: ChapterData = StoryCampaign.first_pending_chapter(_save, _chapters, _current_tier())
	_select_chapter(pending if pending != null else _chapters[0])
	MenuTheme.add_fade_in(self)


func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameFlow.return_to_main_menu()


func _current_tier() -> int:
	return StoryCampaign.get_story_difficulty(_save)


## Fondo: degradado + luna + siluetas de tejados con gatos (ambiente narrativo).
func _draw() -> void:
	var s: Vector2 = get_viewport_rect().size
	for i in 20:
		var t: float = float(i) / 19.0
		draw_rect(Rect2(0, s.y * t, s.x, s.y / 20.0 + 1.0), MenuTheme.BG_TOP.lerp(MenuTheme.BG_BOTTOM, t), true)
	draw_circle(Vector2(s.x * 0.88, s.y * 0.12), 40.0, Color(0.92, 0.94, 0.85, 0.55))
	draw_circle(Vector2(s.x * 0.88, s.y * 0.12), 56.0, Color(0.92, 0.94, 0.85, 0.07))
	# Tejados al fondo.
	for i in 10:
		var w: float = s.x / 10.0
		var h: float = s.y * (0.05 + 0.045 * abs(sin(float(i) * 2.9)))
		draw_rect(Rect2(float(i) * w, s.y * 0.2 - h, w - 4, h), Color(0.05, 0.055, 0.09, 0.8), true)
	# Huellas tenues cruzando la parte baja.
	for i in 8:
		var bx: float = s.x * (0.08 + float(i) * 0.12)
		var by: float = s.y * 0.94 + sin(_anim_time * 0.5 + float(i) * 1.3) * 8.0
		var a: float = 0.04 + 0.02 * sin(_anim_time * 0.8 + float(i))
		draw_circle(Vector2(bx, by), 6.0, Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, a))


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 44)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	# Cabecera: titulo + chips de estado.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.add_theme_constant_override("separation", 2)
	top.add_child(title_block)
	var title := MenuTheme.make_title("Modo Historia", 38, MenuTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_block.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "La gata que abre camino: seis capitulos para recuperar la ciudad."
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	title_block.add_child(subtitle)
	_chips_box = HBoxContainer.new()
	_chips_box.add_theme_constant_override("separation", 8)
	_chips_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_chips_box)
	_refresh_chips()

	# Selector de dificultad global.
	var diff_label := Label.new()
	diff_label.text = "La dificultad se elige antes de iniciar."
	diff_label.add_theme_font_size_override("font_size", 14)
	diff_label.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	col.add_child(diff_label)
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.add_theme_constant_override("separation", 10)
	_difficulty_row.visible = false
	col.add_child(_difficulty_row)
	_build_difficulty_chips()

	# Camino de capitulos.
	_chapter_row = HBoxContainer.new()
	_chapter_row.add_theme_constant_override("separation", 14)
	_chapter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_chapter_row)
	_build_chapter_nodes()

	# Panel de detalle del capitulo seleccionado.
	_detail_panel = PanelContainer.new()
	MenuTheme.style_panel(_detail_panel, MenuTheme.ACCENT, MenuTheme.PANEL_BG_SOFT)
	col.add_child(_detail_panel)
	var detail_col := VBoxContainer.new()
	detail_col.add_theme_constant_override("separation", 6)
	_detail_panel.add_child(detail_col)
	_detail_title = MenuTheme.make_title("", 24, MenuTheme.TEXT)
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail_col.add_child(_detail_title)
	_detail_tagline = Label.new()
	_detail_tagline.add_theme_font_size_override("font_size", 15)
	_detail_tagline.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	detail_col.add_child(_detail_tagline)
	_detail_objective = Label.new()
	_detail_objective.add_theme_font_size_override("font_size", 15)
	_detail_objective.add_theme_color_override("font_color", MenuTheme.TEXT)
	detail_col.add_child(_detail_objective)
	_detail_reward = Label.new()
	_detail_reward.add_theme_font_size_override("font_size", 14)
	_detail_reward.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	detail_col.add_child(_detail_reward)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	detail_col.add_child(buttons)
	_play_button = MenuTheme.make_button("Jugar capitulo", MenuTheme.ACCENT)
	_play_button.custom_minimum_size = Vector2(240, 46)
	_play_button.pressed.connect(_on_play_pressed)
	buttons.add_child(_play_button)
	_cinematic_button = MenuTheme.make_button("Ver cinematica", MenuTheme.CYAN)
	_cinematic_button.custom_minimum_size = Vector2(220, 46)
	_cinematic_button.pressed.connect(_on_cinematic_pressed)
	buttons.add_child(_cinematic_button)

	# Pie: continuar historia + volver.
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)
	var continue_btn := MenuTheme.make_button("Continuar historia", MenuTheme.ZOMBIE)
	continue_btn.custom_minimum_size = Vector2(260, 48)
	continue_btn.pressed.connect(func() -> void:
		var pending: ChapterData = StoryCampaign.first_pending_chapter(_save, _chapters, _current_tier())
		if pending != null:
			_show_difficulty_prompt(pending))
	footer.add_child(continue_btn)
	_skip_cinematics_button = CheckBox.new()
	_skip_cinematics_button.custom_minimum_size = Vector2(210, 48)
	_skip_cinematics_button.add_theme_font_size_override("font_size", 15)
	_skip_cinematics_button.add_theme_color_override("font_color", MenuTheme.TEXT)
	_skip_cinematics_button.toggled.connect(func(enabled: bool) -> void:
		var settings: Node = get_node_or_null("/root/Settings")
		if settings != null and settings.has_method("set_value"):
			settings.set_value("skip_cinematics", enabled)
		_refresh_skip_button())
	footer.add_child(_skip_cinematics_button)
	_refresh_skip_button()
	_abandon_button = MenuTheme.make_button("Abandonar campaña", Color(0.85, 0.35, 0.35))
	_abandon_button.custom_minimum_size = Vector2(230, 48)
	_abandon_button.tooltip_text = "Reinicia capítulos, first-clears y desbloqueos de campaña."
	_abandon_button.pressed.connect(_on_abandon_pressed)
	footer.add_child(_abandon_button)
	var back := MenuTheme.make_button("Volver  (ESC)", MenuTheme.TEXT_DIM)
	back.custom_minimum_size = Vector2(200, 48)
	back.pressed.connect(func() -> void: GameFlow.return_to_main_menu())
	footer.add_child(back)


func _refresh_chips() -> void:
	for child in _chips_box.get_children():
		child.queue_free()
	var sardines: String = str(_save.get_sardines()) if _save != null and _save.has_method("get_sardines") else "0"
	_chips_box.add_child(_make_chip("🐟 %s" % sardines, MenuTheme.ACCENT))
	_chips_box.add_child(_make_chip("Capitulos %d/%d" % [StoryCampaign.chapters_cleared(_save), StoryCampaign.TOTAL_CHAPTERS], MenuTheme.ZOMBIE))
	if StoryCampaign.is_campaign_completed(_save):
		_chips_box.add_child(_make_chip("★ Campaña completa", Color(1.0, 0.85, 0.4)))


func _build_difficulty_chips() -> void:
	for child in _difficulty_row.get_children():
		child.queue_free()
	var current: int = _current_tier()
	for tier in StoryCampaign.DIFFICULTIES.size():
		var d: Dictionary = StoryCampaign.get_difficulty(tier)
		var chip := Button.new()
		chip.text = str(d["name"]) + ("  ✓" if tier == current else "")
		chip.custom_minimum_size = Vector2(150, 40)
		chip.tooltip_text = "Presion x%.2f · Vida x%.2f · Daño x%.2f\nRecompensa de sardinas x%.1f" % [
			float(d["pressure"]), float(d["health"]), float(d["damage"]), float(d["reward"])]
		chip.add_theme_font_size_override("font_size", 15)
		var accent: Color = d["color"]
		for state in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = accent.lerp(Color(0.09, 0.10, 0.14), 0.4 if tier == current else 0.85)
			box.border_color = accent if tier == current else Color(accent.r, accent.g, accent.b, 0.4)
			box.set_border_width_all(2)
			box.set_corner_radius_all(10)
			box.set_content_margin_all(8)
			chip.add_theme_stylebox_override(state, box)
		chip.add_theme_color_override("font_color", Color(1, 1, 1) if tier == current else MenuTheme.TEXT_DIM)
		chip.disabled = true
		_difficulty_row.add_child(chip)


func _on_difficulty_pressed(tier: int) -> void:
	if _save != null and _save.has_method("set_value"):
		_save.set_value("story_difficulty", clampi(tier, 0, 3))
	_build_difficulty_chips()
	_build_chapter_nodes()
	if _selected != null:
		_update_detail()


## Nodo-boton por capitulo con estado visual y estrellas por tiers superados.
func _build_chapter_nodes() -> void:
	for child in _chapter_row.get_children():
		child.queue_free()
	var tier: int = _current_tier()
	for chapter in _chapters:
		var unlocked: bool = StoryCampaign.is_chapter_unlocked(_save, chapter.number)
		var node := Button.new()
		node.custom_minimum_size = Vector2(150, 118)
		node.disabled = not unlocked
		var stars: String = ""
		for t in StoryCampaign.DIFFICULTIES.size():
			stars += "★" if StoryCampaign.is_tier_cleared(_save, chapter.id, t) else "☆"
		var pending_reward: String = ""
		if unlocked and not StoryCampaign.is_tier_cleared(_save, chapter.id, tier):
			var reward_mult: float = float(StoryCampaign.get_difficulty(tier)["reward"])
			pending_reward = "\n+%d 🐟" % int(round(chapter.first_clear_reward * reward_mult))
		node.text = ("%d\n%s\n%s%s" % [chapter.number, chapter.title, stars, pending_reward]) if unlocked \
			else ("%d\n🔒" % chapter.number)
		node.add_theme_font_size_override("font_size", 13)
		var accent: Color = chapter.accent_color if unlocked else Color(0.3, 0.31, 0.36)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = accent.lerp(Color(0.08, 0.09, 0.13), 0.82)
			box.border_color = accent if unlocked else Color(0.25, 0.26, 0.3)
			box.set_border_width_all(2 if _selected != chapter else 3)
			box.set_corner_radius_all(12)
			box.set_content_margin_all(8)
			node.add_theme_stylebox_override(state, box)
		node.add_theme_color_override("font_color", MenuTheme.TEXT if unlocked else MenuTheme.TEXT_DIM)
		if unlocked:
			node.pressed.connect(_select_chapter.bind(chapter))
		node.tooltip_text = chapter.tagline if unlocked else "Completa el capitulo %d para desbloquear" % (chapter.number - 1)
		_chapter_row.add_child(node)


func _select_chapter(chapter: ChapterData) -> void:
	_selected = chapter
	_build_chapter_nodes()
	_update_detail()


func _update_detail() -> void:
	if _selected == null:
		return
	var tier: int = _current_tier()
	var d: Dictionary = StoryCampaign.get_difficulty(tier)
	_detail_title.text = "Capitulo %d — %s" % [_selected.number, _selected.title]
	_detail_title.add_theme_color_override("font_color", _selected.accent_color)
	_detail_tagline.text = "\"%s\"" % _selected.tagline
	var objective: String = _selected.map.objective_description if _selected.map != null else ""
	_detail_objective.text = "Objetivo: %s   ·   Zona: %s" % [objective, _selected.map.display_name if _selected.map != null else "?"]
	if StoryCampaign.is_tier_cleared(_save, _selected.id, tier):
		_detail_reward.text = "Completado en %s ✓ (rejuega por sardinas normales x%.1f)" % [str(d["name"]), float(d["reward"])]
	else:
		_detail_reward.text = "Primera vez en %s: +%d 🐟" % [str(d["name"]), int(round(_selected.first_clear_reward * float(d["reward"])))]


func _on_play_pressed() -> void:
	if _selected != null:
		_show_difficulty_prompt(_selected)


func _on_cinematic_pressed() -> void:
	if _selected != null and not _selected.cinematic_panels.is_empty():
		GameFlow.play_cinematic(_selected.cinematic_panels, _selected.accent_color, GameFlow.STORY_MENU)


func _show_difficulty_prompt(chapter: ChapterData) -> void:
	if chapter == null:
		return
	if is_instance_valid(_difficulty_overlay):
		_difficulty_overlay.queue_free()
	_difficulty_overlay = Control.new()
	_difficulty_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_difficulty_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_difficulty_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 0)
	panel.position = Vector2(-310, -190)
	MenuTheme.style_panel(panel, chapter.accent_color)
	_difficulty_overlay.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var title := MenuTheme.make_title("Capitulo %d: %s" % [chapter.number, chapter.title], 26, chapter.accent_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var hint := Label.new()
	hint.text = "Elige dificultad para esta partida."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	col.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for tier in StoryCampaign.DIFFICULTIES.size():
		grid.add_child(_difficulty_start_button(chapter, tier))
	var cancel := MenuTheme.make_button("Cancelar", MenuTheme.TEXT_DIM)
	cancel.custom_minimum_size = Vector2(180, 42)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func() -> void:
		if is_instance_valid(_difficulty_overlay):
			_difficulty_overlay.queue_free())
	col.add_child(cancel)


func _difficulty_start_button(chapter: ChapterData, tier: int) -> Button:
	var d: Dictionary = StoryCampaign.get_difficulty(tier)
	var button := MenuTheme.make_button(str(d["name"]), d["color"])
	button.custom_minimum_size = Vector2(285, 58)
	var reward: int = int(round(chapter.first_clear_reward * float(d["reward"])))
	button.tooltip_text = "First-clear: %d sardinas" % reward
	button.pressed.connect(func() -> void:
		if is_instance_valid(_difficulty_overlay):
			_difficulty_overlay.queue_free()
		GameFlow.start_story_chapter(chapter, tier))
	return button


func _toggle_skip_cinematics() -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("set_value"):
		var current: bool = bool(settings.get_value("skip_cinematics", false))
		settings.set_value("skip_cinematics", not current)
	_refresh_skip_button()


func _refresh_skip_button() -> void:
	if _skip_cinematics_button == null:
		return
	var settings: Node = get_node_or_null("/root/Settings")
	var enabled: bool = settings != null and settings.has_method("get_value") and bool(settings.get_value("skip_cinematics", false))
	_skip_cinematics_button.set_pressed_no_signal(enabled)
	_skip_cinematics_button.text = "Omitir cinematicas"


func _on_abandon_pressed() -> void:
	if _save == null or not _save.has_method("abandon_story_campaign"):
		return
	_abandon_stage += 1
	if _abandon_stage == 1:
		_abandon_button.text = "Confirmar abandono"
		_abandon_button.add_theme_color_override("font_color", Color(1.0, 0.78, 0.45))
		var audio_warn: Node = get_node_or_null("/root/AudioManager")
		if audio_warn != null and audio_warn.has_method("play_ui"):
			audio_warn.play_ui(&"ui_error")
		return
	_save.abandon_story_campaign()
	_abandon_stage = 0
	_abandon_button.text = "Campaña reiniciada"
	_abandon_button.disabled = true
	_refresh_chips()
	_build_difficulty_chips()
	_build_chapter_nodes()
	if not _chapters.is_empty():
		_select_chapter(_chapters[0])


func _make_chip(text: String, accent: Color) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", MenuTheme.TEXT)
	var box := StyleBoxFlat.new()
	box.bg_color = accent.lerp(Color(0.10, 0.12, 0.15, 1.0), 0.78)
	box.border_color = Color(accent.r, accent.g, accent.b, 0.6)
	box.set_border_width_all(1)
	box.set_corner_radius_all(999)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	label.add_theme_stylebox_override("normal", box)
	return label
