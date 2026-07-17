extends Control
## Menu principal (Fase 08). Punto de entrada del juego. Navega a selector de mapas,
## mejoras permanentes, estadisticas, opciones y salir, todo via el autoload GameFlow.
## Fondo urbano nocturno dibujado por codigo (luna, silueta de gato, huellas).

@warning_ignore("shadowed_global_identifier")
const MenuTheme = preload("res://scripts/menus/menu_theme.gd")

var _anim_time: float = 0.0
var _title_box: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	MenuTheme.add_fade_in(self)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_music"):
		audio.play_music(&"menu")


func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()
	if _title_box != null:
		_title_box.position.y = 26.0 + sin(_anim_time * 1.6) * 4.0


## Logo compuesto (FASE VISUAL 3): tres piezas con color propio — "Cats" en
## naranja gato, "vs" pequeno en rojo y "Zombie Dogs" en verde pútrido — sobre
## una marca de garra dibujada en _draw(). Se lee como capsule de Steam, no
## como un Label plano.
func _build_ui() -> void:
	_title_box = CenterContainer.new()
	_title_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_box.position = Vector2(0, 26)
	add_child(_title_box)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 14)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.add_child(title_row)

	title_row.add_child(_logo_word("Cats", 60, MenuTheme.ACCENT, Color(0.16, 0.09, 0.03)))
	var vs := _logo_word("vs", 30, MenuTheme.DANGER, Color(0.1, 0.02, 0.02))
	vs.size_flags_vertical = Control.SIZE_SHRINK_END
	# Ligera rotacion del "vs": rompe la rigidez tipografica del logo.
	vs.rotation = -0.12
	vs.pivot_offset = Vector2(18, 30)
	title_row.add_child(vs)
	title_row.add_child(_logo_word("Zombie Dogs", 60, MenuTheme.ZOMBIE, Color(0.04, 0.10, 0.04)))

	var subtitle := MenuTheme.make_title("Rescata la colonia.", 22, MenuTheme.CYAN)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	subtitle.position = Vector2(0, 108)
	add_child(subtitle)

	# Columna central con jerarquía: acción primaria destacada, luego secundarias
	# y un grupo compacto de progresión/sistema.
	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_top = 0.32
	center.anchor_right = 1.0
	center.anchor_bottom = 0.98
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_M)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# Acción primaria: continuar la campaña.
	var b_story := MenuTheme.make_button("Historia", MenuTheme.ACCENT, &"primary")
	b_story.custom_minimum_size = Vector2(380, 64)
	b_story.add_theme_font_size_override("font_size", MenuTheme.FS_H2)
	b_story.pressed.connect(func() -> void: GameFlow.open_story())
	col.add_child(b_story)

	# Secundarias: partida libre y refugio (lado a lado).
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation", MenuTheme.GAP_M)
	secondary.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(secondary)
	var b_play := MenuTheme.make_button("Partida libre", MenuTheme.CYAN, &"secondary")
	b_play.custom_minimum_size = Vector2(184, 52)
	b_play.pressed.connect(func() -> void: GameFlow.open_map_select())
	secondary.add_child(b_play)
	var b_shelter := MenuTheme.make_button("Refugio", MenuTheme.PURPLE, &"secondary")
	b_shelter.custom_minimum_size = Vector2(184, 52)
	b_shelter.pressed.connect(func() -> void: GameFlow.open_shelter())
	secondary.add_child(b_shelter)

	# Grupo de progresión/sistema (bajo perfil).
	var tertiary := HBoxContainer.new()
	tertiary.add_theme_constant_override("separation", MenuTheme.GAP_S)
	tertiary.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(tertiary)
	var b_meta := MenuTheme.make_button("Mejoras", MenuTheme.ZOMBIE, &"ghost")
	b_meta.custom_minimum_size = Vector2(120, 44)
	b_meta.pressed.connect(func() -> void: GameFlow.open_meta_progression())
	tertiary.add_child(b_meta)
	var b_stats := MenuTheme.make_button("Progreso", MenuTheme.CYAN, &"ghost")
	b_stats.custom_minimum_size = Vector2(120, 44)
	b_stats.pressed.connect(func() -> void: GameFlow.open_stats())
	tertiary.add_child(b_stats)
	var b_options := MenuTheme.make_button("Opciones", MenuTheme.PURPLE, &"ghost")
	b_options.custom_minimum_size = Vector2(120, 44)
	b_options.pressed.connect(func() -> void: GameFlow.open_options())
	tertiary.add_child(b_options)

	var b_quit := MenuTheme.make_button("Salir", MenuTheme.DANGER, &"ghost")
	b_quit.custom_minimum_size = Vector2(120, 40)
	b_quit.pressed.connect(func() -> void: GameFlow.quit_game())
	col.add_child(b_quit)

	b_story.grab_focus.call_deferred()


## Palabra del logo con contorno grueso y sombra propios.
func _logo_word(text: String, font_size: int, color: Color, outline: Color) -> Label:
	var label := MenuTheme.make_title(text, font_size, color)
	label.add_theme_color_override("font_outline_color", outline)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_y", 5)
	label.add_theme_constant_override("shadow_offset_x", 0)
	return label


## Fondo decorativo: degradado, luna, silueta de gato y huellas. Solo formas.
func _draw() -> void:
	@warning_ignore("shadowed_variable_base_class")
	var size: Vector2 = get_viewport_rect().size
	# Degradado vertical simple por bandas.
	var bands: int = 24
	for i in bands:
		var t: float = float(i) / float(bands - 1)
		var col: Color = MenuTheme.BG_TOP.lerp(MenuTheme.BG_BOTTOM, t)
		draw_rect(Rect2(0, size.y * t, size.x, size.y / bands + 1), col, true)

	# Estrellas deterministas con parpadeo suave en la mitad superior del cielo.
	for i in 44:
		var sx: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) * size.x
		var sy: float = fposmod(sin(float(i) * 78.233) * 12543.123, 1.0) * size.y * 0.55
		var twinkle: float = 0.22 + 0.18 * sin(_anim_time * (1.0 + fposmod(float(i) * 0.37, 1.0)) + float(i))
		var star_radius: float = 2.1 if i % 5 == 0 else 1.3
		draw_circle(Vector2(sx, sy), star_radius, Color(0.82, 0.88, 1.0, maxf(0.06, twinkle)))

	# Marca de garra tras el logo: tres tajos diagonales tenues (identidad felina).
	var claw_center := Vector2(size.x * 0.5, 74.0)
	for k in 3:
		var off := Vector2(float(k - 1) * 52.0, float(abs(k - 1)) * 6.0)
		var a: Vector2 = claw_center + off + Vector2(-42, -50)
		var b: Vector2 = claw_center + off + Vector2(28, 56)
		draw_line(a, b, Color(MenuTheme.DANGER.r, MenuTheme.DANGER.g, MenuTheme.DANGER.b, 0.08), 13.0)
		draw_line(a, b, Color(MenuTheme.DANGER.r, MenuTheme.DANGER.g, MenuTheme.DANGER.b, 0.14), 4.5)

	# Luna con leve halo.
	var moon: Vector2 = Vector2(size.x * 0.82, size.y * 0.22)
	draw_circle(moon, 80.0, Color(0.95, 0.95, 0.8, 0.10))
	draw_circle(moon, 58.0, Color(0.95, 0.94, 0.78, 0.85))
	draw_circle(moon + Vector2(18, -8), 50.0, MenuTheme.BG_TOP.lerp(MenuTheme.BG_BOTTOM, 0.2))

	# Silueta de gato sentado (placeholder geometrico) abajo a la izquierda.
	var base: Vector2 = Vector2(size.x * 0.16, size.y * 0.82)
	var body := PackedVector2Array([
		base + Vector2(-34, 0), base + Vector2(-30, -70), base + Vector2(-10, -88),
		base + Vector2(10, -88), base + Vector2(30, -70), base + Vector2(34, 0),
	])
	draw_colored_polygon(body, Color(0.03, 0.03, 0.05, 1.0))
	# Orejas.
	draw_colored_polygon(PackedVector2Array([base + Vector2(-30, -78), base + Vector2(-22, -108), base + Vector2(-10, -84)]), Color(0.03, 0.03, 0.05, 1.0))
	draw_colored_polygon(PackedVector2Array([base + Vector2(30, -78), base + Vector2(22, -108), base + Vector2(10, -84)]), Color(0.03, 0.03, 0.05, 1.0))
	# Ojos brillantes (acento zombi).
	draw_circle(base + Vector2(-12, -74), 4.0, MenuTheme.ZOMBIE)
	draw_circle(base + Vector2(12, -74), 4.0, MenuTheme.ZOMBIE)
	# Cola.
	draw_line(base + Vector2(32, -6), base + Vector2(70, -30), Color(0.03, 0.03, 0.05, 1.0), 12.0)

	# Huellas de gato cruzando (puntos suaves).
	for i in 7:
		var p: Vector2 = Vector2(size.x * (0.30 + i * 0.06), size.y * (0.9 - sin(i * 0.9 + _anim_time * 0.4) * 0.02))
		var a: float = 0.10 + 0.05 * sin(_anim_time + i)
		draw_circle(p, 6.0, Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, a))
		draw_circle(p + Vector2(7, -7), 3.0, Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, a))
		draw_circle(p + Vector2(0, -9), 3.0, Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, a))
		draw_circle(p + Vector2(-7, -7), 3.0, Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, a))

	# Skyline simple al fondo para que la pantalla no se sienta vacia.
	var building_w: float = size.x / 11.0
	for i in 11:
		var h: float = size.y * (0.18 + 0.18 * abs(sin(float(i) * 0.8 + 0.4)))
		var x: float = i * building_w
		draw_rect(Rect2(x, size.y - h, building_w + 4.0, h), Color(0.05, 0.06, 0.08, 0.95), true)
		for w in 4:
			for row in 4:
				if int(abs(sin(float(i * 3 + w * 7 + row) + _anim_time * 0.2)) * 10.0) % 3 == 0:
					continue
				var wx: float = x + 10.0 + w * 18.0
				var wy: float = size.y - h + 12.0 + row * 22.0
				draw_rect(Rect2(wx, wy, 8, 12), Color(1.0, 0.78, 0.34, 0.22), true)
