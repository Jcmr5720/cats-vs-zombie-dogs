extends PanelContainer
## Tienda del Refugio (Fase 10): categorias, lista de objetos con estado
## (no comprado / comprado / colocado / nivel maximo), detalle con bonus actual
## y siguiente, y acciones Comprar / Mejorar / Colocar / Quitar.
## Emite request_place para que el ShelterMenu entre en modo colocacion.

signal request_place(item_id: StringName)
signal closed()

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const ShelterBonusCalculator = preload("res://scripts/shelter/shelter_bonus_calculator.gd")

const CATEGORIES: Array[Dictionary] = [
	{"id": &"entrenamiento", "label": "Entrenamiento", "color": Color(1.0, 0.6, 0.2)},
	{"id": &"companeros", "label": "Compañeros", "color": Color(0.75, 0.55, 0.9)},
	{"id": &"economia", "label": "Economia", "color": Color(1.0, 0.85, 0.35)},
	{"id": &"rescate", "label": "Rescate", "color": Color(0.45, 0.85, 1.0)},
	{"id": &"defensa", "label": "Defensa", "color": Color(0.9, 0.6, 0.3)},
]

var _shelter: Node
var _save: Node
var _category: StringName = &"entrenamiento"
var _selected_id: StringName = &""

var _category_row: HBoxContainer
var _list_box: VBoxContainer
var _sardines_label: Label
var _detail_name: Label
var _detail_desc: Label
var _detail_state: Label
var _detail_current: Label
var _detail_next: Label
var _buy_button: Button
var _upgrade_button: Button
var _place_button: Button
var _remove_button: Button
var _message_label: Label


func _ready() -> void:
	_shelter = get_node_or_null("/root/Shelter")
	_save = get_node_or_null("/root/SaveManager")
	MenuTheme.style_panel(self, MenuTheme.ACCENT, Color(0.07, 0.06, 0.055, 0.97))
	_build_ui()
	if _shelter != null:
		_shelter.shelter_items_changed.connect(refresh)
	if _save != null and _save.has_signal("sardines_changed"):
		_save.sardines_changed.connect(func(_total: int) -> void: refresh())
	refresh()


func _build_ui() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	# Cabecera: titulo + sardinas + cerrar.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var title := MenuTheme.make_title("Tienda del Refugio", 24, MenuTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_sardines_label = Label.new()
	_sardines_label.add_theme_font_size_override("font_size", 17)
	_sardines_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	head.add_child(_sardines_label)
	var close_btn := MenuTheme.make_button("Cerrar", MenuTheme.TEXT_DIM)
	close_btn.custom_minimum_size = Vector2(110, 38)
	close_btn.pressed.connect(func() -> void: closed.emit())
	head.add_child(close_btn)

	# Pestañas de categoria.
	_category_row = HBoxContainer.new()
	_category_row.add_theme_constant_override("separation", 6)
	col.add_child(_category_row)

	# Cuerpo: lista (izquierda) + detalle (derecha).
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(330, 0)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	body.add_child(detail)
	_detail_name = MenuTheme.make_title("", 20, MenuTheme.TEXT)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail.add_child(_detail_name)
	_detail_state = Label.new()
	_detail_state.add_theme_font_size_override("font_size", 13)
	detail.add_child(_detail_state)
	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.add_theme_font_size_override("font_size", 14)
	_detail_desc.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	detail.add_child(_detail_desc)
	_detail_current = Label.new()
	_detail_current.add_theme_font_size_override("font_size", 14)
	_detail_current.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	detail.add_child(_detail_current)
	_detail_next = Label.new()
	_detail_next.add_theme_font_size_override("font_size", 14)
	_detail_next.add_theme_color_override("font_color", MenuTheme.CYAN)
	detail.add_child(_detail_next)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	detail.add_child(actions)
	_buy_button = MenuTheme.make_button("Comprar", MenuTheme.ACCENT)
	_buy_button.custom_minimum_size = Vector2(140, 40)
	_buy_button.pressed.connect(_on_buy)
	actions.add_child(_buy_button)
	_upgrade_button = MenuTheme.make_button("Mejorar", MenuTheme.ZOMBIE)
	_upgrade_button.custom_minimum_size = Vector2(140, 40)
	_upgrade_button.pressed.connect(_on_upgrade)
	actions.add_child(_upgrade_button)
	var actions2 := HBoxContainer.new()
	actions2.add_theme_constant_override("separation", 8)
	detail.add_child(actions2)
	_place_button = MenuTheme.make_button("Colocar", MenuTheme.CYAN)
	_place_button.custom_minimum_size = Vector2(140, 40)
	_place_button.pressed.connect(_on_place)
	actions2.add_child(_place_button)
	_remove_button = MenuTheme.make_button("Quitar", MenuTheme.TEXT_DIM)
	_remove_button.custom_minimum_size = Vector2(140, 40)
	_remove_button.pressed.connect(_on_remove)
	actions2.add_child(_remove_button)

	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", 13)
	detail.add_child(_message_label)


func refresh() -> void:
	if _shelter == null:
		return
	_sardines_label.text = "🐟 %d" % (_save.get_sardines() if _save != null else 0)
	_rebuild_categories()
	_rebuild_list()
	_refresh_detail()


func _rebuild_categories() -> void:
	for child in _category_row.get_children():
		child.queue_free()
	for cat in CATEGORIES:
		var chip := Button.new()
		chip.text = str(cat["label"])
		chip.custom_minimum_size = Vector2(0, 34)
		chip.add_theme_font_size_override("font_size", 13)
		var accent: Color = cat["color"]
		var active: bool = cat["id"] == _category
		for state in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = accent.lerp(Color(0.09, 0.08, 0.075), 0.35 if active else 0.85)
			box.border_color = accent if active else Color(accent.r, accent.g, accent.b, 0.35)
			box.set_border_width_all(1)
			box.set_corner_radius_all(8)
			box.content_margin_left = 12
			box.content_margin_right = 12
			chip.add_theme_stylebox_override(state, box)
		chip.add_theme_color_override("font_color", Color(1, 1, 1) if active else MenuTheme.TEXT_DIM)
		chip.pressed.connect(func() -> void:
			_category = cat["id"]
			_selected_id = &""
			refresh())
		_category_row.add_child(chip)


func _rebuild_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	var first_id: StringName = &""
	for item in _shelter.get_items():
		if item.category != _category:
			continue
		if first_id == &"":
			first_id = item.id
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 46)
		var selected: bool = item.id == _selected_id
		var unlocked: bool = _shelter.is_unlocked(item.id)
		for state in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(0.14, 0.12, 0.11, 0.98) if selected else Color(0.10, 0.09, 0.085, 0.95)
			if state == "hover":
				box.bg_color = Color(0.14, 0.12, 0.11, 0.98)
			box.border_color = item.accent_color if selected else Color(0.28, 0.25, 0.2)
			if not unlocked:
				box.bg_color = Color(0.065, 0.06, 0.06, 0.9)
				box.border_color = Color(0.18, 0.17, 0.16)
			box.set_border_width_all(2 if selected else 1)
			box.set_corner_radius_all(8)
			row.add_theme_stylebox_override(state, box)
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 10
		hb.offset_right = -10
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hb)
		var swatch := ColorRect.new()
		swatch.color = item.visual_color
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(swatch)
		var name_label := Label.new()
		name_label.text = item.display_name
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", MenuTheme.TEXT if unlocked else MenuTheme.TEXT_DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(name_label)
		var status := Label.new()
		status.add_theme_font_size_override("font_size", 12)
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status.text = _item_status_text(item)
		status.add_theme_color_override("font_color", _item_status_color(item))
		hb.add_child(status)
		row.pressed.connect(func() -> void:
			_selected_id = item.id
			refresh())
		_list_box.add_child(row)
	if _selected_id == &"" and first_id != &"":
		_selected_id = first_id


func _item_status_text(item) -> String:
	if not _shelter.is_unlocked(item.id):
		return "Bloqueado"
	if not _shelter.is_purchased(item.id):
		return "🐟 %d" % item.price
	var level: int = _shelter.get_level(item.id)
	var placed: String = "● " if _shelter.is_placed(item.id) else ""
	if level >= item.max_level:
		return "%sMAX" % placed
	return "%sNv. %d" % [placed, level]


func _item_status_color(item) -> Color:
	if not _shelter.is_unlocked(item.id):
		return Color(0.62, 0.58, 0.52)
	if not _shelter.is_purchased(item.id):
		return Color(1.0, 0.85, 0.4)
	return Color(0.55, 0.9, 0.5) if _shelter.is_placed(item.id) else MenuTheme.TEXT_DIM


func _refresh_detail() -> void:
	var item = _shelter.get_item(_selected_id) if _selected_id != &"" else null
	var has_item: bool = item != null
	for button in [_buy_button, _upgrade_button, _place_button, _remove_button]:
		button.visible = has_item
	if not has_item:
		_detail_name.text = ""
		_detail_desc.text = "Elige un objeto de la lista."
		_detail_state.text = ""
		_detail_current.text = ""
		_detail_next.text = ""
		return
	var purchased: bool = _shelter.is_purchased(item.id)
	var placed: bool = _shelter.is_placed(item.id)
	var unlocked: bool = _shelter.is_unlocked(item.id)
	var level: int = _shelter.get_level(item.id)
	_detail_name.text = item.display_name
	_detail_name.add_theme_color_override("font_color", item.accent_color)
	_detail_desc.text = item.description
	if not unlocked:
		_detail_state.text = _shelter.get_unlock_text(item.id)
		_detail_state.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
		_detail_current.text = "Bonus futuro: %s" % ShelterBonusCalculator.format_effect(item.effect_type, item.effect_value_per_level, 1)
		_detail_next.text = ""
	elif not purchased:
		_detail_state.text = "No comprado"
		_detail_state.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		_detail_current.text = "Bonus al comprar: %s" % ShelterBonusCalculator.format_effect(item.effect_type, item.effect_value_per_level, 1)
		_detail_next.text = ""
	else:
		var slot_name: String = str(_shelter.get_slot(_shelter.get_slot_of_item(item.id)).get("label", ""))
		_detail_state.text = ("Colocado en %s" % slot_name) if placed else "Comprado (sin colocar: no da bonus)"
		_detail_state.add_theme_color_override("font_color", Color(0.55, 0.9, 0.5) if placed else Color(1.0, 0.72, 0.4))
		_detail_current.text = "Nivel %d/%d — %s" % [level, item.max_level, ShelterBonusCalculator.format_effect(item.effect_type, item.effect_value_per_level, level)]
		if level < item.max_level:
			_detail_next.text = "Siguiente nivel: %s" % ShelterBonusCalculator.format_effect(item.effect_type, item.effect_value_per_level, level + 1)
		else:
			_detail_next.text = "Nivel maximo alcanzado"

	var sardines: int = _save.get_sardines() if _save != null else 0
	_buy_button.visible = unlocked and not purchased
	_buy_button.disabled = sardines < item.price
	_buy_button.text = "Comprar (🐟 %d)" % item.price
	_upgrade_button.visible = unlocked and purchased and level < item.max_level
	var upgrade_cost: int = _shelter.get_upgrade_cost(item.id)
	_upgrade_button.disabled = not _shelter.can_upgrade(item.id)
	_upgrade_button.text = "Mejorar (🐟 %d)" % upgrade_cost if upgrade_cost > 0 else "Mejorar"
	_place_button.visible = unlocked and purchased and not placed
	_remove_button.visible = unlocked and placed


func _on_buy() -> void:
	var item = _shelter.get_item(_selected_id)
	if item == null:
		return
	if _shelter.purchase(_selected_id):
		_show_message("¡%s comprado! Colocalo en un slot para activar su bonus." % item.display_name, Color(0.6, 1.0, 0.7))
		_play_ui(&"ui_click")
	else:
		_show_message("No tienes suficientes Sardinas.", Color(1.0, 0.58, 0.58))
	refresh()


func _on_upgrade() -> void:
	var item = _shelter.get_item(_selected_id)
	if item == null:
		return
	if _shelter.upgrade(_selected_id):
		_show_message("%s mejorado a Nv. %d." % [item.display_name, _shelter.get_level(item.id)], Color(0.6, 1.0, 0.7))
		_play_ui(&"ui_click")
	else:
		_show_message("No se pudo mejorar (Sardinas o nivel maximo).", Color(1.0, 0.58, 0.58))
	refresh()


func _on_place() -> void:
	if _selected_id != &"" and _shelter.is_purchased(_selected_id):
		request_place.emit(_selected_id)


func _on_remove() -> void:
	var slot_id: StringName = _shelter.get_slot_of_item(_selected_id)
	if slot_id != &"" and _shelter.remove_from_slot(slot_id):
		_show_message("Objeto retirado del refugio.", MenuTheme.TEXT_DIM)
	refresh()


func _show_message(text: String, color: Color) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", color)


func _play_ui(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)
