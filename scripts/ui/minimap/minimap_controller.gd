extends Control
## MinimapController (Sistema Minimapa): UN minimapa estilo radar, centrado en su
## jugador (focus). En solo hay uno (esquina superior derecha, bajo el objetivo);
## en coop de pantalla dividida hay uno por mitad, cada uno siguiendo a su jugador.
##
## Rendimiento:
## - Iconos importantes (jugadores, companeros, jefes, rescates): ≤ ~15 nodos,
##   se actualizan cada frame reciclando marcadores de un pool (cero alta/baja
##   de nodos por frame).
## - Zombies y obstaculos: se dibujan TODOS en un solo canvas item (DotLayer)
##   a cadencia limitada (DOT_INTERVAL); con hordas grandes se agrupan por celdas
##   (un punto por celda) y hay tope duro de nodos procesados.
## - Con el PerformanceManager en critico, la cadencia del radar baja sola.
##
## No toca gameplay: solo LEE grupos via MinimapEntityRegistry y propiedades
## publicas de los nodos (con has_method/get defensivos).

const MinimapConfig = preload("res://scripts/ui/minimap/minimap_config.gd")
const MinimapMarker = preload("res://scripts/ui/minimap/minimap_marker.gd")
const MinimapTerrain = preload("res://scripts/ui/minimap/minimap_terrain.gd")

## Capa unica que dibuja todos los puntos baratos (zombies, elites, grupos) y las
## SILUETAS de obstaculos grandes en UNA sola llamada de _draw: nada de un nodo
## por enemigo ni por obstaculo.
class DotLayer:
	extends Control
	const Cfg = preload("res://scripts/ui/minimap/minimap_config.gd")

	var normal_points := PackedVector2Array()
	var elite_points := PackedVector2Array()
	## Categorias de las Partidas rapidas (especial/pesado/esbirro del jefe).
	var special_points := PackedVector2Array()
	var heavy_points := PackedVector2Array()
	var minion_points := PackedVector2Array()
	var cluster_points := PackedVector2Array()
	var cluster_sizes := PackedFloat32Array()
	## Siluetas de obstaculos: poligonos (rects rotados) y circulos (arboles/rocas).
	var struct_polys: Array[PackedVector2Array] = []
	var struct_circles := PackedVector2Array()
	var struct_radii := PackedFloat32Array()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		for poly in struct_polys:
			draw_colored_polygon(poly, Cfg.STRUCT_COLOR)
		for i in struct_circles.size():
			draw_circle(struct_circles[i], struct_radii[i], Cfg.STRUCT_COLOR)
		var half: float = Cfg.ENEMY_DOT * 0.5
		for p in normal_points:
			draw_rect(Rect2(p - Vector2(half, half), Vector2(Cfg.ENEMY_DOT, Cfg.ENEMY_DOT)), Cfg.ENEMY_COLOR)
		for i in cluster_points.size():
			var s: float = cluster_sizes[i]
			draw_rect(Rect2(cluster_points[i] - Vector2(s, s) * 0.5, Vector2(s, s)), Cfg.ENEMY_COLOR)
		var half_e: float = Cfg.ENEMY_ELITE_DOT * 0.5
		for p in elite_points:
			draw_rect(Rect2(p - Vector2(half_e, half_e), Vector2(Cfg.ENEMY_ELITE_DOT, Cfg.ENEMY_ELITE_DOT)), Cfg.ENEMY_ELITE_COLOR)
		# Especiales: ROMBO naranja (forma distinta, no solo color).
		for p in special_points:
			_draw_diamond(p, Cfg.ENEMY_SPECIAL_DOT, Cfg.ENEMY_SPECIAL_COLOR)
		# Pesados: cuadrado claramente mas grande.
		var half_h: float = Cfg.ENEMY_HEAVY_DOT * 0.5
		for p in heavy_points:
			draw_rect(Rect2(p - Vector2(half_h, half_h), Vector2(Cfg.ENEMY_HEAVY_DOT, Cfg.ENEMY_HEAVY_DOT)), Cfg.ENEMY_HEAVY_COLOR)
		# Esbirros del jefe: rombo pequeño en el color familiar del jefe.
		for p in minion_points:
			_draw_diamond(p, Cfg.BOSS_MINION_DOT, Cfg.BOSS_MINION_COLOR)

	func _draw_diamond(center: Vector2, size: float, color: Color) -> void:
		var h: float = size * 0.5
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -h), center + Vector2(h, 0),
			center + Vector2(0, h), center + Vector2(-h, 0),
		]), color)


## Registro compartido de entidades (lo inyecta MinimapSystem).
var registry: Node
## Jugador que este minimapa sigue (1 o 2).
var player_id: int = 1
## true = partida cooperativa (colores de identidad CoopConfig y tamano de mitad).
var coop: bool = false
## HUD (para saber si hay seleccion de cartas visible sin pausa).
var hud: Node
## Fuente de terreno compartida (MinimapTerrainSource; la inyecta MinimapSystem).
var terrain_source: RefCounted

var _focus: Node2D
var _map_manager: Node
var _perf: Node
var _terrain: Control
var _terrain_timer: float = 0.0
var _dots: DotLayer
var _marker_layer: Control
var _marker_pool: Array = []
var _markers_used: int = 0
var _expanded: bool = false
var _world_radius: float = MinimapConfig.WORLD_RADIUS
var _dot_timer: float = 0.0
## Layout: anclado en anchor_x*pantalla + edge_offset. Con grow_left el panel
## crece hacia la izquierda desde ese borde; sin el, hacia la derecha.
var _anchor_x: float = 1.0
var _edge_offset: float = -16.0
var _grow_left: bool = true


func _ready() -> void:
	# ALWAYS: en pausa (cartas/pausa/fin de partida) el _process sigue corriendo
	# SOLO para ocultarse; los paneles del HUD estan en el arbol antes que este
	# nodo y se dibujarian debajo del minimapa si quedara visible.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_perf = get_node_or_null("/root/Performance")
	_build_background()
	# Terreno del mapa (calles/senderos/lago/estructuras) DEBAJO de los puntos
	# de enemigos y los marcadores: el terreno nunca tapa entidades.
	_terrain = MinimapTerrain.new()
	_terrain.name = "Terrain"
	_terrain.source = terrain_source
	add_child(_terrain)
	_dots = DotLayer.new()
	_dots.name = "Dots"
	add_child(_dots)
	_marker_layer = Control.new()
	_marker_layer.name = "Markers"
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_marker_layer)
	_build_frame()
	_build_legend()
	_apply_layout()


## Leyenda de iconos de botin (FASE 13): visible SOLO con el radar ampliado
## (Tab), como referencia accesible sin ocupar pantalla en combate. Reutiliza los
## MinimapMarker reales, asi la forma de la leyenda es EXACTAMENTE la del radar.
var _legend: PanelContainer


func _build_legend() -> void:
	_legend = PanelContainer.new()
	_legend.name = "Legend"
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.visible = false
	var box := StyleBoxFlat.new()
	box.bg_color = MinimapConfig.BG_COLOR
	box.set_corner_radius_all(8)
	box.set_content_margin_all(7)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	_legend.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_legend.add_child(col)
	for entry in MinimapConfig.LEGEND_ENTRIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(14, 14)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var marker := MinimapMarker.new()
		marker.position = Vector2(7, 7)
		marker.setup(entry[0], entry[1])
		holder.add_child(marker)
		row.add_child(holder)
		var label := Label.new()
		label.text = str(entry[2])
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
		row.add_child(label)
		col.add_child(row)
	# Fuera del area recortada del radar (clip_contents la escondia dentro):
	# cuelga del PADRE del minimapa y se recoloca bajo el panel en _process.
	if get_parent() != null:
		get_parent().add_child.call_deferred(_legend)


func _exit_tree() -> void:
	if _legend != null and is_instance_valid(_legend):
		_legend.queue_free()


func _build_background() -> void:
	var bg := Panel.new()
	bg.name = "Bg"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := StyleBoxFlat.new()
	box.bg_color = MinimapConfig.BG_COLOR
	box.set_corner_radius_all(10)
	bg.add_theme_stylebox_override("panel", box)
	add_child(bg)


## Borde por encima de los puntos. En coop toma el color de identidad del
## jugador (mismo codigo de color que el marco de su mitad).
func _build_frame() -> void:
	var frame := Panel.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_corner_radius_all(10)
	box.set_border_width_all(2)
	var border: Color = MinimapConfig.BORDER_COLOR
	if coop:
		var c: Color = CoopConfig.player_color(player_id)
		border = Color(c.r, c.g, c.b, 0.8)
	box.border_color = border
	frame.add_theme_stylebox_override("panel", box)
	add_child(frame)


# --- Layout ------------------------------------------------------------------------

## anchor_x: 1.0 = borde derecho de pantalla; 0.0 = borde izquierdo. grow_left
## decide hacia donde crece el panel desde ese borde (esquinas exteriores en
## coop: el centro queda libre para los mensajes del HUD).
func configure_layout(anchor_x: float, edge_offset: float, grow_left: bool = true) -> void:
	_anchor_x = anchor_x
	_edge_offset = edge_offset
	_grow_left = grow_left
	_apply_layout()


func set_expanded(expanded: bool) -> void:
	if _expanded == expanded:
		return
	_expanded = expanded
	_apply_layout()


func is_expanded() -> bool:
	return _expanded


func _panel_side() -> float:
	if coop:
		return MinimapConfig.SIZE_COOP_EXPANDED if _expanded else MinimapConfig.SIZE_COOP
	return MinimapConfig.SIZE_EXPANDED if _expanded else MinimapConfig.SIZE


func _apply_layout() -> void:
	var side: float = _panel_side()
	anchor_left = _anchor_x
	anchor_right = _anchor_x
	anchor_top = 0.0
	anchor_bottom = 0.0
	if _grow_left:
		offset_right = _edge_offset
		offset_left = _edge_offset - side
	else:
		offset_left = _edge_offset
		offset_right = _edge_offset + side
	offset_top = MinimapConfig.TOP_MARGIN
	offset_bottom = MinimapConfig.TOP_MARGIN + side
	_world_radius = MinimapConfig.WORLD_RADIUS_EXPANDED if _expanded else MinimapConfig.WORLD_RADIUS
	_dot_timer = 0.0      # fuerza refresco inmediato de los puntos con la nueva escala
	_terrain_timer = 0.0  # y del terreno (nueva escala/nivel de detalle)


# --- Bucle -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _should_show():
		visible = false
		_update_legend()
		return
	_refresh_focus()
	if _focus == null:
		visible = false
		_update_legend()
		return
	visible = true
	_update_legend()
	_update_markers()
	# Scroll suave del terreno: solo se mueve la capa (el redibujado va aparte).
	if _terrain != null:
		_terrain.position = size * 0.5 - _focus.global_position * _map_scale()
	_terrain_timer -= delta
	if _terrain_timer <= 0.0:
		_terrain_timer = MinimapConfig.TERRAIN_INTERVAL
		if _terrain != null:
			_terrain.update_region(_focus.global_position, _world_radius, _map_scale(), _expanded)
	_dot_timer -= delta
	if _dot_timer <= 0.0:
		var critical: bool = _perf != null and _perf.has_method("is_critical") and _perf.is_critical()
		_dot_timer = MinimapConfig.DOT_INTERVAL_CRITICAL if critical else MinimapConfig.DOT_INTERVAL
		_update_dots()


## La leyenda solo acompaña al radar AMPLIADO y visible; se pega bajo el panel
## alineada a su borde derecho (crece hacia la izquierda, como el propio radar).
func _update_legend() -> void:
	if _legend == null or not is_instance_valid(_legend):
		return
	var show: bool = visible and _expanded
	if _legend.visible != show:
		_legend.visible = show
	if show:
		_legend.position = Vector2(position.x + size.x - _legend.size.x, position.y + size.y + 6.0)


## Oculto en pausa (menus, cartas, fin de partida, desconexion de mando), al
## terminar la partida y durante la seleccion de cartas coop sin pausa.
func _should_show() -> bool:
	if get_tree().paused:
		return false
	if registry == null:
		return false
	if not is_instance_valid(_map_manager):
		_map_manager = get_tree().get_first_node_in_group("map_manager")
	if is_instance_valid(_map_manager) and _map_manager.has_method("is_run_ended") and _map_manager.is_run_ended():
		return false
	return true


## Resuelve/revalida el jugador seguido. Si el P2 sale de la partida (nodo
## liberado), el minimapa 2 simplemente se oculta hasta que vuelva.
func _refresh_focus() -> void:
	if _valid_node2d(_focus) and int(_focus.get("player_id")) == player_id:
		return
	_focus = null
	for p in registry.get_list(&"players"):
		if _valid_node2d(p) and int(p.get("player_id")) == player_id:
			_focus = p
			return


func _valid_node2d(node) -> bool:
	return node != null and is_instance_valid(node) and node is Node2D and (node as Node2D).is_inside_tree()


# --- Conversion mundo -> minimapa ----------------------------------------------------

func _map_scale() -> float:
	return (minf(size.x, size.y) * 0.5 - MinimapConfig.EDGE_MARGIN) / maxf(1.0, _world_radius)


func _to_map(world_pos: Vector2, focus_pos: Vector2, map_scale: float) -> Vector2:
	return size * 0.5 + (world_pos - focus_pos) * map_scale


func _inside(local: Vector2) -> bool:
	var m: float = MinimapConfig.EDGE_MARGIN
	return local.x >= m and local.x <= size.x - m and local.y >= m and local.y <= size.y - m


func _clamp_to_edge(local: Vector2) -> Vector2:
	var m: float = MinimapConfig.EDGE_MARGIN
	return Vector2(clampf(local.x, m, size.x - m), clampf(local.y, m, size.y - m))


# --- Iconos importantes (cada frame, con pool) ---------------------------------------

func _update_markers() -> void:
	_markers_used = 0
	var fp: Vector2 = _focus.global_position
	var map_scale: float = _map_scale()
	var pulse: float = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.006))

	# Jugador local: siempre centrado, con orientacion.
	_place_player(_focus, fp, map_scale, pulse)

	# Otros jugadores (coop): visibles aunque esten muy lejos (flecha de borde).
	for p in registry.get_list(&"players"):
		if p == _focus or not _valid_node2d(p):
			continue
		_place_player(p, fp, map_scale, pulse)

	# Companeros aliados (derribados: apagados).
	for c in registry.get_list(&"companions"):
		if not _valid_node2d(c):
			continue
		var downed: bool = c.has_method("is_downed") and c.is_downed()
		_place_entity(c, fp, map_scale, &"companion", MinimapConfig.COMPANION_COLOR, false, downed)

	# Puntos de rescate: objetivo amarillo, sujetado al borde si queda lejos.
	for r in registry.get_list(&"rescue_points"):
		if _valid_node2d(r):
			_place_entity(r, fp, map_scale, &"rescue", MinimapConfig.RESCUE_COLOR, true)

	# Mini-jefes y jefes: prioridad maxima, siempre indicados (borde si lejos).
	for mb in registry.get_list(&"miniboss"):
		if _valid_node2d(mb):
			_place_entity(mb, fp, map_scale, &"miniboss", MinimapConfig.MINIBOSS_COLOR, true)
	for b in registry.get_list(&"boss"):
		if _valid_node2d(b):
			var marker := _place_entity(b, fp, map_scale, &"boss", MinimapConfig.BOSS_COLOR, true)
			if marker != null:
				marker.modulate.a = pulse  # el jefe late para no pasar desapercibido

	_place_loot_markers(fp, map_scale)
	_hide_unused_markers()


## Botin en el radar (FASE 13): cajas, armas del suelo, nucleos, mutaciones y
## (solo si estan cerca) power-ups comunes. Cada tipo con forma propia. Con tope
## de marcadores para que una lluvia de drops no infle el pool.
func _place_loot_markers(fp: Vector2, map_scale: float) -> void:
	var placed: int = 0

	# Cajas: el rol vive en el interactable; los demas roles devuelven "".
	for crate in registry.get_list(&"map_interactables"):
		if placed >= MinimapConfig.MAX_LOOT_MARKERS:
			return
		if not _valid_node2d(crate) or not crate.has_method("minimap_loot_kind"):
			continue
		var kind: StringName = crate.minimap_loot_kind()
		if kind == &"":
			continue
		if _place_entity(crate, fp, map_scale, kind, _loot_color(kind), false) != null:
			placed += 1

	# Armas abandonadas en el suelo.
	for wp in registry.get_list(&"weapon_pickups"):
		if placed >= MinimapConfig.MAX_LOOT_MARKERS:
			return
		if not _valid_node2d(wp) or (wp.has_method("is_claimed") and wp.is_claimed()):
			continue
		if _place_entity(wp, fp, map_scale, &"loot_weapon", MinimapConfig.LOOT_WEAPON_COLOR, false) != null:
			placed += 1

	# Power-ups: nucleos y mutaciones siempre; los comunes solo cerca del
	# jugador (el radar no debe chivar todo el botin del mapa).
	for pickup in registry.get_list(&"pickups"):
		if placed >= MinimapConfig.MAX_LOOT_MARKERS:
			return
		if not _valid_node2d(pickup) or not pickup.has_method("minimap_loot_kind"):
			continue
		if pickup.has_method("is_claimed") and pickup.is_claimed():
			continue
		var kind: StringName = pickup.minimap_loot_kind()
		if kind == &"loot_powerup" and fp.distance_to((pickup as Node2D).global_position) > MinimapConfig.LOOT_COMMON_NEAR_RADIUS:
			continue
		if _place_entity(pickup, fp, map_scale, kind, _loot_color(kind), false) != null:
			placed += 1


func _loot_color(kind: StringName) -> Color:
	match kind:
		&"crate_weapon":
			return MinimapConfig.CRATE_WEAPON_COLOR
		&"crate_supply":
			return MinimapConfig.CRATE_SUPPLY_COLOR
		&"crate_special":
			return MinimapConfig.CRATE_SPECIAL_COLOR
		&"loot_weapon":
			return MinimapConfig.LOOT_WEAPON_COLOR
		&"loot_mutation":
			return MinimapConfig.LOOT_MUTATION_COLOR
		&"loot_core":
			return MinimapConfig.LOOT_CORE_COLOR
	return MinimapConfig.LOOT_POWERUP_COLOR


func _place_player(p: Node2D, fp: Vector2, map_scale: float, pulse: float) -> void:
	var pid: int = int(p.get("player_id"))
	var color: Color
	if coop:
		color = CoopConfig.player_color(pid)
	else:
		color = MinimapConfig.PLAYER_SOLO_COLOR if pid <= 1 else MinimapConfig.PLAYER_2_SOLO_FALLBACK
	var facing: float = 0.0
	if p.has_method("get_last_facing_direction"):
		facing = (p.get_last_facing_direction() as Vector2).angle()
	var downed: bool = p.has_method("is_downed") and p.is_downed()

	var marker := _acquire_marker()
	var local: Vector2 = _to_map(p.global_position, fp, map_scale)
	var off_map: bool = not _inside(local)
	var heading: float = facing
	if off_map:
		heading = (local - size * 0.5).angle()
		local = _clamp_to_edge(local)
	marker.setup(&"player", color, heading, off_map, downed)
	marker.position = local
	marker.modulate.a = pulse if downed else 1.0  # derribado: parpadea (SOS)


## Coloca un marcador para una entidad. clamp_to_edge=true la mantiene indicada
## en el borde cuando queda fuera del radar; false la oculta si esta lejos.
func _place_entity(node: Node2D, fp: Vector2, map_scale: float, kind: StringName,
		color: Color, clamp_to_edge: bool, dimmed: bool = false) -> MinimapMarker:
	var local: Vector2 = _to_map(node.global_position, fp, map_scale)
	var off_map: bool = not _inside(local)
	if off_map and not clamp_to_edge:
		return null
	var heading: float = 0.0
	if off_map:
		heading = (local - size * 0.5).angle()
		local = _clamp_to_edge(local)
	var marker := _acquire_marker()
	marker.setup(kind, color, heading, off_map, dimmed)
	marker.position = local
	marker.modulate.a = 1.0
	return marker


# --- Pool de marcadores ---------------------------------------------------------------

func _acquire_marker() -> MinimapMarker:
	if _markers_used < _marker_pool.size():
		var m: MinimapMarker = _marker_pool[_markers_used]
		_markers_used += 1
		m.visible = true
		return m
	var marker: MinimapMarker = MinimapMarker.new()
	_marker_layer.add_child(marker)
	_marker_pool.append(marker)
	_markers_used += 1
	return marker


func _hide_unused_markers() -> void:
	for i in range(_markers_used, _marker_pool.size()):
		_marker_pool[i].visible = false


# --- Puntos baratos (zombies/obstaculos, cadencia limitada) ---------------------------

func _update_dots() -> void:
	var dl := _dots
	dl.normal_points.clear()
	dl.elite_points.clear()
	dl.special_points.clear()
	dl.heavy_points.clear()
	dl.minion_points.clear()
	dl.cluster_points.clear()
	dl.cluster_sizes.clear()
	dl.struct_polys.clear()
	dl.struct_circles.clear()
	dl.struct_radii.clear()

	var fp: Vector2 = _focus.global_position
	var map_scale: float = _map_scale()

	var enemies: Array = registry.get_list(&"enemies")
	# El modo horda se decide con los enemigos VIVOS, no con el tamano bruto de la
	# foto (puede contener nodos recien liberados hasta el proximo refresco).
	var valid_count: int = 0
	for e in enemies:
		if _valid_node2d(e):
			valid_count += 1
	var use_clusters: bool = valid_count >= MinimapConfig.CLUSTER_THRESHOLD
	var clusters: Dictionary = {}
	var scanned: int = 0
	for e in enemies:
		if scanned >= MinimapConfig.MAX_ENEMY_SCAN:
			break
		scanned += 1
		if not _valid_node2d(e):
			continue
		# Jefes/mini-jefes tambien estan en "enemies": ya tienen marcador propio.
		if e.is_in_group("boss") or e.is_in_group("miniboss"):
			continue
		var local: Vector2 = _to_map((e as Node2D).global_position, fp, map_scale)
		if not _inside(local):
			continue
		# Elite = variante rara encendida: punto mas grande, nunca agrupado.
		var elite_kind = e.get("_elite_kind")
		if elite_kind != null and elite_kind is StringName and elite_kind != &"":
			dl.elite_points.append(local)
			continue
		# Categorias de las Partidas rapidas: esbirros del jefe, especiales y
		# pesados llevan marcador propio y nunca se agrupan en celdas.
		var edata = e.get("enemy_data")
		if edata != null:
			if edata.get("role") == &"boss_minion":
				dl.minion_points.append(local)
				continue
			var tier = edata.get("tier")
			if tier == &"special":
				dl.special_points.append(local)
				continue
			if tier == &"heavy":
				dl.heavy_points.append(local)
				continue
		if use_clusters:
			var cell := Vector2i((local / MinimapConfig.CLUSTER_CELL).floor())
			clusters[cell] = int(clusters.get(cell, 0)) + 1
		else:
			dl.normal_points.append(local)

	# Un punto por celda: crece suavemente con la cantidad agrupada.
	if use_clusters:
		for cell in clusters:
			var count: int = clusters[cell]
			var center: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * MinimapConfig.CLUSTER_CELL
			dl.cluster_points.append(center)
			dl.cluster_sizes.append(3.0 + minf(float(count), 10.0) * 0.55)

	# Obstaculos GRANDES como siluetas (rect rotado real del footprint), no como
	# nube de puntos. El radar compacto solo muestra la estructura principal; el
	# ampliado baja el umbral. Los pequenos (barriles, arbustos...) no se dibujan.
	var min_side: float = MinimapConfig.SILHOUETTE_MIN_SIZE_EXPANDED if _expanded else MinimapConfig.SILHOUETTE_MIN_SIZE
	var obstacles: Array = registry.get_list(&"obstacles")
	var drawn: int = 0
	for o in obstacles:
		if drawn >= MinimapConfig.MAX_SILHOUETTES:
			break
		if not _valid_node2d(o) or not o.has_method("get_footprint_size"):
			continue
		var fsize: Vector2 = o.get_footprint_size()
		if maxf(fsize.x, fsize.y) < min_side:
			continue
		var center: Vector2 = _to_map((o as Node2D).global_position, fp, map_scale)
		if not _inside(center):
			continue
		var odata = o.get("data")
		var category: StringName = odata.category if odata != null else &""
		if category in [&"tree", &"bush", &"rock"]:
			dl.struct_circles.append(center)
			dl.struct_radii.append(maxf(2.0, maxf(fsize.x, fsize.y) * 0.5 * map_scale))
		else:
			var rot: float = (o as Node2D).rotation
			var he: Vector2 = fsize * 0.5 * map_scale
			var poly := PackedVector2Array()
			for corner in [Vector2(-he.x, -he.y), Vector2(he.x, -he.y), Vector2(he.x, he.y), Vector2(-he.x, he.y)]:
				poly.append(center + corner.rotated(rot))
			dl.struct_polys.append(poly)
		drawn += 1

	dl.queue_redraw()
