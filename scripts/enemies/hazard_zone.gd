extends Node2D
## Zona peligrosa temporal generalizada (FASE 11). Nacio como el charco del
## Portador de Infeccion; ahora es el sistema COMPARTIDO de areas de peligro:
## infeccion del Parque, vapor/tren del Callejon Industrial, etc. La lectura
## visual cambia por `kind` (color/patron) y la faccion decide a quien dana:
##   faction = &"players"  -> solo jugadores (charco clasico; por defecto)
##   faction = &"enemies"  -> solo enemigos
##   faction = &"both"     -> ambos bandos (peligros industriales)
## `arm_delay` telegrafia la zona: parpadea sin danar hasta armarse (tren/vapor).
##
## Crear zonas SIEMPRE via try_spawn(): aplica el presupuesto por tipo
## (RunPhaseConfig.zone_budget) y FUSIONA zonas superpuestas del mismo tipo en
## vez de acumular nodos (mismo espiritu que la fusion de orbes de XP).

const GROUP := &"hazard_zones"
## Tope duro de radio al fusionar zonas (legibilidad + coste del tick).
const MERGE_RADIUS_CAP: float = 150.0

var radius: float = 70.0
var damage_per_tick: int = 4
var duration: float = 3.0
var color: Color = Color(0.55, 0.9, 0.3, 1.0)
## Tipo de zona: presupuesto propio y lectura visual propia.
var kind: StringName = &"infection"
## A quien dana: &"players" / &"enemies" / &"both".
var faction: StringName = &"players"
## Telegrafo: segundos sin danar (parpadeo de aviso) antes de armarse.
var arm_delay: float = 0.0

var _time: float = 0.0
var _tick_timer: float = 0.35  # pequeño margen: no dana el mismo frame de nacer

## Zonas creadas pero aun no dentro del arbol (add_child va diferido): sin este
## registro, una rafaga de muertes en el MISMO frame crearia N zonas superpuestas
## saltandose presupuesto y fusion.
static var _pending: Array = []


## Crea una zona respetando el presupuesto por tipo. Si ya hay una zona del mismo
## tipo superpuesta (viva o pendiente de entrar al arbol), la ABSORBE (extiende
## radio/duracion con tope) en vez de crear otro nodo. Devuelve la zona viva
## (nueva o absorbida) o null si el presupuesto del tipo esta lleno.
static func try_spawn(parent: Node, pos: Vector2, config: Dictionary = {}) -> Node2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var zone_kind: StringName = config.get("kind", &"infection")
	var zone_radius: float = float(config.get("radius", 70.0))
	var tree := parent.get_tree()

	# Candidatas: zonas vivas del grupo + pendientes (creadas este frame).
	for i in range(_pending.size() - 1, -1, -1):
		var pending_zone = _pending[i]
		if not is_instance_valid(pending_zone) or pending_zone.is_inside_tree():
			_pending.remove_at(i)
	var candidates: Array = []
	for z in tree.get_nodes_in_group(GROUP):
		if is_instance_valid(z) and z is Node2D:
			candidates.append(z)
	candidates.append_array(_pending)

	var alive_of_kind: int = 0
	for z in candidates:
		if z.get("kind") != zone_kind:
			continue
		alive_of_kind += 1
		var other_radius: float = float(z.get("radius"))
		var other_pos: Vector2 = (z as Node2D).global_position if (z as Node2D).is_inside_tree() else (z as Node2D).position
		if pos.distance_to(other_pos) < (zone_radius + other_radius) * 0.7:
			z.set("radius", minf(MERGE_RADIUS_CAP, maxf(other_radius, zone_radius) * 1.12))
			z.set("duration", maxf(float(z.get("duration")), float(config.get("duration", 3.0))))
			RunTelemetry.count(&"zones_merged")
			return z

	if alive_of_kind >= RunPhaseConfig.zone_budget(zone_kind):
		RunTelemetry.count(&"zones_denied_by_budget")
		return null

	var zone := Node2D.new()
	zone.set_script(load("res://scripts/enemies/hazard_zone.gd"))
	zone.position = pos
	for key in config:
		zone.set(key, config[key])
	_pending.append(zone)
	parent.add_child.call_deferred(zone)
	RunTelemetry.count(&"zones_created")
	RunTelemetry.count(StringName("zones_created_%s" % zone_kind))
	return zone


func _ready() -> void:
	add_to_group(GROUP)
	z_index = -1
	_apply_kind_visuals()


## Paleta por tipo (si el creador no fijo un color propio).
func _apply_kind_visuals() -> void:
	if kind == &"industrial" and color.is_equal_approx(Color(0.55, 0.9, 0.3, 1.0)):
		color = Color(1.0, 0.62, 0.2, 1.0)


func _process(delta: float) -> void:
	_time += delta
	if arm_delay > 0.0:
		# Telegrafo: parpadea sin danar. La duracion NO corre hasta armarse.
		arm_delay -= delta
		queue_redraw()
		return
	duration -= delta
	if duration <= 0.0:
		queue_free()
		return
	queue_redraw()
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = 0.5
	if faction != &"enemies":
		_damage_players()
	if faction != &"players":
		_damage_enemies()


func _damage_players() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if p.has_method("is_active") and not p.is_active():
			continue
		if global_position.distance_to((p as Node2D).global_position) <= radius:
			if p.has_method("take_damage"):
				p.take_damage(damage_per_tick)
			# El tick es de 0.5 s: cada golpe equivale a medio segundo dentro.
			RunTelemetry.add_time(&"player_time_in_hazard", 0.5)


## Dana enemigos dentro (peligros industriales: el jugador habil los usa a favor).
## Los interactables de mapa (marcas, nidos) no se ven afectados.
func _damage_enemies() -> void:
	var hits: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.is_in_group("map_interactables"):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= radius:
			if e.has_method("take_damage"):
				e.take_damage(damage_per_tick * 3)
				RunTelemetry.count(&"environmental_damage_to_enemies", damage_per_tick * 3)
				hits += 1
				if hits >= 12:
					break


## La consume un jefe (Mastin del Pantano): reduce duracion/radio a cambio de
## curacion. Devuelve cuanto "material" quedaba (0..1) antes de consumir.
func consume(amount: float) -> float:
	var before: float = clampf(duration / 3.0, 0.0, 1.0)
	duration -= amount
	radius = maxf(24.0, radius - amount * 6.0)
	return before


func _draw() -> void:
	# Telegrafo: anillo intermitente sin relleno (aviso claro, aun sin daño).
	if arm_delay > 0.0:
		var blink: float = 0.25 + 0.5 * absf(sin(_time * 10.0))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40,
			Color(color.r, color.g, color.b, blink), 4.0, true)
		return
	# Se desvanece al final para avisar de que va a desaparecer.
	var fade: float = clampf(duration / 0.6, 0.0, 1.0)
	var pulse: float = 0.85 + sin(_time * 6.0) * 0.15
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.16 * fade))
	draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 40,
		Color(color.r, color.g, color.b, 0.55 * fade), 3.0, true)
	if kind == &"industrial":
		# Lenguaje industrial: aspas de peligro en vez de burbujas organicas.
		for i in 4:
			var a: float = float(i) * TAU / 4.0 + _time * 1.2
			var dir := Vector2(cos(a), sin(a))
			draw_line(dir * radius * 0.25, dir * radius * 0.8,
				Color(color.r, color.g, color.b, 0.35 * fade), 3.0, true)
		return
	# Burbujas interiores simples (arte provisional pero legible).
	for i in 5:
		var a: float = float(i) * TAU / 5.0 + _time * 0.8
		var d: float = radius * (0.25 + 0.35 * float(i % 3) / 2.0)
		draw_circle(Vector2(cos(a), sin(a)) * d, 4.0, Color(color.r, color.g, color.b, 0.30 * fade))
