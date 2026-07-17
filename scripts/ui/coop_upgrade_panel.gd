extends Control
## Panel de cartas del coop (Rework Coop). Cada jugador tiene SU columna de cartas
## en SU mitad de la pantalla y elige con SUS controles, en simultaneo:
## - J1: W/S (o flechas) para navegar, ESPACIO/ENTER para confirmar, o raton.
## - J2: stick/dpad arriba-abajo (o I/K) para navegar, boton A (o H) para confirmar.
## Si solo un jugador subio de nivel, el otro ve un aviso discreto y la partida
## sigue pausada hasta que se confirme la eleccion. Sin cartas compartidas: lo que
## eliges es TUYO (armas, stats). Lo crea UpgradeManager solo en coop.

## Fase correccion: se elimino la opcion de SALTAR ("Pasar") y toda recompensa
## por omitir. La seleccion solo termina eligiendo una carta valida. El auto-pick
## por inactividad quedo desactivado por defecto: solo actua si el jugador activa
## el ajuste de accesibilidad "card_auto_pick" (Settings).
signal card_chosen(player_id: int, card_index: int)

@warning_ignore("shadowed_global_identifier")
const IconDrawer = preload("res://scripts/ui/icon_drawer.gd")

const P1_COLOR := Color(0.99, 0.72, 0.28)
const P2_COLOR := Color(0.4, 0.72, 1.0)

const RARITY_STYLE: Dictionary = {
	&"common": {"label": "COMUN", "color": Color(0.78, 0.82, 0.88)},
	&"rare": {"label": "RARO", "color": Color(0.36, 0.66, 1.0)},
	&"epic": {"label": "EPICO", "color": Color(0.78, 0.45, 1.0)},
	&"legendary": {"label": "LEGENDARIA", "color": Color(1.0, 0.82, 0.25)},
}

## Acciones de input por jugador (indice 0 = J1, 1 = J2).
const CONTROLS: Array[Dictionary] = [
	{"up": &"move_up", "down": &"move_down", "confirm": &"p1_card_confirm",
		"hint": "W/S elegir  ·  ESPACIO confirmar"},
	{"up": &"p2_move_up", "down": &"p2_move_down", "confirm": &"p2_card_confirm",
		"hint": "Stick/I-K elegir  ·  A/H confirmar"},
]

## Estado por lado: {open, cards, index, buttons, column, title, hint, waiting,
## accent, idle, confirm_lock}
var _sides: Array = [{}, {}]


func _ready() -> void:
	add_to_group("coop_upgrade_panel")
	# Procesa siempre: el arbol esta pausado mientras se elige.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	for index in 2:
		_build_side(index)


func _build_side(index: int) -> void:
	var color: Color = P1_COLOR if index == 0 else P2_COLOR
	var host := Control.new()
	host.name = "Side%d" % (index + 1)
	host.anchor_left = 0.0 if index == 0 else 0.5
	host.anchor_right = 0.5 if index == 0 else 1.0
	host.anchor_top = 0.0
	host.anchor_bottom = 1.0
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(center)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", color)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 5)
	column.add_child(title)

	var buttons: Array = []
	for card_index in 3:
		var button := _make_card_button(index)
		column.add_child(button)
		button.pressed.connect(_on_card_pressed.bind(index, card_index))
		buttons.append(button)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = CONTROLS[index]["hint"]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88, 0.9))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hint.add_theme_constant_override("outline_size", 3)
	column.add_child(hint)

	# Aviso "esperando al otro": visible cuando este lado NO elige pero el otro si.
	var waiting := Label.new()
	waiting.text = "%s esta eligiendo su mejora..." % CoopConfig.player_tag(2 - index)
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting.set_anchors_preset(Control.PRESET_CENTER)
	waiting.position = Vector2(-160, -12)
	waiting.custom_minimum_size = Vector2(320, 0)
	waiting.add_theme_font_size_override("font_size", 18)
	waiting.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98, 0.95))
	waiting.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	waiting.add_theme_constant_override("outline_size", 4)
	waiting.visible = false
	host.add_child(waiting)

	_sides[index] = {
		"open": false,
		"cards": [],
		"index": 0,
		"buttons": buttons,
		"column": column,
		"title": title,
		"hint": hint,
		"waiting": waiting,
		"accent": color,
		"idle": 0.0,
		"confirm_lock": 0.0,
	}


func _make_card_button(side_index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(440, 92)
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	# Solo el lado del J1 acepta raton: el J2 juega con gamepad/teclado derecho y
	# asi un clic de J1 no puede "robarle" la decision.
	if side_index != 0:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return button


# --- API para UpgradeManager ---------------------------------------------------

## Abre (o refresca) la seleccion de un jugador. cards = hasta 3 diccionarios de
## carta del UpgradeManager. Elegir una es obligatorio (no existe "Pasar").
func open_for(player_id: int, cards: Array) -> void:
	var side: Dictionary = _sides[_side_index(player_id)]
	side["open"] = true
	side["cards"] = cards
	side["index"] = 0
	side["idle"] = 0.0
	# Anti doble-confirmacion: ignora confirms un instante tras abrir/refrescar
	# (un confirm mantenido o duplicado no puede elegir la mano nueva a ciegas).
	side["confirm_lock"] = 0.25
	visible = true

	(side["title"] as Label).text = "%s · ¡Elige tu mejora!" % CoopConfig.player_tag(player_id)
	var buttons: Array = side["buttons"]
	for i in buttons.size():
		var button: Button = buttons[i]
		if i >= cards.size():
			button.visible = false
			continue
		button.visible = true
		_fill_card(button, cards[i])
	_apply_selection_styles(side)
	_set_waiting_visible()


## Cierra el lado de un jugador (eligio o no tiene mas pendientes).
func close_for(player_id: int) -> void:
	var side: Dictionary = _sides[_side_index(player_id)]
	side["open"] = false
	side["cards"] = []
	_set_waiting_visible()
	if not is_open(1) and not is_open(2):
		visible = false


func is_open(player_id: int) -> bool:
	return bool(_sides[_side_index(player_id)].get("open", false))


func _side_index(player_id: int) -> int:
	return clampi(player_id - 1, 0, 1)


## Muestra columnas solo de lados abiertos; el lado cerrado ve el aviso de espera.
func _set_waiting_visible() -> void:
	for index in 2:
		var side: Dictionary = _sides[index]
		var open: bool = bool(side.get("open", false))
		(side["column"] as Control).visible = open
		var other_open: bool = bool(_sides[1 - index].get("open", false))
		(side["waiting"] as Label).visible = (not open) and other_open


# --- Render de cartas ------------------------------------------------------------

func _fill_card(button: Button, card: Dictionary) -> void:
	for child in button.get_children():
		child.queue_free()
	var rarity: StringName = card.get("rarity", &"common")
	var style: Dictionary = RARITY_STYLE.get(rarity, RARITY_STYLE[&"common"])
	var accent: Color = style["color"]

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10.0
	row.offset_right = -10.0
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var icon := IconDrawer.new()
	icon.custom_minimum_size = Vector2(52, 52)
	icon.icon_type = _card_icon_type(str(card.get("type_label", "")))
	icon.accent = accent
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 1)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)

	var name_label := Label.new()
	name_label.text = str(card.get("name", "Mejora"))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	texts.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = str(card.get("description", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	texts.add_child(desc_label)

	var meta_label := Label.new()
	var type_label: String = str(card.get("type_label", ""))
	meta_label.text = style["label"] if type_label == "" else "%s · %s" % [type_label.to_upper(), style["label"]]
	meta_label.add_theme_font_size_override("font_size", 10)
	meta_label.add_theme_color_override("font_color", accent)
	texts.add_child(meta_label)


func _card_icon_type(type_label: String) -> StringName:
	var t: String = type_label.to_lower()
	if t.contains("arma"):
		return &"weapon_projectile"
	if t.contains("compa"):
		return &"companion"
	if t.contains("stat") or t.contains("mejora"):
		return &"upgrade"
	return &"cat"


## Estilo por estado de seleccion: la carta elegida brilla con el color del jugador.
func _apply_selection_styles(side: Dictionary) -> void:
	var buttons: Array = side["buttons"]
	var selected: int = int(side["index"])
	var accent: Color = side["accent"]
	var entries: Array = []
	for i in buttons.size():
		entries.append([buttons[i], i])
	for entry in entries:
		var button: Button = entry[0]
		var is_selected: bool = int(entry[1]) == selected
		var rarity_color: Color = accent
		var cards: Array = side["cards"]
		if int(entry[1]) < cards.size():
			var card: Dictionary = cards[entry[1]]
			rarity_color = RARITY_STYLE.get(card.get("rarity", &"common"), RARITY_STYLE[&"common"])["color"]
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(0.09, 0.10, 0.145, 0.97).lerp(rarity_color, 0.16 if is_selected else 0.05)
			box.border_color = accent if is_selected else Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.6)
			box.set_border_width_all(4 if is_selected else 2)
			box.set_corner_radius_all(12)
			box.set_content_margin_all(8)
			box.shadow_size = 12 if is_selected else 4
			box.shadow_color = Color(accent.r, accent.g, accent.b, 0.35) if is_selected else Color(0, 0, 0, 0.4)
			button.add_theme_stylebox_override(state, box)
		button.scale = Vector2(1.0, 1.0)
		button.pivot_offset = button.custom_minimum_size * 0.5


# --- Input por jugador -------------------------------------------------------------

## Ajuste de accesibilidad "card_auto_pick" (Settings), cacheado. -1 = sin leer.
var _auto_pick_enabled: int = -1


## Relee el ajuste de accesibilidad (lo llaman las opciones o los tests al cambiarlo).
func refresh_accessibility() -> void:
	_auto_pick_enabled = -1


func _is_auto_pick_enabled() -> bool:
	if _auto_pick_enabled < 0:
		_auto_pick_enabled = 0
		var settings: Node = get_node_or_null("/root/Settings")
		if settings != null and settings.has_method("get_value") and bool(settings.get_value("card_auto_pick", false)):
			_auto_pick_enabled = 1
	return _auto_pick_enabled == 1


func _process(delta: float) -> void:
	if not visible:
		return
	for index in 2:
		var side: Dictionary = _sides[index]
		if not bool(side.get("open", false)):
			continue
		side["confirm_lock"] = maxf(0.0, float(side.get("confirm_lock", 0.0)) - delta)
		var controls: Dictionary = CONTROLS[index]
		var option_count: int = _option_count(side)
		if option_count <= 0:
			continue
		if Input.is_action_just_pressed(controls["down"]):
			side["index"] = (int(side["index"]) + 1) % option_count
			side["idle"] = 0.0
			_apply_selection_styles(side)
			_play_ui(&"ui_hover")
		elif Input.is_action_just_pressed(controls["up"]):
			side["index"] = (int(side["index"]) - 1 + option_count) % option_count
			side["idle"] = 0.0
			_apply_selection_styles(side)
			_play_ui(&"ui_hover")
		elif Input.is_action_just_pressed(controls["confirm"]):
			if float(side.get("confirm_lock", 0.0)) <= 0.0:
				_confirm_side(index)
		else:
			_update_auto_pick(index, side, delta)


## Seleccion automatica SOLO como accesibilidad opcional (ajuste "card_auto_pick",
## desactivado por defecto). Sin el ajuste, el panel espera indefinidamente: si un
## mando se desconecta, la seleccion queda PENDIENTE hasta que vuelva el control.
func _update_auto_pick(index: int, side: Dictionary, delta: float) -> void:
	if not _is_auto_pick_enabled() or CoopConfig.CARD_AUTO_PICK_SECONDS <= 0.0:
		return
	side["idle"] = float(side.get("idle", 0.0)) + delta
	var remaining: float = CoopConfig.CARD_AUTO_PICK_SECONDS - float(side["idle"])
	var hint: Label = side["hint"]
	if remaining <= 0.0:
		hint.text = CONTROLS[index]["hint"]
		_confirm_side(index)
	elif remaining <= CoopConfig.CARD_AUTO_PICK_WARN_SECONDS:
		hint.text = "%s   ·   auto en %d s" % [CONTROLS[index]["hint"], int(ceilf(remaining))]
	else:
		hint.text = CONTROLS[index]["hint"]


## Opciones navegables: SOLO las cartas (elegir es obligatorio).
func _option_count(side: Dictionary) -> int:
	return mini(3, (side["cards"] as Array).size())


func _confirm_side(index: int) -> void:
	var side: Dictionary = _sides[index]
	var selected: int = int(side["index"])
	var cards: Array = side["cards"]
	if selected >= cards.size():
		return
	_play_ui(&"ui_click")
	card_chosen.emit(index + 1, selected)


func _on_card_pressed(side_index: int, card_index: int) -> void:
	var side: Dictionary = _sides[side_index]
	if not bool(side.get("open", false)) or card_index >= (side["cards"] as Array).size():
		return
	if float(side.get("confirm_lock", 0.0)) > 0.0:
		return
	_play_ui(&"ui_click")
	card_chosen.emit(side_index + 1, card_index)


func _play_ui(sound_name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(sound_name)
