class_name MenuTheme
extends RefCounted
## Utilidades visuales compartidas por los menus (Fase 08): paleta, botones grandes
## con hover, titulos y fade-in. Sin assets externos: todo formas y tweens.

const BG_TOP := Color(0.07, 0.07, 0.12, 1.0)
const BG_BOTTOM := Color(0.04, 0.04, 0.07, 1.0)
const ACCENT := Color(1.0, 0.6, 0.2, 1.0)      # naranja
const CYAN := Color(0.45, 0.85, 1.0, 1.0)
const PURPLE := Color(0.6, 0.4, 0.85, 1.0)
const ZOMBIE := Color(0.45, 0.8, 0.4, 1.0)
const TEXT := Color(0.9, 0.93, 1.0, 1.0)
const TEXT_DIM := Color(0.62, 0.66, 0.74, 1.0)
const PANEL_BG := Color(0.08, 0.10, 0.14, 0.92)
const PANEL_BG_SOFT := Color(0.10, 0.12, 0.17, 0.84)


## Crea un boton grande y estilizado con color de acento y hover.
static func make_button(text: String, accent: Color = ACCENT) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 52)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", TEXT)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.11, 0.12, 0.17, 0.96)
		if state == "hover" or state == "focus":
			box.bg_color = accent.lerp(Color(0.14, 0.15, 0.20, 1.0), 0.75)
		if state == "pressed":
			box.bg_color = accent.lerp(Color(0.18, 0.19, 0.24, 1.0), 0.64)
		if state == "disabled":
			box.bg_color = Color(0.09, 0.09, 0.12, 0.9)
		box.border_color = accent if state != "disabled" else Color(0.3, 0.3, 0.34)
		box.shadow_color = Color(0, 0, 0, 0.35)
		box.shadow_size = 6
		box.set_border_width_all(2)
		box.set_corner_radius_all(12)
		box.set_content_margin_all(10)
		button.add_theme_stylebox_override(state, box)
	# Hover: leve crecimiento.
	button.mouse_entered.connect(func() -> void:
		_play_ui(&"ui_hover")
		var t := button.create_tween()
		t.tween_property(button, "scale", Vector2(1.04, 1.04), 0.08))
	button.mouse_exited.connect(func() -> void:
		var t := button.create_tween()
		t.tween_property(button, "scale", Vector2.ONE, 0.08))
	button.pressed.connect(func() -> void: _play_ui(&"ui_click"))
	button.pivot_offset = button.custom_minimum_size * 0.5
	return button


static func make_title(text: String, size: int = 54, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func make_badge(text: String, accent: Color = ACCENT, fg: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", fg)
	var box := StyleBoxFlat.new()
	box.bg_color = accent.lerp(Color(0.10, 0.12, 0.15, 1.0), 0.72)
	box.border_color = accent
	box.set_border_width_all(1)
	box.set_corner_radius_all(999)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	label.add_theme_stylebox_override("normal", box)
	return label


static func style_panel(panel: PanelContainer, accent: Color = ACCENT, bg: Color = PANEL_BG) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = accent
	box.shadow_color = Color(0, 0, 0, 0.32)
	box.shadow_size = 10
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", box)


static func make_info_pair(title: String, value: String, accent: Color = TEXT_DIM) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", accent)
	col.add_child(t)
	var v := Label.new()
	v.text = value
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_theme_font_size_override("font_size", 15)
	v.add_theme_color_override("font_color", TEXT)
	col.add_child(v)
	return col


## Fade-in negro al entrar a una escena de menu. Devuelve el overlay creado.
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


static func _play_ui(name: StringName) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var audio: Node = tree.root.get_node_or_null("AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)
