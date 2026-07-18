class_name MenuTheme
extends RefCounted
## Sistema de diseño compartido de los menús (rediseño Steam). Única fuente de
## tokens (color, espaciado, tipografía) y fábrica de componentes reutilizables
## (botones con variantes, barra superior con retorno, tarjetas de dato, chips,
## interruptores, sliders, segmentos, pips de progreso, overlays centrados).
## Todo procedural, sin assets externos: formas, tweens e IconDrawer.

# --- Paleta (alineada con ThemeColors para una identidad única) ----------------
const BG_TOP := Color(0.07, 0.075, 0.12, 1.0)
const BG_BOTTOM := Color(0.035, 0.04, 0.065, 1.0)
const ACCENT := Color(1.0, 0.6, 0.2, 1.0)      # naranja gato
const CYAN := Color(0.45, 0.85, 1.0, 1.0)
const PURPLE := Color(0.62, 0.44, 0.88, 1.0)
const ZOMBIE := Color(0.48, 0.82, 0.42, 1.0)
const DANGER := Color(0.95, 0.42, 0.42, 1.0)
const GOLD := Color(1.0, 0.82, 0.36, 1.0)      # sardinas
const TEXT := Color(0.92, 0.95, 1.0, 1.0)
const TEXT_DIM := Color(0.62, 0.67, 0.76, 1.0)

# Superficies (jerarquía de fondos, de más hundido a más elevado).
const PANEL_BG := Color(0.085, 0.10, 0.145, 0.95)
const PANEL_BG_SOFT := Color(0.11, 0.13, 0.18, 0.88)
const SURFACE := Color(0.13, 0.15, 0.20, 1.0)
const SURFACE_HI := Color(0.17, 0.19, 0.25, 1.0)
const HAIRLINE := Color(0.30, 0.33, 0.40, 1.0)

# --- Tokens de espaciado -------------------------------------------------------
const GAP_XS := 4
const GAP_S := 8
const GAP_M := 12
const GAP_L := 20
const GAP_XL := 32

# --- Escala tipográfica --------------------------------------------------------
# Tamaños BASE: siempre pasan por UIFonts.scaled() (ajuste de accesibilidad
# "Tamaño de texto" + mínimo legible). Las fuentes vienen de UIFonts:
# Fredoka (principal), Nunito Sans (lectura), Lilita One (impacto).
const FS_DISPLAY := 52
const FS_H1 := 32
const FS_H2 := 22
const FS_H3 := 17
const FS_BODY := 15
const FS_CAPTION := 13
const FS_MICRO := 11

const RADIUS := 12


# ==============================================================================
# Botones
# ==============================================================================

## Botón estilizado con hover, foco y sonido. `variant`:
##  - &"primary"   : relleno de acento, alta jerarquía (una acción por pantalla).
##  - &"secondary" : superficie con borde de acento (por defecto).
##  - &"ghost"     : transparente con borde tenue (acciones de bajo perfil).
##  - &"danger"    : rojo, para acciones destructivas.
static func make_button(text: String, accent: Color = ACCENT, variant: StringName = &"secondary") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 48)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", UIFonts.fredoka(600))
	button.add_theme_font_size_override("font_size", UIFonts.scaled(FS_H3 + 3))
	var use_accent: Color = DANGER if variant == &"danger" else accent
	_apply_button_variant(button, use_accent, variant)
	_wire_button_feedback(button)
	return button


## Reaplica el estilo de un botón ya creado (útil al cambiar de variante).
static func style_button(button: Button, accent: Color, variant: StringName = &"secondary") -> void:
	_apply_button_variant(button, DANGER if variant == &"danger" else accent, variant)


static func _apply_button_variant(button: Button, accent: Color, variant: StringName) -> void:
	var fg: Color = TEXT
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(RADIUS)
		box.set_content_margin_all(11)
		box.shadow_color = Color(0, 0, 0, 0.35)
		box.shadow_size = 6
		match variant:
			&"primary":
				box.bg_color = accent.lerp(Color(0.10, 0.11, 0.15, 1.0), 0.10)
				if state == "hover" or state == "focus":
					box.bg_color = accent.lightened(0.10)
				elif state == "pressed":
					box.bg_color = accent.darkened(0.12)
				box.border_color = accent.lightened(0.25)
				box.set_border_width_all(0)
				box.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
				box.shadow_size = 10
				fg = _readable_on(accent)
			&"ghost":
				box.bg_color = Color(1, 1, 1, 0.03) if state not in ["hover", "focus"] else Color(accent.r, accent.g, accent.b, 0.14)
				box.border_color = Color(accent.r, accent.g, accent.b, 0.45)
				box.set_border_width_all(1)
				box.shadow_size = 0
				fg = TEXT if variant != &"danger" else DANGER
			_:  # secondary / danger
				box.bg_color = SURFACE if state != "pressed" else SURFACE_HI
				if state == "hover" or state == "focus":
					box.bg_color = accent.lerp(SURFACE, 0.70)
				if state == "disabled":
					box.bg_color = Color(0.09, 0.09, 0.12, 0.9)
				box.border_color = accent if state != "disabled" else HAIRLINE
				box.set_border_width_all(2)
		# FASE VISUAL 3: el foco de teclado/gamepad SIEMPRE se ve — borde claro
		# extra en cualquier variante (el hover del mouse ya tiene su tinte).
		if state == "focus":
			box.set_border_width_all(2)
			box.border_color = accent.lightened(0.35)
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_focus_color", fg)


## Devuelve texto oscuro o claro según el brillo del fondo (contraste legible).
static func _readable_on(bg: Color) -> Color:
	var luma: float = bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114
	return Color(0.08, 0.07, 0.05, 1.0) if luma > 0.6 else TEXT


static func _wire_button_feedback(button: Button) -> void:
	button.pivot_offset = button.custom_minimum_size * 0.5
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.mouse_entered.connect(func() -> void:
		if button.disabled:
			return
		_play_ui(&"ui_hover")
		var t := button.create_tween()
		t.tween_property(button, "scale", Vector2(1.035, 1.035), 0.08))
	button.mouse_exited.connect(func() -> void:
		var t := button.create_tween()
		t.tween_property(button, "scale", Vector2.ONE, 0.08))
	button.pressed.connect(func() -> void: _play_ui(&"ui_click"))


## Botón cuadrado con un glifo de IconDrawer (retorno, cerrar, +, engranaje...).
static func make_icon_button(icon: StringName, tooltip: String = "", accent: Color = TEXT, size: int = 44) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(size, size)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.04) if state != "hover" else Color(accent.r, accent.g, accent.b, 0.16)
		box.border_color = Color(accent.r, accent.g, accent.b, 0.35)
		box.set_border_width_all(1)
		box.set_corner_radius_all(RADIUS)
		button.add_theme_stylebox_override(state, box)
	var glyph := IconDrawer.new()
	glyph.icon_type = icon
	glyph.accent = accent
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Sin minimo propio: el IconDrawer trae 38px por defecto y desbordaba el
	# boton (la ✕ se salia de la caja en tienda/inventario).
	glyph.custom_minimum_size = Vector2.ZERO
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad: float = size * 0.24
	glyph.offset_left = pad
	glyph.offset_top = pad
	glyph.offset_right = -pad
	glyph.offset_bottom = -pad
	button.add_child(glyph)
	_wire_button_feedback(button)
	return button


# ==============================================================================
# Tipografía y encabezados
# ==============================================================================

## Título (Fredoka Bold): jerarquía alta con outline sutil para contraste.
static func make_title(text: String, size: int = FS_DISPLAY, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UIFonts.fredoka(700))
	label.add_theme_font_size_override("font_size", UIFonts.scaled(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.07, 0.9))
	label.add_theme_constant_override("outline_size", 3 if size < FS_H1 else 5)
	return label


## Título de IMPACTO (Lilita One): solo textos cortos y memorables
## (logo, VICTORIA, DERROTA, BOSS). No usar en HUD permanente ni botones.
static func make_impact_title(text: String, size: int = FS_DISPLAY, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UIFonts.lilita())
	label.add_theme_font_size_override("font_size", UIFonts.scaled(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.07, 0.92))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label


## Etiqueta estándar (Fredoka Medium, hereda la fuente del Theme global).
static func make_label(text: String, size: int = FS_BODY, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIFonts.scaled(size))
	label.add_theme_color_override("font_color", color)
	return label


## Texto de LECTURA (Nunito Sans): descripciones, explicaciones, ajustes,
## créditos... Interlineado cómodo y autowrap activado por defecto.
static func make_text(text: String, size: int = FS_BODY, color: Color = TEXT, weight: int = 400) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UIFonts.nunito(weight))
	label.add_theme_font_size_override("font_size", UIFonts.scaled(size))
	label.add_theme_constant_override("line_spacing", 3)
	label.add_theme_color_override("font_color", color)
	return label


## Encabezado de sección: título en acento + línea fina que ocupa el resto.
static func make_section_header(text: String, accent: Color = ACCENT) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_M)
	var label := make_label(text.to_upper(), FS_CAPTION, accent)
	label.add_theme_constant_override("outline_size", 0)
	row.add_child(label)
	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = Color(accent.r, accent.g, accent.b, 0.22)
	box.set_corner_radius_all(2)
	rule.add_theme_stylebox_override("panel", box)
	row.add_child(rule)
	return row


## Botón "Volver" estándar: píldora con flecha en el propio texto (siempre
## alineada, sin icono suelto que se descuadre), igual en TODAS las pantallas.
static func make_back_button(on_back: Callable, accent: Color = TEXT) -> Button:
	var button := Button.new()
	button.text = "←  Volver"
	button.tooltip_text = "ESC"
	button.custom_minimum_size = Vector2(140, 46)
	button.focus_mode = Control.FOCUS_ALL
	button.clip_contents = false
	button.add_theme_font_override("font", UIFonts.fredoka(600))
	button.add_theme_font_size_override("font_size", UIFonts.scaled(FS_BODY))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		var hovered: bool = state != "normal"
		box.bg_color = Color(1, 1, 1, 0.12) if hovered else Color(1, 1, 1, 0.05)
		box.border_color = Color(accent.r, accent.g, accent.b, 0.75 if hovered else 0.38)
		box.set_border_width_all(1)
		if hovered:
			box.border_width_left = 3
		box.set_corner_radius_all(23)
		# Margenes simetricos: el texto (flecha incluida) queda centrado en la pildora.
		box.content_margin_left = 20.0
		box.content_margin_right = 20.0
		box.content_margin_top = 9.0
		box.content_margin_bottom = 9.0
		button.add_theme_stylebox_override(state, box)
	button.pressed.connect(on_back)
	_wire_button_feedback(button)
	return button


## Barra superior estándar: retorno a la izquierda + título + zona de acciones a
## la derecha (accesible con `bar.get_node("Actions")`). Da navegación coherente.
static func make_top_bar(title: String, on_back: Callable = Callable(), accent: Color = ACCENT) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", GAP_M)
	if on_back.is_valid():
		bar.add_child(make_back_button(on_back, accent))
	var label := make_title(title, FS_H1, accent)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(label)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", GAP_S)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(actions)
	return bar


# ==============================================================================
# Chips, badges y tarjetas
# ==============================================================================

## Píldora compacta con icono opcional. Unifica las copias de `_make_chip`.
static func make_chip(text: String, accent: Color = ACCENT, icon: StringName = &"") -> Control:
	var chip := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = accent.lerp(Color(0.10, 0.12, 0.15, 1.0), 0.80)
	box.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(999)
	box.content_margin_left = 12
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	chip.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_S)
	chip.add_child(row)
	if icon != &"":
		var ic := IconDrawer.new()
		ic.icon_type = icon
		ic.accent = accent.lightened(0.15)
		ic.custom_minimum_size = Vector2(18, 18)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	row.add_child(make_label(text, FS_BODY, TEXT))
	return chip


static func make_badge(text: String, accent: Color = ACCENT, fg: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UIFonts.fredoka(600))
	label.add_theme_font_size_override("font_size", UIFonts.scaled(FS_MICRO + 1))
	label.add_theme_color_override("font_color", fg)
	var box := StyleBoxFlat.new()
	box.bg_color = accent.lerp(Color(0.10, 0.12, 0.15, 1.0), 0.68)
	box.border_color = accent
	box.set_border_width_all(1)
	box.set_corner_radius_all(999)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	label.add_theme_stylebox_override("normal", box)
	return label


## Tarjeta de dato: icono opcional + valor grande + etiqueta. Usada en Estadísticas
## y en las pantallas de fin de partida.
static func make_stat_card(value: String, label_text: String, accent: Color = CYAN, icon: StringName = &"") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(140, 96)
	style_panel(panel, accent, PANEL_BG_SOFT)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", GAP_XS)
	panel.add_child(v)
	if icon != &"":
		var ic := IconDrawer.new()
		ic.icon_type = icon
		ic.accent = accent
		ic.custom_minimum_size = Vector2(22, 22)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
	var val := make_label(value, FS_H1 - 4, accent.lightened(0.15))
	# Valor numérico grande: Fredoka Bold con cifras tabulares (no "baila").
	val.add_theme_font_override("font", UIFonts.fredoka_numeric(700))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(val)
	var lab := make_label(label_text, FS_CAPTION, TEXT_DIM)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(lab)
	return panel


# ==============================================================================
# Controles: segmentos, interruptores, sliders, progreso
# ==============================================================================

## Control segmentado (pestañas). `options` = [{"id","label","color"?}]. Llama a
## `on_select.call(id)`. Devuelve el HBox; usa `refresh_segmented` para marcar.
static func make_segmented(options: Array, selected_id: Variant, on_select: Callable, accent: Color = ACCENT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_S)
	for opt in options:
		var oid: Variant = opt.get("id")
		var seg := Button.new()
		seg.text = str(opt.get("label", oid))
		seg.custom_minimum_size = Vector2(0, 38)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.focus_mode = Control.FOCUS_ALL
		seg.add_theme_font_override("font", UIFonts.fredoka(600))
		seg.add_theme_font_size_override("font_size", UIFonts.scaled(FS_CAPTION + 1))
		seg.set_meta("seg_id", oid)
		seg.set_meta("seg_accent", opt.get("color", accent))
		seg.pressed.connect(func() -> void:
			_play_ui(&"ui_click")
			on_select.call(oid))
		row.add_child(seg)
	refresh_segmented(row, selected_id)
	return row


static func refresh_segmented(row: HBoxContainer, selected_id: Variant) -> void:
	for seg in row.get_children():
		if not seg is Button:
			continue
		var oid: Variant = seg.get_meta("seg_id")
		var seg_accent: Color = seg.get_meta("seg_accent")
		var active: bool = oid == selected_id
		for state in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = seg_accent.lerp(SURFACE, 0.35 if active else 0.88)
			if state == "hover" and not active:
				box.bg_color = seg_accent.lerp(SURFACE, 0.72)
			box.border_color = seg_accent if active else Color(seg_accent.r, seg_accent.g, seg_accent.b, 0.30)
			box.set_border_width_all(2 if active else 1)
			box.set_corner_radius_all(9)
			box.set_content_margin_all(8)
			seg.add_theme_stylebox_override(state, box)
		seg.add_theme_color_override("font_color", TEXT if active else TEXT_DIM)


## Interruptor visual (pastilla con perilla animada). Reemplaza los botones "Si/No".
static func make_switch(value: bool, on_change: Callable = Callable()) -> Button:
	var sw := Button.new()
	sw.toggle_mode = true
	sw.button_pressed = value
	sw.custom_minimum_size = Vector2(56, 30)
	sw.focus_mode = Control.FOCUS_ALL
	var knob := Panel.new()
	knob.name = "Knob"
	knob.custom_minimum_size = Vector2(22, 22)
	knob.size = Vector2(22, 22)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kbox := StyleBoxFlat.new()
	kbox.bg_color = Color(0.96, 0.97, 1.0)
	kbox.set_corner_radius_all(999)
	knob.add_theme_stylebox_override("panel", kbox)
	sw.add_child(knob)
	_style_switch(sw, knob, value, false)
	sw.toggled.connect(func(on: bool) -> void:
		_style_switch(sw, knob, on, true)
		_play_ui(&"ui_click")
		if on_change.is_valid():
			on_change.call(on))
	return sw


static func _style_switch(sw: Button, knob: Panel, on: bool, animate: bool) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = ZOMBIE.lerp(Color(0.10, 0.12, 0.16, 1.0), 0.20) if on else Color(0.16, 0.17, 0.22, 1.0)
	track.border_color = ZOMBIE if on else HAIRLINE
	track.set_border_width_all(1)
	track.set_corner_radius_all(999)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		sw.add_theme_stylebox_override(state, track)
	var target := Vector2(30.0 if on else 4.0, 4.0)
	if animate:
		var t := knob.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(knob, "position", target, 0.14)
	else:
		knob.position = target


## Fila etiqueta + interruptor enlazada a una clave del autoload Settings.
static func make_setting_toggle(label_text: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_M)
	var label := make_label(label_text, FS_H3, TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var settings := _settings()
	var value: bool = bool(settings.get_value(key, false)) if settings != null else false
	var sw := make_switch(value, func(on: bool) -> void:
		var st := _settings()
		if st != null and st.has_method("set_value"):
			st.set_value(key, on))
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	return row


## Fila etiqueta + slider estilizado + porcentaje, enlazada a Settings.
static func make_setting_slider(label_text: String, key: String, accent: Color = CYAN) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_M)
	var label := make_label(label_text, FS_H3, TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var value_label := make_label("", FS_BODY, TEXT_DIM)
	value_label.custom_minimum_size = Vector2(48, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value_label)
	var settings := _settings()
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(210, 26)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(settings.get_value(key, 0.75)) if settings != null else 0.75
	_style_slider(slider, accent)
	value_label.text = "%d%%" % int(round(slider.value * 100.0))
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%d%%" % int(round(v * 100.0))
		var st := _settings()
		if st != null and st.has_method("set_value"):
			st.set_value(key, v))
	row.add_child(slider)
	return row


static func _style_slider(slider: HSlider, accent: Color) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.10, 0.11, 0.15, 1.0)
	track.set_corner_radius_all(999)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.set_corner_radius_all(999)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)


## Pips de progreso ●○ como pequeños paneles redondos (reemplaza los strings).
static func make_progress_pips(level: int, max_level: int, accent: Color = ACCENT, pip: int = 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_XS + 1)
	for i in max_level:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(pip, pip)
		var box := StyleBoxFlat.new()
		box.bg_color = accent if i < level else Color(1, 1, 1, 0.10)
		box.border_color = accent if i < level else HAIRLINE
		box.set_border_width_all(1)
		box.set_corner_radius_all(999)
		dot.add_theme_stylebox_override("panel", box)
		row.add_child(dot)
	return row


## Barra de progreso continua (para conteos grandes donde los pips no caben).
static func make_progress_bar(value: float, max_value: float, accent: Color = CYAN, width: int = 160, height: int = 8) -> Control:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(width, height)
	var tbox := StyleBoxFlat.new()
	tbox.bg_color = Color(0.10, 0.11, 0.15, 1.0)
	tbox.set_corner_radius_all(999)
	track.add_theme_stylebox_override("panel", tbox)
	var ratio: float = clampf(value / maxf(1.0, max_value), 0.0, 1.0)
	var fill := Panel.new()
	fill.custom_minimum_size = Vector2(maxf(height, width * ratio), height)
	fill.size = fill.custom_minimum_size
	var fbox := StyleBoxFlat.new()
	fbox.bg_color = accent
	fbox.set_corner_radius_all(999)
	fill.add_theme_stylebox_override("panel", fbox)
	track.add_child(fill)
	return track


# ==============================================================================
# Paneles, overlays y utilidades de layout
# ==============================================================================

static func style_panel(panel: PanelContainer, accent: Color = ACCENT, bg: Color = PANEL_BG) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	box.shadow_color = Color(0, 0, 0, 0.32)
	box.shadow_size = 10
	box.set_border_width_all(2)
	box.set_corner_radius_all(RADIUS + 2)
	box.set_content_margin_all(GAP_L - 4)
	panel.add_theme_stylebox_override("panel", box)


## Overlay modal: oscurece el fondo y centra un PanelContainer por anclas (sin
## posiciones absolutas frágiles). Devuelve el panel; el overlay raíz es su
## `panel.get_parent().get_parent()` — libéralo para cerrar. Incluye fade-in.
static func make_overlay(parent: Control, accent: Color = ACCENT, min_size: Vector2 = Vector2(560, 0)) -> PanelContainer:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	style_panel(panel, accent)
	center.add_child(panel)
	root.modulate.a = 0.0
	var t := root.create_tween()
	t.tween_property(root, "modulate:a", 1.0, 0.12)
	return panel


## Cierra un overlay creado con make_overlay a partir de su panel.
static func close_overlay(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var center := panel.get_parent()
	if center != null and center.get_parent() != null:
		center.get_parent().queue_free()


## Envuelve un contenido en un ScrollContainer vertical para que nunca se recorte.
static func wrap_scrollable(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


static func make_info_pair(title: String, value: String, accent: Color = TEXT_DIM) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.add_child(make_label(title, FS_CAPTION, accent))
	var v := make_label(value, FS_BODY, TEXT)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(v)
	return col


## Fade-in negro al entrar a una escena de menú. Devuelve el overlay creado.
static func add_fade_in(parent: Control) -> ColorRect:
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fade)
	var tween := fade.create_tween()
	tween.tween_property(fade, "color:a", 0.0, 0.25)
	tween.tween_callback(fade.queue_free)
	return fade


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Settings")


static func _play_ui(name: StringName) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var audio: Node = tree.root.get_node_or_null("AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)
