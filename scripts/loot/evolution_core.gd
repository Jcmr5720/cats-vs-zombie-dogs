extends "res://scripts/loot/ground_pickup.gd"
## Nucleo de evolucion (FASE 12). Premio garantizado de los jefes: sustituye a la
## antigua carta de evolucion.
##
## Al recogerse evoluciona el arma elegible mas avanzada del jugador. La eleccion
## y todas las validaciones (nivel maximo, requisito de power-up, tope por
## partida) las hace WeaponManager.evolve_best_weapon(); aqui solo se dispara.
##
## El LootDirector NO suelta un nucleo si no hay ningun arma elegible: en ese caso
## el jefe suelta una mutacion, para que el premio nunca se desperdicie.

const CORE_COLOR := Color(0.85, 0.55, 1.0, 1.0)


func _ready() -> void:
	visual_color = CORE_COLOR
	visual_radius = 20.0
	icon_type = &"star"
	# Nunca caduca: es el premio de un jefe y el jugador debe poder ir a por el
	# aunque la pelea lo haya dejado al otro lado del mapa.
	lifetime = 0.0
	attract_multiplier = 2.2
	_setup_body(8, collect_radius)
	# Tarjeta de informacion (FASE 13): el nucleo se explica solo al acercarse.
	_set_card_rows([
		{"text": "Núcleo de evolución", "color": CORE_COLOR, "size": 14, "weight": 600},
		{"text": "Premio de jefe", "color": LootCatalog.rarity_color(&"legendary"), "size": 11},
		{"text": "\"Evoluciona automáticamente un arma compatible.\"",
			"color": Color(0.85, 0.87, 0.94), "size": 11},
		{"text": "Transforma tu mejor arma lista en su versión evolucionada",
			"color": Color(1.0, 0.93, 0.6), "size": 11},
	])
	_show_tip(&"core")
	Feedback.hit_effect(global_position, visual_color, 0.8, 3.0)


## Icono en el minimapa (FASE 13): el nucleo siempre se ve (premio de jefe).
func minimap_loot_kind() -> StringName:
	return &"loot_core"


func collect(player_node: Node) -> bool:
	if not claim():
		return false
	var wm: Node = null
	if player_node != null and player_node.has_method("get_weapon_manager"):
		wm = player_node.get_weapon_manager()

	# evolve_weapon ya trae su propio juice (hitstop + shake + toast de evolucion).
	var evolved: bool = wm != null and wm.evolve_best_weapon()
	if evolved:
		RunTelemetry.count(&"evolution_cores_used")
	else:
		# Salvaguarda: el director no deberia soltar un nucleo inservible, pero si
		# el estado cambio entre la suelta y la recogida (el arma evoluciono por
		# otra via), el nucleo no se traga sin dar nada.
		if player_node != null and player_node.has_method("apply_upgrade"):
			player_node.apply_upgrade(&"weapon_damage")
		var hud: Node = _hud()
		if hud != null and hud.has_method("show_loot_toast"):
			hud.show_loot_toast("NÚCLEO INESTABLE", "Sin arma lista para evolucionar",
				"+10 % de daño con todas las armas", CORE_COLOR,
				int(player_node.get("player_id")) if player_node != null else 1)

	_play_collect_feedback()
	return true


func _draw() -> void:
	super._draw()
	# Anillo giratorio: lo distingue de un power-up normal de un vistazo.
	var r: float = visual_radius * 1.7
	for i in 3:
		var from: float = _time * 1.4 + float(i) * TAU / 3.0
		draw_arc(Vector2.ZERO, r, from, from + 0.9, 12,
			Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.75), 2.5, true)
