extends CanvasLayer
## HUD minimalista (Fase 08.5). Durante el combate solo se muestra lo esencial:
## vida/XP/nivel (arriba izq.), tiempo (arriba centro), objetivo corto + gatos
## (arriba der.) y mini-iconos de armas y companeros. La informacion detallada
## (kills, intensidad, sinergias, mapa, estado de companeros) se conserva en memoria
## y se ofrece en la pausa (ESC) via get_run_info(). No saturar la pantalla de juego.

const META_PANEL_SCENE := preload("res://scenes/ui/MetaUpgradePanel.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/menus/PauseMenu.tscn")
const MINIMAP_SYSTEM_SCRIPT := preload("res://scripts/ui/minimap/minimap_system.gd")
@warning_ignore("shadowed_global_identifier")
const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
@warning_ignore("shadowed_global_identifier")
const IconDrawer = preload("res://scripts/ui/icon_drawer.gd")

var _meta_panel: Control
var _pause_menu: Control

const COMPANION_STATE_STYLE: Dictionary = {
	&"active": {"label": "Activo", "color": Color(0.64, 1.0, 0.72, 1.0)},
	&"hurt": {"label": "Herido", "color": Color(1.0, 0.84, 0.46, 1.0)},
	&"downed": {"label": "Caido", "color": Color(1.0, 0.58, 0.58, 1.0)},
	&"reviving": {"label": "Reviviendo", "color": Color(0.72, 1.0, 0.84, 1.0)},
}

const WEAPON_TYPE_STYLE: Dictionary = {
	&"projectile": {"icon": &"weapon_projectile"},
	&"explosive": {"icon": &"weapon_explosive"},
	&"boomerang": {"icon": &"weapon_boomerang"},
	&"laser": {"icon": &"weapon_laser"},
	&"orbital": {"icon": &"weapon_orbital"},
	&"area": {"icon": &"weapon_area"},
}

@onready var level_label: Label = $TopLeft/Stats/LevelLabel
@onready var health_bar: ProgressBar = $TopLeft/Stats/HealthBar
@onready var health_value: Label = $TopLeft/Stats/HealthBar/HealthValue
@onready var xp_bar: ProgressBar = $TopLeft/Stats/XPBar
@onready var time_label: Label = $TopCenter/TimeLabel
@onready var rescue_status_label: Label = $TopCenter/RescueStatus
@onready var rescue_arrow: Control = $TopCenter/RescueArrow
@onready var rescue_arrow_glyph: Label = $TopCenter/RescueArrow/Glyph
@onready var event_label: Label = $TopCenter/EventMessage
@onready var _objective_label: Label = $TopRight/List/Objective
@onready var _cats_label: Label = $TopRight/List/Cats
@onready var _weapons_bar: HBoxContainer = $WeaponsBar
@onready var _companion_bar: HBoxContainer = $CompanionBar
@onready var _boss_bar: Control = $BossBar
@onready var _boss_name_label: Label = $BossBar/BossName
@onready var _boss_health_bar: ProgressBar = $BossBar/BossHealth
@onready var _damage_flash: ColorRect = $DamageFlash
# --- Paneles de fin de partida (victoria / derrota) ---
@onready var _victory_panel: Control = $VictoryPanel
@onready var _victory_title: Label = $VictoryPanel/Center/Content/Title
@onready var _victory_subtitle: Label = $VictoryPanel/Center/Content/Subtitle
@onready var _victory_summary: Label = $VictoryPanel/Center/Content/Summary
@onready var _victory_details: Label = $VictoryPanel/Center/Content/Details
@onready var _victory_details_button: Button = $VictoryPanel/Center/Content/DetailsButton
@onready var game_over_panel: Control = $GameOverPanel
@onready var _defeat_title: Label = $GameOverPanel/Center/Content/Title
@onready var _defeat_subtitle: Label = $GameOverPanel/Center/Content/Subtitle
@onready var _defeat_summary: Label = $GameOverPanel/Center/Content/Summary
@onready var _defeat_details: Label = $GameOverPanel/Center/Content/Details
@onready var _defeat_details_button: Button = $GameOverPanel/Center/Content/DetailsButton
## Mosaicos de estadÃ­sticas de fin de partida (reemplazan el resumen de texto).
var _victory_tiles: GridContainer
var _defeat_tiles: GridContainer
## BotÃ³n "Reintentar" de cada panel (foco inicial para navegaciÃ³n con gamepad).
var _victory_retry: Button
var _defeat_retry: Button
## Tarjetas de fondo de fin de partida (se reajustan al tamaÃ±o del viewport).
var _run_end_cards: Array[Control] = []

var _damage_flash_tween: Tween
var _event_tween: Tween
var _rescue_target_active: bool = false
var _rescue_target_position: Vector2 = Vector2.ZERO

# Estado de la run que el HUD ya no muestra pero conserva para la pausa / fin.
var _last_time: float = 0.0
var _last_kills: int = 0
var _last_level: int = 1
var _last_cats: int = 0
var _last_max_cats: int = 4
var _last_weapons: int = 0
var _last_difficulty: float = 0.0
var _last_weapon_names: Array[String] = []
var _weapon_snapshots: Array = []
var _companion_snapshots: Array = []
var _synergy_states: Array = []
var _map_name: String = ""
var _objective_text: String = "Sobrevive"
var _game_over_title: String = "COLONIA PERDIDA"
## Overlay de rendimiento (F8): FPS/estado/conteos del PerformanceManager.
var _debug_label: Label
var _perf: Node
## Barra fantasma de vida (valor previo que persigue al actual tras un golpe).
var _health_ghost: float = 0.0
var _ghost_tween: Tween
var _low_health_tween: Tween
## Rotulo de racha de bajas (combo), creado en _ready.
var _combo_label: Label
var _combo_tween: Tween
## Cola de toasts de mision completada (se muestran de a uno).
var _mission_toasts: Array[Dictionary] = []
var _mission_toast_active: bool = false
## FASE 13: toast de botin activo por mitad de pantalla (1 = izq/solo, 2 = der).
var _loot_toast_by_side: Dictionary = {}
## Consejos de tutorial ya mostrados EN ESTA SESION (el perfil guarda los suyos).
var _tips_shown: Dictionary = {}
var _tip_panel: PanelContainer
var _tip_tween: Tween
## Niveles previos por arma para animar SOLO el chip que cambio.
var _prev_weapon_levels: Dictionary = {}
## Panel de build (tecla B): armas + mejoras + compañero + mutaciones. No pausa.
var _build_panel: Control


func _ready() -> void:
	game_over_panel.visible = false
	game_over_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	rescue_status_label.visible = false
	rescue_arrow.visible = false
	event_label.visible = false
	_boss_bar.visible = false
	_victory_panel.visible = false
	_victory_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_to_group("hud")
	_style_bars()
	_build_vignette()
	# Sistema Minimapa: radar de jugadores/aliados/enemigos/jefes/rescates.
	# Se auto-configura (solo o coop) y se oculta solo en pausa/fin de partida.
	var minimap_system := MINIMAP_SYSTEM_SCRIPT.new()
	minimap_system.name = "MinimapSystem"
	add_child(minimap_system)
	# Panel de mejoras permanentes (Fase 07) y menu de pausa (Fase 08).
	_meta_panel = META_PANEL_SCENE.instantiate()
	add_child(_meta_panel)
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	add_child(_pause_menu)
	update_companion_roster([])
	on_weapons_changed([])

	_victory_details_button.pressed.connect(_toggle_victory_details)
	_victory_details_button.pressed.connect(func() -> void: _play_ui(&"ui_click"))
	_defeat_details_button.pressed.connect(_toggle_defeat_details)
	_defeat_details_button.pressed.connect(func() -> void: _play_ui(&"ui_click"))

	_perf = get_node_or_null("/root/Performance")
	_build_boss_bar_bg()
	_build_combo_label()
	_build_phase_label()
	_build_aim_badge()
	_build_debug_overlay()
	_build_run_end_cards()
	_victory_retry = _build_run_end_buttons($VictoryPanel/Center/Content)
	_defeat_retry = _build_run_end_buttons($GameOverPanel/Center/Content)
	_victory_tiles = _make_summary_tiles($VictoryPanel/Center/Content, _victory_summary)
	_defeat_tiles = _make_summary_tiles($GameOverPanel/Center/Content, _defeat_summary)


## Tarjeta de fondo del panel de fin de partida: da marco y jerarquia al resumen
## (antes el contenido "flotaba" sobre el oscurecido). Se inserta DETRAS del
## contenido centrado, sin tocar el arbol que referencian los @onready.
func _build_run_end_cards() -> void:
	_make_run_end_card($VictoryPanel, $VictoryPanel/Center, Color(0.55, 1.0, 0.72), Color(0.09, 0.13, 0.11, 0.96))
	_make_run_end_card($GameOverPanel, $GameOverPanel/Center, Color(1.0, 0.5, 0.5), Color(0.14, 0.09, 0.10, 0.96))
	# Reajusta las tarjetas si cambia el tamaÃ±o de la ventana (stretch "expand").
	get_viewport().size_changed.connect(_fit_run_end_cards)


## TamaÃ±o de tarjeta acotado por el viewport: nunca se sale de pantalla.
func _fit_run_end_card(card: Control) -> void:
	if not is_instance_valid(card):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var half_w: float = minf(400.0, (vp.x - 24.0) * 0.5)
	var half_h: float = minf(330.0, (vp.y - 16.0) * 0.5)
	card.offset_left = -half_w
	card.offset_right = half_w
	card.offset_top = -half_h
	card.offset_bottom = half_h


func _fit_run_end_cards() -> void:
	for card in _run_end_cards:
		_fit_run_end_card(card)


func _make_run_end_card(panel: Control, center: Control, accent: Color, bg: Color) -> void:
	if panel == null or center == null:
		return
	var card := Panel.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centrada y ADAPTADA al viewport: una tarjeta de tamaÃ±o fijo se cortaba por
	# abajo en la resolucion base (648 px de alto < 660 de tarjeta).
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	_run_end_cards.append(card)
	_fit_run_end_card(card)
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	box.set_border_width_all(2)
	box.border_width_top = 5
	box.set_corner_radius_all(22)
	box.content_margin_left = 44.0
	box.content_margin_right = 44.0
	box.content_margin_top = 34.0
	box.content_margin_bottom = 34.0
	box.shadow_color = Color(0, 0, 0, 0.55)
	box.shadow_size = 26
	card.add_theme_stylebox_override("panel", box)
	panel.add_child(card)
	# Detras del contenido centrado (que se dibuja despues) pero sobre el oscurecido.
	panel.move_child(card, center.get_index())
	# Banda de acento superior (remate fino bajo el borde).
	var strip := ColorRect.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.color = Color(accent.r, accent.g, accent.b, 0.16)
	strip.anchor_right = 1.0
	strip.offset_top = 5.0
	strip.offset_bottom = 92.0
	strip.offset_left = 2.0
	strip.offset_right = -2.0
	card.add_child(strip)


## Botones clicables de fin de partida (ademÃ¡s de los atajos R/M/ESC). Devuelve el
## primer boton (Reintentar) para poder darle el foco al mostrar el panel (gamepad P2).
func _build_run_end_buttons(content: Node) -> Button:
	if content == null:
		return null
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var retry := MenuTheme.make_button("Reintentar", MenuTheme.ZOMBIE)
	retry.custom_minimum_size = Vector2(190, 46)
	retry.focus_mode = Control.FOCUS_ALL
	retry.pressed.connect(_on_run_end_retry)
	row.add_child(retry)
	var meta := MenuTheme.make_button("Mejoras", MenuTheme.ACCENT)
	meta.custom_minimum_size = Vector2(190, 46)
	meta.focus_mode = Control.FOCUS_ALL
	meta.pressed.connect(func() -> void:
		_play_ui(&"ui_click")
		toggle_meta_panel())
	row.add_child(meta)
	var menu := MenuTheme.make_button("Menu", MenuTheme.TEXT_DIM)
	menu.custom_minimum_size = Vector2(190, 46)
	menu.focus_mode = Control.FOCUS_ALL
	menu.pressed.connect(_on_run_end_menu)
	row.add_child(menu)
	content.add_child(row)
	return retry


func _on_run_end_retry() -> void:
	_play_ui(&"ui_click")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_run_end_menu() -> void:
	_play_ui(&"ui_click")
	get_tree().paused = false
	var gf: Node = get_node_or_null("/root/GameFlow")
	# En una run de historia el boton vuelve a la pantalla de Historia (y dispara
	# la cinematica final si corresponde); en partida libre, al menu principal.
	if gf != null and gf.has_method("is_story_run") and gf.is_story_run():
		gf.exit_story_run()
	elif gf != null and gf.has_method("return_to_main_menu"):
		gf.return_to_main_menu()


## ViÃ±eta radial sutil (recurso interno, sin texturas externas): oscurece los
## bordes de la pantalla para dar profundidad y centrar la vista en el combate.
## Va al Ã­ndice 0 del CanvasLayer, debajo de todos los paneles del HUD.
func _build_vignette() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.30)
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, -0.06)
	texture.width = 512
	texture.height = 288
	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	move_child(rect, 0)


## Fondo propio de la barra de boss: panel oscuro redondeado detras del nombre y
## la barra, para que no se solape/mezcle con las etiquetas del centro superior.
var _boss_bar_bg: Panel


func _build_boss_bar_bg() -> void:
	_boss_bar_bg = Panel.new()
	_boss_bar_bg.name = "BossBarBg"
	_boss_bar_bg.visible = false
	_boss_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Cubre la banda de la barra de boss con un margen; centrado y ancho fijo.
	_boss_bar_bg.anchor_left = 0.5
	_boss_bar_bg.anchor_right = 0.5
	_boss_bar_bg.offset_left = -340.0
	_boss_bar_bg.offset_right = 340.0
	_boss_bar_bg.offset_top = 88.0
	_boss_bar_bg.offset_bottom = 158.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.045, 0.06, 0.82)
	box.border_color = Color(0.82, 0.24, 0.28, 0.85)
	box.set_border_width_all(2)
	box.border_width_top = 3
	box.set_corner_radius_all(10)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 10
	_boss_bar_bg.add_theme_stylebox_override("panel", box)
	add_child(_boss_bar_bg)
	# Debajo de la barra en el arbol (se dibuja antes = queda por detras).
	move_child(_boss_bar_bg, _boss_bar.get_index())


## Rotulo de racha de bajas: aparece a partir de 4 bajas encadenadas, con punch
## en cada baja y color que se calienta con la racha. Se coloca en una banda
## centrada BAJO la barra de boss (antes iba en el centro superior y se solapaba).
func _build_combo_label() -> void:
	var band := CenterContainer.new()
	band.name = "ComboBand"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_top = 176.0
	band.offset_bottom = 214.0
	add_child(band)
	_combo_label = Label.new()
	_combo_label.visible = false
	# Racha: Lilita One (impacto corto) con outline para leerse sobre el combate.
	_combo_label.add_theme_font_override("font", UIFonts.lilita())
	_combo_label.add_theme_font_size_override("font_size", UIFonts.scaled(24))
	_combo_label.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.07, 0.92))
	_combo_label.add_theme_constant_override("outline_size", 5)
	_combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_combo_label.add_theme_constant_override("shadow_offset_x", 0)
	_combo_label.add_theme_constant_override("shadow_offset_y", 2)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(_combo_label)


## Rotulo de fase de las Partidas rapidas: "Fase Â· tiempo restante" bajo el
## reloj. Lo actualiza el PhaseDirector (~4 veces por segundo).
var _phase_label: Label


func _build_phase_label() -> void:
	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.theme_type_variation = &"HudSecondary"
	_phase_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.95))
	_phase_label.text = ""
	var center := $TopCenter as Control
	if center != null:
		center.add_child(_phase_label)
		center.move_child(_phase_label, time_label.get_index() + 1)
	else:
		add_child(_phase_label)


## Fase actual y cuenta atras de la partida rapida (PhaseDirector).
func set_phase_info(text: String) -> void:
	if _phase_label != null:
		_phase_label.text = text


## Aviso discreto del modo de punteria (Rework de apuntado). Solo en SOLO: en coop
## cada mitad muestra el suyo (CoopSplitScreen), porque el modo es de CADA jugador
## y este HUD es compartido. Manual (el defecto) no rotula nada.
var _aim_badge: Label
## Jugador cuyo modo se rotula en solo, cacheado para no barrer el grupo por frame.
var _aim_badge_player: Node


func _build_aim_badge() -> void:
	_aim_badge = Label.new()
	_aim_badge.name = "AimBadge"
	_aim_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_badge.theme_type_variation = &"HudSecondary"
	_aim_badge.visible = false
	_aim_badge.add_theme_color_override("font_color", Color(0.72, 0.82, 0.95, 0.8))
	var center := $TopCenter as Control
	if center != null:
		center.add_child(_aim_badge)
	else:
		add_child(_aim_badge)


func _update_aim_badge() -> void:
	if _aim_badge == null:
		return
	if _is_coop():
		_aim_badge.visible = false
		return
	if not is_instance_valid(_aim_badge_player):
		_aim_badge_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_aim_badge_player) or not _aim_badge_player.has_method("get_aim_mode"):
		_aim_badge.visible = false
		return
	match _aim_badge_player.get_aim_mode():
		&"auto":
			_aim_badge.text = "Auto-mira"
			_aim_badge.visible = true
		&"assist":
			_aim_badge.text = "Mira asistida"
			_aim_badge.visible = true
		_:
			_aim_badge.visible = false


## Llamado por Feedback.register_kill vÃ­a el grupo "hud". count=0 termina la racha.
func show_combo(count: int) -> void:
	if _combo_label == null:
		return
	if count < 4:
		if _combo_label.visible and count == 0:
			var out := create_tween()
			out.tween_property(_combo_label, "modulate:a", 0.0, 0.3)
			out.tween_callback(func() -> void: _combo_label.visible = false)
		return
	_combo_label.visible = true
	_combo_label.modulate.a = 1.0
	_combo_label.text = "RACHA x%d" % count
	# El color se calienta con la racha: amarillo -> naranja -> rojo fuego.
	var heat: float = clampf(float(count) / 40.0, 0.0, 1.0)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4).lerp(Color(1.0, 0.35, 0.2), heat))
	_combo_label.pivot_offset = _combo_label.size * 0.5
	if _combo_tween != null and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_label.scale = Vector2(1.25, 1.25)
	_combo_tween = create_tween()
	_combo_tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Toast de mision completada: panel dorado que entra por la derecha, espera y
## sale. Si llegan varias a la vez se encolan para no taparse entre si.
func show_mission_toast(mission_name: String, reward: int) -> void:
	_mission_toasts.append({"name": mission_name, "reward": reward})
	if not _mission_toast_active:
		_show_next_mission_toast()


func _show_next_mission_toast() -> void:
	if _mission_toasts.is_empty():
		_mission_toast_active = false
		return
	_mission_toast_active = true
	var data: Dictionary = _mission_toasts.pop_front()
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.07, 0.04, 0.94)
	box.border_color = Color(1.0, 0.78, 0.25)
	box.set_border_width_all(2)
	box.border_width_left = 5
	box.set_corner_radius_all(10)
	box.set_content_margin_all(12)
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 8
	panel.add_theme_stylebox_override("panel", box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var title := Label.new()
	title.text = "â˜… Mision completada"
	title.add_theme_font_override("font", UIFonts.fredoka(600))
	title.add_theme_font_size_override("font_size", UIFonts.scaled(13))
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	v.add_child(title)
	var body := Label.new()
	body.text = "%s   +%d ðŸŸ" % [data["name"], int(data["reward"])]
	body.add_theme_font_size_override("font_size", UIFonts.scaled(17))
	body.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	v.add_child(body)
	add_child(panel)
	# Posicion: borde derecho, bajo el panel de objetivo; entra deslizando.
	await get_tree().process_frame
	var viewport_w: float = get_viewport().get_visible_rect().size.x
	panel.position = Vector2(viewport_w, 92.0)
	var target_x: float = viewport_w - panel.size.x - 16.0
	var t := create_tween()
	t.tween_property(panel, "position:x", target_x, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.6)
	t.tween_property(panel, "position:x", viewport_w + 8.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		panel.queue_free()
		_show_next_mission_toast())


## Overlay de depuracion de rendimiento (F8). Oculto por defecto.
func _build_debug_overlay() -> void:
	_debug_label = Label.new()
	_debug_label.visible = false
	_debug_label.position = Vector2(16, 96)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_debug_label)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		if _debug_label != null:
			_debug_label.visible = not _debug_label.visible
			_toggle_map_debug(_debug_label.visible)
	# FASE 13: panel de build (tecla B). No pausa la partida.
	if event.is_action_pressed(&"build_panel") and not get_tree().paused:
		_toggle_build_panel()


func _style_bars() -> void:
	# Vida en rojo, XP en azul, jefe en carmesi. Bordes y highlight superior para
	# que las barras se lean "con volumen" en vez del ProgressBar plano por defecto.
	_apply_bar_color(health_bar, Color(0.9, 0.36, 0.38))
	_apply_bar_color(xp_bar, Color(0.4, 0.72, 1.0))
	_apply_bar_color(_boss_health_bar, Color(0.82, 0.22, 0.28), 3.0)
	# Barra fantasma de vida: al recibir daÃ±o, un tramo palido persigue al valor
	# real, mostrando cuanta vida acabas de perder (lectura instantanea del golpe).
	health_bar.draw.connect(_draw_health_ghost)


func _apply_bar_color(bar: ProgressBar, fill: Color, radius: float = 5.0) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.09, 0.9)
	bg.border_color = Color(0.28, 0.31, 0.38, 0.8)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(int(radius))
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.border_color = fill.lightened(0.25)
	fg.border_width_top = 2
	fg.set_corner_radius_all(int(radius))
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)


## Dibuja el tramo "fantasma" de vida recien perdida sobre la barra de vida.
func _draw_health_ghost() -> void:
	if _health_ghost <= health_bar.value or health_bar.max_value <= 0.0:
		return
	var size: Vector2 = health_bar.size
	var from_x: float = size.x * float(health_bar.value) / float(health_bar.max_value)
	var to_x: float = size.x * clampf(float(_health_ghost) / float(health_bar.max_value), 0.0, 1.0)
	health_bar.draw_rect(Rect2(from_x, 2.0, to_x - from_x, size.y - 4.0), Color(1.0, 0.78, 0.5, 0.55), true)


func _process(_delta: float) -> void:
	_update_rescue_arrow()
	_update_downed_arrow()
	_update_aim_badge()
	if _debug_label != null and _debug_label.visible and _perf != null and _perf.has_method("get_debug_line"):
		var map_line: String = _map_debug_line()
		_debug_label.text = _perf.get_debug_line() + ("\n" + map_line if map_line != "" else "")


func _toggle_map_debug(enabled: bool) -> void:
	for manager in get_tree().get_nodes_in_group("map_manager"):
		if not is_instance_valid(manager):
			continue
		var spawner = manager.get("_obstacle_spawner")
		if spawner != null and spawner.has_method("set_debug_draw"):
			spawner.set_debug_draw(enabled)


func _map_debug_line() -> String:
	var chunks: int = 0
	var obstacles: int = get_tree().get_node_count_in_group(&"obstacles")
	var map_seed: int = 0
	for manager in get_tree().get_nodes_in_group("map_manager"):
		if not is_instance_valid(manager):
			continue
		var spawner = manager.get("_obstacle_spawner")
		if spawner != null:
			if spawner.has_method("get_active_chunk_count"):
				chunks = int(spawner.get_active_chunk_count())
			if spawner.has_method("get_active_obstacle_count"):
				obstacles = int(spawner.get_active_obstacle_count())
			if spawner.has_method("get_resolved_seed"):
				map_seed = int(spawner.get_resolved_seed())
	return "MAP seed:%d chunks:%d obstacles:%d stuck:%d" % [map_seed, chunks, obstacles, get_tree().get_node_count_in_group(&"stuck_enemies")]


## --- Stats esenciales ---------------------------------------------------------

func on_health_changed(current: int, maximum: int) -> void:
	var previous: float = health_bar.value
	health_bar.max_value = max(1, maximum)
	health_bar.value = clampi(current, 0, maximum)
	health_value.text = "%d / %d" % [current, maximum]
	# Barra fantasma: arranca en el valor previo y baja lentamente hasta el actual.
	if previous > health_bar.value:
		_health_ghost = maxf(_health_ghost, previous)
		if _ghost_tween != null and _ghost_tween.is_valid():
			_ghost_tween.kill()
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(0.35)
		_ghost_tween.tween_method(func(v: float) -> void:
			_health_ghost = v
			health_bar.queue_redraw(), _health_ghost, health_bar.value, 0.4)
	else:
		_health_ghost = health_bar.value
	health_bar.queue_redraw()
	# Pulso de vida baja: la barra respira en rojo por debajo del 25%.
	var low: bool = maximum > 0 and float(current) / float(maximum) <= 0.25
	if low and _low_health_tween == null:
		_low_health_tween = create_tween().set_loops()
		_low_health_tween.tween_property(health_bar, "modulate", Color(1.5, 0.75, 0.75), 0.45)
		_low_health_tween.tween_property(health_bar, "modulate", Color(1, 1, 1), 0.45)
	elif not low and _low_health_tween != null:
		_low_health_tween.kill()
		_low_health_tween = null
		health_bar.modulate = Color(1, 1, 1)


func on_experience_changed(current: int, needed: int) -> void:
	xp_bar.max_value = max(1, needed)
	xp_bar.value = clampi(current, 0, needed)


func on_level_changed(level: int) -> void:
	_last_level = level
	level_label.text = "Nv. %d" % level
	# Punch del rotulo de nivel al subir: la mejora se nota tambien en el HUD.
	level_label.pivot_offset = level_label.size * 0.5
	var t := create_tween()
	t.tween_property(level_label, "scale", Vector2(1.35, 1.35), 0.08)
	t.tween_property(level_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func on_time_updated(seconds: float) -> void:
	_last_time = seconds
	var total: int = int(seconds)
	@warning_ignore("integer_division")
	time_label.text = "%02d:%02d" % [total / 60, total % 60]


func on_player_damaged(_amount: int) -> void:
	if _damage_flash_tween != null and _damage_flash_tween.is_valid():
		_damage_flash_tween.kill()
	_damage_flash.color.a = 0.32
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_damage_flash, "color:a", 0.0, 0.35)


## Kills e intensidad ya no se muestran durante el combate; se guardan para la pausa.
func on_stats_updated(kills: int, difficulty: float) -> void:
	_last_kills = kills
	_last_difficulty = difficulty


func on_companions_changed(current: int, maximum: int) -> void:
	_last_cats = current
	_last_max_cats = maximum
	_cats_label.text = "Gatos %d/%d" % [current, maximum]


## --- Mini-iconos de armas -----------------------------------------------------

func on_weapons_changed(snapshots: Array) -> void:
	_weapon_snapshots = snapshots
	_last_weapons = snapshots.size()
	_last_weapon_names.clear()
	for child in _weapons_bar.get_children():
		child.queue_free()
	var changed_index: int = -1
	var new_levels: Dictionary = {}
	for index in snapshots.size():
		var snapshot: Dictionary = snapshots[index]
		var color: Color = snapshot.get("color", Color(1, 1, 1))
		var weapon_type: StringName = snapshot.get("weapon_type", &"")
		var level: int = int(snapshot.get("level", 1))
		var display_name: String = snapshot.get("display_name", "Arma")
		var id: StringName = snapshot.get("id", &"")
		_last_weapon_names.append(display_name)
		var chip := _make_weapon_chip(LootCatalog.weapon_icon(weapon_type), level, color,
			"%s  Nv. %d" % [display_name, level], display_name,
			bool(snapshot.get("evolved", false)))
		_weapons_bar.add_child(chip)
		# FASE 13: detecta el UNICO slot que cambio (nuevo o subio de nivel) para
		# animar solo ese, no toda la barra.
		new_levels[id] = level
		if not _prev_weapon_levels.has(id) or int(_prev_weapon_levels[id]) < level:
			changed_index = index
	_prev_weapon_levels = new_levels
	if changed_index >= 0:
		_punch_weapon_chip(changed_index)
	# Tutorial (FASE 13): con la segunda arma ya hay "build" que consultar.
	if snapshots.size() >= 2:
		show_tip(&"build_panel")


func _make_weapon_chip(icon: StringName, level: int, color: Color, tooltip: String,
		display_name: String = "", evolved: bool = false) -> Control:
	var chip := PanelContainer.new()
	chip.tooltip_text = tooltip
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.09, 0.13, 0.78)
	# Un arma evolucionada se lee distinta: borde dorado mas grueso + estrella.
	box.border_color = Color(1.0, 0.82, 0.3) if evolved else color
	box.set_border_width_all(3 if evolved else 2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(6)
	chip.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	chip.add_child(col)
	var icon_node := IconDrawer.new()
	icon_node.custom_minimum_size = Vector2(34, 34)
	icon_node.icon_type = icon
	icon_node.accent = color
	icon_node.level = level
	col.add_child(icon_node)
	# FASE 13: nombre corto y estado bajo el icono; el jugador revisa su arsenal
	# de un vistazo sin abrir menus.
	var name_label := Label.new()
	name_label.text = ("★ " if evolved else "") + _short_weapon_name(display_name)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override("font", UIFonts.fredoka(600))
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color",
		Color(1.0, 0.88, 0.5) if evolved else Color(0.85, 0.88, 0.95))
	col.add_child(name_label)
	return chip


## Primera palabra del nombre del arma ("Pistola Gatuna" -> "Pistola"): cabe en
## el chip sin ensanchar la barra.
func _short_weapon_name(display_name: String) -> String:
	var first: String = display_name.get_slice(" ", 0)
	return first if first != "" else display_name


## Punch de escala SOLO en el chip que cambio (FASE 13).
func _punch_weapon_chip(index: int) -> void:
	if index < 0 or index >= _weapons_bar.get_child_count():
		return
	var chip := _weapons_bar.get_child(index) as Control
	if chip == null:
		return
	# El chip recien creado aun no tiene tamano: anclar el pivote al centro
	# cuando el layout lo resuelva.
	chip.resized.connect(func() -> void: chip.pivot_offset = chip.size * 0.5, CONNECT_ONE_SHOT)
	chip.scale = Vector2(1.35, 1.35)
	chip.modulate = Color(1.6, 1.5, 1.2)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(chip, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(chip, "modulate", Color(1, 1, 1), 0.4)


## Sinergias ya no se listan en el HUD; se conservan para la pausa.
func on_synergies_changed(states: Array) -> void:
	_synergy_states = states


## --- Mini-iconos de companeros ------------------------------------------------

func update_companion_roster(snapshots: Array) -> void:
	_companion_snapshots = snapshots
	for child in _companion_bar.get_children():
		child.queue_free()
	for snapshot in snapshots:
		var state_name: StringName = snapshot.get("state", &"active")
		var style: Dictionary = COMPANION_STATE_STYLE.get(state_name, COMPANION_STATE_STYLE[&"active"])
		var display_name: String = snapshot.get("display_name", "Companero")
		var ability_name: String = str(snapshot.get("ability_name", ""))
		var tooltip: String = "%s Â· %s" % [display_name, style["label"]]
		if ability_name != "":
			var ability_state: String = "lista"
			if bool(snapshot.get("ability_locked", false)):
				ability_state = "bloqueada"
			elif not bool(snapshot.get("ability_ready", true)):
				ability_state = "recargando"
			tooltip += "\n%s (%s)" % [ability_name, ability_state]
		_companion_bar.add_child(_make_companion_dot(snapshot, style, tooltip))


func _make_companion_dot(snapshot: Dictionary, style: Dictionary, tooltip: String) -> Control:
	var col := VBoxContainer.new()
	col.tooltip_text = tooltip
	col.add_theme_constant_override("separation", 2)
	var dot := IconDrawer.new()
	dot.custom_minimum_size = Vector2(30, 30)
	dot.icon_type = &"companion"
	dot.accent = snapshot.get("visual_color", Color.WHITE)
	dot.dimmed = snapshot.get("state", &"active") == &"downed"
	col.add_child(dot)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(26, 5)
	bar.show_percentage = false
	bar.max_value = max(1, int(snapshot.get("max_health", 1)))
	bar.value = int(snapshot.get("current_health", 0))
	bar.modulate = style["color"]
	col.add_child(bar)
	# Mini-barra de habilidad: llena y verde = lista; vaciandose = recargando;
	# roja = bloqueada por penalizacion de reaparicion.
	if snapshot.has("ability_cooldown_ratio"):
		var ability_bar := ProgressBar.new()
		ability_bar.custom_minimum_size = Vector2(26, 3)
		ability_bar.show_percentage = false
		ability_bar.max_value = 1.0
		ability_bar.value = 1.0 - float(snapshot.get("ability_cooldown_ratio", 0.0))
		if bool(snapshot.get("ability_locked", false)):
			ability_bar.modulate = Color(1.0, 0.45, 0.45, 0.9)
			ability_bar.value = 0.15
		elif bool(snapshot.get("ability_ready", false)):
			ability_bar.modulate = Color(0.55, 1.0, 0.72, 1.0)
		else:
			ability_bar.modulate = Color(0.85, 0.85, 0.6, 0.8)
		col.add_child(ability_bar)
	return col


## --- Barra de vida de jefe ----------------------------------------------------

func show_boss_bar(boss_name: String, max_health: int) -> void:
	_boss_bar.visible = true
	if _boss_bar_bg != null:
		_boss_bar_bg.visible = true
	_boss_name_label.text = boss_name
	_boss_health_bar.max_value = max(1, max_health)
	_boss_health_bar.value = max_health


func update_boss_bar(current: int, maximum: int) -> void:
	_boss_health_bar.max_value = max(1, maximum)
	_boss_health_bar.value = clampi(current, 0, maximum)


func hide_boss_bar() -> void:
	_boss_bar.visible = false
	if _boss_bar_bg != null:
		_boss_bar_bg.visible = false


## --- Mapa y objetivos ---------------------------------------------------------

func set_map_name(map_name: String) -> void:
	_map_name = map_name


func set_objective_text(text: String) -> void:
	_objective_text = text
	_objective_label.text = text


func set_game_over_title(text: String) -> void:
	_game_over_title = text if text != "" else "COLONIA PERDIDA"


## Informacion detallada para el panel de pausa (centro de informacion).
func get_run_info() -> Dictionary:
	return {
		"map_name": _map_name,
		"objective": _objective_text,
		"time": _last_time,
		"level": _last_level,
		"kills": _last_kills,
		"difficulty": _last_difficulty,
		"cats": _last_cats,
		"max_cats": _last_max_cats,
		"weapons": _weapon_snapshots,
		"companions": _companion_snapshots,
		"synergies": _synergy_states,
	}


## --- Fin de partida -----------------------------------------------------------

## Oculta el HUD de combate al abrir un panel de fin de partida: los rotulos de
## racha/fase/armas se colaban ENCIMA del resumen y lo hacian ver desordenado.
func _hide_gameplay_chrome() -> void:
	for node in [$TopLeft, $TopCenter, $TopRight, _weapons_bar, _companion_bar,
			_combo_label, _phase_label, _announcement_label, event_label,
			_downed_arrow, _downed_tag, rescue_arrow, rescue_status_label,
			_tip_panel]:
		if node != null and is_instance_valid(node):
			(node as CanvasItem).visible = false
	if _build_panel != null and is_instance_valid(_build_panel):
		_build_panel.queue_free()
		_build_panel = null
	_rescue_target_active = false


func show_run_end(summary: Dictionary) -> void:
	if bool(summary.get("victory", false)):
		show_victory(summary)
	else:
		show_defeat(summary)


func show_victory(summary: Dictionary) -> void:
	hide_boss_bar()
	_hide_gameplay_chrome()
	_victory_title.text = summary.get("victory_message", "ZONA ASEGURADA").to_upper()
	_victory_subtitle.text = summary.get("map_name", "") + _mode_suffix() + _record_suffix(summary)
	_fill_summary_tiles(_victory_tiles, summary)
	_victory_details.text = _summary_details(summary)
	_victory_details.visible = false
	if is_instance_valid(_victory_tiles):
		_victory_tiles.visible = true
	_victory_details_button.text = "Detalles"
	_fit_run_end_cards()
	_victory_panel.visible = true
	_animate_victory_panel()
	if is_instance_valid(_victory_retry):
		_victory_retry.call_deferred("grab_focus")


func show_defeat(summary: Dictionary) -> void:
	hide_boss_bar()
	_hide_gameplay_chrome()
	_defeat_title.text = summary.get("victory_message", _game_over_title).to_upper()
	_defeat_subtitle.text = summary.get("map_name", _map_name) + _mode_suffix() + _record_suffix(summary)
	_fill_summary_tiles(_defeat_tiles, summary)
	_defeat_details.text = _summary_details(summary)
	_defeat_details.visible = false
	if is_instance_valid(_defeat_tiles):
		_defeat_tiles.visible = true
	_defeat_details_button.text = "Detalles"
	_fit_run_end_cards()
	game_over_panel.visible = true
	if is_instance_valid(_defeat_retry):
		_defeat_retry.call_deferred("grab_focus")


## Crea el mosaico de estadÃ­sticas y lo coloca donde estaba el resumen de texto
## (que se oculta). Se rellena en cada fin de partida con _fill_summary_tiles.
func _make_summary_tiles(content: Node, summary_label: Label) -> GridContainer:
	if content == null:
		return null
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", MenuTheme.GAP_S)
	grid.add_theme_constant_override("v_separation", MenuTheme.GAP_S)
	content.add_child(grid)
	if summary_label != null:
		summary_label.visible = false
		content.move_child(grid, summary_label.get_index())
	return grid


## Rellena el mosaico con las cifras clave de la partida como tarjetas con icono.
func _fill_summary_tiles(grid: GridContainer, summary: Dictionary) -> void:
	if grid == null:
		return
	for child in grid.get_children():
		child.queue_free()
	var total: int = int(summary.get("time", 0.0))
	# Partida libre (score >= 0): Puntuacion en vez de Sardinas.
	var score: int = int(summary.get("score", -1))
	if score >= 0:
		var label: String = "%d" % score
		if bool(summary.get("is_new_record", false)):
			label = "â˜… %d" % score
		grid.add_child(MenuTheme.make_stat_card(label, "PuntuaciÃ³n", MenuTheme.GOLD, &"star"))
	else:
		grid.add_child(MenuTheme.make_stat_card("+%d" % int(summary.get("sardines_earned", 0)), "Sardinas", MenuTheme.GOLD, &"sardine"))
	@warning_ignore("integer_division")
	grid.add_child(MenuTheme.make_stat_card("%02d:%02d" % [total / 60, total % 60], "Tiempo", MenuTheme.CYAN, &"clock"))
	grid.add_child(MenuTheme.make_stat_card(str(int(summary.get("kills", 0))), "Enemigos", MenuTheme.DANGER, &"boss"))
	grid.add_child(MenuTheme.make_stat_card(str(int(summary.get("cats", 0))), "Gatos", MenuTheme.PURPLE, &"companion"))
	grid.add_child(MenuTheme.make_stat_card(str(int(summary.get("level", 1))), "Nivel", MenuTheme.CYAN, &"upgrade"))
	grid.add_child(MenuTheme.make_stat_card(str(int(summary.get("bosses", 0))), "Jefes", MenuTheme.ACCENT, &"shield"))


## Resumen limpio: solo los datos clave.
func _summary_core(summary: Dictionary) -> String:
	var total: int = int(summary.get("time", 0.0))
	@warning_ignore("integer_division")
	var lines: Array[String] = [
		"Sardinas  +%d" % int(summary.get("sardines_earned", 0)),
		"Tiempo  %02d:%02d" % [total / 60, total % 60],
		"Enemigos  %d" % int(summary.get("kills", 0)),
		"Gatos  %d" % int(summary.get("cats", 0)),
		"Nivel  %d" % int(summary.get("level", 1)),
		"Jefes  %d" % int(summary.get("bosses", 0)),
	]
	return "\n".join(lines)


## Desglose detallado: solo visible al pulsar "Detalles".
func _summary_details(summary: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Arsenal: %s" % _weapon_loadout_text())
	# Partida libre (score >= 0): semilla + desglose de puntuacion (sin Sardinas).
	if int(summary.get("score", -1)) >= 0:
		var seed_value: int = int(summary.get("world_seed", 0))
		if seed_value != 0:
			lines.append("Semilla: %d  (rejuega la misma para competir)" % seed_value)
		lines.append_array(_score_breakdown_lines(summary))
		lines.append("Mejor puntuaciÃ³n de esta zona/dificultad: %d" % int(summary.get("best_score", 0)))
		return "\n".join(lines)
	lines.append_array(_sardine_breakdown_lines(summary))
	lines.append("Sardinas totales: %d" % int(summary.get("total_sardines", 0)))
	return "\n".join(lines)


## Desglose de la puntuacion de Partida libre.
func _score_breakdown_lines(summary: Dictionary) -> Array[String]:
	var b: Dictionary = summary.get("score_breakdown", {})
	if b.is_empty():
		return ["PuntuaciÃ³n: %d" % int(summary.get("score", 0))]
	var lines: Array[String] = ["Desglose de puntuaciÃ³n:"]
	for entry in [["Enemigos", "kills"], ["Nivel", "level"], ["Gatos", "cats"], ["Mini-jefes", "minibosses"], ["Jefes", "bosses"], ["Tiempo", "time"], ["Bonus victoria", "victory"]]:
		var value: int = int(b.get(entry[1], 0))
		if value > 0:
			lines.append("- %s: +%d" % [entry[0], value])
	lines.append("- Multiplicador dificultad: x%.2f" % float(b.get("difficulty_mult", 1.0)))
	var plague_mult: float = float(b.get("plague_mult", 1.0))
	if plague_mult > 1.001:
		lines.append("- Multiplicador Plaga: x%.2f" % plague_mult)
	lines.append("Total: %d" % int(b.get("total", summary.get("score", 0))))
	return lines


func _toggle_victory_details() -> void:
	_victory_details.visible = not _victory_details.visible
	_victory_details_button.text = "Ocultar" if _victory_details.visible else "Detalles"
	# Los detalles REEMPLAZAN al mosaico: sumados, el contenido superaba el alto
	# de la pantalla y el panel se salia por abajo.
	if is_instance_valid(_victory_tiles):
		_victory_tiles.visible = not _victory_details.visible


func _toggle_defeat_details() -> void:
	_defeat_details.visible = not _defeat_details.visible
	_defeat_details_button.text = "Ocultar" if _defeat_details.visible else "Detalles"
	if is_instance_valid(_defeat_tiles):
		_defeat_tiles.visible = not _defeat_details.visible


func _sardine_breakdown_lines(summary: Dictionary) -> Array[String]:
	var breakdown: Dictionary = summary.get("sardine_breakdown", {})
	if breakdown.is_empty():
		return []
	var lines: Array[String] = ["Desglose de Sardinas:"]
	var entries: Array = [
		["Base del mapa", "base_map"],
		["Tiempo", "time"],
		["Enemigos", "kills"],
		["Gatos", "cats"],
		["Companeros", "active_companions"],
		["Mini-jefes", "minibosses"],
		["Jefes", "bosses"],
		["Objetivos", "objective"],
		["Bonus victoria", "victory"],
	]
	for entry in entries:
		var value: int = int(breakdown.get(entry[1], 0))
		if value > 0:
			lines.append("- %s: +%d" % [entry[0], value])
	lines.append("- Multiplicador mapa: x%.2f" % float(breakdown.get("map_multiplier", 1.0)))
	var sardine_mult: float = float(breakdown.get("sardine_multiplier", 1.0))
	if sardine_mult > 1.001:
		lines.append("- Mochila de Sardinas: x%.2f" % sardine_mult)
	# Bonus de partida libre (plaga) y de historia (dificultad + first-clear).
	for extra in [["Bonus del refugio", "refugio"], ["Bonus de Plaga", "plaga"], ["Bonus de dificultad", "dificultad"], ["Bonus de historia", "historia"]]:
		var extra_value: int = int(breakdown.get(extra[1], 0))
		if extra_value > 0:
			lines.append("- %s: +%d" % [extra[0], extra_value])
	return lines


func _weapon_loadout_text() -> String:
	if _last_weapon_names.is_empty():
		return "Pistola Gatuna"
	return ", ".join(_last_weapon_names)


func toggle_meta_panel() -> void:
	if is_instance_valid(_meta_panel) and _meta_panel.has_method("toggle"):
		_meta_panel.toggle()


func _is_coop() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_coop") and gf.is_coop()


## Sufijo de modo para el resumen de fin de partida.
func _mode_suffix() -> String:
	return "  Â·  Coop local" if _is_coop() else ""


## Sufijo de nuevo record (Partida libre).
func _record_suffix(summary: Dictionary) -> String:
	return "   Â·   Â¡NUEVO RÃ‰CORD!" if bool(summary.get("is_new_record", false)) else ""




func _animate_victory_panel() -> void:
	var content := $VictoryPanel/Center/Content as Control
	if content == null:
		return
	content.scale = Vector2(0.88, 0.88)
	content.pivot_offset = content.size * 0.5
	var tween := create_tween()
	tween.tween_property(content, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spawn_victory_confetti()


func _spawn_victory_confetti() -> void:
	for i in 18:
		var piece := ColorRect.new()
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		piece.size = Vector2(7, 12)
		piece.position = Vector2(randf_range(140.0, get_viewport().get_visible_rect().size.x - 140.0), randf_range(60.0, 180.0))
		piece.color = [Color(0.55, 1.0, 0.75, 0.9), Color(1.0, 0.84, 0.35, 0.9), Color(0.55, 0.85, 1.0, 0.9)][i % 3]
		_victory_panel.add_child(piece)
		# Detras de la tarjeta central (indice 1: tras el fondo, antes del Card):
		# el confeti celebra sin ensuciar el resumen.
		_victory_panel.move_child(piece, 1)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(piece, "position:y", piece.position.y + randf_range(120.0, 240.0), randf_range(1.0, 1.8))
		tween.tween_property(piece, "rotation", randf_range(-5.0, 5.0), 1.4)
		tween.tween_property(piece, "modulate:a", 0.0, 1.4)
		tween.chain().tween_callback(piece.queue_free)



func _play_ui(sound_name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(sound_name)


## --- Guia de rescate ----------------------------------------------------------

func set_rescue_status(text: String, active: bool) -> void:
	rescue_status_label.visible = active
	rescue_status_label.text = text


func set_rescue_target(active: bool, world_position: Vector2) -> void:
	_rescue_target_active = active
	_rescue_target_position = world_position
	rescue_arrow.visible = active


func _update_rescue_arrow() -> void:
	if not _rescue_target_active:
		rescue_arrow.visible = false
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		rescue_arrow.visible = false
		return
	var center: Vector2 = camera.get_screen_center_position()
	var direction: Vector2 = center.direction_to(_rescue_target_position)
	if direction == Vector2.ZERO:
		direction = Vector2.UP
	rescue_arrow.rotation = direction.angle() + PI * 0.5
	rescue_arrow_glyph.modulate.a = 0.76 + sin(Time.get_ticks_msec() * 0.01) * 0.18
	rescue_arrow.visible = true


## Flecha VERDE hacia el companero caido mas cercano: sin ella no habia forma de
## saber donde quedo un gato derribado fuera de camara. Se crea en codigo (clon
## del patron de la flecha de rescate) y solo aparece si hay un caido lejos.
var _downed_arrow: Control
var _downed_arrow_glyph: Label
var _downed_tag: Label


func _update_downed_arrow() -> void:
	var camera := get_viewport().get_camera_2d()
	var target: Node2D = null
	if camera != null:
		var best: float = INF
		var center: Vector2 = camera.get_screen_center_position()
		for c in get_tree().get_nodes_in_group("companions"):
			if not is_instance_valid(c) or not (c is Node2D):
				continue
			if not c.has_method("is_downed") or not c.is_downed():
				continue
			var d: float = center.distance_to((c as Node2D).global_position)
			if d < best:
				best = d
				target = c
		# Cerca de camara ya se ve el ping/etiqueta del propio gato: sin flecha.
		if target != null and best < 320.0:
			target = null
	if target == null:
		if _downed_arrow != null:
			_downed_arrow.visible = false
			_downed_tag.visible = false
		return
	if _downed_arrow == null:
		_downed_arrow = Control.new()
		_downed_arrow.name = "DownedArrow"
		_downed_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_downed_arrow.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_downed_arrow.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 150.0)
		add_child(_downed_arrow)
		_downed_arrow_glyph = Label.new()
		_downed_arrow_glyph.text = "â–²"
		_downed_arrow_glyph.add_theme_font_size_override("font_size", 30)
		_downed_arrow_glyph.add_theme_color_override("font_color", Color(0.62, 1.0, 0.72))
		_downed_arrow_glyph.position = Vector2(-12.0, -34.0)
		_downed_arrow.add_child(_downed_arrow_glyph)
		# Rotulo FIJO (no rota con la flecha) bajo el ancla.
		_downed_tag = Label.new()
		_downed_tag.name = "DownedTag"
		_downed_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_downed_tag.text = "GATO CAIDO"
		_downed_tag.add_theme_font_size_override("font_size", 12)
		_downed_tag.add_theme_color_override("font_color", Color(0.62, 1.0, 0.72, 0.9))
		_downed_tag.position = _downed_arrow.position + Vector2(-38.0, 40.0)
		add_child(_downed_tag)
	var dir: Vector2 = camera.get_screen_center_position().direction_to(target.global_position)
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	_downed_arrow.rotation = dir.angle() + PI * 0.5
	_downed_arrow_glyph.modulate.a = 0.76 + sin(Time.get_ticks_msec() * 0.012) * 0.2
	_downed_arrow.visible = true
	_downed_tag.visible = true


## Aviso de IMPACTO (Lilita One): apariciones de boss/mini-boss, fases especiales.
## Texto corto y grande, con entrada elÃ¡stica y salida rÃ¡pida; no bloquea la vista.
## Para mensajes informativos ("Arma: X", "Gato cercano") usar show_event_message.
var _announcement_label: Label
var _announcement_tween: Tween


func show_announcement(text: String, duration: float = 1.6) -> void:
	if _announcement_label == null:
		var band := CenterContainer.new()
		band.name = "AnnouncementBand"
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.set_anchors_preset(Control.PRESET_TOP_WIDE)
		band.offset_top = 218.0
		band.offset_bottom = 290.0
		add_child(band)
		_announcement_label = Label.new()
		_announcement_label.theme_type_variation = &"BossAnnouncement"
		_announcement_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.5))
		_announcement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		band.add_child(_announcement_label)
	if _announcement_tween != null and _announcement_tween.is_valid():
		_announcement_tween.kill()
	_announcement_label.text = text
	_announcement_label.visible = true
	_announcement_label.modulate.a = 0.0
	_announcement_label.pivot_offset = _announcement_label.size * 0.5
	_announcement_label.scale = Vector2(0.7, 0.7)
	_announcement_tween = create_tween()
	_announcement_tween.set_parallel(true)
	_announcement_tween.tween_property(_announcement_label, "modulate:a", 1.0, 0.12)
	_announcement_tween.tween_property(_announcement_label, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announcement_tween.chain().tween_interval(duration)
	_announcement_tween.chain().tween_property(_announcement_label, "modulate:a", 0.0, 0.22)
	_announcement_tween.chain().tween_callback(func() -> void:
		_announcement_label.visible = false)


func show_event_message(text: String, duration: float = 1.8) -> void:
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	event_label.visible = true
	event_label.text = text
	event_label.modulate.a = 1.0
	_event_tween = create_tween()
	_event_tween.tween_interval(duration)
	_event_tween.tween_property(event_label, "modulate:a", 0.0, 0.35)
	_event_tween.tween_callback(func() -> void:
		event_label.visible = false
	)


## --- FASE 13: confirmacion de botin -------------------------------------------

## Toast de ~2 s tras recoger algo: cabecera de categoria ("MEJORA OBTENIDA"...),
## nombre y efecto en llano. En coop aparece en la MITAD del recolector y cada
## mitad tiene su propio hueco (no se pisan entre jugadores). No pausa nada.
func show_loot_toast(header: String, title: String, body: String,
		accent: Color, player_id: int = 1) -> void:
	var side: int = clampi(player_id, 1, 2) if _is_coop() else 1
	# Un toast nuevo del mismo lado sustituye al anterior: sin colas que tapen.
	var previous = _loot_toast_by_side.get(side)
	if previous != null and is_instance_valid(previous):
		previous.queue_free()

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.065, 0.1, 0.94)
	box.border_color = accent
	box.set_border_width_all(2)
	box.border_width_top = 4
	box.set_corner_radius_all(10)
	box.set_content_margin_all(10)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 8
	panel.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	panel.add_child(col)
	var header_label := Label.new()
	header_label.text = header
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_label.add_theme_font_override("font", UIFonts.lilita())
	header_label.add_theme_font_size_override("font_size", UIFonts.scaled(15))
	header_label.add_theme_color_override("font_color", accent)
	col.add_child(header_label)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", UIFonts.fredoka(600))
	title_label.add_theme_font_size_override("font_size", UIFonts.scaled(15))
	title_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	col.add_child(title_label)
	if body != "":
		var body_label := Label.new()
		body_label.text = body
		body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body_label.add_theme_font_size_override("font_size", UIFonts.scaled(12))
		body_label.add_theme_color_override("font_color", Color(0.8, 0.83, 0.9))
		col.add_child(body_label)
	add_child(panel)
	_loot_toast_by_side[side] = panel

	# Posicion: centro de la mitad correspondiente (o de la pantalla en solo),
	# bajo la zona de anuncios para no chocar con la barra de boss.
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var center_x: float = vp.x * 0.5
	if _is_coop():
		center_x = vp.x * (0.25 if side == 1 else 0.75)
	panel.position = Vector2(center_x - panel.size.x * 0.5, 300.0)
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.8, 0.8)
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.14)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(1.9)
	tween.chain().tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(panel.queue_free)


## --- FASE 13: consejos de tutorial (una vez por perfil) ------------------------

## Muestra el consejo `tip_id` del catalogo si este perfil no lo vio nunca.
## Persistido en el guardado ("tip_seen_*"); reiniciable desde Opciones→Juego.
func show_tip(tip_id: StringName) -> void:
	if _tips_shown.has(tip_id):
		return
	_tips_shown[tip_id] = true
	var text: String = LootCatalog.tip_text(tip_id)
	if text == "":
		return
	var save: Node = get_node_or_null("/root/SaveManager")
	var key: String = "tip_seen_%s" % tip_id
	if save != null and save.has_method("get_value") and bool(save.get_value(key, false)):
		return
	if save != null and save.has_method("set_value"):
		save.set_value(key, true)
	_display_tip(text)


func _display_tip(text: String) -> void:
	if _tip_panel == null or not is_instance_valid(_tip_panel):
		_tip_panel = PanelContainer.new()
		_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.05, 0.07, 0.06, 0.94)
		box.border_color = Color(0.62, 1.0, 0.72)
		box.set_border_width_all(1)
		box.border_width_left = 5
		box.set_corner_radius_all(10)
		box.set_content_margin_all(10)
		box.content_margin_left = 16.0
		box.content_margin_right = 16.0
		_tip_panel.add_theme_stylebox_override("panel", box)
		var label := Label.new()
		label.name = "TipText"
		label.add_theme_font_override("font", UIFonts.fredoka(500))
		label.add_theme_font_size_override("font_size", UIFonts.scaled(14))
		label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.94))
		_tip_panel.add_child(label)
		add_child(_tip_panel)
	var tip_label := _tip_panel.get_node("TipText") as Label
	tip_label.text = "💡 " + text
	_tip_panel.visible = true
	if _tip_tween != null and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_panel.modulate.a = 0.0
	# Banda inferior central: fuera del combate visual y de los toasts de botin.
	await get_tree().process_frame
	if not is_instance_valid(_tip_panel):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_tip_panel.position = Vector2(vp.x * 0.5 - _tip_panel.size.x * 0.5, vp.y - 118.0)
	_tip_tween = create_tween()
	_tip_tween.tween_property(_tip_panel, "modulate:a", 1.0, 0.25)
	_tip_tween.tween_interval(4.5)
	_tip_tween.tween_property(_tip_panel, "modulate:a", 0.0, 0.4)
	_tip_tween.tween_callback(func() -> void:
		if is_instance_valid(_tip_panel):
			_tip_panel.visible = false)


## --- FASE 13: panel de build (tecla B, sin pausar) -----------------------------

func _toggle_build_panel() -> void:
	if _build_panel != null and is_instance_valid(_build_panel):
		_build_panel.queue_free()
		_build_panel = null
		_play_ui(&"ui_close")
		return
	_build_panel = _build_build_panel()
	add_child(_build_panel)
	_play_ui(&"ui_open")


## Panel lateral con la build actual, separada en Armas / Mejoras / Mejoras de
## compañero / Mutaciones, en lenguaje llano (sin formulas internas). En coop
## muestra una columna por jugador. Se refresca al abrirse: es una foto, no una
## vista viva (suficiente para consultar y barato de mantener).
func _build_build_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "BuildPanel"
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.055, 0.09, 0.95)
	box.border_color = Color(0.45, 0.85, 1.0, 0.9)
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.set_content_margin_all(14)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 12
	panel.add_theme_stylebox_override("panel", box)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)
	var title := Label.new()
	title.text = "TU BUILD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIFonts.lilita())
	title.add_theme_font_size_override("font_size", UIFonts.scaled(18))
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	root.add_child(title)
	var hint := Label.new()
	hint.text = "Pulsa B para cerrar · El juego sigue en marcha"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", UIFonts.scaled(10))
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	root.add_child(hint)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	root.add_child(columns)
	var players: Array = get_tree().get_nodes_in_group("players")
	players.sort_custom(func(a, b) -> bool: return int(a.get("player_id")) < int(b.get("player_id")))
	for player in players:
		if is_instance_valid(player):
			columns.add_child(_build_player_column(player, players.size() > 1))

	# Centrado tras el layout (el tamano depende del contenido).
	panel.resized.connect(func() -> void:
		panel.offset_left = -panel.size.x * 0.5
		panel.offset_top = -panel.size.y * 0.5
		panel.offset_right = panel.size.x * 0.5
		panel.offset_bottom = panel.size.y * 0.5, CONNECT_ONE_SHOT)
	return panel


func _build_player_column(player: Node, show_tag: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size = Vector2(280, 0)
	if show_tag:
		col.add_child(_build_section_label(CoopConfig.player_tag(int(player.get("player_id"))), Color(1.0, 0.85, 0.4)))

	# --- Armas ---
	col.add_child(_build_section_label("Armas", LootCatalog.category_color(&"weapon")))
	var snapshots: Array = []
	if player.has_method("get_weapon_manager"):
		var wm: Node = player.get_weapon_manager()
		if wm != null and wm.has_method("get_weapon_snapshots"):
			snapshots = wm.get_weapon_snapshots()
	for snapshot in snapshots:
		var evolved: bool = bool(snapshot.get("evolved", false))
		var line: String = "%s%s · Nv. %d/%d" % ["★ " if evolved else "",
			snapshot.get("display_name", "Arma"), int(snapshot.get("level", 1)),
			int(snapshot.get("max_level", 5))]
		col.add_child(_build_entry_label(line, str(snapshot.get("description", ""))))
	if snapshots.is_empty():
		col.add_child(_build_entry_label("Sin armas", ""))

	# --- Mejoras / compañero / mutaciones, desde lo recogido en la run ---
	var counts: Dictionary = {}
	var raw_counts = player.get("powerup_counts")
	if raw_counts is Dictionary:
		counts = raw_counts
	for section in [[&"upgrade", "Mejoras"], [&"companion", "Mejoras de compañero"], [&"mutation", "Mutaciones"]]:
		var category: StringName = section[0]
		col.add_child(_build_section_label(section[1], LootCatalog.category_color(category)))
		var any: bool = false
		for effect_id in counts:
			var data: PowerUpData = PowerUpRegistry.get_by_id(effect_id)
			if data == null or LootCatalog.powerup_category(data) != category:
				continue
			any = true
			var stacks: int = int(counts[effect_id])
			var name_line: String = data.display_name
			if stacks > 1:
				name_line += " ×%d" % stacks
			col.add_child(_build_entry_label(name_line, LootCatalog.effect_line(data.effect_id())))
		if not any:
			col.add_child(_build_entry_label("Nada todavía", ""))
	return col


func _build_section_label(text: String, accent: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UIFonts.fredoka(700))
	label.add_theme_font_size_override("font_size", UIFonts.scaled(13))
	label.add_theme_color_override("font_color", accent)
	return label


func _build_entry_label(title: String, effect: String) -> Label:
	var label := Label.new()
	label.text = "  %s" % title if effect == "" else "  %s — %s" % [title, effect]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UIFonts.scaled(11))
	label.add_theme_color_override("font_color", Color(0.86, 0.89, 0.95))
	return label
