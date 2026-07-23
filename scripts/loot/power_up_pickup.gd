extends "res://scripts/loot/ground_pickup.gd"
## Power-up recogible del suelo (FASE 12). Sustituye a las cartas de stat, de
## companero y a las mutaciones del mini-boss.
##
## No implementa efectos: al recogerse llama a player.apply_upgrade() con el
## `upgrade_id` del PowerUpData, asi que el `match` de player.gd sigue siendo la
## unica fuente de verdad. En coop el efecto es SOLO del recolector, salvo los de
## categoria companero, que apply_upgrade ya redirige al CompanionManager
## compartido.

const PICKUP_SCRIPT := "res://scripts/loot/power_up_pickup.gd"
## Los power-ups normales caducan: sin esto, una racha de drops en una zona que el
## jugador no vuelve a pisar deja nodos vivos toda la partida.
const DEFAULT_LIFETIME: float = 45.0

var data: PowerUpData


## Fabrica del pickup. Patron identico a MapInteractable.spawn(): construye el
## nodo por codigo y lo mete diferido, sin .tscn que mantener.
static func spawn(powerup: PowerUpData, parent: Node, pos: Vector2,
		pop: Vector2 = Vector2.ZERO) -> Node2D:
	if powerup == null or parent == null or not parent.is_inside_tree():
		return null
	var node := Area2D.new()
	node.set_script(load(PICKUP_SCRIPT))
	node.set("data", powerup)
	node.set("pop_velocity", pop)
	node.position = pos
	parent.add_child.call_deferred(node)
	return node


func _ready() -> void:
	if data != null:
		visual_color = data.visual_color
		icon_type = data.icon_type
		# Las mutaciones se leen distinto: mas grandes y sin caducidad, son el
		# premio de un jefe y el jugador debe poder ir a por ellas con calma.
		if data.is_mutation():
			visual_radius = 19.0
			lifetime = 0.0
		else:
			lifetime = DEFAULT_LIFETIME
	_setup_body(8, collect_radius)
	_build_info_card()
	# Tutorial (FASE 13): primera mejora / primera mutacion, una vez por perfil.
	_show_tip(&"mutation" if data != null and data.is_mutation() else &"upgrade")
	# Aparicion anunciada, igual que los interactables de mapa.
	Feedback.hit_effect(global_position, visual_color, 0.5, 2.0)


## Tarjeta de informacion previa a recoger (FASE 13): nombre, categoria + rareza,
## descripcion de una frase, efecto numerico y estado. Todo sale del catalogo y
## del .tres: nada de ids tecnicos.
func _build_info_card() -> void:
	if data == null:
		return
	var category: StringName = LootCatalog.powerup_category(data)
	var rows: Array = [
		{"text": data.display_name, "color": visual_color, "size": 14, "weight": 600},
		{"text": LootCatalog.kind_line(category, data.rarity),
			"color": LootCatalog.rarity_color(data.rarity), "size": 11},
	]
	if data.description != "":
		rows.append({"text": "\"%s\"" % data.description, "color": Color(0.85, 0.87, 0.94), "size": 11})
	var effect: String = LootCatalog.effect_line(data.effect_id())
	if effect != "":
		rows.append({"text": effect, "color": Color(1.0, 0.93, 0.6), "size": 12, "weight": 600})
	var state: String = LootCatalog.powerup_state_line(data, _nearest_active_player())
	if state != "":
		rows.append({"text": state, "color": Color(0.7, 0.74, 0.82), "size": 10})
	_set_card_rows(rows)


## Icono en el minimapa (FASE 13): las mutaciones tienen forma propia; los
## power-ups comunes solo se dibujan si estan cerca (lo decide el controller).
func minimap_loot_kind() -> StringName:
	return &"loot_mutation" if data != null and data.is_mutation() else &"loot_powerup"


func collect(player_node: Node) -> bool:
	if not claim():
		return false
	if data == null or player_node == null or not player_node.has_method("apply_upgrade"):
		return false

	player_node.apply_upgrade(data.effect_id())

	# Confirmacion post-recogida (FASE 13): toast por categoria con el efecto en
	# lenguaje llano, en la mitad del recolector si es coop.
	var category: StringName = LootCatalog.powerup_category(data)
	var effect: String = LootCatalog.effect_line(data.effect_id())
	var hud: Node = _hud()
	if hud != null and hud.has_method("show_loot_toast"):
		hud.show_loot_toast(LootCatalog.category_toast(category), data.display_name,
			effect if effect != "" else data.description,
			LootCatalog.category_color(category), int(player_node.get("player_id")))

	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(LootCatalog.category_sfx(category))

	if data.is_mutation():
		# Una mutacion es un momento de partida: se anuncia como tal.
		Feedback.hitstop(0.1, 0.06)
		Feedback.shake(0.6)
	# Reaccion visual sobre el personaje que recoge, no solo sobre el pickup.
	if player_node is Node2D:
		Feedback.hit_effect((player_node as Node2D).global_position, visual_color, 0.35, 1.6)
	Feedback.hit_effect(global_position, visual_color, 0.45, 2.2)

	RunTelemetry.count(&"mutations_collected" if data.is_mutation() else &"powerups_collected")
	_play_collect_feedback()
	return true
