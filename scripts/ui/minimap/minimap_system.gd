extends Node
## MinimapSystem (Sistema Minimapa): orquestador que el HUD monta en _ready.
## Crea el MinimapEntityRegistry compartido y los MinimapController:
## - Solo / Historia: un minimapa en la esquina superior derecha.
## - Coop local (pantalla dividida): un minimapa POR MITAD, cada uno siguiendo a
##   su jugador y con el borde del color de identidad de esa mitad. El companero
##   aparece siempre (flecha de borde) aunque este muy lejos.
##
## Ampliacion temporal: la accion "minimap_expand" (TAB / boton Select del mando)
## alterna el tamano y el alcance del radar de TODOS los minimapas a la vez.
## No detecta escenas concretas: vive dentro del HUD (solo existe en MainLevel)
## y cada controller se oculta solo en pausa/cartas/fin de partida.

const REGISTRY_SCRIPT := preload("res://scripts/ui/minimap/minimap_entity_registry.gd")
const CONTROLLER_SCRIPT := preload("res://scripts/ui/minimap/minimap_controller.gd")
const TERRAIN_SOURCE_SCRIPT := preload("res://scripts/ui/minimap/minimap_terrain_source.gd")

var _registry: Node
## Fuente de terreno COMPARTIDA (una sola cache de layouts para ambos radares).
var _terrain_source: RefCounted
var _controllers: Array = []
var _hud: Node
var _coop_layout: bool = false
var _expanded: bool = false
var _check_timer: float = 0.0


func _ready() -> void:
	_hud = get_parent()
	_registry = REGISTRY_SCRIPT.new()
	_registry.name = "MinimapEntityRegistry"
	add_child(_registry)
	_terrain_source = TERRAIN_SOURCE_SCRIPT.new()
	# Minimapa del J1 (layout solo: borde derecho de la pantalla).
	var c1: Control = _make_controller(1, _is_coop())
	c1.configure_layout(1.0, -16.0)
	_controllers.append(c1)


func _make_controller(player_id: int, coop: bool) -> Control:
	var c: Control = CONTROLLER_SCRIPT.new()
	c.name = "Minimap%d" % player_id
	c.registry = _registry
	c.player_id = player_id
	c.coop = coop
	c.hud = _hud
	c.terrain_source = _terrain_source
	_hud.add_child(c)
	return c


func _process(delta: float) -> void:
	if _coop_layout:
		return
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.5
	if not _is_coop():
		return
	# El P2 se instancia diferido (PlayerManager): cuando aparece, se pasa al
	# layout de dos minimapas (uno por mitad de la pantalla dividida).
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and int(p.get("player_id")) >= 2:
			_activate_coop_layout()
			return


func _activate_coop_layout() -> void:
	_coop_layout = true
	# Esquinas EXTERIORES (espejo): J1 arriba-izquierda de su mitad, J2 arriba-
	# derecha de la suya. El centro queda libre para el reloj y los mensajes del
	# HUD, y cada minimapa queda bajo la cabecera coop de su jugador.
	var c1: Control = _controllers[0]
	c1.configure_layout(0.0, 16.0, false)
	# Mitad derecha (J2): borde derecho de la pantalla.
	var c2: Control = _make_controller(2, true)
	c2.configure_layout(1.0, -16.0, true)
	c2.set_expanded(_expanded)
	_controllers.append(c2)
	if _registry.has_method("refresh_now"):
		_registry.refresh_now(&"players")


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action("minimap_expand"):
		return
	if event.is_action_pressed("minimap_expand"):
		_expanded = not _expanded
		for c in _controllers:
			if is_instance_valid(c):
				c.set_expanded(_expanded)


func _is_coop() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_coop") and gf.is_coop()
