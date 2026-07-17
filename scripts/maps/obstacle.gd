extends StaticBody2D
## Obstaculo de mapa (Fase 08.75). Cuerpo geometrico con colision (StaticBody2D en
## la capa 5) que el jugador, los enemigos y los companeros no pueden atravesar.
## El dibujo depende de `data.category` para dar identidad visual (carro, muro,
## arbol, contenedor, barril, banca, roca, caja, valla, tuberia, arbusto, señal).
## Todo con _draw (formas simples), sin assets externos.

# ObstacleData es clase global (class_name): se usa sin preload.
const XP_ORB_SCENE := preload("res://scenes/loot/XPOrb.tscn")

## Luz global desde el noroeste: las sombras se proyectan al sureste con este
## offset (mismo criterio que ChunkGroundRenderer para coherencia visual).
const SHADOW_OFFSET := Vector2(10.0, 12.0)

var data: ObstacleData
var _size: Vector2 = Vector2(36, 36)
var _block_radius: float = 24.0
var _rng_tint: float = 0.0
## Semilla propia para los detalles de variacion (oxido, AC del techo, puertas
## abiertas...): estable entre redraws, sorteada del rng del chunk en configure.
var _variant_seed: int = 0
var _health: int = 0
var _broken: bool = false
var _flash_tween: Tween

@onready var _shape: CollisionShape2D = $CollisionShape2D


## Configura tamaño, colision, z-index y colores a partir de un ObstacleData.
## Si el spawner ya sorteo tamaño/rotacion (para validar el footprint ANTES de
## colocar), los recibe como preset y el dibujo/colision coinciden exactamente
## con lo que se valido. preset_rotation usa INF como "sin preset".
func configure(obstacle_data: ObstacleData, rng: RandomNumberGenerator, preset_size: Vector2 = Vector2.ZERO, preset_rotation: float = INF) -> void:
	data = obstacle_data
	if data == null:
		return
	if preset_size != Vector2.ZERO:
		_size = preset_size
	else:
		_size = Vector2(
			lerpf(data.min_size.x, data.max_size.x, rng.randf()),
			lerpf(data.min_size.y, data.max_size.y, rng.randf())
		)
	if is_finite(preset_rotation):
		rotation = preset_rotation
	elif data.max_rotation > 0.0:
		rotation = rng.randf_range(-data.max_rotation, data.max_rotation)
	_rng_tint = rng.randf_range(-0.06, 0.06)
	_variant_seed = rng.randi()
	_block_radius = max(_size.x, _size.y) * 0.5 * max(0.4, data.block_scale)
	z_index = data.z_offset
	_health = data.health

	if not is_node_ready():
		await ready
	_build_collision()
	queue_redraw()


func _build_collision() -> void:
	if data == null:
		return
	if not data.collidable:
		collision_layer = 0
		_shape.disabled = true
		return
	collision_layer = 1 << 4  # capa 5 (valor 16): obstaculos solidos
	collision_mask = 0
	add_to_group("obstacles")
	if data.collision_shape == &"circle":
		var circle := CircleShape2D.new()
		circle.radius = max(_size.x, _size.y) * 0.5
		_shape.shape = circle
	else:
		var rect := RectangleShape2D.new()
		rect.size = _size
		_shape.shape = rect


func get_block_radius() -> float:
	return _block_radius


## Tamaño real del cuerpo (px, sin rotar). Lo usan los tests de solapes.
func get_footprint_size() -> Vector2:
	return _size


# --- Interaccion con proyectiles (Fase 08.9) ----------------------------------

## True si este obstaculo detiene proyectiles basicos.
func blocks_projectiles() -> bool:
	return data != null and data.blocks_projectiles


## True si este obstaculo detiene el laser.
func blocks_laser() -> bool:
	return data != null and data.blocks_laser


## Recibe el impacto de un proyectil. Devuelve true si el proyectil debe detenerse.
## Si el obstaculo es destructible, aplica daño (y flash); al llegar a 0 se rompe.
func absorb_projectile(damage: int) -> bool:
	if data != null and data.destructible and not _broken:
		_apply_damage(damage)
	return blocks_projectiles()


func _apply_damage(amount: int) -> void:
	if _broken:
		return
	_health -= amount
	_flash()
	if _health <= 0:
		_break()


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color(1.7, 1.7, 1.7, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.16)


func _break() -> void:
	if _broken:
		return
	_broken = true
	# Deja de colisionar y sale de los grupos.
	set_deferred("collision_layer", 0)
	if is_in_group("obstacles"):
		remove_from_group("obstacles")
	# Barril explosivo: daña a los enemigos cercanos (nunca al jugador, sin cadena).
	if data.explosive:
		_explode()
	# Recompensa pequeña: suelta un orbe de XP si corresponde.
	if data.xp_reward > 0:
		_drop_xp(data.xp_reward)
	var feedback: Node = get_node_or_null("/root/Feedback")
	if feedback != null:
		if feedback.has_method("hit_effect"):
			feedback.hit_effect(global_position, data.accent_color, 0.4, max(_size.x, _size.y) / 12.0)
		if feedback.has_method("shake"):
			feedback.shake(0.12)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"explosion" if data.explosive else &"enemy_hit")
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", scale * 0.2, 0.16)
	tween.tween_property(self, "modulate:a", 0.0, 0.16)
	tween.chain().tween_callback(queue_free)


func _explode() -> void:
	var radius_sq: float = data.explosion_radius * data.explosion_radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		var offset: Vector2 = (enemy as Node2D).global_position - global_position
		if offset.length_squared() <= radius_sq:
			var dir: Vector2 = offset.normalized() if offset.length_squared() > 0.01 else Vector2.RIGHT
			enemy.take_damage(data.explosion_damage, dir)


func _drop_xp(amount: int) -> void:
	if XP_ORB_SCENE == null:
		return
	var orb := XP_ORB_SCENE.instantiate() as Node2D
	if orb == null:
		return
	orb.set("xp_value", amount)
	orb.global_position = global_position
	orb.set("pop_velocity", Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 90.0))
	get_parent().add_child.call_deferred(orb)


# --- Dibujo por categoria -----------------------------------------------------
# Estilo: pseudo-3D top-down con luz global desde el noroeste. Cada categoria
# proyecta sombra al SE, ilumina sus caras N/O y oscurece las S/E. Los detalles
# de variacion salen de _variant_seed (estables entre redraws).

## Paleta urbana de pintura de coches (el body_color del .tres queda sin usar).
const CAR_PALETTE: Array[Color] = [
	Color(0.55, 0.22, 0.18), Color(0.24, 0.36, 0.54), Color(0.55, 0.56, 0.58),
	Color(0.72, 0.70, 0.62), Color(0.80, 0.63, 0.16), Color(0.27, 0.43, 0.31),
	Color(0.32, 0.27, 0.38), Color(0.17, 0.18, 0.21),
]


func _draw() -> void:
	if data == null:
		return
	var vr := RandomNumberGenerator.new()
	vr.seed = _variant_seed
	var body: Color = data.body_color.lightened(maxf(0.0, _rng_tint)).darkened(maxf(0.0, -_rng_tint))
	var detail: Color = data.detail_color
	var outline: Color = data.outline_color
	var accent: Color = data.accent_color
	match data.category:
		&"car":
			_draw_car(outline, vr)
		&"wall", &"house":
			_draw_building(body, outline, vr)
		&"container":
			_draw_container(body, detail, outline, accent, vr)
		&"barrel":
			_draw_barrel(body, detail, outline, accent, vr)
		&"tree":
			_draw_tree(body, detail, vr)
		&"bush":
			_draw_bush(body, detail, vr)
		&"bench":
			_draw_bench(body, detail, outline)
		&"rock":
			_draw_rock(body, detail, outline, vr)
		&"fence":
			_draw_fence(body, detail, outline)
		&"pipe":
			_draw_pipe(body, detail, outline, accent)
		&"sign":
			_draw_sign(body, detail, outline, accent)
		_:
			_draw_crate(body, detail, outline)


# --- Helpers de luz y forma ----------------------------------------------------

## Elipse rellena por poligono (draw_circle no acepta radios distintos).
func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)


## Sombra elipsoidal proyectada al SE (compensa la rotacion del nodo para que la
## luz global apunte siempre en la misma direccion del mundo).
func _drop_shadow(radii: Vector2, height: float = 0.6, alpha: float = 0.26) -> void:
	_ellipse((SHADOW_OFFSET * height).rotated(-rotation), radii * 1.04, Color(0, 0, 0, alpha))


func _rect(size: Vector2, color: Color, center: Vector2 = Vector2.ZERO) -> void:
	draw_rect(Rect2(center - size * 0.5, size), color, true)


func _outline_rect(size: Vector2, color: Color, width: float = 2.0, center: Vector2 = Vector2.ZERO) -> void:
	draw_rect(Rect2(center - size * 0.5, size), color, false, width)


# --- Coche ----------------------------------------------------------------------

func _draw_car(outline: Color, vr: RandomNumberGenerator) -> void:
	var w: float = _size.x
	var h: float = _size.y
	var hw: float = w * 0.5
	var hh: float = h * 0.42
	var paint: Color = CAR_PALETTE[vr.randi_range(0, CAR_PALETTE.size() - 1)]
	paint = paint.lightened(maxf(0.0, _rng_tint)).darkened(maxf(0.0, -_rng_tint))
	_drop_shadow(Vector2(hw, hh * 1.15), 0.6)
	# Ruedas asomando por los laterales.
	var wheel := Color(0.07, 0.07, 0.09)
	for wx in [-w * 0.30, w * 0.30]:
		for wy in [-h * 0.44, h * 0.44]:
			draw_rect(Rect2(Vector2(wx - h * 0.15, wy - h * 0.10), Vector2(h * 0.30, h * 0.20)), wheel, true)
	# Carroceria: silueta redondeada (morro a +X).
	var pts := PackedVector2Array([
		Vector2(-hw + 6, -hh), Vector2(hw - 10, -hh), Vector2(hw - 3, -hh * 0.55),
		Vector2(hw, 0), Vector2(hw - 3, hh * 0.55), Vector2(hw - 10, hh),
		Vector2(-hw + 6, hh), Vector2(-hw + 1, hh * 0.6), Vector2(-hw, 0), Vector2(-hw + 1, -hh * 0.6),
	])
	draw_colored_polygon(pts, paint)
	draw_polyline(pts + PackedVector2Array([pts[0]]), outline, 2.0)
	# Capo (mas claro) y maletero con lineas de panel.
	draw_rect(Rect2(Vector2(w * 0.18, -hh * 0.84), Vector2(w * 0.24, hh * 1.68)), paint.lightened(0.10), true)
	draw_rect(Rect2(Vector2(-hw + 7, -hh * 0.84), Vector2(w * 0.15, hh * 1.68)), paint.lightened(0.05), true)
	draw_line(Vector2(w * 0.18, -hh * 0.84), Vector2(w * 0.18, hh * 0.84), paint.darkened(0.25), 1.5)
	draw_line(Vector2(-hw + 7 + w * 0.15, -hh * 0.84), Vector2(-hw + 7 + w * 0.15, hh * 0.84), paint.darkened(0.25), 1.5)
	# Zona de cabina.
	draw_rect(Rect2(Vector2(-w * 0.16, -hh * 0.8), Vector2(w * 0.30, hh * 1.6)), paint.darkened(0.16), true)
	# Parabrisas y luneta trapezoidales.
	var glass := Color(0.42, 0.55, 0.64, 0.92)
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.14, -hh * 0.72), Vector2(w * 0.225, -hh * 0.56), Vector2(w * 0.225, hh * 0.56), Vector2(w * 0.14, hh * 0.72),
	]), glass)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.16, -hh * 0.66), Vector2(-w * 0.235, -hh * 0.50), Vector2(-w * 0.235, hh * 0.50), Vector2(-w * 0.16, hh * 0.66),
	]), glass.darkened(0.15))
	# Ventanillas laterales y brillo diagonal del lado NO en el techo.
	draw_rect(Rect2(Vector2(-w * 0.12, -hh * 0.88), Vector2(w * 0.22, hh * 0.18)), glass.darkened(0.25), true)
	draw_rect(Rect2(Vector2(-w * 0.12, hh * 0.70), Vector2(w * 0.22, hh * 0.18)), glass.darkened(0.25), true)
	draw_line(Vector2(-w * 0.10, -hh * 0.5), Vector2(w * 0.08, -hh * 0.25), Color(1, 1, 1, 0.16), 3.0)
	# Retrovisores.
	draw_rect(Rect2(Vector2(w * 0.11, -hh - 4.0), Vector2(5, 4)), paint.darkened(0.1), true)
	draw_rect(Rect2(Vector2(w * 0.11, hh), Vector2(5, 4)), paint.darkened(0.1), true)
	# Faros (delante) y pilotos (detras).
	draw_circle(Vector2(hw - 4, -hh * 0.55), 3.4, Color(0.95, 0.92, 0.70))
	draw_circle(Vector2(hw - 4, hh * 0.55), 3.4, Color(0.95, 0.92, 0.70))
	draw_rect(Rect2(Vector2(-hw + 1, -hh * 0.62), Vector2(3.5, 6)), Color(0.75, 0.15, 0.14), true)
	draw_rect(Rect2(Vector2(-hw + 1, hh * 0.62 - 6.0), Vector2(3.5, 6)), Color(0.75, 0.15, 0.14), true)
	# Deterioro apocaliptico determinista: oxido, cristal estrellado, puerta abierta.
	if vr.randf() < 0.35:
		for i in 3:
			draw_circle(Vector2(vr.randf_range(-hw * 0.7, hw * 0.7), vr.randf_range(-hh * 0.8, hh * 0.8)), vr.randf_range(2.0, 5.0), Color(0.42, 0.26, 0.12, 0.65))
	if vr.randf() < 0.2:
		var cx: float = vr.randf_range(-w * 0.1, w * 0.2)
		for i in 5:
			var ang: float = vr.randf() * TAU
			draw_line(Vector2(cx, 0), Vector2(cx, 0) + Vector2.RIGHT.rotated(ang) * vr.randf_range(4.0, 9.0), Color(0.9, 0.95, 1.0, 0.5), 1.2)
	if vr.randf() < 0.15:
		var side: float = 1.0 if vr.randf() < 0.5 else -1.0
		var door := PackedVector2Array([
			Vector2(-w * 0.02, side * hh), Vector2(w * 0.12, side * hh),
			Vector2(w * 0.16, side * (hh + h * 0.26)), Vector2(0.0, side * (hh + h * 0.22)),
		])
		draw_colored_polygon(door, paint.darkened(0.08))
		draw_polyline(door + PackedVector2Array([door[0]]), outline, 1.5)


# --- Edificio pseudo-3D ----------------------------------------------------------

func _draw_building(body: Color, outline: Color, vr: RandomNumberGenerator) -> void:
	var w: float = _size.x
	var h: float = _size.y
	var half := _size * 0.5
	var is_house: bool = data != null and data.category == &"house"
	# Altura visual de la fachada: los bloques grandes se leen mas altos.
	var wall_h: float = clampf(h * 0.22, 16.0, 34.0) if is_house else clampf(h * 0.30, 8.0, 14.0)
	# Paleta por edificio: variacion determinista de tono y valor.
	var shift: float = vr.randf_range(-0.09, 0.09)
	var roof: Color = body.lightened(maxf(0.0, shift)).darkened(maxf(0.0, -shift))
	roof.h = wrapf(roof.h + vr.randf_range(-0.03, 0.05), 0.0, 1.0)
	# 1. Sombra proyectada al SE del volumen completo.
	draw_rect(Rect2(-half + SHADOW_OFFSET * (1.0 + wall_h * 0.02), _size), Color(0, 0, 0, 0.30), true)
	# 2. Fachada sur visible (pared frontal en sombra parcial).
	var facade: Color = roof.darkened(0.35)
	draw_rect(Rect2(Vector2(-half.x, half.y - wall_h), Vector2(w, wall_h)), facade, true)
	draw_line(Vector2(-half.x, half.y), Vector2(half.x, half.y), outline, 2.0)
	# 3. Franja este en sombra (lado opuesto a la luz).
	draw_rect(Rect2(Vector2(half.x - 5.0, -half.y - wall_h * 0.4), Vector2(5.0, h)), roof.darkened(0.45), true)
	# Detalles de fachada: ventanas tapiadas y puerta (solo en casas).
	if is_house and wall_h > 15.0:
		var win_count: int = maxi(1, int(w / 62.0))
		for i in win_count:
			var wx: float = -half.x + w * (float(i) + 0.5) / float(win_count)
			var win := Rect2(Vector2(wx - 9.0, half.y - wall_h + 5.0), Vector2(18.0, wall_h - 12.0))
			draw_rect(win, Color(0.10, 0.10, 0.12), true)
			draw_line(win.position + Vector2(1, 2), win.end - Vector2(1, 2), Color(0.45, 0.33, 0.18), 3.0)
			draw_line(Vector2(win.end.x - 1, win.position.y + 2), Vector2(win.position.x + 1, win.end.y - 2), Color(0.42, 0.30, 0.16), 3.0)
		if vr.randf() < 0.7:
			var door := Rect2(Vector2(-9.0 + vr.randf_range(-w * 0.2, w * 0.2), half.y - wall_h + 3.0), Vector2(18.0, wall_h - 3.0))
			draw_rect(door, Color(0.16, 0.12, 0.09), true)
			draw_rect(door, outline, false, 1.5)
	# Grieta en la fachada.
	if vr.randf() < 0.5:
		var gx: float = vr.randf_range(-half.x * 0.7, half.x * 0.7)
		draw_line(Vector2(gx, half.y), Vector2(gx + vr.randf_range(-6.0, 6.0), half.y - wall_h * 0.7), outline, 1.5)
	# 4. Plano de techo desplazado hacia arriba wall_h.
	var roof_rect := Rect2(Vector2(-half.x, -half.y - wall_h), Vector2(w, h))
	draw_rect(roof_rect, roof, true)
	draw_rect(roof_rect, outline, false, 3.0)
	# Highlight NO del parapeto (bordes norte y oeste iluminados).
	draw_line(roof_rect.position + Vector2(2, 2.5), roof_rect.position + Vector2(w - 2, 2.5), roof.lightened(0.18), 3.0)
	draw_line(roof_rect.position + Vector2(2.5, 2), roof_rect.position + Vector2(2.5, h - 2), roof.lightened(0.14), 3.0)
	# Gravilla del techo: punteado tenue.
	for i in int(w * h / 2400.0):
		draw_circle(roof_rect.position + Vector2(vr.randf() * w, vr.randf() * h), 1.4, roof.darkened(0.12))
	# Mancha de agua.
	if vr.randf() < 0.45:
		_ellipse(roof_rect.get_center() + Vector2(vr.randf_range(-w * 0.2, w * 0.2), vr.randf_range(-h * 0.2, h * 0.2)), Vector2(vr.randf_range(9.0, 18.0), vr.randf_range(6.0, 12.0)), Color(0, 0, 0, 0.10))
	if is_house and w > 70.0 and h > 70.0:
		# Unidad de AC con ventilador y sombra propia.
		var ac := roof_rect.position + Vector2(w * vr.randf_range(0.22, 0.66), h * vr.randf_range(0.22, 0.6))
		draw_rect(Rect2(ac + Vector2(3, 4), Vector2(20, 16)), Color(0, 0, 0, 0.25), true)
		draw_rect(Rect2(ac, Vector2(20, 16)), Color(0.60, 0.63, 0.66), true)
		draw_rect(Rect2(ac, Vector2(20, 16)), outline, false, 1.5)
		draw_circle(ac + Vector2(10, 8), 5.5, Color(0.34, 0.37, 0.41))
		draw_circle(ac + Vector2(10, 8), 2.0, Color(0.2, 0.22, 0.25))
		# Respiraderos.
		for i in vr.randi_range(1, 2):
			var vp := roof_rect.position + Vector2(w * vr.randf_range(0.12, 0.8), h * vr.randf_range(0.12, 0.78))
			draw_rect(Rect2(vp + Vector2(2, 2), Vector2(10, 8)), Color(0, 0, 0, 0.2), true)
			draw_rect(Rect2(vp, Vector2(10, 8)), roof.darkened(0.3), true)
			draw_rect(Rect2(vp, Vector2(10, 8)), outline, false, 1.0)
		# Claraboya con brillo.
		if vr.randf() < 0.4 and w > 82.0:
			var sk := roof_rect.position + Vector2(w * vr.randf_range(0.2, 0.66), h * vr.randf_range(0.2, 0.66))
			draw_rect(Rect2(sk, Vector2(16, 12)), Color(0.15, 0.23, 0.33), true)
			draw_line(sk + Vector2(2, 2), sk + Vector2(9, 6), Color(0.6, 0.75, 0.85, 0.5), 2.0)
			draw_rect(Rect2(sk, Vector2(16, 12)), outline, false, 1.2)
		# Antena.
		if vr.randf() < 0.3:
			var ant := roof_rect.position + Vector2(w * 0.85, h * 0.2)
			draw_line(ant, ant + Vector2(0, -12), Color(0.5, 0.52, 0.56), 2.0)
			draw_circle(ant + Vector2(0, -12), 2.0, Color(0.7, 0.72, 0.75))


# --- Resto de categorias ----------------------------------------------------------

func _draw_container(body: Color, detail: Color, _outline: Color, accent: Color, vr: RandomNumberGenerator) -> void:
	_drop_shadow(Vector2(_size.x * 0.52, _size.y * 0.52), 0.7)
	_rect(_size, body)
	# Techo corrugado: lineas transversales alternando tono.
	var lines: int = max(3, int(_size.x / 12.0))
	for i in range(1, lines):
		var x: float = -_size.x * 0.5 + _size.x * float(i) / lines
		draw_line(Vector2(x, -_size.y * 0.5 + 2), Vector2(x, _size.y * 0.5 - 2), body.darkened(0.16) if i % 2 == 0 else body.lightened(0.05), 2.0)
	_outline_rect(_size, accent, 3.0)
	# Highlight NO.
	draw_line(Vector2(-_size.x * 0.5 + 3, -_size.y * 0.5 + 3), Vector2(_size.x * 0.5 - 3, -_size.y * 0.5 + 3), body.lightened(0.2), 2.0)
	draw_line(Vector2(-_size.x * 0.5 + 3, -_size.y * 0.5 + 3), Vector2(-_size.x * 0.5 + 3, _size.y * 0.5 - 3), body.lightened(0.14), 2.0)
	# Puertas con barras y candado en el extremo este.
	var door_w: float = _size.x * 0.14
	_rect(Vector2(door_w, _size.y - 6.0), body.darkened(0.15), Vector2(_size.x * 0.5 - door_w * 0.5 - 2.0, 0))
	for dy in [-_size.y * 0.22, 0.0, _size.y * 0.22]:
		draw_line(Vector2(_size.x * 0.5 - door_w - 2.0, dy), Vector2(_size.x * 0.5 - 2.0, dy), detail, 1.8)
	draw_circle(Vector2(_size.x * 0.5 - door_w * 0.5 - 2.0, _size.y * 0.28), 2.5, Color(0.8, 0.8, 0.55))
	# Oxido en esquinas.
	if vr.randf() < 0.6:
		draw_circle(Vector2(-_size.x * 0.42, _size.y * 0.36), 4.5, Color(0.45, 0.27, 0.12, 0.6))
		draw_circle(Vector2(_size.x * 0.40, -_size.y * 0.30), 3.5, Color(0.45, 0.27, 0.12, 0.5))


func _draw_barrel(body: Color, detail: Color, outline: Color, accent: Color, vr: RandomNumberGenerator) -> void:
	var r: float = max(_size.x, _size.y) * 0.5
	_drop_shadow(Vector2(r, r * 0.85), 0.55)
	# Gradiente falso: claro al NO, oscuro al SE.
	draw_circle(Vector2.ZERO, r, body.darkened(0.22))
	draw_circle(Vector2(-r * 0.10, -r * 0.10), r * 0.85, body)
	draw_circle(Vector2(-r * 0.20, -r * 0.20), r * 0.55, body.lightened(0.13))
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, outline, 2.0)
	draw_arc(Vector2.ZERO, r * 0.68, 0, TAU, 20, detail, 1.5)
	# Tapa central.
	draw_circle(Vector2.ZERO, r * 0.26, accent)
	draw_circle(Vector2(r * 0.06, r * 0.06), r * 0.10, accent.darkened(0.35))
	# Goteo de acento.
	if vr.randf() < 0.5:
		draw_line(Vector2(r * 0.2, r * 0.2), Vector2(r * 0.45, r * 0.72), accent.darkened(0.15), 2.5)


func _draw_tree(body: Color, detail: Color, vr: RandomNumberGenerator) -> void:
	var r: float = max(_size.x, _size.y) * 0.5
	# Sombra de copa grande al SE.
	_ellipse((SHADOW_OFFSET * 1.3).rotated(-rotation), Vector2(r * 1.05, r * 0.8), Color(0, 0, 0, 0.24))
	# Tronco con base mas oscura.
	_rect(Vector2(r * 0.34, r * 0.8), Color(0.30, 0.21, 0.13), Vector2(0, r * 0.45))
	_rect(Vector2(r * 0.34, r * 0.22), Color(0.24, 0.16, 0.10), Vector2(0, r * 0.74))
	# Copa en 3 capas: base oscura de blobs, capa media, lobulos highlight al NO.
	var dark := body.darkened(0.18)
	for i in 5:
		var a: float = TAU * float(i) / 5.0 + vr.randf_range(-0.3, 0.3)
		draw_circle(Vector2(0, -r * 0.1) + Vector2.RIGHT.rotated(a) * r * 0.45, r * 0.55, dark)
	draw_circle(Vector2(0, -r * 0.1), r * 0.72, body)
	draw_circle(Vector2(-r * 0.28, -r * 0.32), r * 0.40, body.lightened(0.14))
	draw_circle(Vector2(-r * 0.05, -r * 0.48), r * 0.28, body.lightened(0.20))
	# Claros/frutos.
	for i in 3:
		draw_circle(Vector2(vr.randf_range(-r * 0.5, r * 0.5), -r * 0.1 + vr.randf_range(-r * 0.4, r * 0.3)), r * 0.07, detail)


func _draw_bush(body: Color, detail: Color, vr: RandomNumberGenerator) -> void:
	var r: float = max(_size.x, _size.y) * 0.5
	_ellipse((SHADOW_OFFSET * 0.7).rotated(-rotation), Vector2(r, r * 0.75), Color(0, 0, 0, 0.22))
	draw_circle(Vector2(-r * 0.35, r * 0.05), r * 0.58, body.darkened(0.12))
	draw_circle(Vector2(r * 0.35, r * 0.05), r * 0.55, body.darkened(0.06))
	draw_circle(Vector2(0, -r * 0.18), r * 0.62, body)
	draw_circle(Vector2(-r * 0.2, -r * 0.32), r * 0.30, body.lightened(0.15))
	draw_circle(Vector2(r * 0.08, -r * 0.12), r * 0.12, detail)
	if vr.randf() < 0.4:
		draw_circle(Vector2(r * 0.3, -r * 0.3), r * 0.08, detail.lightened(0.2))


func _draw_bench(body: Color, detail: Color, outline: Color) -> void:
	_drop_shadow(Vector2(_size.x * 0.52, _size.y * 0.45), 0.5)
	_rect(Vector2(_size.x, _size.y * 0.4), body, Vector2(0, _size.y * 0.1))
	_rect(Vector2(_size.x, _size.y * 0.28), detail, Vector2(0, -_size.y * 0.22))
	_outline_rect(Vector2(_size.x, _size.y * 0.4), outline, 2.0, Vector2(0, _size.y * 0.1))
	# Vetas de madera y highlight NO.
	draw_line(Vector2(-_size.x * 0.45, -_size.y * 0.30), Vector2(_size.x * 0.45, -_size.y * 0.30), detail.lightened(0.15), 1.5)
	draw_line(Vector2(-_size.x * 0.45, _size.y * 0.02), Vector2(_size.x * 0.45, _size.y * 0.02), body.lightened(0.15), 1.5)
	# Patas.
	_rect(Vector2(_size.x * 0.08, _size.y * 0.4), outline, Vector2(-_size.x * 0.4, _size.y * 0.32))
	_rect(Vector2(_size.x * 0.08, _size.y * 0.4), outline, Vector2(_size.x * 0.4, _size.y * 0.32))


func _draw_rock(body: Color, detail: Color, outline: Color, vr: RandomNumberGenerator) -> void:
	var r: float = max(_size.x, _size.y) * 0.5
	_drop_shadow(Vector2(r, r * 0.8), 0.55)
	var pts := PackedVector2Array([
		Vector2(-r, r * 0.2), Vector2(-r * 0.6, -r * 0.7), Vector2(r * 0.1, -r),
		Vector2(r * 0.8, -r * 0.4), Vector2(r, r * 0.3), Vector2(r * 0.3, r * 0.8),
		Vector2(-r * 0.5, r * 0.7),
	])
	draw_colored_polygon(pts, body)
	# Cara SE en sombra.
	draw_colored_polygon(PackedVector2Array([
		Vector2(r, r * 0.3), Vector2(r * 0.3, r * 0.8), Vector2(-r * 0.5, r * 0.7),
		Vector2(-r * 0.1, r * 0.25), Vector2(r * 0.55, r * 0.05),
	]), body.darkened(0.25))
	# Cara NO iluminada.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.6, -r * 0.7), Vector2(r * 0.1, -r), Vector2(r * 0.3, -r * 0.55), Vector2(-r * 0.35, -r * 0.3),
	]), body.lightened(0.14))
	draw_polyline(pts + PackedVector2Array([pts[0]]), outline, 2.0)
	# Grietas.
	draw_line(Vector2(-r * 0.2, -r * 0.1), Vector2(r * 0.15, r * 0.3), outline, 1.3)
	draw_line(Vector2(r * 0.15, r * 0.3), Vector2(r * 0.45, r * 0.15), outline, 1.0)
	draw_circle(Vector2(-r * 0.2, -r * 0.25), r * 0.12, detail)
	# Musgo ocasional.
	if vr.randf() < 0.4:
		draw_circle(Vector2(r * 0.35, r * 0.4), r * 0.09, Color(0.25, 0.32, 0.2, 0.6))


func _draw_fence(body: Color, detail: Color, outline: Color) -> void:
	_drop_shadow(Vector2(_size.x * 0.5, _size.y * 0.5), 0.45)
	_rect(_size, body)
	# Highlight superior (luz NO).
	draw_line(Vector2(-_size.x * 0.5 + 2, -_size.y * 0.5 + 2), Vector2(_size.x * 0.5 - 2, -_size.y * 0.5 + 2), body.lightened(0.18), 2.0)
	var posts: int = max(2, int(_size.x / 12.0))
	for i in posts + 1:
		var x: float = -_size.x * 0.5 + _size.x * float(i) / posts
		draw_line(Vector2(x, -_size.y * 0.5), Vector2(x, _size.y * 0.5), outline, 1.5)
	# Veta horizontal.
	draw_line(Vector2(-_size.x * 0.5, 0), Vector2(_size.x * 0.5, 0), detail, 1.2)


func _draw_pipe(body: Color, detail: Color, outline: Color, accent: Color) -> void:
	_drop_shadow(Vector2(_size.x * 0.5, _size.y * 0.55), 0.5)
	_rect(_size, body)
	_outline_rect(_size, outline, 2.0)
	# Brillo cilindrico: banda clara arriba, oscura abajo.
	draw_line(Vector2(-_size.x * 0.48, -_size.y * 0.28), Vector2(_size.x * 0.48, -_size.y * 0.28), body.lightened(0.22), 3.0)
	draw_line(Vector2(-_size.x * 0.48, _size.y * 0.3), Vector2(_size.x * 0.48, _size.y * 0.3), body.darkened(0.25), 3.0)
	draw_line(Vector2(-_size.x * 0.5, 0), Vector2(_size.x * 0.5, 0), accent, 2.0)
	# Bridas en los extremos.
	_rect(Vector2(_size.x * 0.1, _size.y + 6), detail, Vector2(-_size.x * 0.42, 0))
	_rect(Vector2(_size.x * 0.1, _size.y + 6), detail, Vector2(_size.x * 0.42, 0))


func _draw_sign(_body: Color, detail: Color, outline: Color, accent: Color) -> void:
	_drop_shadow(Vector2(_size.x * 0.4, _size.y * 0.3), 0.5)
	# Poste.
	_rect(Vector2(_size.x * 0.14, _size.y), Color(0.4, 0.4, 0.44))
	# Cartel con highlight.
	_rect(Vector2(_size.x, _size.y * 0.5), accent, Vector2(0, -_size.y * 0.25))
	draw_line(Vector2(-_size.x * 0.46, -_size.y * 0.46), Vector2(_size.x * 0.46, -_size.y * 0.46), accent.lightened(0.2), 2.0)
	_outline_rect(Vector2(_size.x, _size.y * 0.5), outline, 2.0, Vector2(0, -_size.y * 0.25))
	draw_line(Vector2(-_size.x * 0.3, -_size.y * 0.25), Vector2(_size.x * 0.3, -_size.y * 0.25), detail, 2.0)


func _draw_crate(body: Color, detail: Color, outline: Color) -> void:
	_drop_shadow(Vector2(_size.x * 0.52, _size.y * 0.52), 0.55)
	_rect(_size, body)
	_outline_rect(_size, outline, 2.0)
	# Cruz interior tipo caja de madera.
	draw_line(-_size * 0.5, _size * 0.5, detail, 1.5)
	draw_line(Vector2(_size.x * 0.5, -_size.y * 0.5), Vector2(-_size.x * 0.5, _size.y * 0.5), detail, 1.5)
	# Highlight NO: tabla iluminada.
	draw_line(Vector2(-_size.x * 0.5 + 2, -_size.y * 0.5 + 3), Vector2(_size.x * 0.5 - 2, -_size.y * 0.5 + 3), body.lightened(0.2), 2.0)
	draw_line(Vector2(-_size.x * 0.5 + 3, -_size.y * 0.5 + 2), Vector2(-_size.x * 0.5 + 3, _size.y * 0.5 - 2), body.lightened(0.14), 2.0)
