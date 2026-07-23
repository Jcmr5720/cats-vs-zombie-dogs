extends "res://scripts/loot/ground_pickup.gd"
## Arma tirada en el suelo (FASE 12). Sustituye a las cartas de "arma nueva" y
## "mejora de arma".
##
## A diferencia del power-up NO tiene iman ni se recoge por contacto cuando hay
## que decidir algo: el jugador manda. Tres casos, en orden de menos a mas
## decision:
##   1. Ya tienes el arma            -> prompt "MEJORAR" (sube un nivel).
##   2. Tienes hueco libre           -> se recoge SOLA al tocarla (no hay que
##                                      decidir nada; pedir un boton seria friccion).
##   3. Inventario lleno (4 armas)   -> prompt "CAMBIAR por X" con barra de hold.
##
## El prompt vive EN EL MUNDO, colgando del pickup, no en el HUD: asi el coop no
## tiene que resolver "el HUD de quien" y el jugador ya esta mirando el suelo.
##
## El arma descartada vuelve al suelo (la suelta quien llama a swap), asi que
## equivocarse en tiempo real no es irreversible.

const PICKUP_SCRIPT := "res://scripts/loot/weapon_pickup.gd"
const WeaponData = preload("res://scripts/weapons/weapon_data.gd")

## Segundos de hold para confirmar un intercambio. Deliberado pero corto: compite
## con la horda encima, al contrario que el rescate de companeros (1.0 s).
const HOLD_DURATION: float = 0.55
## Distancia a la que el pickup reacciona al jugador.
const INTERACT_RADIUS: float = 48.0

var data: WeaponData

var _bar: ProgressBar
var _progress: float = 0.0
## Jugador que esta manteniendo el boton ahora mismo (coop: gana quien complete).
var _holder: Node2D
## Firma del ultimo contenido de la tarjeta: solo se reconstruye al cambiar de
## caso (lejos / mejorar / comparar), no cada frame.
var _card_state: String = ""


static func spawn(weapon: WeaponData, parent: Node, pos: Vector2,
		pop: Vector2 = Vector2.ZERO) -> Node2D:
	if weapon == null or parent == null or not parent.is_inside_tree():
		return null
	var node := Area2D.new()
	node.set_script(load(PICKUP_SCRIPT))
	node.set("data", weapon)
	node.set("pop_velocity", pop)
	node.position = pos
	parent.add_child.call_deferred(node)
	return node


func _ready() -> void:
	magnet_enabled = false
	lifetime = 0.0  # un arma espera al jugador el tiempo que haga falta
	visual_radius = 16.0
	if data != null:
		visual_color = data.visual_color
	_setup_body(8, INTERACT_RADIUS, WEAPON_GROUP)
	_build_bar()
	_apply_card(&"idle", null, null)
	# Tutorial (FASE 13): primera arma vista en el suelo.
	_show_tip(&"weapon")
	Feedback.hit_effect(global_position, visual_color, 0.6, 2.4)


func _build_bar() -> void:
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.position = Vector2(-45, -14)
	_bar.custom_minimum_size = Vector2(90, 8)
	_bar.visible = false
	add_child(_bar)


## Filas base de la tarjeta del arma: nombre, categoria + rareza, descripcion,
## rasgos principales y aviso de evolucion. Todo desde el catalogo (FASE 13).
func _base_rows() -> Array:
	var rows: Array = [
		{"text": data.display_name if data != null else "Arma",
			"color": visual_color, "size": 14, "weight": 600},
	]
	if data == null:
		return rows
	rows.append({"text": LootCatalog.kind_line(&"weapon", data.rarity),
		"color": LootCatalog.rarity_color(data.rarity), "size": 11})
	if data.description != "":
		rows.append({"text": "\"%s\"" % data.description, "color": Color(0.85, 0.87, 0.94), "size": 11})
	rows.append({"text": LootCatalog.weapon_traits(data), "color": Color(1.0, 0.93, 0.6), "size": 11})
	var evo: String = LootCatalog.weapon_evolution_hint(data)
	if evo != "":
		rows.append({"text": evo, "color": Color(0.85, 0.65, 1.0), "size": 10})
	return rows


## Reconstruye la tarjeta segun el caso actual. `state` cambia poco (lejos /
## recoger / mejorar / maximo / comparar), asi que la reconstruccion es rara.
func _apply_card(state: StringName, actor: Node2D, target: Node2D) -> void:
	var signature: String = str(state)
	if actor != null:
		signature += ":%d" % int(actor.get("player_id"))
	if target != null and target.data != null:
		signature += ":" + str(target.data.id)
	if signature == _card_state:
		return
	_card_state = signature

	var rows: Array = _base_rows()
	match state:
		&"pickup":
			rows.append({"text": "Recoger arma (acércate)", "color": Color(0.62, 1.0, 0.72), "size": 12, "weight": 600})
		&"upgrade":
			var weapon: Node2D = null
			if actor != null:
				var wm: Node = _weapon_manager(actor)
				if wm != null:
					weapon = wm.get_weapon(data.id)
			if weapon != null:
				rows.append({"text": "Nivel actual: %d → %d" % [int(weapon.level), int(weapon.level) + 1],
					"color": Color(0.7, 0.74, 0.82), "size": 11})
			rows.append({"text": "%sMantén %s para MEJORAR" % [_actor_prefix(actor), _key_hint(actor)],
				"color": Color(0.62, 1.0, 0.72), "size": 12, "weight": 600})
		&"maxed":
			rows.append({"text": "Ya la tienes al nivel máximo", "color": Color(0.7, 0.74, 0.82), "size": 11})
		&"swap":
			# Panel de comparacion compacto (FASE 13): arma encontrada arriba, la
			# que saldria abajo, tecla de hold y aviso de que nada se pierde.
			rows.append({"text": "Nivel actual: 0 → 1", "color": Color(0.7, 0.74, 0.82), "size": 10})
			if target != null and target.data != null:
				rows.append({"text": "Reemplazará: %s (Nv. %d)" % [target.data.display_name, int(target.level)],
					"color": Color(1.0, 0.62, 0.55), "size": 11, "weight": 600})
				rows.append({"text": LootCatalog.weapon_traits(target.data),
					"color": Color(0.82, 0.7, 0.66), "size": 10})
			rows.append({"text": "%sMantén %s para cambiar" % [_actor_prefix(actor), _key_hint(actor)],
				"color": Color(0.62, 1.0, 0.72), "size": 12, "weight": 600})
			rows.append({"text": "La descartada quedará en el suelo", "color": Color(0.7, 0.74, 0.82), "size": 10})
	_set_card_rows(rows)


func _process(delta: float) -> void:
	super._process(delta)
	if _claimed:
		return

	# La tarjeta reacciona al jugador mas cercano aunque aun no este a rango de
	# interaccion: la informacion llega ANTES que la decision (FASE 13).
	var viewer: Node2D = _nearest_active_player()
	var viewer_wm: Node = _weapon_manager(viewer) if viewer != null else null
	if viewer_wm != null:
		if not viewer_wm.has_weapon(data.id):
			if viewer_wm.can_add_weapon():
				_apply_card(&"pickup", viewer, null)
			else:
				_apply_card(&"swap", viewer, viewer_wm.get_swap_candidate())
		else:
			var owned: Node2D = viewer_wm.get_weapon(data.id)
			if owned != null and owned.is_max_level():
				_apply_card(&"maxed", viewer, null)
			else:
				_apply_card(&"upgrade", viewer, null)

	var actor: Node2D = _nearest_player_in_range()
	if actor == null:
		_reset_hold()
		return

	var wm: Node = _weapon_manager(actor)
	if wm == null:
		_reset_hold()
		return

	# Caso 2: hueco libre y arma nueva -> entra sola, sin friccion.
	if not wm.has_weapon(data.id) and wm.can_add_weapon():
		if claim():
			wm.add_weapon(data)
			_announce_taken()
		return

	# Casos 1 y 3: hay decision, asi que hay hold con barra.
	var upgrading: bool = wm.has_weapon(data.id)
	var target: Node2D = null
	if upgrading:
		var weapon: Node2D = wm.get_weapon(data.id)
		if weapon != null and weapon.is_max_level():
			_reset_hold()
			return
	else:
		target = wm.get_swap_candidate()
		if target == null:
			_reset_hold()
			return
		# Tutorial (FASE 13): primera vez con el inventario lleno.
		_show_tip(&"swap")

	_bar.visible = true
	if not Input.is_action_pressed(_interact_action(actor)):
		# Soltar reinicia: un hold a medias no se guarda.
		_progress = 0.0
		_holder = null
		_bar.value = 0.0
		return

	# Coop: si cambia quien mantiene el boton, el progreso empieza de cero.
	if _holder != actor:
		_holder = actor
		_progress = 0.0

	_progress += delta
	_bar.value = clampf(_progress / HOLD_DURATION, 0.0, 1.0)
	if _progress < HOLD_DURATION:
		return

	if not claim():
		return
	if upgrading:
		wm.level_up_weapon(data.id)
	else:
		var discarded: WeaponData = wm.replace_weapon(target.data.id, data)
		# El arma descartada vuelve al suelo: el intercambio es reversible, que es
		# lo que hace tolerable decidir en tiempo real. Se suelta un poco por
		# debajo del jugador para que no se solape con este mismo pickup.
		if discarded != null:
			var drop_at: Vector2 = actor.global_position + Vector2(randf_range(-30.0, 30.0), 44.0)
			(load(PICKUP_SCRIPT) as GDScript).call("spawn", discarded, get_parent(), drop_at)
	_announce_taken()


## Icono en el minimapa (FASE 13): arma abandonada/soltada en el suelo.
func minimap_loot_kind() -> StringName:
	return &"loot_weapon"


func _announce_taken() -> void:
	_reset_hold()
	RunTelemetry.count(&"weapons_taken")
	Feedback.hit_effect(global_position, visual_color, 0.4, 2.0)
	_play_collect_feedback()


func _reset_hold() -> void:
	_progress = 0.0
	_holder = null
	if is_instance_valid(_bar):
		_bar.visible = false
		_bar.value = 0.0


## Jugador activo mas cercano DENTRO del radio de interaccion, o null.
func _nearest_player_in_range() -> Node2D:
	var p := _nearest_active_player()
	if p == null or not is_instance_valid(p):
		return null
	if global_position.distance_to(p.global_position) > INTERACT_RADIUS:
		return null
	return p


func _weapon_manager(actor: Node) -> Node:
	if actor != null and actor.has_method("get_weapon_manager"):
		return actor.get_weapon_manager()
	return null


## Accion de interaccion segun el jugador, igual que el player resuelve sus
## acciones de movimiento por player_id.
func _interact_action(actor: Node) -> StringName:
	return &"p2_interact" if int(actor.get("player_id")) >= 2 else &"interact"


func _key_hint(actor: Node) -> String:
	return "H" if int(actor.get("player_id")) >= 2 else "E"


func _draw() -> void:
	super._draw()
	# Marco de caja para que se lea como "arma en el suelo" y no como power-up.
	var r: float = visual_radius * 1.5
	var outline := visual_color
	outline.a = 0.9
	draw_rect(Rect2(Vector2(-r, -r), Vector2(r * 2.0, r * 2.0)), outline, false, 2.5)
