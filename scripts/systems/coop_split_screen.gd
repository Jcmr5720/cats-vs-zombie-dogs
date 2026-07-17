extends Control
## Pantalla dividida del coop local (Rework Coop). Dos SubViewports que COMPARTEN
## el mundo (world_2d) de MainLevel, cada uno con su camara propia siguiendo a un
## jugador. Se acabo la correa y el "¿cual gato soy?": cada jugador tiene su mitad,
## su marco de color, su mini-HUD (vida/XP/nivel) y una flecha hacia su companero.
##
## Lo monta PlayerManager SOLO en coop, como hijo del HUD (CanvasLayer) en el
## indice 0: queda por encima del mundo y por debajo de todos los paneles del HUD.
## El mundo del viewport raiz sigue existiendo debajo (tapado); los CanvasLayer del
## nivel (fondo/overlays) no se dibujan dentro de los SubViewports, asi que cada
## mitad pinta su propio fondo.

const SPLIT_CAMERA_SCRIPT := preload("res://scripts/systems/split_camera.gd")

const P1_COLOR := Color(0.99, 0.72, 0.28)
const P2_COLOR := Color(0.4, 0.72, 1.0)
## Mismo color que el fondo de MainLevel (Background/Color).
const BG_COLOR := Color(0.12, 0.13, 0.17, 1.0)
## Margen (px) para considerar al companero "fuera de mi mitad".
const ARROW_MARGIN: float = 46.0

## Flecha de borde que apunta al companero (triangulo dibujado, sin texturas).
class EdgeArrow:
	extends Control
	var color := Color.WHITE
	var angle: float = 0.0

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
		draw_colored_polygon(
			PackedVector2Array([Vector2(14, 0), Vector2(-9, -9), Vector2(-9, 9)]), color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var _players: Array = []
var _viewports: Array = []
var _cameras: Array = []
## Referencias de UI por jugador (indice paralelo a _players).
var _huds: Array = []
var _player_manager: Node


## Monta las dos mitades. players = [P1, P2] (Node2D); manager = PlayerManager
## (para leer el progreso de revive).
func setup(players: Array, manager: Node) -> void:
	_players = players
	_player_manager = manager
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var world: World2D = get_viewport().world_2d
	for index in _players.size():
		_build_view(index, world)
	_build_divider()


func _build_view(index: int, world: World2D) -> void:
	var color: Color = P1_COLOR if index == 0 else P2_COLOR
	var container := SubViewportContainer.new()
	container.name = "View%d" % (index + 1)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_to_half(container, index)
	add_child(container)

	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	viewport.world_2d = world
	_viewports.append(viewport)

	# Fondo propio de la mitad (los CanvasLayer del nivel no entran al SubViewport).
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -100
	viewport.add_child(bg_layer)
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)

	# Camara exclusiva del jugador.
	var cam := Camera2D.new()
	cam.set_script(SPLIT_CAMERA_SCRIPT)
	cam.name = "SplitCamera%d" % (index + 1)
	cam.set("target", _players[index])
	viewport.add_child(cam)
	cam.make_current()
	_cameras.append(cam)

	_build_overlay(index, color)


func _anchor_to_half(control: Control, index: int) -> void:
	control.anchor_left = 0.0 if index == 0 else 0.5
	control.anchor_right = 0.5 if index == 0 else 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = 0.0
	control.offset_bottom = 0.0


## Linea divisoria central para que las mitades se lean como dos "pantallas".
func _build_divider() -> void:
	var divider := ColorRect.new()
	divider.color = Color(0.03, 0.035, 0.05, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.anchor_left = 0.5
	divider.anchor_right = 0.5
	divider.anchor_bottom = 1.0
	divider.offset_left = -2.0
	divider.offset_right = 2.0
	add_child(divider)


## Overlay de una mitad: marco de color, cabecera con placa+vida+XP, panel de
## derribado con barra de revive y flecha hacia el companero.
func _build_overlay(index: int, color: Color) -> void:
	var overlay := Control.new()
	overlay.name = "Overlay%d" % (index + 1)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_to_half(overlay, index)
	add_child(overlay)

	# Marco sutil del color del jugador (identidad constante de la mitad).
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_box := StyleBoxFlat.new()
	frame_box.draw_center = false
	frame_box.border_color = Color(color.r, color.g, color.b, 0.55)
	frame_box.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", frame_box)
	overlay.add_child(frame)

	# Cabecera: [J1] [barra de vida + XP] Nv.
	var header := HBoxContainer.new()
	header.position = Vector2(14, 12)
	header.add_theme_constant_override("separation", 10)
	overlay.add_child(header)

	var badge := Label.new()
	# Icono + numero: identidad legible tambien sin distinguir colores.
	badge.text = CoopConfig.player_tag(index + 1)
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
	var badge_box := StyleBoxFlat.new()
	badge_box.bg_color = color
	badge_box.set_corner_radius_all(8)
	badge_box.set_content_margin_all(6)
	badge_box.content_margin_left = 10.0
	badge_box.content_margin_right = 10.0
	badge.add_theme_stylebox_override("normal", badge_box)
	header.add_child(badge)

	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 3)
	header.add_child(bars)

	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(170, 18)
	hp_bar.show_percentage = false
	_style_bar(hp_bar, Color(0.9, 0.36, 0.38))
	bars.add_child(hp_bar)
	var hp_label := Label.new()
	hp_label.add_theme_font_size_override("font_size", 11)
	hp_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hp_label.add_theme_constant_override("outline_size", 3)
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hp_bar.add_child(hp_label)

	var xp_bar := ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(170, 7)
	xp_bar.show_percentage = false
	_style_bar(xp_bar, Color(0.4, 0.72, 1.0))
	bars.add_child(xp_bar)

	var level_label := Label.new()
	level_label.add_theme_font_size_override("font_size", 17)
	level_label.add_theme_color_override("font_color", color)
	level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	level_label.add_theme_constant_override("outline_size", 4)
	level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(level_label)

	# Panel de derribado: oscurece SU mitad y muestra el progreso de revive.
	var downed := ColorRect.new()
	downed.color = Color(0.25, 0.02, 0.04, 0.42)
	downed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	downed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	downed.visible = false
	overlay.add_child(downed)

	var downed_box := VBoxContainer.new()
	downed_box.set_anchors_preset(Control.PRESET_CENTER)
	downed_box.position = Vector2(-130, -46)
	downed_box.custom_minimum_size = Vector2(260, 0)
	downed_box.add_theme_constant_override("separation", 6)
	downed.add_child(downed_box)

	var downed_title := Label.new()
	downed_title.text = "¡DERRIBADO!"
	downed_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	downed_title.add_theme_font_size_override("font_size", 30)
	downed_title.add_theme_color_override("font_color", Color(1.0, 0.42, 0.38))
	downed_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	downed_title.add_theme_constant_override("outline_size", 6)
	downed_box.add_child(downed_title)

	var downed_hint := Label.new()
	downed_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	downed_hint.add_theme_font_size_override("font_size", 15)
	downed_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	downed_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	downed_hint.add_theme_constant_override("outline_size", 4)
	downed_box.add_child(downed_hint)

	var revive_bar := ProgressBar.new()
	revive_bar.custom_minimum_size = Vector2(260, 12)
	revive_bar.min_value = 0.0
	revive_bar.max_value = 1.0
	revive_bar.show_percentage = false
	_style_bar(revive_bar, Color(0.5, 1.0, 0.7))
	downed_box.add_child(revive_bar)

	# Flecha hacia el companero cuando esta fuera de esta mitad.
	var partner_color: Color = P2_COLOR if index == 0 else P1_COLOR
	var arrow := EdgeArrow.new()
	arrow.color = partner_color
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.visible = false
	overlay.add_child(arrow)

	var arrow_label := Label.new()
	arrow_label.add_theme_font_size_override("font_size", 13)
	arrow_label.add_theme_color_override("font_color", partner_color)
	arrow_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	arrow_label.add_theme_constant_override("outline_size", 4)
	arrow_label.visible = false
	overlay.add_child(arrow_label)

	# Aviso corto del rescatador ("estas reviviendo al otro").
	var rescue_label := Label.new()
	rescue_label.text = "Reviviendo al companero..."
	rescue_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	rescue_label.position = Vector2(-110, -64)
	rescue_label.add_theme_font_size_override("font_size", 16)
	rescue_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.75))
	rescue_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	rescue_label.add_theme_constant_override("outline_size", 4)
	rescue_label.visible = false
	overlay.add_child(rescue_label)

	_huds.append({
		"hp_bar": hp_bar,
		"hp_label": hp_label,
		"xp_bar": xp_bar,
		"level_label": level_label,
		"downed": downed,
		"downed_hint": downed_hint,
		"revive_bar": revive_bar,
		"arrow": arrow,
		"arrow_label": arrow_label,
		"rescue_label": rescue_label,
	})


func _style_bar(bar: ProgressBar, fill: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.09, 0.9)
	bg.border_color = Color(0.28, 0.31, 0.38, 0.85)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.border_color = fill.lightened(0.25)
	fg.border_width_top = 2
	fg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)


func _process(_delta: float) -> void:
	for index in _players.size():
		if index >= _huds.size():
			break
		_update_half(index)


func _update_half(index: int) -> void:
	var player: Node = _players[index]
	var refs: Dictionary = _huds[index]
	if not is_instance_valid(player):
		return

	# Vida / XP / nivel (poll directo: 2 jugadores, costo despreciable).
	var hp_bar: ProgressBar = refs["hp_bar"]
	var cur: int = int(player.get("current_health"))
	var mx: int = maxi(1, int(player.get("max_health")))
	hp_bar.max_value = mx
	hp_bar.value = clampi(cur, 0, mx)
	(refs["hp_label"] as Label).text = "%d / %d" % [maxi(0, cur), mx]
	var xp_bar: ProgressBar = refs["xp_bar"]
	xp_bar.max_value = maxi(1, int(player.get("experience_to_level")))
	xp_bar.value = clampi(int(player.get("experience")), 0, int(xp_bar.max_value))
	(refs["level_label"] as Label).text = "Nv. %d" % int(player.get("level"))

	# Estado de derribado + progreso de revive de ESTE jugador.
	var is_down: bool = player.has_method("is_downed") and player.is_downed()
	var downed_panel: ColorRect = refs["downed"]
	downed_panel.visible = is_down
	if is_down:
		var fraction: float = _revive_fraction(player)
		(refs["revive_bar"] as ProgressBar).value = fraction
		var hint: Label = refs["downed_hint"]
		if fraction > 0.0:
			hint.text = "¡Tu companero te esta levantando!"
		else:
			hint.text = "%s: ¡corre a levantarlo!" % CoopConfig.player_tag(2 - index)

	_update_partner_arrow(index, refs)


func _revive_fraction(player: Node) -> float:
	if is_instance_valid(_player_manager) and _player_manager.has_method("revive_fraction"):
		return _player_manager.revive_fraction(player)
	return 0.0


## Flecha de borde apuntando al companero cuando queda fuera de esta mitad, con
## distancia aproximada. Si el companero esta derribado, la flecha pulsa (SOS).
func _update_partner_arrow(index: int, refs: Dictionary) -> void:
	var arrow: EdgeArrow = refs["arrow"]
	var label: Label = refs["arrow_label"]
	var rescue_label: Label = refs["rescue_label"]
	var partner_index: int = 1 - index
	if partner_index >= _players.size() or index >= _cameras.size():
		return
	var partner: Node = _players[partner_index]
	var me: Node = _players[index]
	var cam: Camera2D = _cameras[index]
	if not is_instance_valid(partner) or not is_instance_valid(cam) or not is_instance_valid(me):
		arrow.visible = false
		label.visible = false
		rescue_label.visible = false
		return

	var partner_down: bool = partner.has_method("is_downed") and partner.is_downed()
	# Aviso de rescate en curso en la mitad del RESCATADOR.
	rescue_label.visible = partner_down and _revive_fraction(partner) > 0.0

	var vp_size: Vector2 = Vector2(_viewports[index].size)
	var center: Vector2 = cam.get_screen_center_position()
	var screen: Vector2 = ((partner as Node2D).global_position - center) * cam.zoom + vp_size * 0.5
	var inside: bool = screen.x >= ARROW_MARGIN and screen.x <= vp_size.x - ARROW_MARGIN \
		and screen.y >= ARROW_MARGIN and screen.y <= vp_size.y - ARROW_MARGIN
	if inside:
		arrow.visible = false
		label.visible = false
		return

	var clamped := Vector2(
		clampf(screen.x, ARROW_MARGIN, vp_size.x - ARROW_MARGIN),
		clampf(screen.y, ARROW_MARGIN, vp_size.y - ARROW_MARGIN))
	var dir: Vector2 = screen - vp_size * 0.5
	arrow.position = clamped
	arrow.angle = dir.angle() if dir.length() > 0.01 else 0.0
	arrow.visible = true
	arrow.queue_redraw()
	var dist_px: float = (me as Node2D).global_position.distance_to((partner as Node2D).global_position)
	var meters: int = int(dist_px / 50.0)
	var tag: String = CoopConfig.player_tag(partner_index + 1)
	if partner_down:
		label.text = "¡SOS %s!" % tag
	elif dist_px >= CoopConfig.XP_SHARE_ZERO_DIST:
		label.text = "%s · %dm · sin XP compartida" % [tag, meters]
	elif dist_px > CoopConfig.XP_SHARE_FULL_DIST:
		label.text = "%s · %dm · XP↓" % [tag, meters]
	else:
		label.text = "%s · %dm" % [tag, meters]
	label.position = clamped + Vector2(-24, 16)
	label.visible = true
	# Pulso de urgencia cuando el companero esta derribado.
	var alpha: float = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.008)) if partner_down else 1.0
	arrow.modulate.a = alpha
	label.modulate.a = alpha
