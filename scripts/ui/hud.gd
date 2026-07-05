extends CanvasLayer
## HUD minimalista (Fase 08.5). Durante el combate solo se muestra lo esencial:
## vida/XP/nivel (arriba izq.), tiempo (arriba centro), objetivo corto + gatos
## (arriba der.) y mini-iconos de armas y companeros. La informacion detallada
## (kills, intensidad, sinergias, mapa, estado de companeros) se conserva en memoria
## y se ofrece en la pausa (ESC) via get_run_info(). No saturar la pantalla de juego.

signal upgrade_card_selected(card_index: int)

const META_PANEL_SCENE := preload("res://scenes/ui/MetaUpgradePanel.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/menus/PauseMenu.tscn")
const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const IconDrawer = preload("res://scripts/ui/icon_drawer.gd")

var _meta_panel: Control
var _pause_menu: Control

const RARITY_STYLE: Dictionary = {
	&"common": {"label": "COMUN", "color": Color(0.78, 0.82, 0.88)},
	&"rare": {"label": "RARO", "color": Color(0.36, 0.66, 1.0)},
	&"epic": {"label": "EPICO", "color": Color(0.78, 0.45, 1.0)},
}

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
@onready var upgrade_panel: Control = $UpgradePanel
@onready var _upgrade_title: Label = $UpgradePanel/Center/Content/Title
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
@onready var _upgrade_buttons: Array[Button] = [
	$UpgradePanel/Center/Content/Cards/Card1,
	$UpgradePanel/Center/Content/Cards/Card2,
	$UpgradePanel/Center/Content/Cards/Card3
]
@onready var _upgrade_titles: Array[Label] = [
	$UpgradePanel/Center/Content/Cards/Card1/Margin/Content/Title,
	$UpgradePanel/Center/Content/Cards/Card2/Margin/Content/Title,
	$UpgradePanel/Center/Content/Cards/Card3/Margin/Content/Title
]
@onready var _upgrade_descriptions: Array[Label] = [
	$UpgradePanel/Center/Content/Cards/Card1/Margin/Content/Description,
	$UpgradePanel/Center/Content/Cards/Card2/Margin/Content/Description,
	$UpgradePanel/Center/Content/Cards/Card3/Margin/Content/Description
]
@onready var _upgrade_icons: Array[Label] = [
	$UpgradePanel/Center/Content/Cards/Card1/Margin/Content/Icon,
	$UpgradePanel/Center/Content/Cards/Card2/Margin/Content/Icon,
	$UpgradePanel/Center/Content/Cards/Card3/Margin/Content/Icon
]
@onready var _upgrade_metas: Array[Label] = [
	$UpgradePanel/Center/Content/Cards/Card1/Margin/Content/Meta,
	$UpgradePanel/Center/Content/Cards/Card2/Margin/Content/Meta,
	$UpgradePanel/Center/Content/Cards/Card3/Margin/Content/Meta
]

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


func _ready() -> void:
	game_over_panel.visible = false
	game_over_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	upgrade_panel.visible = false
	upgrade_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	rescue_status_label.visible = false
	rescue_arrow.visible = false
	event_label.visible = false
	_boss_bar.visible = false
	_victory_panel.visible = false
	_victory_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_to_group("hud")
	_style_bars()
	_build_vignette()
	# Panel de mejoras permanentes (Fase 07) y menu de pausa (Fase 08).
	_meta_panel = META_PANEL_SCENE.instantiate()
	add_child(_meta_panel)
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	add_child(_pause_menu)
	update_companion_roster([])
	on_weapons_changed([])

	for index in _upgrade_buttons.size():
		var button: Button = _upgrade_buttons[index]
		button.pressed.connect(_on_upgrade_button_pressed.bind(index))
		button.pressed.connect(func() -> void: _play_ui(&"ui_click"))
		button.pivot_offset = button.custom_minimum_size * 0.5
		button.mouse_entered.connect(_on_card_hover.bind(button, true))
		button.mouse_exited.connect(_on_card_hover.bind(button, false))

	_victory_details_button.pressed.connect(_toggle_victory_details)
	_victory_details_button.pressed.connect(func() -> void: _play_ui(&"ui_click"))
	_defeat_details_button.pressed.connect(_toggle_defeat_details)
	_defeat_details_button.pressed.connect(func() -> void: _play_ui(&"ui_click"))

	_perf = get_node_or_null("/root/Performance")
	_build_combo_label()
	_build_debug_overlay()
	_build_run_end_buttons($VictoryPanel/Center/Content)
	_build_run_end_buttons($GameOverPanel/Center/Content)


## Botones clicables de fin de partida (además de los atajos R/M/ESC).
func _build_run_end_buttons(content: Node) -> void:
	if content == null:
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var retry := MenuTheme.make_button("Reintentar", MenuTheme.ZOMBIE)
	retry.custom_minimum_size = Vector2(190, 46)
	retry.pressed.connect(_on_run_end_retry)
	row.add_child(retry)
	var meta := MenuTheme.make_button("Mejoras", MenuTheme.ACCENT)
	meta.custom_minimum_size = Vector2(190, 46)
	meta.pressed.connect(func() -> void:
		_play_ui(&"ui_click")
		toggle_meta_panel())
	row.add_child(meta)
	var menu := MenuTheme.make_button("Menu", MenuTheme.TEXT_DIM)
	menu.custom_minimum_size = Vector2(190, 46)
	menu.pressed.connect(_on_run_end_menu)
	row.add_child(menu)
	content.add_child(row)


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


## Viñeta radial sutil (recurso interno, sin texturas externas): oscurece los
## bordes de la pantalla para dar profundidad y centrar la vista en el combate.
## Va al índice 0 del CanvasLayer, debajo de todos los paneles del HUD.
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


## Rotulo de racha de bajas: aparece a partir de 4 bajas encadenadas, con punch
## en cada baja y color que se calienta con la racha.
func _build_combo_label() -> void:
	_combo_label = Label.new()
	_combo_label.visible = false
	_combo_label.add_theme_font_size_override("font_size", 24)
	_combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_combo_label.add_theme_constant_override("shadow_offset_x", 2)
	_combo_label.add_theme_constant_override("shadow_offset_y", 2)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var center := $TopCenter as Control
	if center != null:
		center.add_child(_combo_label)
	else:
		add_child(_combo_label)


## Llamado por Feedback.register_kill vía el grupo "hud". count=0 termina la racha.
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
	title.text = "★ Mision completada"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	v.add_child(title)
	var body := Label.new()
	body.text = "%s   +%d 🐟" % [data["name"], int(data["reward"])]
	body.add_theme_font_size_override("font_size", 17)
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


func _style_bars() -> void:
	# Vida en rojo, XP en azul, jefe en carmesi. Bordes y highlight superior para
	# que las barras se lean "con volumen" en vez del ProgressBar plano por defecto.
	_apply_bar_color(health_bar, Color(0.9, 0.36, 0.38))
	_apply_bar_color(xp_bar, Color(0.4, 0.72, 1.0))
	_apply_bar_color(_boss_health_bar, Color(0.82, 0.22, 0.28), 3.0)
	# Barra fantasma de vida: al recibir daño, un tramo palido persigue al valor
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
	var seed: int = 0
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
				seed = int(spawner.get_resolved_seed())
	return "MAP seed:%d chunks:%d obstacles:%d stuck:%d" % [seed, chunks, obstacles, get_tree().get_node_count_in_group(&"stuck_enemies")]


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
	for snapshot in snapshots:
		var color: Color = snapshot.get("color", Color(1, 1, 1))
		var weapon_type: StringName = snapshot.get("weapon_type", &"")
		var style: Dictionary = WEAPON_TYPE_STYLE.get(weapon_type, {"icon": &"weapon_projectile"})
		var level: int = int(snapshot.get("level", 1))
		var display_name: String = snapshot.get("display_name", "Arma")
		_last_weapon_names.append(display_name)
		_weapons_bar.add_child(_make_weapon_chip(style["icon"], level, color, "%s  Nv. %d" % [display_name, level]))


func _make_weapon_chip(icon: StringName, level: int, color: Color, tooltip: String) -> Control:
	var chip := PanelContainer.new()
	chip.tooltip_text = tooltip
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.09, 0.13, 0.78)
	box.border_color = color
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(6)
	chip.add_theme_stylebox_override("panel", box)
	var icon_node := IconDrawer.new()
	icon_node.custom_minimum_size = Vector2(34, 34)
	icon_node.icon_type = icon
	icon_node.accent = color
	icon_node.level = level
	chip.add_child(icon_node)
	return chip


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
		_companion_bar.add_child(_make_companion_dot(snapshot, style, "%s · %s" % [display_name, style["label"]]))


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
	return col


## --- Barra de vida de jefe ----------------------------------------------------

func show_boss_bar(boss_name: String, max_health: int) -> void:
	_boss_bar.visible = true
	_boss_name_label.text = boss_name
	_boss_health_bar.max_value = max(1, max_health)
	_boss_health_bar.value = max_health


func update_boss_bar(current: int, maximum: int) -> void:
	_boss_health_bar.max_value = max(1, maximum)
	_boss_health_bar.value = clampi(current, 0, maximum)


func hide_boss_bar() -> void:
	_boss_bar.visible = false


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

func show_run_end(summary: Dictionary) -> void:
	if bool(summary.get("victory", false)):
		show_victory(summary)
	else:
		show_defeat(summary)


func show_victory(summary: Dictionary) -> void:
	hide_boss_bar()
	_victory_title.text = summary.get("victory_message", "ZONA ASEGURADA").to_upper()
	_victory_subtitle.text = summary.get("map_name", "")
	_victory_summary.text = _summary_core(summary)
	_victory_details.text = _summary_details(summary)
	_victory_details.visible = false
	_victory_details_button.text = "Detalles"
	_victory_panel.visible = true
	_animate_victory_panel()


func show_defeat(summary: Dictionary) -> void:
	hide_boss_bar()
	_defeat_title.text = summary.get("victory_message", _game_over_title).to_upper()
	_defeat_subtitle.text = summary.get("map_name", _map_name)
	_defeat_summary.text = _summary_core(summary)
	_defeat_details.text = _summary_details(summary)
	_defeat_details.visible = false
	_defeat_details_button.text = "Detalles"
	game_over_panel.visible = true


## Resumen limpio: solo los datos clave.
func _summary_core(summary: Dictionary) -> String:
	var total: int = int(summary.get("time", 0.0))
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
	lines.append_array(_sardine_breakdown_lines(summary))
	lines.append("Sardinas totales: %d" % int(summary.get("total_sardines", 0)))
	return "\n".join(lines)


func _toggle_victory_details() -> void:
	_victory_details.visible = not _victory_details.visible
	_victory_details_button.text = "Ocultar" if _victory_details.visible else "Detalles"


func _toggle_defeat_details() -> void:
	_defeat_details.visible = not _defeat_details.visible
	_defeat_details_button.text = "Ocultar" if _defeat_details.visible else "Detalles"


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


## True mientras se muestran las cartas de mejora (para que la pausa no interfiera).
func is_selecting_upgrade() -> bool:
	return is_instance_valid(upgrade_panel) and upgrade_panel.visible




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
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(piece, "position:y", piece.position.y + randf_range(120.0, 240.0), randf_range(1.0, 1.8))
		tween.tween_property(piece, "rotation", randf_range(-5.0, 5.0), 1.4)
		tween.tween_property(piece, "modulate:a", 0.0, 1.4)
		tween.chain().tween_callback(piece.queue_free)


## --- Cartas de mejora (minimalistas) ------------------------------------------

func show_upgrade_selection(cards: Array[Dictionary]) -> void:
	upgrade_panel.visible = true
	_animate_panel_entrance()

	for index in _upgrade_buttons.size():
		var card: Dictionary = cards[index]
		var rarity: StringName = card.get("rarity", &"common")
		var style: Dictionary = RARITY_STYLE.get(rarity, RARITY_STYLE[&"common"])

		_prepare_upgrade_card_layout(index)
		_upgrade_titles[index].text = _compact_card_title(card.get("name", "Mejora"))
		# Descripcion de 1 linea; el detalle largo va al tooltip al hacer hover.
		_upgrade_descriptions[index].text = _compact_card_description(card.get("description", ""))
		var affects: String = card.get("affects", "")
		var type_label: String = card.get("type_label", "")
		var tip: String = card.get("description", "")
		if type_label != "" or affects != "":
			tip += "\n(%s%s)" % [type_label, "" if affects == "" else " · " + affects]
		_upgrade_buttons[index].tooltip_text = tip
		# Icono geometrico grande coloreado por rareza + linea de tipo·rareza.
		_upgrade_icons[index].text = ""
		_upgrade_icons[index].visible = false
		_ensure_upgrade_icon(index, _card_icon_type(type_label), style["color"])
		var meta: String = style["label"] if type_label == "" else "%s · %s" % [type_label.to_upper(), style["label"]]
		_upgrade_metas[index].text = meta
		_upgrade_metas[index].add_theme_color_override("font_color", style["color"])
		_style_card(_upgrade_buttons[index], style["color"])
		_animate_card_entrance(_upgrade_buttons[index], index)


func _prepare_upgrade_card_layout(index: int) -> void:
	var button := _upgrade_buttons[index]
	button.custom_minimum_size = Vector2(232, 264)
	button.clip_contents = true
	button.pivot_offset = button.custom_minimum_size * 0.5

	var title := _upgrade_titles[index]
	title.custom_minimum_size = Vector2(188, 48)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.set("max_lines_visible", 2)

	var desc := _upgrade_descriptions[index]
	desc.custom_minimum_size = Vector2(188, 44)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 14)
	desc.set("max_lines_visible", 2)

	var meta := _upgrade_metas[index]
	meta.custom_minimum_size = Vector2(188, 18)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 11)


func _compact_card_title(text: String) -> String:
	if text.length() <= 28:
		return text
	return text.substr(0, 25).strip_edges() + "..."


func _compact_card_description(text: String) -> String:
	if text.length() <= 58:
		return text
	return text.substr(0, 55).strip_edges() + "..."


func _card_icon_type(type_label: String) -> StringName:
	var t: String = type_label.to_lower()
	if t.contains("arma"):
		return &"weapon_projectile"
	if t.contains("compa"):
		return &"companion"
	if t.contains("sinerg"):
		return &"xp"
	if t.contains("stat") or t.contains("mejora"):
		return &"upgrade"
	return &"cat"


func _ensure_upgrade_icon(index: int, icon_type: StringName, color: Color) -> void:
	var host := _upgrade_icons[index].get_parent()
	if host == null:
		return
	var node: Control = host.get_node_or_null("DrawnIcon%d" % index) as Control
	if node == null:
		node = IconDrawer.new()
		node.name = "DrawnIcon%d" % index
		node.custom_minimum_size = Vector2(58, 58)
		host.add_child(node)
		host.move_child(node, _upgrade_icons[index].get_index())
	node.custom_minimum_size = Vector2(58, 58)
	node.set("icon_type", icon_type)
	node.set("accent", color)


## Glifo geometrico simple segun el tipo de carta.
func _card_icon(type_label: String) -> String:
	var t: String = type_label.to_lower()
	if t.contains("arma"):
		return "✦"
	if t.contains("compa"):
		return "✚"
	if t.contains("sinerg"):
		return "◆"
	if t.contains("stat") or t.contains("mejora"):
		return "▲"
	return "●"


func _animate_card_entrance(button: Button, index: int) -> void:
	button.scale = Vector2(0.8, 0.8)
	button.modulate.a = 0.0
	var tween := upgrade_panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE, 0.22) \
		.set_delay(index * 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "modulate:a", 1.0, 0.18).set_delay(index * 0.06)


func _animate_panel_entrance() -> void:
	if not is_instance_valid(_upgrade_title):
		return
	_upgrade_title.scale = Vector2(0.85, 0.85)
	_upgrade_title.pivot_offset = _upgrade_title.size * 0.5
	var tween := upgrade_panel.create_tween()
	tween.tween_property(_upgrade_title, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_card_hover(button: Button, hovering: bool) -> void:
	if hovering:
		_play_ui(&"ui_hover")
	var tween := upgrade_panel.create_tween()
	var target: Vector2 = Vector2(1.06, 1.06) if hovering else Vector2.ONE
	tween.tween_property(button, "scale", target, 0.10).set_trans(Tween.TRANS_SINE)


func _style_card(button: Button, accent: Color) -> void:
	# Cartas tipo juego: fondo teñido por rareza, esquinas suaves, sombra que se
	# convierte en glow del color de la rareza al hacer hover.
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		var hovered: bool = state == "hover" or state == "pressed" or state == "focus"
		box.bg_color = Color(0.09, 0.10, 0.145, 0.97).lerp(accent, 0.14 if hovered else 0.05)
		box.border_color = accent if hovered else Color(accent.r, accent.g, accent.b, 0.75)
		box.set_border_width_all(3)
		box.border_width_top = 6
		box.set_corner_radius_all(14)
		box.set_content_margin_all(8)
		box.shadow_size = 14 if hovered else 8
		box.shadow_color = Color(accent.r, accent.g, accent.b, 0.30) if hovered else Color(0, 0, 0, 0.45)
		box.shadow_offset = Vector2(0, 4)
		button.add_theme_stylebox_override(state, box)


func hide_upgrade_selection() -> void:
	upgrade_panel.visible = false


func _on_upgrade_button_pressed(card_index: int) -> void:
	upgrade_card_selected.emit(card_index)


func _play_ui(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)


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
