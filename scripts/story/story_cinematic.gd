extends Control
## Cinematica reutilizable del Modo Historia (Fase 09). Reproduce los paneles
## narrativos que GameFlow deja en pending_panels ({title, body, kind}) con un
## fondo procedural por `kind`, tintado con pending_accent. Sin assets externos.
##
## Controles: cualquier tecla/clic avanza al siguiente panel; ESC salta toda la
## cinematica. Cada panel avanza solo a los 3 s. Al terminar llama a
## GameFlow.on_cinematic_finished(), que navega a la escena pendiente.

const PANEL_SECONDS: float = 3.0

var _panels: Array = []
var _accent: Color = Color(1.0, 0.6, 0.2)
var _index: int = -1
var _finishing: bool = false
var _anim_time: float = 0.0
var _panel_timer: float = 0.0

var _title_label: Label
var _body_label: Label
var _hint_label: Label
var _progress_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf != null and not gf.pending_panels.is_empty():
		_panels = gf.pending_panels.duplicate()
		_accent = gf.pending_accent
	else:
		# Fallback (F6 directo o sin contexto): un panel y de vuelta al menu.
		_panels = [{"title": "Cats vs Zombie Dogs", "body": "La gata que abre camino.", "kind": &"hero"}]
	_build_ui()
	_next_panel()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.anchor_top = 0.6
	box.anchor_bottom = 0.6
	box.custom_minimum_size = Vector2(760, 0)
	box.position.x = -380
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 38)
	_title_label.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(_title_label)

	_body_label = Label.new()
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(720, 0)
	_body_label.add_theme_font_size_override("font_size", 19)
	_body_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.96))
	_body_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_body_label.add_theme_constant_override("shadow_offset_x", 1)
	_body_label.add_theme_constant_override("shadow_offset_y", 1)
	box.add_child(_body_label)

	_hint_label = Label.new()
	_hint_label.text = "Pulsa una tecla para continuar  ·  ESC salta"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.64, 0.72, 0.8))
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.position.y -= 34
	add_child(_hint_label)

	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 13)
	_progress_label.add_theme_color_override("font_color", Color(0.6, 0.64, 0.72, 0.8))
	_progress_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_progress_label.position += Vector2(-56, 22)
	add_child(_progress_label)


func _process(delta: float) -> void:
	_anim_time += delta
	_panel_timer += delta
	if _panel_timer >= PANEL_SECONDS and not _finishing:
		_next_panel()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if event.is_action_pressed("ui_cancel"):
		_finish()
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_next_panel()


func _next_panel() -> void:
	_index += 1
	if _index >= _panels.size():
		_finish()
		return
	_panel_timer = 0.0
	var panel: Dictionary = _panels[_index]
	_title_label.text = str(panel.get("title", ""))
	_body_label.text = str(panel.get("body", ""))
	_progress_label.text = "%d / %d" % [_index + 1, _panels.size()]
	# Fade-in escalonado de titulo y cuerpo.
	_title_label.modulate.a = 0.0
	_body_label.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_title_label, "modulate:a", 1.0, 0.35)
	t.parallel().tween_property(_body_label, "modulate:a", 1.0, 0.45).set_delay(0.2)


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	var t := create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.4)
	t.tween_callback(func() -> void:
		var gf: Node = get_node_or_null("/root/GameFlow")
		if gf != null and gf.has_method("on_cinematic_finished"):
			gf.on_cinematic_finished()
	)


# --- Fondos procedurales por kind ------------------------------------------------

func _draw() -> void:
	var s: Vector2 = get_viewport_rect().size
	var kind: StringName = &"hero"
	if _index >= 0 and _index < _panels.size():
		kind = _panels[_index].get("kind", &"hero")
	# Degradado base nocturno con matiz del accent del capitulo.
	var top := Color(0.05, 0.05, 0.09).lerp(_accent, 0.06)
	var bottom := Color(0.02, 0.02, 0.045)
	for i in 20:
		var t: float = float(i) / 19.0
		draw_rect(Rect2(0, s.y * t, s.x, s.y / 20.0 + 1.0), top.lerp(bottom, t), true)
	match kind:
		&"city":
			_draw_city(s, false)
		&"storm":
			_draw_city(s, true)
		&"dogs":
			_draw_dogs(s)
		&"cats":
			_draw_cats(s)
		&"park", &"park_dark":
			_draw_park(s, kind == &"park_dark")
		&"factory":
			_draw_factory(s)
		&"dawn":
			_draw_dawn(s)
		_:
			_draw_hero(s)
	# Vineta lateral para centrar la lectura.
	draw_rect(Rect2(0, s.y * 0.52, s.x, s.y * 0.48), Color(0, 0, 0, 0.35), true)


## Skyline nocturno; con tormenta la luna se cubre y caen lineas de lluvia.
func _draw_city(s: Vector2, storm: bool) -> void:
	if not storm:
		draw_circle(Vector2(s.x * 0.82, s.y * 0.18), 46.0, Color(0.92, 0.94, 0.85, 0.9))
		draw_circle(Vector2(s.x * 0.82, s.y * 0.18), 62.0, Color(0.92, 0.94, 0.85, 0.10))
	var count: int = 12
	for i in count:
		var w: float = s.x / float(count)
		var h: float = s.y * (0.18 + 0.16 * abs(sin(float(i) * 2.7)))
		var x: float = float(i) * w
		draw_rect(Rect2(x + 3, s.y * 0.5 - h, w - 6, h), Color(0.07, 0.08, 0.12), true)
		# Ventanas: apagadas en tormenta, alguna encendida si no.
		if not storm and i % 3 == 0:
			draw_rect(Rect2(x + w * 0.3, s.y * 0.5 - h * 0.7, 7, 9), Color(0.95, 0.8, 0.4, 0.7), true)
	if storm:
		for i in 40:
			var rx: float = fmod(float(i) * 97.3 + _anim_time * 340.0, s.x)
			var ry: float = fmod(float(i) * 61.7 + _anim_time * 640.0, s.y * 0.55)
			draw_line(Vector2(rx, ry), Vector2(rx - 4.0, ry + 14.0), Color(0.6, 0.7, 0.9, 0.30), 1.5)
		# Relampago ocasional.
		if fmod(_anim_time, 3.7) < 0.12:
			draw_rect(Rect2(0, 0, s.x, s.y * 0.5), Color(0.8, 0.85, 1.0, 0.08), true)


## Manada: siluetas bajas con ojos verdes brillantes.
func _draw_dogs(s: Vector2) -> void:
	for i in 7:
		var x: float = s.x * (0.08 + float(i) * 0.13)
		var y: float = s.y * (0.34 + 0.05 * sin(float(i) * 1.7))
		var body_w: float = 74.0 + 18.0 * sin(float(i) * 2.1)
		draw_rect(Rect2(x, y, body_w, 30.0), Color(0.05, 0.06, 0.07), true)
		draw_rect(Rect2(x + body_w * 0.78, y - 16.0, 26.0, 22.0), Color(0.05, 0.06, 0.07), true)
		var blink: float = 0.75 + 0.25 * sin(_anim_time * 3.0 + float(i))
		draw_circle(Vector2(x + body_w * 0.88, y - 7.0), 3.2, Color(0.4, 1.0, 0.45, blink))
		draw_circle(Vector2(x + body_w * 0.96, y - 7.0), 3.2, Color(0.4, 1.0, 0.45, blink))


## Colonia en los tejados: gatos sentados recortados contra el cielo.
func _draw_cats(s: Vector2) -> void:
	draw_rect(Rect2(0, s.y * 0.42, s.x, s.y * 0.1), Color(0.06, 0.07, 0.1), true)
	for i in 6:
		var x: float = s.x * (0.1 + float(i) * 0.15)
		var y: float = s.y * 0.42
		# Cuerpo sentado + cabeza + orejas.
		draw_circle(Vector2(x, y - 14.0), 15.0, Color(0.04, 0.05, 0.07))
		draw_circle(Vector2(x, y - 36.0), 10.0, Color(0.04, 0.05, 0.07))
		draw_colored_polygon(PackedVector2Array([Vector2(x - 9, y - 42), Vector2(x - 3, y - 44), Vector2(x - 8, y - 52)]), Color(0.04, 0.05, 0.07))
		draw_colored_polygon(PackedVector2Array([Vector2(x + 9, y - 42), Vector2(x + 3, y - 44), Vector2(x + 8, y - 52)]), Color(0.04, 0.05, 0.07))
		# Ojos reflejando la luna.
		var glow: float = 0.6 + 0.3 * sin(_anim_time * 2.0 + float(i) * 1.4)
		draw_circle(Vector2(x - 4, y - 37), 1.8, Color(0.85, 0.95, 0.6, glow))
		draw_circle(Vector2(x + 4, y - 37), 1.8, Color(0.85, 0.95, 0.6, glow))


## Parque: copas de arboles y sendero; en version oscura, niebla venenosa.
func _draw_park(s: Vector2, dark: bool) -> void:
	var canopy := Color(0.05, 0.10, 0.06) if not dark else Color(0.04, 0.055, 0.045)
	for i in 8:
		var x: float = s.x * (0.05 + float(i) * 0.13)
		var r: float = 55.0 + 25.0 * sin(float(i) * 2.3)
		draw_circle(Vector2(x, s.y * 0.32), r, canopy)
		draw_rect(Rect2(x - 6, s.y * 0.32 + r * 0.5, 12, s.y * 0.14), Color(0.08, 0.06, 0.04), true)
	# Sendero.
	draw_line(Vector2(0, s.y * 0.5), Vector2(s.x, s.y * 0.44), Color(0.16, 0.13, 0.09, 0.8), 22.0)
	if dark:
		for i in 5:
			var fx: float = s.x * (0.1 + float(i) * 0.2) + sin(_anim_time * 0.7 + float(i)) * 24.0
			draw_circle(Vector2(fx, s.y * 0.42), 46.0, Color(0.3, 0.9, 0.4, 0.05))


## Fabrica: naves con dientes de sierra, chimeneas y humo.
func _draw_factory(s: Vector2) -> void:
	var body := Color(0.07, 0.07, 0.09)
	draw_rect(Rect2(s.x * 0.08, s.y * 0.3, s.x * 0.84, s.y * 0.2), body, true)
	# Techo dientes de sierra.
	for i in 8:
		var x: float = s.x * 0.08 + float(i) * s.x * 0.105
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, s.y * 0.3), Vector2(x + s.x * 0.06, s.y * 0.24), Vector2(x + s.x * 0.105, s.y * 0.3),
		]), body)
	# Chimeneas con humo animado.
	for i in 2:
		var cx: float = s.x * (0.28 + float(i) * 0.36)
		draw_rect(Rect2(cx, s.y * 0.13, 26, s.y * 0.17), body, true)
		for k in 3:
			var puff_t: float = fmod(_anim_time * 0.4 + float(k) * 0.33 + float(i) * 0.5, 1.0)
			draw_circle(Vector2(cx + 13 + puff_t * 30.0, s.y * 0.12 - puff_t * 60.0),
				8.0 + puff_t * 14.0, Color(0.3, 0.32, 0.35, 0.25 * (1.0 - puff_t)))
	# Resplandor enfermo en las ventanas.
	for i in 5:
		var wx: float = s.x * (0.16 + float(i) * 0.16)
		var pulse: float = 0.35 + 0.2 * sin(_anim_time * 1.8 + float(i))
		draw_rect(Rect2(wx, s.y * 0.36, 18, 12), Color(0.4, 1.0, 0.4, pulse), true)


## Amanecer: sol calido subiendo sobre el skyline en paz.
func _draw_dawn(s: Vector2) -> void:
	# Cielo calido superpuesto al degradado base.
	for i in 12:
		var t: float = float(i) / 11.0
		draw_rect(Rect2(0, s.y * 0.5 * t, s.x, s.y * 0.5 / 12.0 + 1.0),
			Color(0.9, 0.55, 0.3, 0.10 * (1.0 - t)), true)
	draw_circle(Vector2(s.x * 0.5, s.y * 0.46), 54.0, Color(1.0, 0.75, 0.4, 0.9))
	draw_circle(Vector2(s.x * 0.5, s.y * 0.46), 78.0, Color(1.0, 0.75, 0.4, 0.15))
	var count: int = 12
	for i in count:
		var w: float = s.x / float(count)
		var h: float = s.y * (0.14 + 0.12 * abs(sin(float(i) * 2.7)))
		draw_rect(Rect2(float(i) * w + 3, s.y * 0.5 - h, w - 6, h), Color(0.09, 0.08, 0.1), true)


## La gata protagonista: silueta grande centrada con bufanda al viento.
func _draw_hero(s: Vector2) -> void:
	var c := Vector2(s.x * 0.5, s.y * 0.34)
	draw_circle(Vector2(s.x * 0.5, s.y * 0.16), 40.0, Color(0.92, 0.94, 0.85, 0.7))
	var body := Color(0.05, 0.05, 0.08)
	# Cuerpo sentado, cabeza y orejas.
	draw_circle(c + Vector2(0, 30), 42.0, body)
	draw_circle(c - Vector2(0, 22), 27.0, body)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-24, -38), c + Vector2(-8, -44), c + Vector2(-21, -64)]), body)
	draw_colored_polygon(PackedVector2Array([c + Vector2(24, -38), c + Vector2(8, -44), c + Vector2(21, -64)]), body)
	# Cola enroscada.
	draw_arc(c + Vector2(46, 48), 26.0, PI * 0.2, PI * 1.2, 20, body, 10.0)
	# Bufanda al viento con el accent del capitulo.
	var wave: float = sin(_anim_time * 2.4) * 6.0
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-16, -6), c + Vector2(16, -6), c + Vector2(52, 10 + wave), c + Vector2(44, 22 + wave), c + Vector2(10, 6),
	]), _accent)
	# Ojos decididos.
	var glow: float = 0.75 + 0.25 * sin(_anim_time * 2.0)
	draw_circle(c + Vector2(-9, -24), 3.4, Color(0.85, 0.95, 0.6, glow))
	draw_circle(c + Vector2(9, -24), 3.4, Color(0.85, 0.95, 0.6, glow))
