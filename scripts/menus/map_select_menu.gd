extends Control
## Selector de mapas (Fase 08). Lee los MapData existentes y muestra una tarjeta por
## mapa con una vista previa del bioma (dibujada con los colores reales del mapa),
## nombre, dificultad, duracion, objetivo, estado (desbloqueado / bloqueado /
## completado), mejor tiempo y boton Jugar. Respeta el desbloqueo guardado.

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const StoryCampaign = preload("res://scripts/story/story_campaign.gd")
# FreePlayScore es clase global (class_name): se usa sin preload.

const MAP_PATHS: Array[String] = [
	"res://data/maps/neighborhood_map.tres",
	"res://data/maps/park_map.tres",
	"res://data/maps/industrial_alley_map.tres",
]

## Requisito de desbloqueo por mapa (texto para el jugador).
const UNLOCK_REQUIREMENT: Dictionary = {
	&"park": "Desbloquea el capitulo 2 en Historia",
	&"industrial_alley": "Desbloquea el capitulo 3 en Historia",
}

const STORY_CHAPTER_UNLOCK: Dictionary = {
	&"neighborhood": 1,
	&"park": 2,
	&"industrial_alley": 3,
}

## Si es true, permite jugar mapas bloqueados (solo para pruebas). Debe ir en false
## para el jugador normal.
const DEBUG_PLAY_LOCKED: bool = false

var _save: Node
var _anim_time: float = 0.0
## Nivel de Plaga elegido por mapa en esta visita al menu (map_id -> 1..5).
var _selected_plague: Dictionary = {}
## Modo de juego elegido (Fase Coop Local): false = Solo, true = Cooperativo local.
var _coop_selected: bool = false
var _mode_solo_btn: Button
var _mode_coop_btn: Button
var _mode_hint: Label
## Dificultad de Partida libre (Coop 1.5): tier 0-3, analogo al de Historia.
var _selected_difficulty: int = 1
var _diff_buttons: Array[Button] = []
var _diff_desc: Label
## Etiqueta de "Récord" por mapa (map_id -> Label), para refrescar al cambiar dificultad.
var _record_labels: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_save = get_node_or_null("/root/SaveManager")
	_build_ui()
	MenuTheme.add_fade_in(self)


func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameFlow.return_to_main_menu()


## Fondo animado: degradado por bandas + huellas de gato flotando suavemente.
func _draw() -> void:
	var size: Vector2 = get_viewport_rect().size
	var bands: int = 20
	for i in bands:
		var t: float = float(i) / float(bands - 1)
		var col: Color = MenuTheme.BG_TOP.lerp(MenuTheme.BG_BOTTOM, t)
		draw_rect(Rect2(0, size.y * t, size.x, size.y / bands + 1.0), col, true)

	# Halo de luz suave arriba a la derecha para dar profundidad.
	var glow: Vector2 = Vector2(size.x * 0.86, size.y * 0.12)
	draw_circle(glow, 220.0, Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, 0.05))
	draw_circle(glow, 130.0, Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, 0.05))

	# Huellas de gato flotando muy tenues como textura de fondo.
	for i in 9:
		var bx: float = size.x * (0.06 + i * 0.11)
		var by: float = size.y * 0.9 + sin(_anim_time * 0.5 + i * 1.3) * 12.0
		var a: float = 0.05 + 0.03 * sin(_anim_time * 0.8 + i)
		var paw := Color(MenuTheme.CYAN.r, MenuTheme.CYAN.g, MenuTheme.CYAN.b, a)
		draw_circle(Vector2(bx, by), 7.0, paw)
		draw_circle(Vector2(bx + 8, by - 8), 3.5, paw)
		draw_circle(Vector2(bx, by - 11), 3.5, paw)
		draw_circle(Vector2(bx - 8, by - 8), 3.5, paw)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_L)
	margin.add_child(col)

	# Barra superior: retorno + título + chips de estado.
	var top := MenuTheme.make_top_bar("Elige una zona", func() -> void: GameFlow.return_to_main_menu(), MenuTheme.ACCENT)
	col.add_child(top)
	var actions: HBoxContainer = top.get_node("Actions")
	actions.add_child(MenuTheme.make_chip(_sardines_text(), MenuTheme.GOLD, &"sardine"))
	actions.add_child(MenuTheme.make_chip("%d/%d" % [_completed_count(), MAP_PATHS.size()], MenuTheme.ZOMBIE, &"check"))

	# Barra de ajustes: Modo (Solo / Coop) + Dificultad. Se aplican al pulsar Jugar.
	_selected_difficulty = GameFlow.get_free_play_difficulty()
	col.add_child(_build_settings_bar())

	# Tarjetas dentro de un scroll: en resoluciones bajas el contenido no se corta.
	var cards := GridContainer.new()
	cards.columns = 3
	cards.add_theme_constant_override("h_separation", 20)
	cards.add_theme_constant_override("v_separation", 20)
	var cards_scroll := MenuTheme.wrap_scrollable(cards)
	cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cards_scroll)

	for path in MAP_PATHS:
		var map_data: Resource = load(path)
		if map_data != null:
			cards.add_child(_build_card(map_data))
	# Récords ya reflejan la dificultad seleccionada (las tarjetas ya existen).
	_refresh_records()
	# Foco inicial para teclado/gamepad (FASE VISUAL 3): el segmento de modo.
	if is_instance_valid(_mode_solo_btn):
		_mode_solo_btn.grab_focus.call_deferred()


## Barra de ajustes previa a jugar: fila de Modo (segmentado Solo/Coop) + aviso de
## gamepad, y fila de Dificultad (segmentado Facil..Extremo) + descripcion. Ambos
## ajustes se envian a GameFlow al pulsar Jugar. Estilo consistente con el menu.
func _build_settings_bar() -> Control:
	var panel := PanelContainer.new()
	MenuTheme.style_panel(panel, MenuTheme.CYAN, MenuTheme.PANEL_BG_SOFT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_S)
	panel.add_child(col)

	# --- Fila Modo ---
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", MenuTheme.GAP_M)
	col.add_child(mode_row)
	var mode_label := MenuTheme.make_label("Modo", MenuTheme.FS_BODY, MenuTheme.TEXT)
	mode_label.custom_minimum_size = Vector2(84, 0)
	mode_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_row.add_child(mode_label)

	var mode_seg := HBoxContainer.new()
	mode_seg.add_theme_constant_override("separation", 2)
	mode_row.add_child(mode_seg)
	_mode_solo_btn = _make_segment_button("Solo", MenuTheme.CYAN, 160.0)
	_mode_solo_btn.pressed.connect(func() -> void:
		_coop_selected = false
		_play_ui(&"ui_click")
		_refresh_mode_buttons())
	mode_seg.add_child(_mode_solo_btn)
	_mode_coop_btn = _make_segment_button("Cooperativo local", MenuTheme.GOLD, 200.0)
	_mode_coop_btn.pressed.connect(func() -> void:
		_coop_selected = true
		_play_ui(&"ui_click")
		_refresh_mode_buttons())
	mode_seg.add_child(_mode_coop_btn)

	_mode_hint = MenuTheme.make_label("", MenuTheme.FS_CAPTION, Color(1.0, 0.78, 0.5))
	_mode_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mode_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(_mode_hint)

	# --- Fila Dificultad ---
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", MenuTheme.GAP_M)
	col.add_child(diff_row)
	var diff_label := MenuTheme.make_label("Dificultad", MenuTheme.FS_BODY, MenuTheme.TEXT)
	diff_label.custom_minimum_size = Vector2(84, 0)
	diff_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	diff_row.add_child(diff_label)

	var diff_seg := HBoxContainer.new()
	diff_seg.add_theme_constant_override("separation", 2)
	diff_row.add_child(diff_seg)
	_diff_buttons.clear()
	for tier in StoryCampaign.DIFFICULTIES.size():
		var d: Dictionary = StoryCampaign.DIFFICULTIES[tier]
		var btn := _make_segment_button(str(d["name"]), d["color"], 118.0)
		btn.pressed.connect(func() -> void:
			_selected_difficulty = tier
			GameFlow.set_free_play_difficulty(tier)
			_play_ui(&"ui_click")
			_refresh_difficulty_buttons())
		diff_seg.add_child(btn)
		_diff_buttons.append(btn)

	_diff_desc = MenuTheme.make_label("", MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM)
	_diff_desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_diff_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_row.add_child(_diff_desc)

	# --- Identidad del modo Partida libre (corto: chip, no frase larga) ---
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", MenuTheme.GAP_S)
	identity_row.add_child(MenuTheme.make_chip("Puntuación pura", MenuTheme.CYAN, &"star"))
	identity_row.add_child(MenuTheme.make_chip("Sin bonos de mejoras ni refugio", MenuTheme.TEXT_DIM))
	col.add_child(identity_row)

	_refresh_mode_buttons()
	_refresh_difficulty_buttons()
	return panel


## Boton segmentado reutilizable con estilo propio (para resaltar el seleccionado).
func _make_segment_button(text: String, color: Color, width: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, 40)
	btn.focus_mode = Control.FOCUS_ALL
	btn.set_meta("seg_color", color)
	_style_segment(btn, color, false)
	return btn


func _style_segment(btn: Button, color: Color, selected: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		var hovered: bool = state == "hover" or state == "focus"
		if selected:
			box.bg_color = color.lerp(Color(0.08, 0.09, 0.13), 0.55)
			box.border_color = color
			box.set_border_width_all(2)
		else:
			box.bg_color = Color(0.10, 0.11, 0.15, 0.9).lerp(color, 0.10 if hovered else 0.0)
			box.border_color = Color(color.r, color.g, color.b, 0.45)
			box.set_border_width_all(1)
		box.set_corner_radius_all(8)
		box.set_content_margin_all(6)
		btn.add_theme_stylebox_override(state, box)
	btn.add_theme_color_override("font_color", MenuTheme.TEXT if selected else MenuTheme.TEXT_DIM)


func _refresh_mode_buttons() -> void:
	if is_instance_valid(_mode_solo_btn):
		_style_segment(_mode_solo_btn, MenuTheme.CYAN, not _coop_selected)
	if is_instance_valid(_mode_coop_btn):
		_style_segment(_mode_coop_btn, MenuTheme.GOLD, _coop_selected)
	if is_instance_valid(_mode_hint):
		if _coop_selected:
			if Input.get_connected_joypads().is_empty():
				_mode_hint.text = "Pantalla dividida. Conecta un control para J2 (o usa IJKL + H)."
				_mode_hint.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
			else:
				_mode_hint.text = "Pantalla dividida: cada gato con su camara y sus cartas. J2: stick izq. + A."
				_mode_hint.add_theme_color_override("font_color", MenuTheme.ZOMBIE)
		else:
			_mode_hint.text = ""


func _play_ui(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)


func _refresh_difficulty_buttons() -> void:
	for i in _diff_buttons.size():
		var d: Dictionary = StoryCampaign.DIFFICULTIES[i]
		_style_segment(_diff_buttons[i], d["color"], i == _selected_difficulty)
	if is_instance_valid(_diff_desc):
		var sel: Dictionary = StoryCampaign.get_difficulty(_selected_difficulty)
		_diff_desc.text = "Enemigos: vida x%.2f · daño x%.2f · presión x%.2f  ·  Puntuación x%.1f" % [
			float(sel["health"]), float(sel["damage"]), float(sel["pressure"]), float(sel["reward"])]
		_diff_desc.add_theme_color_override("font_color", sel["color"])
	_refresh_records()


## Actualiza las etiquetas de "Récord" de cada tarjeta a la dificultad seleccionada.
func _refresh_records() -> void:
	var tier_name: String = str(StoryCampaign.get_difficulty(_selected_difficulty)["name"])
	for map_id in _record_labels:
		var label: Label = _record_labels[map_id]
		if not is_instance_valid(label):
			continue
		var best: int = FreePlayScore.get_best(_save, map_id, _selected_difficulty)
		label.text = "Récord (%s): %d" % [tier_name, best] if best > 0 else "Sin récord en %s" % tier_name


func _build_card(map_data: Resource) -> Control:
	var unlocked: bool = _is_free_play_map_unlocked(map_data.id)
	var completed: bool = _save != null and _save.has_method("is_map_completed") and _save.is_map_completed(map_data.id)
	var best_time: float = _save.get_best_time(map_data.id) if _save != null and _save.has_method("get_best_time") else 0.0

	var accent: Color = map_data.accent_color if unlocked else Color(0.34, 0.35, 0.40)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 360)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.tooltip_text = map_data.description
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	MenuTheme.style_panel(panel, accent)

	# Animacion sutil al pasar el mouse: leve crecimiento y brillo.
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size * 0.5)
	panel.mouse_entered.connect(func() -> void:
		var t := panel.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(panel, "scale", Vector2(1.03, 1.03), 0.12))
	panel.mouse_exited.connect(func() -> void:
		var t := panel.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(panel, "scale", Vector2.ONE, 0.12))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	# --- Vista previa del bioma (banner superior) ---
	v.add_child(_build_preview(map_data, unlocked, completed))

	# Cabecera: nombre + estado.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var name_label := MenuTheme.make_title(map_data.display_name, 24, accent if unlocked else MenuTheme.TEXT_DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)

	var badge_text: String = "Bloqueado"
	var badge_color: Color = Color(1.0, 0.55, 0.55)
	if unlocked and completed:
		badge_text = "Completado"
		badge_color = MenuTheme.ZOMBIE
	elif unlocked:
		badge_text = "Disponible"
		badge_color = MenuTheme.CYAN
	head.add_child(MenuTheme.make_badge(badge_text, badge_color))

	# Linea compacta: dificultad en puntos + duracion.
	var meta := Label.new()
	meta.text = "%s   ·   %s" % [_difficulty_dots(map_data.difficulty_modifier), _format_minutes(map_data.duration_seconds)]
	meta.add_theme_font_size_override("font_size", 16)
	meta.add_theme_color_override("font_color", MenuTheme.TEXT)
	v.add_child(meta)

	# Objetivo corto.
	var objective := Label.new()
	objective.text = "Objetivo: %s" % _objective_text(map_data)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_font_size_override("font_size", 15)
	objective.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	v.add_child(objective)

	if not unlocked:
		var req_row := HBoxContainer.new()
		req_row.add_theme_constant_override("separation", MenuTheme.GAP_XS + 2)
		var lock := IconDrawer.new()
		lock.icon_type = &"lock"
		lock.accent = Color(1.0, 0.78, 0.5)
		lock.custom_minimum_size = Vector2(16, 16)
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		req_row.add_child(lock)
		var req := MenuTheme.make_label(str(UNLOCK_REQUIREMENT.get(map_data.id, "Asegura la zona anterior")), MenuTheme.FS_CAPTION, Color(1.0, 0.78, 0.5))
		req.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		req.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		req_row.add_child(req)
		v.add_child(req_row)
	elif best_time > 0.0:
		var bt_row := HBoxContainer.new()
		bt_row.add_theme_constant_override("separation", MenuTheme.GAP_XS + 2)
		var clock := IconDrawer.new()
		clock.icon_type = &"clock"
		clock.accent = MenuTheme.ZOMBIE
		clock.custom_minimum_size = Vector2(16, 16)
		clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bt_row.add_child(clock)
		bt_row.add_child(MenuTheme.make_label("Mejor tiempo: %s" % _format_time(best_time), MenuTheme.FS_CAPTION, MenuTheme.ZOMBIE))
		v.add_child(bt_row)

	# Récord de puntuación (Partida libre) del mapa en la dificultad seleccionada.
	# Se refresca al cambiar el segmentado de dificultad.
	if unlocked:
		var rec_row := HBoxContainer.new()
		rec_row.add_theme_constant_override("separation", MenuTheme.GAP_XS + 2)
		var star := IconDrawer.new()
		star.icon_type = &"star"
		star.accent = MenuTheme.GOLD
		star.custom_minimum_size = Vector2(16, 16)
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rec_row.add_child(star)
		var rec_label := MenuTheme.make_label("", MenuTheme.FS_CAPTION, MenuTheme.GOLD)
		rec_row.add_child(rec_label)
		_record_labels[map_data.id] = rec_label
		v.add_child(rec_row)

	# Selector de Nivel de Plaga (rejugabilidad): visible cuando ya ganaste el nivel 1.
	if unlocked and completed:
		v.add_child(_build_plague_selector(map_data))

	var v_spacer := Control.new()
	v_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(v_spacer)

	var play := MenuTheme.make_button("Jugar", map_data.accent_color, &"primary" if unlocked else &"secondary")
	play.custom_minimum_size = Vector2(260, 46)
	var can_play: bool = unlocked or DEBUG_PLAY_LOCKED
	play.disabled = not can_play
	play.text = "Jugar" if unlocked else ("Jugar (debug)" if DEBUG_PLAY_LOCKED else "Bloqueado")
	play.pressed.connect(func() -> void:
		if unlocked or DEBUG_PLAY_LOCKED:
			GameFlow.set_game_mode(GameFlow.MODE_LOCAL_COOP if _coop_selected else GameFlow.MODE_SOLO)
			GameFlow.start_run(map_data, 0, int(_selected_plague.get(map_data.id, 1))))
	v.add_child(play)

	return panel


## Fila de botones I..V para elegir el Nivel de Plaga. Ganar en el nivel N
## desbloquea el N+1 de ese mapa; cada nivel sube la presion y da +50% sardinas.
func _build_plague_selector(map_data: Resource) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var title := Label.new()
	var max_unlocked: int = 1
	if _save != null and _save.has_method("get_value"):
		max_unlocked = clampi(int(_save.get_value("plague_unlocked_%s" % map_data.id, 1)), 1, 5)
	title.text = "Nivel de Plaga  (+50% sardinas por nivel)"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var numerals: Array[String] = ["I", "II", "III", "IV", "V"]
	var buttons: Array[Button] = []
	var selected: int = clampi(int(_selected_plague.get(map_data.id, 1)), 1, max_unlocked)
	_selected_plague[map_data.id] = selected

	var refresh := func() -> void:
		var current: int = int(_selected_plague.get(map_data.id, 1))
		for i in buttons.size():
			var b: Button = buttons[i]
			b.modulate = Color(1, 1, 1, 1.0 if i + 1 <= max_unlocked else 0.35)
			b.add_theme_color_override("font_color",
				Color(1.0, 0.45, 0.3) if i + 1 == current else MenuTheme.TEXT_DIM)

	for i in 5:
		var level: int = i + 1
		var b := Button.new()
		b.text = numerals[i]
		b.custom_minimum_size = Vector2(40, 30)
		b.disabled = level > max_unlocked
		b.tooltip_text = "Plaga %d" % level if level <= max_unlocked else "Gana en Plaga %d para desbloquear" % (level - 1)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.11, 0.15, 0.95)
		style.border_color = Color(1.0, 0.45, 0.3, 0.7)
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, style)
		b.pressed.connect(func() -> void:
			_selected_plague[map_data.id] = level
			refresh.call())
		row.add_child(b)
		buttons.append(b)
	refresh.call()
	return box


## Banner con una miniatura del bioma dibujada con los colores reales del mapa.
func _build_preview(map_data: Resource, unlocked: bool, completed: bool) -> Control:
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(0, 130)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.clip_contents = true
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.draw.connect(_draw_preview.bind(preview, map_data, unlocked, completed))
	return preview


func _draw_preview(preview: Control, map_data: Resource, unlocked: bool, completed: bool) -> void:
	var s: Vector2 = preview.size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var full := Rect2(Vector2.ZERO, s)

	# Fondo del bioma (degradado vertical entre color base y secundario).
	var bg_top: Color = map_data.background_color
	var bg_bottom: Color = map_data.secondary_color
	var steps: int = 12
	for i in steps:
		var t: float = float(i) / float(steps - 1)
		preview.draw_rect(Rect2(0, s.y * t, s.x, s.y / steps + 1.0), bg_top.lerp(bg_bottom, t), true)

	# Rejilla sutil del mapa.
	var grid: Color = map_data.grid_color
	var cell: float = 22.0
	var gx: float = cell
	while gx < s.x:
		preview.draw_line(Vector2(gx, 0), Vector2(gx, s.y), Color(grid.r, grid.g, grid.b, 0.5), 1.0)
		gx += cell
	var gy: float = cell
	while gy < s.y:
		preview.draw_line(Vector2(0, gy), Vector2(s.x, gy), Color(grid.r, grid.g, grid.b, 0.5), 1.0)
		gy += cell

	# Patron caracteristico segun el bioma.
	_draw_biome_hint(preview, map_data, s)

	# Vignette suave en los bordes para integrar con la tarjeta.
	preview.draw_rect(full, Color(0, 0, 0, 0.12), false, 8.0)

	# Etiqueta de bioma abajo a la izquierda.
	var font := ThemeDB.fallback_font
	var tag: String = _biome_tag(map_data.biome)
	preview.draw_string(font, Vector2(10, s.y - 12), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 1, 1, 0.7))

	if completed:
		preview.draw_string(font, Vector2(s.x - 26, 22), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, MenuTheme.ZOMBIE)

	# Overlay de bloqueo: oscurecer + candado centrado.
	if not unlocked:
		preview.draw_rect(full, Color(0.02, 0.02, 0.04, 0.62), true)
		var c: Vector2 = s * 0.5
		var body := Rect2(c + Vector2(-16, -6), Vector2(32, 26))
		preview.draw_rect(body, Color(0.85, 0.86, 0.9, 0.92), true, -1.0)
		preview.draw_arc(c + Vector2(0, -6), 11.0, PI, TAU, 20, Color(0.85, 0.86, 0.9, 0.92), 5.0)
		preview.draw_circle(c + Vector2(0, 6), 3.5, Color(0.2, 0.2, 0.25, 1.0))


## Dibuja un guiño del patron del bioma con los colores del mapa.
func _draw_biome_hint(preview: Control, map_data: Resource, s: Vector2) -> void:
	var accent: Color = map_data.decoration_accent_color
	match map_data.biome:
		&"park":
			# Sendero curvo + arbustos.
			var path := Color(0.43, 0.35, 0.20, 0.5)
			preview.draw_line(Vector2(0, s.y * 0.7), Vector2(s.x, s.y * 0.55), path, 14.0)
			for i in 4:
				var px: float = s.x * (0.15 + i * 0.24)
				preview.draw_circle(Vector2(px, s.y * (0.3 + 0.1 * sin(float(i)))), 12.0,
					Color(accent.r, accent.g, accent.b, 0.55))
		&"industrial":
			# Placas metalicas + linea de peligro.
			var plate := Color(accent.r, accent.g, accent.b, 0.3)
			for i in 3:
				for j in 2:
					var r := Rect2(Vector2(s.x * (0.12 + i * 0.3), s.y * (0.2 + j * 0.4)), Vector2(34, 22))
					preview.draw_rect(r, plate, false, 2.0)
			preview.draw_line(Vector2(0, s.y * 0.85), Vector2(s.x, s.y * 0.85),
				Color(map_data.hazard_color.r, map_data.hazard_color.g, map_data.hazard_color.b, 0.55), 4.0)
		_:
			# Barrio: linea central de calle discontinua + bloques.
			preview.draw_line(Vector2(0, s.y * 0.5), Vector2(s.x, s.y * 0.5),
				Color(accent.r, accent.g, accent.b, 0.35), 3.0)
			var dx: float = 8.0
			while dx < s.x:
				preview.draw_line(Vector2(dx, s.y * 0.5), Vector2(dx + 14, s.y * 0.5),
					Color(0.88, 0.88, 0.78, 0.4), 3.0)
				dx += 30.0
			for i in 3:
				var bx: float = s.x * (0.15 + i * 0.32)
				preview.draw_rect(Rect2(Vector2(bx, s.y * 0.16), Vector2(30, 16)),
					Color(accent.r, accent.g, accent.b, 0.4), true)


func _biome_tag(biome: StringName) -> String:
	match biome:
		&"park":
			return "PARQUE"
		&"industrial":
			return "INDUSTRIAL"
		_:
			return "URBANO"


func _sardines_text() -> String:
	return str(_save.get_sardines()) if _save != null and _save.has_method("get_sardines") else "0"


func _completed_count() -> int:
	var completed: int = 0
	for path in MAP_PATHS:
		var data: Resource = load(path)
		if data != null and _save != null and _save.has_method("is_map_completed") and _save.is_map_completed(data.id):
			completed += 1
	return completed


func _is_free_play_map_unlocked(map_id: StringName) -> bool:
	if DEBUG_PLAY_LOCKED:
		return true
	var chapter_required: int = int(STORY_CHAPTER_UNLOCK.get(map_id, 1))
	if chapter_required <= 1:
		return true
	var cleared: int = int(_save.get_value("story_chapters_cleared", 0)) if _save != null and _save.has_method("get_value") else 0
	return chapter_required <= cleared + 1


## Dificultad como 1-3 puntos llenos (○●) en vez de texto largo.
func _difficulty_dots(modifier: float) -> String:
	var level: int = 1
	if modifier > 1.15:
		level = 3
	elif modifier > 1.0:
		level = 2
	var text: String = ""
	for i in 3:
		text += "●" if i < level else "○"
	return text


func _objective_text(map_data: Resource) -> String:
	if map_data.objective_description != "":
		return map_data.objective_description
	if map_data.require_defeat_boss:
		return "Sobrevive y derrota al jefe"
	if map_data.rescue_cats_required > 0:
		return "Rescata %d gatos" % map_data.rescue_cats_required
	if map_data.defeat_minibosses_required > 0:
		return "Derrota %d mini-jefes" % map_data.defeat_minibosses_required
	return "Sobrevive hasta asegurar la zona"


func _format_minutes(seconds: float) -> String:
	return "%d min" % int(round(seconds / 60.0))


func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [total / 60, total % 60]
