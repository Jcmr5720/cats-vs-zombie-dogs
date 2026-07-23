extends StaticBody2D
## Interactable de mapa destruible (FASE 11). Base COMPARTIDA de las mecanicas
## exclusivas: marcas de aullido del Barrio, nidos del Corazon del Parque y
## lineas de produccion de La Fabrica. El `role` decide el efecto pasivo por
## tick y la lectura visual; el resto (vida, dano, muerte, grupos) es comun.
##
## Vive en el grupo "enemies" para que TODAS las armas y compañeros puedan
## dañarlo sin tocar el targeting, y en "map_interactables" para que los
## sistemas que no deben tratarlo como perro lo excluyan (limpieza de emergencia
## del spawner, zonas de daño a enemigos). No bloquea el movimiento: esta en la
## capa 2 (balas) y sin mascara.
##
## Crear SIEMPRE via spawn(): construye colision y registra grupos.

const GROUP := &"map_interactables"
## Grupo propio de las marcas de aullido: las consultas de territorio no deben
## barrer nidos ni lineas de produccion.
const HOWL_GROUP := &"howl_posts"
const XP_ORB_SCENE := "res://scenes/loot/XPOrb.tscn"
const HAZARD_ZONE := preload("res://scripts/enemies/hazard_zone.gd")

## Presupuesto de marcas simultaneas del Barrio. Con mas de 3 el mapa deja de
## tener espacio neutral y la lectura territorial se pierde.
const MAX_HOWL_POSTS: int = 3
## Por debajo de esta fraccion de vida la marca esta DEBILITADA: su territorio
## sigue existiendo pero coordina a la mitad. Da lectura de progreso al jugador
## antes de destruirla del todo.
const WEAKENED_AT: float = 0.4
## Fuerza del territorio de una marca debilitada.
const WEAKENED_STRENGTH: float = 0.5

## Marcas creadas pero aun no dentro del arbol (add_child va diferido). Sin este
## registro, una rafaga del mismo frame se saltaria el presupuesto.
static var _pending_posts: Array = []


## Limpia el registro de pendientes. Lo llama el arranque de partida: las static
## vars sobreviven al cambio de escena.
static func reset_pending() -> void:
	_pending_posts.clear()

## Rol del interactable (efecto por tick + visual):
##   &"howl_post"          marca de aullido: acelera enemigos cercanos (Barrio)
##   &"nest_spawner"       nido que genera perros junto a el (Corazon)
##   &"nest_healer"        nido que cura enemigos cercanos (Corazon)
##   &"nest_contaminator"  nido que contamina el terreno (Corazon)
##   &"production_runners" linea que fabrica corredores (Fabrica)
##   &"production_armor"   linea que blinda un enemigo vivo (Fabrica)
##   &"production_repair"  linea que repara al jefe (Fabrica)
var role: StringName = &"howl_post"
var max_health: int = 90
var current_health: int = 90
## Radio del efecto pasivo (aura de la marca / curacion del nido).
var effect_radius: float = 300.0
var xp_reward: int = 8

var _time: float = 0.0
var _tick_timer: float = 1.0
var _flash: float = 0.0
## Momento de nacimiento (telemetria: vida media de las marcas).
var _born_at: float = 0.0
## FASE 13 (solo cajas): icono flotante + prompt de proximidad.
var _crate_icon: Control
var _crate_prompt: Label
const CRATE_PROMPT_RADIUS: float = 170.0


## Fabrica del interactable segun su tipo. `kind` admite tanto roles concretos
## como familias (&"nest" y &"production_line" sortean un rol de la familia).
##
## `rng` hace el sorteo DETERMINISTA: la distribucion de interactables forma
## parte del guion de la semilla (misma semilla = mismos roles en el mismo
## orden). Sin rng se cae al azar global, solo para llamadas sueltas de debug.
static func spawn(kind: StringName, parent: Node, pos: Vector2,
		rng: RandomNumberGenerator = null) -> Node2D:
	if parent == null or not parent.is_inside_tree():
		return null
	# Presupuesto de marcas: por encima del tope no se planta otra. Devuelve null
	# y el llamador (director o jefe) decide si reintenta mas tarde.
	#
	# Cuenta las marcas VIVAS mas las PENDIENTES de entrar al arbol: `add_child`
	# es diferido, asi que dos plantados en el mismo frame (director + jefe, o el
	# jefe en dos umbrales seguidos) veian ambos el grupo vacio y se saltaban el
	# tope. Mismo registro estatico que usa `hazard_zone.try_spawn`.
	if kind == &"howl_post":
		for i in range(_pending_posts.size() - 1, -1, -1):
			var pending = _pending_posts[i]
			if not is_instance_valid(pending) or pending.is_inside_tree():
				_pending_posts.remove_at(i)
		var total: int = parent.get_tree().get_node_count_in_group(HOWL_GROUP) + _pending_posts.size()
		if total >= MAX_HOWL_POSTS:
			RunTelemetry.count(&"howl_posts_denied_by_budget")
			return null
	var resolved: StringName = kind
	match kind:
		&"nest":
			resolved = _pick_role([&"nest_spawner", &"nest_healer", &"nest_contaminator"], rng)
		&"production_line":
			resolved = _pick_role([&"production_runners", &"production_armor", &"production_repair"], rng)
	var node := StaticBody2D.new()
	node.set_script(load("res://scripts/maps/map_interactable.gd"))
	node.set("role", resolved)
	match resolved:
		&"howl_post":
			node.set("max_health", 90)
			# XP SIMBOLICA. La recompensa de romper una marca es liberar el
			# territorio y el pulso de empuje, no experiencia. Con 4-6 marcas
			# destruidas por partida (el Alfa planta las suyas), una XP normal
			# financiaba cartas extra y volteaba el soak "flow" —jugador
			# estatico, debe terminar en DERROTA— a victoria de vez en cuando.
			node.set("xp_reward", 2)
		&"nest_spawner", &"nest_healer", &"nest_contaminator":
			node.set("max_health", 160)
			node.set("xp_reward", 14)
		&"production_runners", &"production_armor", &"production_repair":
			node.set("max_health", 220)
			node.set("xp_reward", 20)
		&"weapon_crate":
			# Caja de armas (FASE 12). Vida moderada: romperla es un compromiso
			# real de DPS con la horda encima, pero no una pared.
			node.set("max_health", 120)
			# XP DELIBERADAMENTE BAJA. La recompensa de una caja es el arma que
			# suelta, no experiencia; una XP normal aqui financiaria niveles extra
			# y volteria el soak (mismo motivo que la marca de aullido).
			node.set("xp_reward", 6)
		&"supply_crate":
			node.set("max_health", 70)
			node.set("xp_reward", 4)
		&"special_crate":
			# Caja especial (FASE 13): mejora rara o mutacion. El rol esta cableado
			# (visual, botin, minimapa) pero NINGUN horario la planta todavia: se
			# activara cuando el balance lo pida, sin tocar las probabilidades hoy.
			node.set("max_health", 100)
			node.set("xp_reward", 4)
	node.set("current_health", node.get("max_health"))
	node.position = pos
	if resolved == &"howl_post":
		_pending_posts.append(node)
	parent.add_child.call_deferred(node)
	return node


## Territorio que cubre `pos`, o {} si el punto es terreno neutral.
##
## REGLA DE COMBINACION: cuando varias marcas se superponen NO se suman. Gana la
## de MAYOR fuerza (y a igualdad, la mas cercana). Sumar territorios convertiria
## tres marcas juntas en una zona intocable y premiaria al juego por ignorarlas;
## con prioridad, plantar marcas encima no da nada y el jugador siempre sabe que
## una sola destruccion cambia algo.
##
## Devuelve {strength: float (0..1], center: Vector2, radius: float, post: Node}.
static func territory_at(tree: SceneTree, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_key: float = -1.0
	for post in tree.get_nodes_in_group(HOWL_GROUP):
		if not is_instance_valid(post) or not (post is Node2D):
			continue
		var center: Vector2 = (post as Node2D).global_position
		var radius: float = float(post.get("effect_radius"))
		var distance: float = pos.distance_to(center)
		if distance > radius:
			continue
		var strength: float = post.territory_strength()
		# Desempate por cercania sin que pese mas que la fuerza.
		var key: float = strength * 10.0 + (1.0 - distance / maxf(1.0, radius))
		if key > best_key:
			best_key = key
			best = {"strength": strength, "center": center, "radius": radius, "post": post}
	return best


## Fuerza del territorio de ESTA marca: 1.0 activa, 0.5 debilitada.
func territory_strength() -> float:
	if current_health <= 0:
		return 0.0
	var ratio: float = float(current_health) / float(maxi(1, max_health))
	return WEAKENED_STRENGTH if ratio <= WEAKENED_AT else 1.0


## Estado legible de la marca (lectura visual y tests): activa / debilitada.
func is_weakened() -> bool:
	return territory_strength() < 1.0


static func _pick_role(roles: Array, rng: RandomNumberGenerator) -> StringName:
	if rng == null:
		return roles.pick_random()
	return roles[rng.randi() % roles.size()]


func _ready() -> void:
	add_to_group("enemies")
	add_to_group(GROUP)
	if role == &"howl_post":
		add_to_group(HOWL_GROUP)
		RunTelemetry.count(&"howl_posts_created")
		_born_at = float(Time.get_ticks_msec()) / 1000.0
	# Capa 2 = misma de los enemigos: las balas y areas de arma lo detectan.
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 26.0
	shape.shape = circle
	add_child(shape)
	current_health = max_health
	z_index = -1
	if LootCatalog.is_crate_role(role):
		_build_crate_extras()
	# Aparicion anunciada: el jugador debe saber que nacio una amenaza de mapa.
	Feedback.hit_effect(global_position, _accent_color(), 0.7, 3.0)


## Icono flotante + prompt de proximidad de las cajas (FASE 13): la caja debe
## reconocerse sin leer y explicarse al acercarse. Un IconDrawer (forma, no solo
## color) y un Label que aparece a CRATE_PROMPT_RADIUS del jugador.
func _build_crate_extras() -> void:
	var icon := IconDrawer.new()
	icon.custom_minimum_size = Vector2(26, 26)
	icon.size = Vector2(26, 26)
	icon.icon_type = LootCatalog.crate_icon(role)
	icon.accent = LootCatalog.crate_color(role).lightened(0.15)
	icon.position = Vector2(-13, -66)
	add_child(icon)
	_crate_icon = icon

	_crate_prompt = Label.new()
	_crate_prompt.text = LootCatalog.crate_prompt(role)
	_crate_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crate_prompt.custom_minimum_size = Vector2(280, 0)
	_crate_prompt.position = Vector2(-140, -96)
	_crate_prompt.add_theme_font_override("font", UIFonts.fredoka(600))
	_crate_prompt.add_theme_font_size_override("font_size", 13)
	_crate_prompt.add_theme_color_override("font_color", LootCatalog.crate_color(role).lightened(0.2))
	_crate_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_crate_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_crate_prompt.visible = false
	add_child(_crate_prompt)

	# Tutorial (FASE 13): primera caja de la partida, una vez por perfil.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_tip"):
		hud.show_tip(&"crate")


func _process(delta: float) -> void:
	_time += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
	queue_redraw()
	# FASE 13: el icono de la caja flota y el prompt aparece al acercarse.
	if _crate_icon != null:
		_crate_icon.position.y = -66.0 + sin(_time * 2.4) * 4.0
		if _crate_prompt != null:
			_crate_prompt.visible = _any_player_within(CRATE_PROMPT_RADIUS)
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = _tick_interval()
	_apply_role_effect()


func _any_player_within(radius: float) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and p is Node2D \
				and global_position.distance_to((p as Node2D).global_position) <= radius:
			return true
	return false


func _tick_interval() -> float:
	match role:
		&"howl_post":
			return 1.0
		&"nest_spawner":
			return 6.0
		&"nest_healer":
			return 1.0
		&"nest_contaminator":
			return 8.0
		&"production_runners", &"production_armor", &"production_repair":
			return 20.0
		&"weapon_crate", &"supply_crate", &"special_crate":
			# Las cajas son INERTES: no amenazan, solo esperan a que las rompan.
			# Un tick largo evita gastar el bucle de roles en nada.
			return 999.0
	return 2.0


func _apply_role_effect() -> void:
	match role:
		&"howl_post":
			# Territorio de manada. NO es un multiplicador de estadisticas: marca
			# a los perros COMPATIBLES del Barrio como "en territorio", y son
			# ellos quienes coordinan mejor (se agrupan antes, esperan a los
			# rezagados, reparten aproximaciones y preparan la carga antes).
			# El unico efecto numerico es un empujon de velocidad pequeño y con
			# tope, por el canal del Aullador, para que el territorio se NOTE.
			var strength: float = territory_strength()
			# Telemetria: cuanto tiempo pasa el jugador DENTRO de territorio
			# enemigo (el tick es de 1 s, asi que cada pasada vale 1 s).
			if RunTelemetry.enabled:
				for p in get_tree().get_nodes_in_group("players"):
					if is_instance_valid(p) and p is Node2D \
							and global_position.distance_to((p as Node2D).global_position) <= effect_radius:
						RunTelemetry.add_time(&"player_time_in_territory", 1.0)
			var touched: int = 0
			for e in get_tree().get_nodes_in_group("pack_dogs"):
				if not is_instance_valid(e) or not (e is Node2D):
					continue
				if global_position.distance_to((e as Node2D).global_position) > effect_radius:
					continue
				if e.has_method("enter_territory"):
					e.enter_territory(strength, global_position, effect_radius)
					touched += 1
					if touched >= 14:
						break
			# Los flanqueadores del territorio tambien saben que estan en casa:
			# cierran rutas con mas decision dentro de el.
			var flankers: int = 0
			for e in get_tree().get_nodes_in_group("flankers"):
				if not is_instance_valid(e) or not (e is Node2D):
					continue
				if global_position.distance_to((e as Node2D).global_position) > effect_radius:
					continue
				if e.has_method("enter_territory"):
					e.enter_territory(strength, global_position, effect_radius)
					flankers += 1
					if flankers >= 8:
						break
		&"nest_spawner":
			# Genera perros JUNTO al nido (bajo el tope global de enemigos).
			if get_tree().get_node_count_in_group("enemies") >= 150:
				return
			var data = RunPhaseConfig.load_enemy_data(&"zombie_dog")
			var scene := load("res://scenes/enemies/Enemy.tscn") as PackedScene
			if data == null or scene == null:
				return
			for i in 2:
				var dog := scene.instantiate() as Node2D
				if dog == null:
					continue
				if dog.has_method("configure"):
					dog.call("configure", data, 1.0, 1.0, 1.0)
				dog.position = global_position + Vector2.RIGHT.rotated(randf() * TAU) * 60.0
				get_parent().add_child.call_deferred(dog)
			Feedback.hit_effect(global_position, _accent_color(), 0.4, 1.6)
		&"nest_healer":
			var healed: int = 0
			for e in get_tree().get_nodes_in_group("enemies"):
				if e == self or not is_instance_valid(e) or e.is_in_group(GROUP):
					continue
				# El jefe tambien vive en "enemies": curarlo aqui seria una
				# regeneracion silenciosa que nada telegrafia. Los nidos
				# sostienen a la horda; el jefe tiene sus propias reglas.
				if e.is_in_group("boss"):
					continue
				if not (e is Node2D) or global_position.distance_to((e as Node2D).global_position) > effect_radius:
					continue
				var cur = e.get("current_health")
				var max_h = e.get("max_health")
				if cur != null and max_h != null and int(cur) < int(max_h):
					e.set("current_health", mini(int(max_h), int(cur) + 3))
					healed += 1
					if healed >= 8:
						break
		&"nest_contaminator":
			HAZARD_ZONE.try_spawn(get_parent(), global_position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(80.0, 220.0),
				{"kind": &"infection", "radius": 60.0, "duration": 7.0, "damage_per_tick": 4})
		&"production_runners":
			var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
			if is_instance_valid(spawner) and spawner.has_method("spawn_pack"):
				spawner.spawn_pack(&"runner_zombie_dog", 3)
			Feedback.hit_effect(global_position, _accent_color(), 0.5, 2.0)
		&"production_armor":
			# Blinda un enemigo comun vivo al azar (mutacion de chatarra).
			var candidates: Array = []
			for e in get_tree().get_nodes_in_group("enemies"):
				if e == self or not is_instance_valid(e) or e.is_in_group(GROUP):
					continue
				if e.has_method("make_elite") and e.get("_elite_kind") == &"":
					candidates.append(e)
					if candidates.size() >= 12:
						break
			if not candidates.is_empty():
				candidates.pick_random().call("make_elite", &"chatarra")
		&"production_repair":
			var boss: Node = get_tree().get_first_node_in_group("boss")
			if is_instance_valid(boss) and boss.has_method("receive_minion_heal"):
				var max_h = boss.get("max_health")
				if max_h != null:
					boss.receive_minion_heal(int(round(float(max_h) * 0.03)))


func take_damage(amount: int, _knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if current_health <= 0:
		return
	current_health -= amount
	_flash = 1.0
	Feedback.damage_number(global_position + Vector2(0, -22), amount)
	if current_health <= 0:
		_die()


func _die() -> void:
	# Recompensa inmediata: pulso que EMPUJA a los enemigos cercanos + XP.
	RunTelemetry.count(&"interactables_destroyed")
	RunTelemetry.count(StringName("destroyed_%s" % role))
	if role == &"howl_post":
		RunTelemetry.count(&"howl_posts_destroyed")
		RunTelemetry.add_time(&"howl_post_total_lifetime",
			float(Time.get_ticks_msec()) / 1000.0 - _born_at)
		remove_from_group(HOWL_GROUP)
	remove_from_group("enemies")
	set_deferred("collision_layer", 0)
	var pushed: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node2D) or e.is_in_group(GROUP):
			continue
		var offset: Vector2 = (e as Node2D).global_position - global_position
		if offset.length() <= 260.0 and e.has_method("apply_push"):
			e.apply_push(offset.normalized() * 240.0)
			pushed += 1
			if pushed >= 10:
				break
	Feedback.hit_effect(global_position, _accent_color(), 0.9, 3.6)
	Feedback.shake(0.2)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		# FASE 13: abrir una caja suena a caja, no a perro muriendo.
		audio.play_sfx(&"crate_open" if LootCatalog.is_crate_role(role) else &"enemy_die")
	var orb_scene := load(XP_ORB_SCENE) as PackedScene
	if orb_scene != null:
		var orb := orb_scene.instantiate() as Node2D
		if orb != null:
			orb.set("xp_value", xp_reward)
			orb.position = global_position
			get_parent().add_child.call_deferred(orb)
	_drop_loot()
	queue_free()


## Botin de las cajas (FASE 12). Quien decide QUE sale es el LootDirector: aqui
## solo se pide. Los demas roles no sueltan nada y salen por la guarda de arriba.
func _drop_loot() -> void:
	if not LootCatalog.is_crate_role(role):
		return
	var director: Node = get_tree().get_first_node_in_group("loot_director")
	if not is_instance_valid(director):
		return
	match role:
		&"weapon_crate":
			director.call("drop_weapon", get_parent(), global_position)
		&"special_crate":
			# Caja especial (FASE 13): mutacion si queda alguna; si no, mejora.
			if director.call("drop_mutation", get_parent(), global_position) == null:
				director.call("drop_powerup", get_parent(), global_position, &"crate")
		_:
			director.call("drop_powerup", get_parent(), global_position, &"crate")


## Icono que representa esta entidad en el minimapa (FASE 13). "" = sin icono.
func minimap_loot_kind() -> StringName:
	match role:
		&"weapon_crate":
			return &"crate_weapon"
		&"supply_crate":
			return &"crate_supply"
		&"special_crate":
			return &"crate_special"
	return &""


func _accent_color() -> Color:
	match role:
		&"howl_post":
			return Color(1.0, 0.72, 0.2)
		&"nest_spawner", &"nest_healer", &"nest_contaminator":
			return Color(0.55, 0.9, 0.35)
		&"weapon_crate", &"supply_crate", &"special_crate":
			# Las cajas se leen como PREMIO, no como amenaza. Color e icono
			# centralizados en el catalogo (FASE 13): minimapa y HUD usan el mismo.
			return LootCatalog.crate_color(role)
	return Color(1.0, 0.45, 0.2)


func _draw() -> void:
	var accent: Color = _accent_color()
	var pulse: float = 0.85 + sin(_time * 3.0) * 0.15
	# Radio de efecto (aura del territorio/nido): anillo tenue pulsante.
	if role == &"howl_post" or str(role).begins_with("nest"):
		# El borde del territorio debe leerse SIN ambiguedad: es la linea que el
		# jugador cruza. Marca debilitada = anillo discontinuo y mas apagado, para
		# que se vea el progreso antes de destruirla.
		var weak: bool = role == &"howl_post" and is_weakened()
		var ring_alpha: float = 0.14 if not weak else 0.09
		if weak:
			# Discontinuo: 12 segmentos con hueco.
			for i in 12:
				var from: float = float(i) * TAU / 12.0
				draw_arc(Vector2.ZERO, effect_radius * pulse, from, from + TAU / 22.0, 6,
					Color(accent.r, accent.g, accent.b, ring_alpha * 2.4), 2.0, true)
		else:
			draw_arc(Vector2.ZERO, effect_radius * pulse, 0.0, TAU, 48,
				Color(accent.r, accent.g, accent.b, ring_alpha * 2.0), 2.5, true)
		draw_circle(Vector2.ZERO, effect_radius * pulse,
			Color(accent.r, accent.g, accent.b, 0.03 if not weak else 0.015))
	# Cuerpo: totem/estructura simple con flash de daño.
	var body: Color = accent.darkened(0.35).lerp(Color.WHITE, _flash * 0.7)
	match role:
		&"howl_post":
			# Totem: poste con "boca" que aulla.
			draw_rect(Rect2(-7, -34, 14, 40), body)
			draw_circle(Vector2(0, -38), 10.0, body.lightened(0.15))
			draw_circle(Vector2(0, -38), 4.0, accent)
			for i in 3:
				var r: float = 14.0 + float(i) * 7.0 + fmod(_time * 14.0, 7.0)
				draw_arc(Vector2(0, -38), r, -0.6, 0.6, 10,
					Color(accent.r, accent.g, accent.b, 0.5 - float(i) * 0.14), 2.0, true)
		&"nest_spawner", &"nest_healer", &"nest_contaminator":
			# Nido: montículo orgánico con membrana que respira.
			draw_circle(Vector2.ZERO, 24.0 * pulse, body)
			draw_circle(Vector2.ZERO, 15.0, accent.darkened(0.1))
			draw_circle(Vector2(0, -2), 8.0 * pulse, accent.lightened(0.25))
		&"weapon_crate":
			# Caja de armas (FASE 13): cofre ancho de tablones con banda metalica
			# y cerradura. Silueta rectangular + brillo moderado: premio grande.
			var glow: float = 0.25 + absf(sin(_time * 2.2)) * 0.2
			draw_circle(Vector2.ZERO, 34.0 * pulse, Color(accent.r, accent.g, accent.b, glow * 0.35))
			draw_rect(Rect2(-24, -18, 48, 36), body)
			draw_rect(Rect2(-24, -18, 48, 36), accent, false, 2.5)
			draw_line(Vector2(-24, -18), Vector2(24, 18), accent, 2.0)
			draw_line(Vector2(24, -18), Vector2(-24, 18), accent, 2.0)
			draw_rect(Rect2(-24, -4, 48, 8), accent.darkened(0.2))
			draw_circle(Vector2(0, 0), 5.0, accent.lightened(0.25))
		&"supply_crate":
			# Caja de suministros (FASE 13): bidon REDONDEADO con cruz de botiquin.
			# Silueta distinta (redonda vs rectangular): se distingue sin leer y
			# sin depender del color.
			var glow_s: float = 0.22 + absf(sin(_time * 2.0)) * 0.18
			draw_circle(Vector2.ZERO, 30.0 * pulse, Color(accent.r, accent.g, accent.b, glow_s * 0.35))
			draw_circle(Vector2.ZERO, 20.0, body)
			draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 28, accent, 2.5, true)
			draw_rect(Rect2(-3, -11, 6, 22), accent.lightened(0.2))
			draw_rect(Rect2(-11, -3, 22, 6), accent.lightened(0.2))
		&"special_crate":
			# Caja especial (FASE 13): rombo facetado con destellos. Ni cofre ni
			# bidon: forma unica para el contenido raro.
			var glow_e: float = 0.3 + absf(sin(_time * 3.0)) * 0.25
			draw_circle(Vector2.ZERO, 34.0 * pulse, Color(accent.r, accent.g, accent.b, glow_e * 0.35))
			var half: float = 22.0
			var diamond := PackedVector2Array([
				Vector2(0, -half), Vector2(half, 0), Vector2(0, half), Vector2(-half, 0)])
			draw_colored_polygon(diamond, body)
			var outline := diamond.duplicate()
			outline.append(diamond[0])
			draw_polyline(outline, accent, 2.5)
			draw_line(Vector2(0, -half), Vector2(0, half), accent.darkened(0.15), 1.5)
			draw_line(Vector2(-half, 0), Vector2(half, 0), accent.darkened(0.15), 1.5)
		_:
			# Linea de produccion: caja industrial con piston.
			draw_rect(Rect2(-26, -18, 52, 36), body)
			draw_rect(Rect2(-20, -12, 40, 8), accent.darkened(0.15))
			var piston: float = absf(sin(_time * 4.0)) * 10.0
			draw_rect(Rect2(-4, -10 - piston, 8, 12), accent)
	# Barra de vida propia (los interactables no usan la barra del HUD).
	var ratio: float = clampf(float(current_health) / float(maxi(1, max_health)), 0.0, 1.0)
	if ratio < 1.0:
		draw_rect(Rect2(-20, -52, 40, 5), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(-20, -52, 40.0 * ratio, 5), accent)
