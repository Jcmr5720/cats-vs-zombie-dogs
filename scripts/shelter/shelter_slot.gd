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
	var occupied: bool = _occupied_item() != null
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
		draw_string(font, Vector2(0, s.y * 0.42), icon, HORIZONTAL_ALIGNMENT_CENTER, s.x, 24, Color(0.55, 0.5, 0.42, 0.6))
		draw_string(font, Vector2(0, s.y * 0.66), slot_label, HORIZONTAL_ALIGNMENT_CENTER, s.x, 11, Color(0.55, 0.52, 0.46, 0.8))
		draw_string(font, Vector2(0, s.y * 0.85), "vacio", HORIZONTAL_ALIGNMENT_CENTER, s.x, 10, Color(0.45, 0.42, 0.38, 0.6))
		return
	# Ocupado: caja del objeto con sombra, cuerpo, tapa de acento y pips de nivel.
	var item_size: Vector2 = item.size
	var center := Vector2(s.x * 0.5, s.y * 0.44)
	if feedback > 0.0:
		center.y -= sin((1.0 - feedback) * PI) * 18.0
		item_size *= Vector2(1.0 + 0.12 * feedback, 1.0 - 0.08 * feedback)
	var rect := Rect2(center - item_size * 0.5, item_size)
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(0, 0, 0, 0.3), true)
	draw_rect(rect, item.visual_color, true)
	draw_rect(rect, item.visual_color.darkened(0.4), false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 7)), item.accent_color, true)
	draw_line(rect.position + Vector2(3, 10), rect.position + Vector2(rect.size.x - 3, 10), item.visual_color.lightened(0.2), 1.5)
	var font2 := ThemeDB.fallback_font
	draw_string(font2, Vector2(0, s.y * 0.82), item.display_name, HORIZONTAL_ALIGNMENT_CENTER, s.x, 11, Color(0.95, 0.92, 0.85))
	# Pips de nivel.
	var level: int = _shelter.get_level(item.id)
	var pip_start: float = s.x * 0.5 - float(item.max_level) * 6.0
	for i in item.max_level:
		var pip_color: Color = item.accent_color if i < level else Color(0.3, 0.28, 0.24)
		draw_circle(Vector2(pip_start + float(i) * 12.0 + 4.0, s.y * 0.92), 3.2, pip_color)
