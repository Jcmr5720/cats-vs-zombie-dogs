class_name ShelterSlot
extends Button
## Slot fijo del Refugio (Fase 10). Muestra su estado (vacio / ocupado /
## resaltado para colocar) y dibuja el objeto colocado con formas simples.
## El ShelterMenu decide que pasa al pulsarlo (colocar, quitar o abrir tienda).

const ShelterBonusCalculator = preload("res://scripts/shelter/shelter_bonus_calculator.gd")

const CATEGORY_ICON: Dictionary = {
	&"entrenamiento": "🐾",
	&"companeros": "🐱",
	&"economia": "🐟",
	&"rescate": "📻",
	&"defensa": "📦",
}

var slot_id: StringName = &""
var allowed_categories: Array = []
var slot_label: String = ""
## true mientras el menu esta en modo colocacion y este slot es valido.
var highlight_for_placement: bool = false

var _shelter: Node
var _anim_time: float = 0.0
var _feedback_time: float = 0.0
var _feedback_color: Color = Color(1.0, 0.75, 0.3)


func setup(slot_info: Dictionary) -> void:
	slot_id = slot_info.get("id", &"")
	allowed_categories = slot_info.get("categories", [])
	slot_label = str(slot_info.get("label", ""))
	custom_minimum_size = Vector2(128, 118)
	tooltip_text = "%s\nAcepta: %s" % [slot_label, ", ".join(allowed_categories.map(func(c): return str(c)))]
	# El autoload se resuelve en _ready: setup() se llama antes de entrar al arbol.
	if is_inside_tree():
		_shelter = get_node_or_null("/root/Shelter")
		_apply_style()


func _ready() -> void:
	if _shelter == null:
		_shelter = get_node_or_null("/root/Shelter")
	_apply_style()
	mouse_entered.connect(func() -> void: queue_redraw())
	mouse_exited.connect(func() -> void: queue_redraw())


func _process(delta: float) -> void:
	_anim_time += delta
	if _feedback_time > 0.0:
		_feedback_time = maxf(0.0, _feedback_time - delta)
	if highlight_for_placement or _feedback_time > 0.0:
		queue_redraw()


func refresh() -> void:
	_apply_style()
	queue_redraw()


func play_place_feedback(color: Color = Color(1.0, 0.75, 0.3)) -> void:
	_feedback_color = color
	_feedback_time = 0.38
	queue_redraw()


func _occupied_item():
	if _shelter == null:
		return null
	var item_id: StringName = _shelter.get_item_in_slot(slot_id)
	return _shelter.get_item(item_id) if item_id != &"" else null


func _apply_style() -> void:
	var item = _occupied_item()
	var occupied: bool = item != null
	tooltip_text = "%s\n%s" % [item.display_name, slot_label] if occupied else "%s\nAcepta: %s" % [slot_label, ", ".join(allowed_categories.map(func(c): return str(c)))]
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.12, 0.10, 0.09, 0.9) if occupied else Color(0.09, 0.08, 0.075, 0.75)
		box.border_color = Color(0.45, 0.36, 0.26) if occupied else Color(0.3, 0.26, 0.2, 0.7)
		if state == "hover":
			box.bg_color = box.bg_color.lightened(0.06)
			box.border_color = box.border_color.lightened(0.2)
		box.set_border_width_all(2)
		box.set_corner_radius_all(10)
		add_theme_stylebox_override(state, box)


func _draw() -> void:
	var s: Vector2 = size
	var item = _occupied_item()
	var feedback: float = _feedback_time / 0.38
	if feedback > 0.0:
		var ring_alpha: float = feedback * 0.75
		var ring_pad: float = 6.0 + (1.0 - feedback) * 22.0
		draw_rect(Rect2(Vector2(ring_pad, ring_pad), s - Vector2(ring_pad * 2.0, ring_pad * 2.0)), Color(_feedback_color.r, _feedback_color.g, _feedback_color.b, ring_alpha), false, 3.0)
		for i in 8:
			var angle: float = TAU * float(i) / 8.0
			var dist: float = lerpf(14.0, 46.0, 1.0 - feedback)
			var center := s * 0.5 + Vector2(cos(angle), sin(angle)) * dist
			draw_circle(center, 3.0 * feedback, Color(_feedback_color.r, _feedback_color.g, _feedback_color.b, ring_alpha))
	# Resaltado pulsante en modo colocacion (slot valido y libre).
	if highlight_for_placement:
		var pulse: float = 0.35 + 0.25 * sin(_anim_time * 6.0)
		draw_rect(Rect2(Vector2(2, 2), s - Vector2(4, 4)), Color(0.5, 1.0, 0.55, pulse), false, 3.0)
	if item == null:
		# Vacio: contorno punteado + icono de categoria + etiqueta.
		var icon: String = CATEGORY_ICON.get(allowed_categories[0] if not allowed_categories.is_empty() else &"", "•")
		if allowed_categories.size() > 1:
			icon = "✦"
		var font := ThemeDB.fallback_font
		draw_circle(s * 0.5, 29.0, Color(0.20, 0.17, 0.14, 0.48))
		draw_circle(s * 0.5, 23.0, Color(0.08, 0.07, 0.065, 0.58))
		draw_string(font, Vector2(0, s.y * 0.58), icon, HORIZONTAL_ALIGNMENT_CENTER, s.x, 30, Color(0.66, 0.58, 0.46, 0.82))
		if allowed_categories.size() > 1:
			for i in allowed_categories.size():
				var dot_x: float = s.x * 0.5 - float(allowed_categories.size() - 1) * 6.0 + float(i) * 12.0
				draw_circle(Vector2(dot_x, s.y * 0.78), 2.8, Color(0.52, 0.80, 0.88, 0.72))
		return
	# Ocupado: caja del objeto con sombra, cuerpo, tapa de acento y pips de nivel.
	var item_size: Vector2 = item.size
	var center := Vector2(s.x * 0.5, s.y * 0.44)
	if feedback > 0.0:
		center.y -= sin((1.0 - feedback) * PI) * 18.0
		item_size *= Vector2(1.0 + 0.12 * feedback, 1.0 - 0.08 * feedback)
	var rect := Rect2(center - item_size * 0.5, item_size)
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(0, 0, 0, 0.28), true)
	_draw_item_visual(item, rect)
	tooltip_text = "%s\n%s" % [item.display_name, slot_label]
	# Pips de nivel.
	var level: int = _shelter.get_level(item.id)
	var pip_start: float = s.x * 0.5 - float(item.max_level) * 6.0
	for i in item.max_level:
		var pip_color: Color = item.accent_color if i < level else Color(0.3, 0.28, 0.24)
		draw_circle(Vector2(pip_start + float(i) * 12.0 + 4.0, s.y * 0.92), 3.2, pip_color)


func _draw_item_visual(item, rect: Rect2) -> void:
	var id: StringName = item.id
	var c: Vector2 = rect.position + rect.size * 0.5
	var v: Color = item.visual_color
	var a: Color = item.accent_color
	match id:
		&"combat_scratcher":
			_draw_post(c, rect.size.y * 0.82, v, a)
		&"agility_treadmill":
			_draw_treadmill(rect, v, a)
		&"training_bag":
			_draw_punching_bag(rect, v, a)
		&"colony_beds":
			_draw_beds(rect, v, a)
		&"medical_station":
			_draw_medical(rect, v, a)
		&"tool_table":
			_draw_tool_table(rect, v, a)
		&"watch_post":
			_draw_watch_post(rect, v, a)
		&"sardine_storage":
			_draw_sardine_storage(rect, v, a)
		&"supply_box":
			_draw_supply_box(rect, v, a)
		&"meow_radio":
			_draw_radio(rect, v, a)
		&"shelter_map":
			_draw_map_item(rect, v, a)
		&"cardboard_barricade":
			_draw_barricade(rect, v, a)
		_:
			draw_rect(rect, v, true)
			draw_rect(rect, v.darkened(0.4), false, 2.0)


func _draw_post(c: Vector2, h: float, v: Color, a: Color) -> void:
	draw_rect(Rect2(c + Vector2(-18, h * 0.33), Vector2(36, 8)), v.darkened(0.25), true)
	draw_rect(Rect2(c + Vector2(-7, -h * 0.38), Vector2(14, h * 0.76)), v, true)
	draw_rect(Rect2(c + Vector2(-15, -h * 0.45), Vector2(30, 8)), a, true)
	for y in 4:
		draw_line(c + Vector2(-6, -h * 0.24 + y * 9), c + Vector2(6, -h * 0.29 + y * 9), v.lightened(0.28), 1.4)


func _draw_treadmill(r: Rect2, v: Color, a: Color) -> void:
	var base := Rect2(r.position + Vector2(2, r.size.y * 0.46), Vector2(r.size.x - 4, r.size.y * 0.32))
	draw_rect(base, v.darkened(0.2), true)
	draw_rect(base, a, false, 2.0)
	draw_line(base.position + Vector2(8, base.size.y * 0.5), base.position + Vector2(base.size.x - 8, base.size.y * 0.5), Color(0.08, 0.09, 0.1), 4.0)
	draw_line(base.position + Vector2(base.size.x * 0.78, 0), r.position + Vector2(r.size.x * 0.88, 4), a, 3.0)
	draw_circle(base.position + Vector2(10, base.size.y), 5.0, Color(0.06, 0.06, 0.07))
	draw_circle(base.position + Vector2(base.size.x - 10, base.size.y), 5.0, Color(0.06, 0.06, 0.07))


func _draw_punching_bag(r: Rect2, v: Color, a: Color) -> void:
	draw_line(r.position + Vector2(r.size.x * 0.5, -2), r.position + Vector2(r.size.x * 0.5, 10), a, 2.0)
	var bag := Rect2(r.position + Vector2(r.size.x * 0.22, 8), Vector2(r.size.x * 0.56, r.size.y - 12))
	draw_circle(bag.position + Vector2(bag.size.x * 0.5, bag.size.x * 0.35), bag.size.x * 0.5, v)
	draw_rect(Rect2(bag.position + Vector2(0, bag.size.x * 0.35), Vector2(bag.size.x, bag.size.y - bag.size.x * 0.65)), v, true)
	draw_circle(bag.position + Vector2(bag.size.x * 0.5, bag.size.y - bag.size.x * 0.3), bag.size.x * 0.5, v.darkened(0.05))
	draw_line(bag.position + Vector2(5, bag.size.y * 0.45), bag.position + Vector2(bag.size.x - 5, bag.size.y * 0.38), a, 2.0)


func _draw_beds(r: Rect2, v: Color, a: Color) -> void:
	for i in 2:
		var bed := Rect2(r.position + Vector2(3 + i * r.size.x * 0.46, r.size.y * 0.32), Vector2(r.size.x * 0.42, r.size.y * 0.42))
		draw_rect(bed, v, true)
		draw_rect(bed, v.darkened(0.35), false, 2.0)
		draw_rect(Rect2(bed.position + Vector2(4, 4), Vector2(bed.size.x - 8, bed.size.y * 0.32)), a.lightened(0.15), true)
		draw_circle(bed.position + Vector2(bed.size.x * 0.72, bed.size.y * 0.62), 5.0, Color(0.08, 0.07, 0.08))


func _draw_medical(r: Rect2, v: Color, a: Color) -> void:
	draw_rect(r, v, true)
	draw_rect(r, Color(0.18, 0.18, 0.2), false, 2.0)
	draw_rect(Rect2(r.position + Vector2(r.size.x * 0.42, 8), Vector2(r.size.x * 0.16, r.size.y - 16)), a, true)
	draw_rect(Rect2(r.position + Vector2(8, r.size.y * 0.42), Vector2(r.size.x - 16, r.size.y * 0.16)), a, true)
	draw_circle(r.position + Vector2(r.size.x - 8, 8), 3.0, Color(0.95, 0.25, 0.25))


func _draw_tool_table(r: Rect2, v: Color, a: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.38), Vector2(r.size.x, r.size.y * 0.18)), v, true)
	draw_rect(Rect2(r.position + Vector2(6, r.size.y * 0.56), Vector2(5, r.size.y * 0.34)), v.darkened(0.25), true)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 11, r.size.y * 0.56), Vector2(5, r.size.y * 0.34)), v.darkened(0.25), true)
	draw_line(r.position + Vector2(12, r.size.y * 0.25), r.position + Vector2(28, r.size.y * 0.12), a, 3.0)
	draw_line(r.position + Vector2(29, r.size.y * 0.14), r.position + Vector2(38, r.size.y * 0.24), a, 3.0)
	draw_rect(Rect2(r.position + Vector2(r.size.x * 0.58, r.size.y * 0.17), Vector2(14, 16)), Color(0.18, 0.2, 0.22), true)


func _draw_watch_post(r: Rect2, v: Color, a: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(r.size.x * 0.42, r.size.y * 0.24), Vector2(r.size.x * 0.16, r.size.y * 0.62)), v.darkened(0.2), true)
	var top := Rect2(r.position + Vector2(5, 2), Vector2(r.size.x - 10, r.size.y * 0.34))
	draw_rect(top, v, true)
	draw_rect(top, a, false, 2.0)
	draw_circle(top.position + Vector2(top.size.x * 0.35, top.size.y * 0.52), 3.2, Color(0.85, 0.95, 0.7))
	draw_circle(top.position + Vector2(top.size.x * 0.65, top.size.y * 0.52), 3.2, Color(0.85, 0.95, 0.7))


func _draw_sardine_storage(r: Rect2, v: Color, a: Color) -> void:
	draw_rect(r, v, true)
	draw_rect(r, v.darkened(0.35), false, 2.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 8)), a, true)
	for i in 3:
		var y: float = r.position.y + 18 + i * 10
		draw_line(Vector2(r.position.x + 10, y), Vector2(r.position.x + r.size.x - 10, y - 2), Color(0.65, 0.82, 0.9), 4.0)
		draw_circle(Vector2(r.position.x + r.size.x - 13, y - 2), 3.0, Color(0.65, 0.82, 0.9))


func _draw_supply_box(r: Rect2, v: Color, a: Color) -> void:
	draw_rect(r, v, true)
	draw_rect(r, v.darkened(0.42), false, 2.0)
	draw_line(r.position + Vector2(r.size.x * 0.5, 0), r.position + Vector2(r.size.x * 0.5, r.size.y), v.darkened(0.35), 2.0)
	draw_circle(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.47), 10.0, a)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(0, r.size.y * 0.58), "?", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(0.12, 0.10, 0.08))


func _draw_radio(r: Rect2, v: Color, a: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(3, 12), Vector2(r.size.x - 6, r.size.y - 14)), v, true)
	draw_rect(Rect2(r.position + Vector2(3, 12), Vector2(r.size.x - 6, r.size.y - 14)), v.darkened(0.4), false, 2.0)
	draw_line(r.position + Vector2(r.size.x * 0.25, 12), r.position + Vector2(4, 0), a, 2.0)
	draw_circle(r.position + Vector2(r.size.x * 0.72, r.size.y * 0.52), 8.0, a)
	for i in 3:
		draw_line(r.position + Vector2(11, 23 + i * 7), r.position + Vector2(r.size.x * 0.48, 23 + i * 7), Color(0.08, 0.08, 0.09), 2.0)


func _draw_map_item(r: Rect2, v: Color, a: Color) -> void:
	var paper := Rect2(r.position + Vector2(4, 4), r.size - Vector2(8, 8))
	draw_rect(paper, v.lightened(0.22), true)
	draw_rect(paper, v.darkened(0.35), false, 2.0)
	draw_line(paper.position + Vector2(paper.size.x * 0.34, 0), paper.position + Vector2(paper.size.x * 0.34, paper.size.y), v.darkened(0.18), 1.5)
	draw_line(paper.position + Vector2(paper.size.x * 0.66, 0), paper.position + Vector2(paper.size.x * 0.66, paper.size.y), v.darkened(0.18), 1.5)
	draw_line(paper.position + Vector2(7, paper.size.y * 0.65), paper.position + Vector2(paper.size.x - 8, paper.size.y * 0.28), a, 2.0)
	draw_circle(paper.position + Vector2(paper.size.x * 0.72, paper.size.y * 0.28), 4.0, Color(0.95, 0.25, 0.25))


func _draw_barricade(r: Rect2, v: Color, a: Color) -> void:
	for i in 3:
		var plank := Rect2(r.position + Vector2(0, 8 + i * 13), Vector2(r.size.x, 9))
		draw_rect(plank, v.lightened(0.05 * i), true)
		draw_rect(plank, v.darkened(0.35), false, 1.5)
	draw_line(r.position + Vector2(8, r.size.y - 4), r.position + Vector2(r.size.x - 8, 5), a, 4.0)
	draw_circle(r.position + Vector2(12, 14), 2.0, Color(0.10, 0.08, 0.06))
	draw_circle(r.position + Vector2(r.size.x - 12, r.size.y - 14), 2.0, Color(0.10, 0.08, 0.06))
