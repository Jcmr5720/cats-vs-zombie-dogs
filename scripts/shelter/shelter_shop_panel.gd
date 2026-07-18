extends PanelContainer
## Tienda del Refugio (rediseño Steam): parece una tienda real. Pestañas de
## categoría (segmented), rejilla de tarjetas de producto con icono, precio como
## badge y estado por color/icono, y un panel de detalle con una acción primaria
## contextual (Comprar → Colocar/Mejorar → Quitar) en vez de cuatro botones fijos.
## Emite request_place para que el ShelterMenu entre en modo colocación.

signal request_place(item_id: StringName)
signal closed()

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const ShelterBonusCalculator = preload("res://scripts/shelter/shelter_bonus_calculator.gd")

const CATEGORIES: Array[Dictionary] = [
	{"id": &"entrenamiento", "label": "Entreno", "color": Color(1.0, 0.6, 0.2), "icon": &"upgrade"},
	{"id": &"companeros", "label": "Compañeros", "color": Color(0.75, 0.55, 0.9), "icon": &"companion"},
	{"id": &"economia", "label": "Economía", "color": Color(1.0, 0.82, 0.36), "icon": &"sardine"},
	{"id": &"rescate", "label": "Rescate", "color": Color(0.45, 0.85, 1.0), "icon": &"paw"},
	{"id": &"defensa", "label": "Defensa", "color": Color(0.9, 0.6, 0.3), "icon": &"shield"},
]

var _shelter: Node
var _save: Node
var _category: StringName = &"entrenamiento"
var _selected_id: StringName = &""

var _category_row: HBoxContainer
var _grid: GridContainer
var _sardines_label: Label
var _detail_name: Label
var _detail_desc: Label
var _detail_state: Label
var _detail_current: Label
var _detail_next: Label
var _primary_button: Button
var _secondary_button: Button
var _message_label: Label


func _ready() -> void:
	_shelter = get_node_or_null("/root/Shelter")
	_save = get_node_or_null("/root/SaveManager")
	MenuTheme.style_panel(self, MenuTheme.ACCENT, Color(0.08, 0.07, 0.065, 0.98))
	_build_ui()
	if _shelter != null:
		_shelter.shelter_items_changed.connect(refresh)
	if _save != null and _save.has_signal("sardines_changed"):
		_save.sardines_changed.connect(func(_total: int) -> void: refresh())
	refresh()


func _category_meta(id: StringName) -> Dictionary:
	for cat in CATEGORIES:
		if cat["id"] == id:
			return cat
	return CATEGORIES[0]


func _build_ui() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_M)
	add_child(col)

	# Cabecera: título + sardinas + cerrar.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", MenuTheme.GAP_M)
	col.add_child(head)
	var title := MenuTheme.make_title("Tienda del Refugio", MenuTheme.FS_H2, MenuTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var sardines_chip := PanelContainer.new()
	var chip_box := StyleBoxFlat.new()
	chip_box.bg_color = MenuTheme.GOLD.lerp(Color(0.10, 0.12, 0.15, 1.0), 0.80)
	chip_box.border_color = Color(MenuTheme.GOLD.r, MenuTheme.GOLD.g, MenuTheme.GOLD.b, 0.55)
	chip_box.set_border_width_all(1)
	chip_box.set_corner_radius_all(999)
	chip_box.content_margin_left = 12
	chip_box.content_margin_right = 14
	chip_box.content_margin_top = 6
	chip_box.content_margin_bottom = 6
	sardines_chip.add_theme_stylebox_override("panel", chip_box)
	sardines_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", MenuTheme.GAP_S)
	sardines_chip.add_child(chip_row)
	var sardine_icon := IconDrawer.new()
	sardine_icon.icon_type = &"sardine"
	sardine_icon.accent = MenuTheme.GOLD
	sardine_icon.custom_minimum_size = Vector2(20, 20)
	sardine_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(sardine_icon)
	_sardines_label = MenuTheme.make_label("0", MenuTheme.FS_H3, MenuTheme.GOLD)
	chip_row.add_child(_sardines_label)
	head.add_child(sardines_chip)
	var close_btn := MenuTheme.make_icon_button(&"close", "Cerrar", MenuTheme.TEXT_DIM, 40)
	close_btn.pressed.connect(func() -> void: closed.emit())
	head.add_child(close_btn)

	# Pestañas de categoría.
	_category_row = MenuTheme.make_segmented(CATEGORIES, _category, _on_category_selected, MenuTheme.ACCENT)
	col.add_child(_category_row)

	# Cuerpo: rejilla de productos (izq) + detalle (der).
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", MenuTheme.GAP_L)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", MenuTheme.GAP_S)
	_grid.add_theme_constant_override("v_separation", MenuTheme.GAP_S)
	scroll.add_child(_grid)

	# Panel de detalle.
	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(300, 0)
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuTheme.style_panel(detail_panel, MenuTheme.ACCENT, MenuTheme.PANEL_BG_SOFT)
	body.add_child(detail_panel)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", MenuTheme.GAP_S)
	detail_panel.add_child(detail)
	_detail_name = MenuTheme.make_title("", MenuTheme.FS_H3 + 3, MenuTheme.TEXT)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail.add_child(_detail_name)
	_detail_state = MenuTheme.make_label("", MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM)
	detail.add_child(_detail_state)
	_detail_desc = MenuTheme.make_label("", MenuTheme.FS_BODY, MenuTheme.TEXT_DIM)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_desc)
	detail.add_child(_thin_rule())
	_detail_current = MenuTheme.make_label("", MenuTheme.FS_BODY, MenuTheme.ZOMBIE)
	_detail_current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_current)
	_detail_next = MenuTheme.make_label("", MenuTheme.FS_BODY, MenuTheme.CYAN)
	_detail_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_next)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)
	_message_label = MenuTheme.make_label("", MenuTheme.FS_CAPTION, MenuTheme.TEXT_DIM)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_message_label)
	_primary_button = MenuTheme.make_button("Comprar", MenuTheme.ACCENT, &"primary")
	_primary_button.custom_minimum_size = Vector2(0, 46)
	_primary_button.pressed.connect(_on_primary)
	detail.add_child(_primary_button)
	_secondary_button = MenuTheme.make_button("Quitar", MenuTheme.TEXT_DIM, &"ghost")
	_secondary_button.custom_minimum_size = Vector2(0, 40)
	_secondary_button.pressed.connect(_on_secondary)
	detail.add_child(_secondary_button)


func _on_category_selected(id: Variant) -> void:
	_category = id
	_selected_id = &""
	MenuTheme.refresh_segmented(_category_row, _category)
	refresh()


func refresh() -> void:
	if _shelter == null:
		return
	_sardines_label.text = str(_save.get_sardines() if _save != null else 0)
	_rebuild_grid()
	_refresh_detail()


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var first_id: StringName = &""
	for item in _shelter.get_items():
		if item.category != _category:
			continue
		if first_id == &"":
			first_id = item.id
		_grid.add_child(_make_product_card(item))
	if _selected_id == &"" and first_id != &"":
		_selected_id = first_id


## Tarjeta de producto: icono de categoría + nombre + estado (precio / colocado /
## nivel / bloqueado / MAX) con color e icono. Seleccionable.
func _make_product_card(item) -> Button:
	var unlocked: bool = _shelter.is_unlocked(item.id)
	var selected: bool = item.id == _selected_id
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 88)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.13, 0.12, 0.11, 0.98) if selected else Color(0.10, 0.095, 0.09, 0.96)
		if state == "hover" and not selected:
			box.bg_color = Color(0.13, 0.12, 0.11, 0.98)
		if not unlocked:
			box.bg_color = Color(0.075, 0.07, 0.068, 0.92)
		box.border_color = item.accent_color if selected else Color(0.26, 0.24, 0.20)
		if not unlocked:
			box.border_color = Color(0.20, 0.19, 0.18)
		box.set_border_width_all(2 if selected else 1)
		box.set_corner_radius_all(MenuTheme.RADIUS)
		box.set_content_margin_all(MenuTheme.GAP_S + 2)
		card.add_theme_stylebox_override(state, box)
	card.pressed.connect(func() -> void:
		_selected_id = item.id
		refresh())

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = MenuTheme.GAP_S + 2
	row.offset_right = -(MenuTheme.GAP_S + 2)
	row.add_theme_constant_override("separation", MenuTheme.GAP_S)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var icon := IconDrawer.new()
	icon.icon_type = _category_meta(item.category)["icon"]
	icon.accent = item.accent_color
	icon.dimmed = not unlocked
	icon.custom_minimum_size = Vector2(40, 40)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 2)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)
	var name_label := MenuTheme.make_label(item.display_name, MenuTheme.FS_BODY, MenuTheme.TEXT if unlocked else MenuTheme.TEXT_DIM)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(name_label)
	text_col.add_child(_card_status(item, unlocked))
	return card


## Línea de estado de la tarjeta: icono + texto corto con color semántico.
func _card_status(item, unlocked: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.GAP_XS + 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon: StringName = &""
	var text: String = ""
	var color: Color = MenuTheme.TEXT_DIM
	if not unlocked:
		icon = &"lock"
		text = "Bloqueado"
		color = Color(0.62, 0.58, 0.52)
	elif not _shelter.is_purchased(item.id):
		icon = &"sardine"
		text = str(item.price)
		# Precio en rojo si no alcanza (lectura inmediata de "no puedo").
		var sardines: int = _save.get_sardines() if _save != null else 0
		color = MenuTheme.GOLD if sardines >= item.price else MenuTheme.DANGER
	elif _shelter.is_placed(item.id):
		icon = &"check"
		var lvl: int = _shelter.get_level(item.id)
		text = "Colocado · Nv %d" % lvl if lvl < item.max_level else "Colocado · MAX"
		color = MenuTheme.ZOMBIE
	else:
		var lvl2: int = _shelter.get_level(item.id)
		text = "En inventario · Nv %d" % lvl2
		color = MenuTheme.TEXT_DIM
	if icon != &"":
		var ic := IconDrawer.new()
		ic.icon_type = icon
		ic.accent = color
		ic.custom_minimum_size = Vector2(14, 14)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
	var label := MenuTheme.make_label(text, MenuTheme.FS_CAPTION, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row


func _refresh_detail() -> void:
	var item = _shelter.get_item(_selected_id) if _selected_id != &"" else null
	if item == null:
		_detail_name.text = ""
		_detail_desc.text = "Elige un objeto de la lista."
		_detail_state.text = ""
		_detail_current.text = ""
		_detail_next.text = ""
		_primary_button.visible = false
		_secondary_button.visible = false
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
		_detail_state.add_theme_color_override("font_color", MenuTheme.ACCENT)
		_detail_current.text = "Bonus futuro: %s" % ShelterBonusCalculator.format_effect(item.effect_type, item.effect_value_per_level, 1)
		_detail_next.text = ""
	elif not purchased:
		_detail_state.text = "No comprado"
		_detail_state.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		_detail_current.text = "Al comprar: %s" % ShelterBonusCalculator.format_effect(item.effect_type, item.effect_value_per_level, 1)
		_detail_next.text = ""
	else:
		var slot_name: String = str(_shelter.get_slot(_shelter.get_slot_of_item(item.id)).get("label", ""))
		_detail_state.text = ("Colocado en %s" % slot_name) if placed else "Comprado · sin colocar (no da bonus)"
		_detail_state.add_theme_color_override("font_color", MenuTheme.ZOMBIE if placed else MenuTheme.ACCENT)
		_detail_current.text = "Nv %d/%d · %s" % [level, item.max_level, ShelterBonusCalculator.format_effect(item.effect_type, item.effect_value_per_level, level)]
		if level < item.max_level:
			_detail_next.text = "Siguiente: %s" % ShelterBonusCalculator.format_effect(item.effect_type, item.effect_value_per_level, level + 1)
		else:
			_detail_next.text = "Nivel máximo alcanzado"

	_update_actions(item, unlocked, purchased, placed, level)


## Configura los dos botones según el estado (acción primaria contextual).
func _update_actions(item, unlocked: bool, purchased: bool, placed: bool, level: int) -> void:
	var sardines: int = _save.get_sardines() if _save != null else 0
	_primary_button.visible = true
	_secondary_button.visible = false
	if not unlocked:
		_primary_button.text = "Bloqueado"
		_primary_button.disabled = true
		MenuTheme.style_button(_primary_button, MenuTheme.TEXT_DIM, &"secondary")
		_primary_button.set_meta("action", &"none")
		return
	if not purchased:
		_primary_button.text = "Comprar · %d" % item.price
		_primary_button.disabled = sardines < item.price
		MenuTheme.style_button(_primary_button, MenuTheme.ACCENT, &"primary")
		_primary_button.set_meta("action", &"buy")
		return
	# Comprado: la acción primaria es colocar (si falta) o mejorar; secundaria adapta.
	var upgrade_cost: int = _shelter.get_upgrade_cost(item.id)
	var can_upgrade: bool = level < item.max_level and _shelter.can_upgrade(item.id)
	if not placed:
		_primary_button.text = "Colocar"
		_primary_button.disabled = false
		MenuTheme.style_button(_primary_button, MenuTheme.CYAN, &"primary")
		_primary_button.set_meta("action", &"place")
		if level < item.max_level:
			_secondary_button.visible = true
			_secondary_button.text = "Mejorar · %d" % upgrade_cost if upgrade_cost > 0 else "Mejorar"
			_secondary_button.disabled = not can_upgrade
			MenuTheme.style_button(_secondary_button, MenuTheme.ZOMBIE, &"secondary")
			_secondary_button.set_meta("action", &"upgrade")
	else:
		if level < item.max_level:
			_primary_button.text = "Mejorar · %d" % upgrade_cost if upgrade_cost > 0 else "Mejorar"
			_primary_button.disabled = not can_upgrade
			MenuTheme.style_button(_primary_button, MenuTheme.ZOMBIE, &"primary")
			_primary_button.set_meta("action", &"upgrade")
		else:
			_primary_button.text = "Nivel máximo"
			_primary_button.disabled = true
			MenuTheme.style_button(_primary_button, MenuTheme.TEXT_DIM, &"secondary")
			_primary_button.set_meta("action", &"none")
		_secondary_button.visible = true
		_secondary_button.text = "Quitar"
		_secondary_button.disabled = false
		MenuTheme.style_button(_secondary_button, MenuTheme.DANGER, &"ghost")
		_secondary_button.set_meta("action", &"remove")


func _on_primary() -> void:
	_run_action(_primary_button.get_meta("action", &"none"))


func _on_secondary() -> void:
	_run_action(_secondary_button.get_meta("action", &"none"))


func _run_action(action: StringName) -> void:
	var item = _shelter.get_item(_selected_id)
	if item == null:
		return
	match action:
		&"buy":
			if _shelter.purchase(_selected_id):
				_show_message("¡%s comprado! Colócalo para activar su bonus." % item.display_name, MenuTheme.ZOMBIE)
				_play_ui(&"ui_buy")
			else:
				_show_message("No tienes suficientes sardinas.", MenuTheme.DANGER)
		&"upgrade":
			if _shelter.upgrade(_selected_id):
				_show_message("%s mejorado a Nv %d." % [item.display_name, _shelter.get_level(item.id)], MenuTheme.ZOMBIE)
				_play_ui(&"ui_buy")
			else:
				_show_message("No se pudo mejorar (sardinas o nivel máximo).", MenuTheme.DANGER)
		&"place":
			if _shelter.is_purchased(_selected_id):
				request_place.emit(_selected_id)
		&"remove":
			var slot_id: StringName = _shelter.get_slot_of_item(_selected_id)
			if slot_id != &"" and _shelter.remove_from_slot(slot_id):
				_show_message("Objeto retirado del refugio.", MenuTheme.TEXT_DIM)
	refresh()


func _show_message(text: String, color: Color) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", color)
	# Destello breve: el mensaje se percibe como respuesta inmediata a la accion.
	_message_label.modulate = Color(1.7, 1.7, 1.7, 1.0)
	var tween := create_tween()
	tween.tween_property(_message_label, "modulate", Color(1, 1, 1, 1), 0.35)


func _thin_rule() -> Control:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.custom_minimum_size = Vector2(0, 2)
	return line


func _play_ui(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)
