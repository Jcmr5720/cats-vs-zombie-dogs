extends Area2D
## Base de los objetos recogibles del suelo (FASE 12). De aqui cuelgan el pickup
## de power-up y el de arma.
##
## Generaliza el contrato que ya usaba el orbe de XP:
## - Metodo `collect(player)` duck-typed, igual que xp_orb.collect().
## - Iman opcional hacia el jugador ACTIVO mas cercano, derivado del radio de
##   recoleccion del propio jugador (asi el power-up "pickup_range" tambien lo
##   agranda).
## - Rebote inicial con friccion al soltarse.
##
## El orbe de XP NO hereda de aqui a proposito: esta muy afinado (fusion al
## saturar, nudge del Gato Ingeniero) y lo tocan varios tests. Se comparte el
## patron, no el codigo.
##
## COOP: `claim()` es la guarda anti-doble-cobro. Los dos jugadores pueden entrar
## en el area el mismo frame; el primero que reclame se lo lleva y el segundo
## recibe false.
##
## Crear SIEMPRE via el spawn() de la subclase: construyen la colision y la forma.

## Tope de pickups vivos a la vez. Por encima se libera el mas antiguo sin
## reclamar, para que una racha de drops no acumule nodos (mismo problema que
## resolvia `max_xp_orbs` en el orbe de XP, aqui sin fusion: no son fungibles).
const MAX_PICKUPS: int = 24
const GROUP := &"pickups"
## Grupo de los pickups de ARMA. Aparte a proposito: el area de recoleccion del
## jugador barre "pickups" por contacto, y un arma nunca debe entrar asi.
const WEAPON_GROUP := &"weapon_pickups"

## Si es false el pickup nunca vuela hacia el jugador ni se auto-recoge: se queda
## quieto esperando (lo usan las armas, que exigen decision del jugador).
@export var magnet_enabled: bool = true
## Impulso inicial al soltarse (lo fija quien lo suelta).
@export var pop_velocity: Vector2 = Vector2.ZERO
## El iman se activa a este multiplo del radio de recoleccion del jugador. Mas
## corto que el del orbe de XP (2.8): un power-up no debe cruzar media pantalla.
@export var attract_multiplier: float = 1.6
@export var collect_radius: float = 26.0
@export var attract_accel: float = 900.0
@export var max_attract_speed: float = 620.0
@export var pop_friction: float = 6.0
## Segundos hasta desaparecer (0 = eterno). Parpadea los ultimos FADE_WARNING.
@export var lifetime: float = 0.0

const FADE_WARNING: float = 3.0
## FASE 13: distancia a la que aparece la tarjeta de informacion del pickup.
## Mayor que el iman corto de los power-ups para que el texto se lea ANTES de la
## auto-recogida por contacto.
const INFO_RADIUS: float = 170.0
## Radio del cuerpo dibujado. Las subclases lo ajustan.
var visual_radius: float = 13.0
var visual_color: Color = Color(0.55, 0.9, 1.0, 1.0)
var icon_type: StringName = &"upgrade"

## Tarjeta de informacion en el mundo (FASE 13): nombre, categoria, rareza,
## efecto... La construyen las subclases con _set_card_rows(); la base solo la
## muestra/oculta por proximidad y la mantiene centrada sobre el pickup.
var _card: PanelContainer
var _card_box: VBoxContainer

var _time: float = 0.0
var _age: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _player: Node2D
var _claimed: bool = false


## Grupo al que pertenece este pickup (GROUP o WEAPON_GROUP). Cada uno lleva su
## propio presupuesto de nodos.
var _group: StringName = GROUP


## Prepara colision y grupos. Las subclases lo llaman desde su _ready().
func _setup_body(layer: int = 8, radius: float = 26.0, group: StringName = GROUP) -> void:
	_group = group
	add_to_group(group)
	collision_layer = layer
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	_velocity = pop_velocity
	_player = _nearest_active_player()
	_enforce_budget()


## Libera el pickup mas antiguo sin reclamar si el grupo se pasa del tope.
## Se salta a si mismo: el drop recien creado es el mas interesante.
func _enforce_budget() -> void:
	var tree := get_tree()
	if tree == null or tree.get_node_count_in_group(_group) <= MAX_PICKUPS:
		return
	var oldest: Node = null
	var oldest_age: float = -1.0
	for p in tree.get_nodes_in_group(_group):
		if p == self or not is_instance_valid(p):
			continue
		# Por la API publica, no leyendo estado privado: un nodo del grupo que aun
		# no corrio su _ready no tiene `_claimed` y `get()` devolveria null.
		if not p.has_method("is_claimed") or p.is_claimed():
			continue
		var age: float = float(p.get("_age"))
		if age > oldest_age:
			oldest_age = age
			oldest = p
	if oldest != null:
		oldest.queue_free()


## Reclama el pickup en exclusiva. Devuelve false si ya lo reclamo alguien: es la
## guarda que impide que los dos jugadores de coop cobren el mismo objeto.
func claim() -> bool:
	if _claimed:
		return false
	_claimed = true
	return true


func is_claimed() -> bool:
	return _claimed


func _process(delta: float) -> void:
	if _claimed:
		return

	_time += delta
	_age += delta
	queue_redraw()

	if lifetime > 0.0 and _age >= lifetime:
		queue_free()
		return

	# Coop: el iman apunta al jugador ACTIVO mas cercano, no siempre al P1.
	_player = _nearest_active_player()
	_update_card_visibility()

	if magnet_enabled and is_instance_valid(_player):
		var to_player: Vector2 = _player.global_position - global_position
		var distance: float = to_player.length()
		var attract_radius: float = _player_pickup_radius() * attract_multiplier

		if distance <= collect_radius:
			collect(_player)
			return

		if distance < attract_radius:
			var pull: float = attract_accel * (1.0 + (1.0 - distance / attract_radius) * 2.0)
			_velocity = _velocity.move_toward(to_player.normalized() * max_attract_speed, pull * delta)
		else:
			_velocity *= exp(-pop_friction * delta)
	else:
		_velocity *= exp(-pop_friction * delta)

	global_position += _velocity * delta


## Jugador activo (ni muerto ni derribado) mas cercano. Misma resolucion que el
## orbe de XP: en solo devuelve al unico jugador y, si nadie esta activo, cae al
## grupo clasico "player".
func _nearest_active_player() -> Node2D:
	var best: Node2D = null
	var best_sq: float = INF
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		if p.has_method("is_active") and not p.is_active():
			continue
		var d: float = global_position.distance_squared_to((p as Node2D).global_position)
		if d < best_sq:
			best_sq = d
			best = p
	if best == null:
		best = get_tree().get_first_node_in_group("player") as Node2D
	return best


func _player_pickup_radius() -> float:
	if is_instance_valid(_player) and _player.has_method("get_pickup_radius"):
		return _player.get_pickup_radius()
	return 90.0


## Contrato de recoleccion. Lo sobrescriben las subclases. Devuelve true si el
## pickup se consumio.
func collect(_player_node: Node) -> bool:
	return false


## Animacion comun de recoleccion: crece, se apaga y se libera. Identica a la del
## orbe de XP para que todo el loot "sepa" igual.
func _play_collect_feedback() -> void:
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.12)
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	tween.chain().tween_callback(queue_free)


func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")


# --- Tarjeta de informacion (FASE 13) -----------------------------------------

## Rellena (o reconstruye) la tarjeta con filas [{text, color, size, weight}].
## Construccion perezosa: si nunca se llama, el pickup no paga ningun nodo extra.
func _set_card_rows(rows: Array) -> void:
	if rows.is_empty():
		if _card != null:
			_card.visible = false
		return
	if _card == null:
		_card = PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.05, 0.06, 0.1, 0.92)
		box.border_color = Color(visual_color.r, visual_color.g, visual_color.b, 0.9)
		box.set_border_width_all(1)
		box.border_width_left = 4
		box.set_corner_radius_all(8)
		box.set_content_margin_all(8)
		box.content_margin_left = 11.0
		box.content_margin_right = 11.0
		_card.add_theme_stylebox_override("panel", box)
		_card.visible = false
		_card.z_index = 60
		_card_box = VBoxContainer.new()
		_card_box.add_theme_constant_override("separation", 1)
		_card.add_child(_card_box)
		add_child(_card)
	for child in _card_box.get_children():
		child.queue_free()
	for row in rows:
		_card_box.add_child(_make_card_label(row))


func _make_card_label(row: Dictionary) -> Label:
	var label := Label.new()
	label.text = str(row.get("text", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UIFonts.fredoka(int(row.get("weight", 500))))
	label.add_theme_font_size_override("font_size", int(row.get("size", 12)))
	label.add_theme_color_override("font_color", row.get("color", Color(0.94, 0.95, 1.0)))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


## Muestra la tarjeta cuando el jugador activo mas cercano esta a rango, centrada
## sobre el pickup (el tamano del PanelContainer se conoce tras el layout, por
## eso se recoloca aqui y no al construir).
func _update_card_visibility() -> void:
	if _card == null:
		return
	var near: bool = is_instance_valid(_player) \
		and global_position.distance_to(_player.global_position) <= INFO_RADIUS
	if near != _card.visible:
		_card.visible = near
	if near:
		_card.position = Vector2(-_card.size.x * 0.5, -visual_radius - 16.0 - _card.size.y)


## Etiqueta de quien tiene el pickup a rango en coop ("J1 · "), vacia en solo.
## Deja claro QUIEN puede recogerlo sin depender del color.
func _actor_prefix(actor: Node) -> String:
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf == null or not gf.has_method("is_coop") or not gf.is_coop():
		return ""
	return "%s · " % CoopConfig.player_tag(int(actor.get("player_id")))


## Consejo de tutorial contextual (FASE 13): lo muestra el HUD una sola vez por
## perfil. Seguro de llamar siempre; el HUD decide si toca.
func _show_tip(tip_id: StringName) -> void:
	var hud: Node = _hud()
	if hud != null and hud.has_method("show_tip"):
		hud.show_tip(tip_id)


func _draw() -> void:
	# Parpadeo de aviso cuando le queda poco: el jugador debe poder decidir si
	# merece la pena ir a por el.
	var alpha: float = 1.0
	if lifetime > 0.0 and _age > lifetime - FADE_WARNING:
		alpha = 0.35 + 0.65 * absf(sin(_time * 9.0))
	var pulse: float = 1.0 + sin(_time * 3.6) * 0.1
	var r: float = visual_radius * pulse
	var glow := visual_color
	glow.a = 0.22 * alpha
	draw_circle(Vector2.ZERO, r * 1.8, glow)
	var body := visual_color
	body.a = alpha
	draw_circle(Vector2.ZERO, r, body)
	draw_circle(Vector2.ZERO, r * 0.45, Color(1, 1, 1, 0.85 * alpha))
