extends Control
## Pantalla del Refugio Felino (Fase 10): habitacion procedural acogedora con
## slots fijos, tienda, panel de bonificaciones activas y tutorial de primera
## visita. Solo los objetos colocados en slots otorgan bonus.

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const ShelterSlot = preload("res://scripts/shelter/shelter_slot.gd")
const ShelterBonusCalculator = preload("res://scripts/shelter/shelter_bonus_calculator.gd")
const SHOP_PANEL_SCENE := preload("res://scenes/shelter/ShelterShopPanel.tscn")

var _shelter: Node
var _save: Node
var _anim_time: float = 0.0
var _cat_react: float = 0.0
var _cat_petted_time: float = 0.0
## Objeto pendiente de colocar (modo colocacion activo si != "").
var _placing_item_id: StringName = &""

var _slots: Array = []
var _shop_panel: PanelContainer
var _inventory_panel: PanelContainer
var _inventory_grid: GridContainer
var _bonus_list: VBoxContainer
var _sardines_label: Label
var _placing_hint: Label
var _tutorial_overlay: Control
var _slot_remove_buttons: Dictionary = {}
## Capa modal compartida (oscurece el fondo y centra tienda/inventario por anclas).
var _modal_dim: ColorRect
var _modal_center: CenterContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shelter = get_node_or_null("/root/Shelter")
	_save = get_node_or_null("/root/SaveManager")
	_build_ui()
	if _shelter != null:
		_shelter.shelter_items_changed.connect(_refresh_all)
		_shelter.shelter_bonus_changed.connect(_refresh_bonuses)
	if _save != null and _save.has_signal("sardines_changed"):
		_save.sardines_changed.connect(func(_total: int) -> void: _refresh_chips())
	_refresh_all()
	if _shelter != null and not _shelter.has_seen_tutorial():
		_show_tutorial()
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_music"):
		audio.play_music(&"shelter")
	MenuTheme.add_fade_in(self)


func _process(delta: float) -> void:
	_anim_time += delta
	if _cat_petted_time > 0.0:
		_cat_petted_time = maxf(0.0, _cat_petted_time - delta)
	var target_react: float = 1.0 if _cat_rect(get_viewport_rect().size).has_point(get_local_mouse_position()) else 0.0
	_cat_react = lerpf(_cat_react, target_react, minf(1.0, delta * 7.0))
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _cat_rect(get_viewport_rect().size).has_point(get_local_mouse_position()):
			_cat_petted_time = 0.9
			_play_ui(&"ui_notification")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _placing_item_id != &"":
			_cancel_placement()
		elif _modal_dim != null and _modal_dim.visible:
			_close_modals()
		else:
			GameFlow.return_to_main_menu()


# --- Fondo procedural: habitacion gatuna post-apocaliptica acogedora -----------

func _draw() -> void:
	var s: Vector2 = get_viewport_rect().size
	var wall_h: float = s.y * 0.42
	# Pared con tablones y suelo de madera.
	draw_rect(Rect2(0, 0, s.x, wall_h), Color(0.14, 0.115, 0.10), true)
	for i in 6:
		draw_line(Vector2(0, wall_h * float(i + 1) / 7.0), Vector2(s.x, wall_h * float(i + 1) / 7.0), Color(0.10, 0.085, 0.075, 0.6), 2.0)
	draw_rect(Rect2(0, wall_h, s.x, s.y - wall_h), Color(0.17, 0.13, 0.10), true)
	var px: float = 0.0
	while px < s.x:
		draw_line(Vector2(px, wall_h), Vector2(px - 60.0, s.y), Color(0.12, 0.095, 0.08, 0.5), 2.0)
		px += 120.0
	draw_line(Vector2(0, wall_h), Vector2(s.x, wall_h), Color(0.08, 0.065, 0.055), 3.0)

	# Ventana tapiada con luna.
	var win := Rect2(s.x * 0.06, wall_h * 0.18, 130, 100)
	draw_rect(win, Color(0.05, 0.06, 0.10), true)
	draw_circle(win.position + Vector2(92, 30), 17.0, Color(0.92, 0.94, 0.85, 0.8))
	draw_rect(win, Color(0.3, 0.24, 0.18), false, 5.0)
	draw_line(win.position + Vector2(-8, 26), win.position + Vector2(win.size.x + 8, 40), Color(0.38, 0.30, 0.22), 9.0)
	draw_line(win.position + Vector2(-8, 74), win.position + Vector2(win.size.x + 8, 62), Color(0.34, 0.27, 0.20), 9.0)

	# Guirnalda de luces calidas colgando de la pared.
	for i in 14:
		var t: float = float(i) / 13.0
		var lx: float = s.x * (0.28 + t * 0.62)
		var ly: float = wall_h * 0.16 + sin(t * PI) * 26.0
		if i > 0:
			var pt: float = float(i - 1) / 13.0
			draw_line(Vector2(s.x * (0.28 + pt * 0.62), wall_h * 0.16 + sin(pt * PI) * 26.0), Vector2(lx, ly), Color(0.25, 0.2, 0.16), 1.5)
		var glow: float = 0.55 + 0.35 * sin(_anim_time * 2.2 + float(i) * 1.1)
		var warm := Color(1.0, 0.8, 0.4) if i % 2 == 0 else Color(0.5, 0.85, 1.0)
		draw_circle(Vector2(lx, ly + 4.0), 3.5, Color(warm.r, warm.g, warm.b, glow))

	# Alfombra tejida en el centro del suelo.
	var rug_center := Vector2(s.x * 0.42, s.y * 0.72)
	for i in 3:
		var rug_size := Vector2(430 - i * 60, 190 - i * 28)
		var tone := Color(0.45, 0.25, 0.22, 0.5) if i % 2 == 0 else Color(0.55, 0.42, 0.25, 0.5)
		draw_rect(Rect2(rug_center - rug_size * 0.5, rug_size), tone, i == 2)
		if i < 2:
			draw_rect(Rect2(rug_center - rug_size * 0.5, rug_size), tone.lightened(0.15), false, 3.0)
	_draw_sleeping_cat(s)

	# Pila de cajas y saco de sardinas en la esquina.
	var box_base := Vector2(s.x * 0.9, s.y * 0.86)
	for b in 3:
		var box_size := Vector2(74 - b * 10, 48 - b * 5)
		var box_pos := box_base - Vector2(box_size.x * 0.5, float(b + 1) * 46.0)
		draw_rect(Rect2(box_pos + Vector2(4, 4), box_size), Color(0, 0, 0, 0.25), true)
		draw_rect(Rect2(box_pos, box_size), Color(0.42, 0.32, 0.2), true)
		draw_rect(Rect2(box_pos, box_size), Color(0.28, 0.21, 0.14), false, 2.0)
		draw_line(box_pos + Vector2(box_size.x * 0.5, 0), box_pos + Vector2(box_size.x * 0.5, box_size.y), Color(0.28, 0.21, 0.14), 1.5)
	# Huellas de pata cruzando el suelo.
	for i in 5:
		var paw := Vector2(s.x * (0.18 + float(i) * 0.06), s.y * (0.9 - float(i) * 0.015))
		draw_circle(paw, 4.0, Color(0.1, 0.08, 0.06, 0.5))
		draw_circle(paw + Vector2(-5, -6), 2.0, Color(0.1, 0.08, 0.06, 0.5))
		draw_circle(paw + Vector2(0, -8), 2.0, Color(0.1, 0.08, 0.06, 0.5))
		draw_circle(paw + Vector2(5, -6), 2.0, Color(0.1, 0.08, 0.06, 0.5))


# --- UI --------------------------------------------------------------------------

func _build_ui() -> void:
	# Cabecera: barra superior estándar (retorno + título + acciones).
	var header := MarginContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.add_theme_constant_override("margin_left", MenuTheme.GAP_L)
	header.add_theme_constant_override("margin_right", MenuTheme.GAP_L)
	header.add_theme_constant_override("margin_top", MenuTheme.GAP_M)
	add_child(header)
	var top := MenuTheme.make_top_bar("Refugio", func() -> void: GameFlow.return_to_main_menu(), MenuTheme.ACCENT)
	header.add_child(top)
	var actions: HBoxContainer = top.get_node("Actions")
	# Chip de sardinas (con handle a la etiqueta para refrescar).
	var sardines_chip := MenuTheme.make_chip("0", MenuTheme.GOLD, &"sardine")
	_sardines_label = sardines_chip.get_child(0).get_child(1)
	actions.add_child(sardines_chip)
	var shop_btn := MenuTheme.make_button("Tienda", MenuTheme.ACCENT, &"primary")
	shop_btn.custom_minimum_size = Vector2(128, 44)
	shop_btn.pressed.connect(_open_shop)
	actions.add_child(shop_btn)
	var inventory_btn := MenuTheme.make_button("Inventario", MenuTheme.CYAN, &"secondary")
	inventory_btn.custom_minimum_size = Vector2(140, 44)
	inventory_btn.pressed.connect(_open_inventory)
	actions.add_child(inventory_btn)

	# Slots del refugio: dos filas sobre el suelo de la habitacion.
	var slots_box := VBoxContainer.new()
	slots_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	slots_box.offset_left = 40
	slots_box.offset_top = -60
	slots_box.add_theme_constant_override("separation", 14)
	add_child(slots_box)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	slots_box.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	slots_box.add_child(row2)
	var slot_infos: Array = _shelter.get_slots() if _shelter != null else []
	for i in slot_infos.size():
		var slot := Button.new()
		slot.set_script(ShelterSlot)
		slot.setup(slot_infos[i])
		slot.pressed.connect(_on_slot_pressed.bind(slot))
		_add_remove_button(slot)
		(row1 if i < 4 else row2).add_child(slot)
		_slots.append(slot)

	# Aviso del modo colocacion.
	_placing_hint = Label.new()
	_placing_hint.visible = false
	_placing_hint.add_theme_font_size_override("font_size", 16)
	_placing_hint.add_theme_color_override("font_color", Color(0.6, 1.0, 0.65))
	_placing_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_placing_hint.add_theme_constant_override("shadow_offset_y", 2)
	_placing_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_placing_hint.offset_top = 92
	add_child(_placing_hint)

	# Panel de bonificaciones activas (derecha).
	var bonus_panel := PanelContainer.new()
	bonus_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	bonus_panel.offset_left = -300
	bonus_panel.offset_right = -MenuTheme.GAP_L
	bonus_panel.offset_top = -140
	MenuTheme.style_panel(bonus_panel, MenuTheme.ZOMBIE, Color(0.06, 0.055, 0.05, 0.94))
	add_child(bonus_panel)
	var bonus_col := VBoxContainer.new()
	bonus_col.add_theme_constant_override("separation", MenuTheme.GAP_S)
	bonus_panel.add_child(bonus_col)
	bonus_col.add_child(MenuTheme.make_section_header("Bonus activos", MenuTheme.ZOMBIE))
	_bonus_list = VBoxContainer.new()
	_bonus_list.add_theme_constant_override("separation", MenuTheme.GAP_XS)
	bonus_col.add_child(_bonus_list)

	# Capa modal compartida: dim + centrador por anclas (tienda / inventario).
	_modal_dim = ColorRect.new()
	_modal_dim.color = Color(0, 0, 0, 0.62)
	_modal_dim.visible = false
	_modal_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal_dim)
	_modal_center = CenterContainer.new()
	_modal_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_center)

	# Tienda (centrada en la capa modal, oculta al inicio).
	_shop_panel = SHOP_PANEL_SCENE.instantiate()
	_shop_panel.visible = false
	_shop_panel.custom_minimum_size = Vector2(780, 480)
	_modal_center.add_child(_shop_panel)
	_shop_panel.request_place.connect(_start_placement)
	_shop_panel.closed.connect(_close_modals)
	_build_inventory_panel()


## Muestra un panel modal (tienda o inventario) con el fondo oscurecido.
func _show_modal(panel: Control) -> void:
	_cancel_placement()
	for child in _modal_center.get_children():
		child.visible = child == panel
	panel.visible = true
	_modal_dim.visible = true


func _close_modals() -> void:
	if _modal_dim != null:
		_modal_dim.visible = false
	if _modal_center != null:
		for child in _modal_center.get_children():
			child.visible = false


func _open_shop() -> void:
	_show_modal(_shop_panel)
	_shop_panel.refresh()


func _open_inventory() -> void:
	_show_modal(_inventory_panel)
	_refresh_inventory()


func _add_remove_button(slot: Button) -> void:
	var remove := Button.new()
	remove.text = "×"
	remove.tooltip_text = "Quitar"
	remove.custom_minimum_size = Vector2(26, 26)
	remove.position = Vector2(96, 6)
	remove.visible = false
	remove.mouse_filter = Control.MOUSE_FILTER_STOP
	remove.add_theme_font_size_override("font_size", 18)
	remove.add_theme_color_override("font_color", Color(1.0, 0.82, 0.7))
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.18, 0.07, 0.06, 0.86) if state != "hover" else Color(0.55, 0.18, 0.13, 0.96)
		box.border_color = Color(1.0, 0.42, 0.32, 0.75)
		box.set_border_width_all(1)
		box.set_corner_radius_all(999)
		remove.add_theme_stylebox_override(state, box)
	remove.pressed.connect(_on_remove_slot_pressed.bind(slot))
	slot.add_child(remove)
	_slot_remove_buttons[slot.slot_id] = remove


func _on_remove_slot_pressed(slot: Button) -> void:
	if _shelter == null:
		return
	if _shelter.remove_from_slot(slot.slot_id):
		_play_ui(&"ui_click")
		_play_slot_feedback(slot, Color(0.75, 0.75, 0.7))
		_refresh_inventory()


func _build_inventory_panel() -> void:
	_inventory_panel = PanelContainer.new()
	_inventory_panel.visible = false
	_inventory_panel.custom_minimum_size = Vector2(640, 400)
	MenuTheme.style_panel(_inventory_panel, MenuTheme.CYAN, Color(0.06, 0.055, 0.05, 0.97))
	_modal_center.add_child(_inventory_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_M)
	_inventory_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", MenuTheme.GAP_M)
	col.add_child(head)
	var title := MenuTheme.make_title("Inventario", MenuTheme.FS_H2, MenuTheme.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := MenuTheme.make_icon_button(&"close", "Cerrar", MenuTheme.TEXT_DIM, 38)
	close_btn.pressed.connect(_close_modals)
	head.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 3
	_inventory_grid.add_theme_constant_override("h_separation", 10)
	_inventory_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_inventory_grid)


func _refresh_inventory() -> void:
	if _inventory_grid == null or _shelter == null:
		return
	for child in _inventory_grid.get_children():
		child.queue_free()
	var any: bool = false
	for item in _shelter.get_items():
		if not _shelter.is_purchased(item.id) or _shelter.is_placed(item.id):
			continue
		any = true
		_inventory_grid.add_child(_make_inventory_item(item))
	if not any:
		var empty := Label.new()
		empty.text = "Sin objetos libres"
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		_inventory_grid.add_child(empty)


func _make_inventory_item(item) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(185, 98)
	MenuTheme.style_panel(panel, item.accent_color, Color(0.10, 0.09, 0.08, 0.94))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var swatch := ColorRect.new()
	swatch.color = item.visual_color
	swatch.custom_minimum_size = Vector2(34, 56)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)
	var name := Label.new()
	name.text = item.display_name
	name.clip_text = true
	name.add_theme_font_size_override("font_size", 13)
	name.add_theme_color_override("font_color", MenuTheme.TEXT)
	text_col.add_child(name)
	var level := Label.new()
	level.text = "Nv. %d" % _shelter.get_level(item.id)
	level.add_theme_font_size_override("font_size", 12)
	level.add_theme_color_override("font_color", item.accent_color)
	text_col.add_child(level)
	var place := _small_icon_button("+", "Colocar")
	place.custom_minimum_size = Vector2(34, 34)
	place.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	place.pressed.connect(func() -> void: _start_placement(item.id))
	row.add_child(place)
	return panel


func _small_icon_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(1, 1, 1))
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.09, 0.10, 0.11, 0.92) if state != "hover" else Color(0.18, 0.25, 0.27, 0.96)
		box.border_color = Color(0.45, 0.85, 1.0, 0.65)
		box.set_border_width_all(1)
		box.set_corner_radius_all(999)
		button.add_theme_stylebox_override(state, box)
	return button


# --- Colocacion ------------------------------------------------------------------

func _start_placement(item_id: StringName) -> void:
	_placing_item_id = item_id
	_close_modals()
	var item = _shelter.get_item(item_id)
	_placing_hint.text = "Elige un slot verde"
	_placing_hint.tooltip_text = item.display_name if item != null else ""
	_placing_hint.visible = true
	for slot in _slots:
		var free: bool = _shelter.get_item_in_slot(slot.slot_id) == &""
		slot.highlight_for_placement = free and _shelter.slot_accepts(slot.slot_id, item_id)
		slot.queue_redraw()


func _cancel_placement() -> void:
	_placing_item_id = &""
	_placing_hint.visible = false
	for slot in _slots:
		slot.highlight_for_placement = false
		slot.queue_redraw()


func _on_slot_pressed(slot: Button) -> void:
	if _shelter == null:
		return
	if _placing_item_id != &"":
		# Modo colocacion: solo acepta slots validos y libres.
		if slot.highlight_for_placement and _shelter.place_item(slot.slot_id, _placing_item_id):
			_play_ui(&"ui_click")
			_play_slot_feedback(slot)
			_cancel_placement()
		return
	var occupied: StringName = _shelter.get_item_in_slot(slot.slot_id)
	if occupied != &"":
		_play_slot_feedback(slot, Color(0.75, 0.9, 1.0))
	else:
		_open_inventory()


# --- Refresco ----------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_chips()
	_refresh_bonuses()
	for slot in _slots:
		slot.refresh()
		var remove := _slot_remove_buttons.get(slot.slot_id) as Button
		if remove != null:
			remove.visible = _shelter != null and _shelter.get_item_in_slot(slot.slot_id) != &""
	if _inventory_panel != null and _inventory_panel.visible:
		_refresh_inventory()


func _refresh_chips() -> void:
	if _sardines_label != null:
		_sardines_label.text = str(_save.get_sardines() if _save != null else 0)


func _refresh_bonuses() -> void:
	for child in _bonus_list.get_children():
		child.queue_free()
	var bonuses: Dictionary = _shelter.get_bonuses() if _shelter != null else {}
	var any: bool = false
	var shown: int = 0
	var total: int = 0
	for key in bonuses:
		var line: String = ShelterBonusCalculator.format_key(str(key), float(bonuses[key]))
		if line == "":
			continue
		any = true
		total += 1
		if shown >= 6:
			continue
		shown += 1
		var label := Label.new()
		label.text = "• %s" % line
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", MenuTheme.TEXT)
		_bonus_list.add_child(label)
	var hidden: int = max(0, total - shown)
	if hidden > 0:
		var more := Label.new()
		more.text = "+%d" % hidden
		more.add_theme_font_size_override("font_size", 13)
		more.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		_bonus_list.add_child(more)
	if not any:
		var empty := Label.new()
		empty.text = "—"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		_bonus_list.add_child(empty)


# --- Tutorial de primera visita ----------------------------------------------------

func _show_tutorial() -> void:
	var panel := MenuTheme.make_overlay(self, MenuTheme.ACCENT, Vector2(480, 0))
	_tutorial_overlay = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.GAP_M)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", MenuTheme.GAP_S)
	col.add_child(head)
	var shelter_icon := IconDrawer.new()
	shelter_icon.icon_type = &"shelter"
	shelter_icon.accent = MenuTheme.ACCENT
	shelter_icon.custom_minimum_size = Vector2(28, 28)
	shelter_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(shelter_icon)
	head.add_child(MenuTheme.make_title("Bienvenida al Refugio", MenuTheme.FS_H2, MenuTheme.ACCENT))
	var body := MenuTheme.make_label("Compra. Coloca. Solo lo equipado da bonus.", MenuTheme.FS_H3, MenuTheme.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	var ok := MenuTheme.make_button("Entendido", MenuTheme.ZOMBIE, &"primary")
	ok.custom_minimum_size = Vector2(200, 44)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		_shelter.mark_tutorial_seen()
		MenuTheme.close_overlay(panel))
	col.add_child(ok)


func _play_ui(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(name)


func _play_slot_feedback(slot: Button, color: Color = Color(1.0, 0.75, 0.3)) -> void:
	if slot != null and slot.has_method("play_place_feedback"):
		slot.play_place_feedback(color)


func _cat_rect(s: Vector2) -> Rect2:
	var center := Vector2(s.x * 0.42, s.y * 0.72)
	return Rect2(center + Vector2(-64, -32), Vector2(128, 70))


func _draw_sleeping_cat(s: Vector2) -> void:
	var rect := _cat_rect(s)
	var center: Vector2 = rect.position + rect.size * 0.5
	var breathe: float = sin(_anim_time * 2.1) * 2.0
	var pet: float = _cat_petted_time / 0.9
	var react: float = maxf(_cat_react, pet)
	var fur := Color(0.12, 0.105, 0.095)
	var highlight := Color(0.24, 0.20, 0.17)
	var shadow := Color(0, 0, 0, 0.22)
	_draw_ellipse(Rect2(center + Vector2(-52, -2 + breathe) + Vector2(5, 7), Vector2(98, 38)), shadow)
	_draw_ellipse(Rect2(center + Vector2(-52, -18 + breathe), Vector2(96, 46 + react * 4.0)), fur)
	_draw_ellipse(Rect2(center + Vector2(13, -27 + breathe - react * 4.0), Vector2(40, 38)), fur)
	var ear_left := PackedVector2Array([
		center + Vector2(18, -22 + breathe - react * 4.0),
		center + Vector2(24, -43 + breathe - react * 8.0),
		center + Vector2(34, -23 + breathe - react * 4.0),
	])
	var ear_right := PackedVector2Array([
		center + Vector2(38, -23 + breathe - react * 4.0),
		center + Vector2(48, -42 + breathe - react * 8.0),
		center + Vector2(51, -20 + breathe - react * 4.0),
	])
	draw_polygon(ear_left, PackedColorArray([fur, fur, fur]))
	draw_polygon(ear_right, PackedColorArray([fur, fur, fur]))
	draw_arc(center + Vector2(-36, 4 + breathe), 24.0 + react * 3.0, PI * 0.2, PI * 1.35, 18, highlight, 7.0)
	draw_circle(center + Vector2(43, -9 + breathe - react * 4.0), 2.2, Color(0.85, 0.78, 0.55) if react > 0.35 else highlight)
	if react > 0.35:
		draw_circle(center + Vector2(28, -10 + breathe - react * 4.0), 2.0, Color(0.85, 0.78, 0.55))
	else:
		draw_line(center + Vector2(26, -10 + breathe), center + Vector2(33, -10 + breathe), highlight, 1.5)
	draw_line(center + Vector2(35, -3 + breathe), center + Vector2(29, 2 + breathe), highlight, 1.5)
	draw_line(center + Vector2(35, -3 + breathe), center + Vector2(43, 0 + breathe), highlight, 1.5)
	if pet > 0.0:
		for i in 3:
			var t: float = float(i) / 2.0
			var p := center + Vector2(4 + t * 28.0, -54.0 - (1.0 - pet) * 18.0 - sin(_anim_time * 4.0 + t) * 2.0)
			draw_string(ThemeDB.fallback_font, p, "~", HORIZONTAL_ALIGNMENT_CENTER, 18.0, 18, Color(1.0, 0.82, 0.55, pet))


func _draw_ellipse(rect: Rect2, color: Color) -> void:
	var center: Vector2 = rect.position + rect.size * 0.5
	draw_set_transform(center, 0.0, Vector2(rect.size.x / rect.size.y, 1.0))
	draw_circle(Vector2.ZERO, rect.size.y * 0.5, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
