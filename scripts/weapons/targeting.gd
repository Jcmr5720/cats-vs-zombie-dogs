class_name Targeting
extends RefCounted
## Auto-apuntado inteligente (Rework de adictividad). Funciones ESTATICAS y puras
## (sin get_tree): reciben la lista de enemigos y devuelven objetivo/direccion.
## Las usan las armas del jugador (WeaponBase), los compañeros y la torreta.
##
## Filosofia: "al mas cercano" se sustituye por un score barato que pondera
## peligro real (lo que se acerca al jugador), la marca del Gato Policia y,
## segun el arma, densidad (explosivos/zonas), alineacion (pierce) o valor del
## objetivo (laser). La punteria ademas LIDERA el tiro (intercept) para que los
## runners no esquiven las balas "por tontas". Sin homing: la bala sigue recta.

# --- Balance del apuntado (todo ajustable aqui) -----------------------------------

## Radio alrededor del jugador/lider donde un enemigo cuenta como amenaza.
const DANGER_RADIUS: float = 180.0
## Multiplicador de score para amenazas (cerca del jugador Y acercandose).
const DANGER_WEIGHT: float = 1.6
## Multiplicador para el enemigo marcado por el Gato Policia (+20% daño de equipo:
## concentrar fuego en el marcado es la sinergia).
const MARK_BONUS: float = 1.2
## El laser (nuke single-target) multiplica por esto a elites/tanques.
const ELITE_BONUS_LASER: float = 2.5
## Candidatos maximos tras la pasada O(n): acota el trabajo cuadratico (clusters).
const MAX_CANDIDATES: int = 20
## Bins angulares para elegir la mejor "fila" de enemigos (armas con pierce).
const ANGULAR_BINS: int = 16
## Medio ancho del corredor de pierce: enemigos a menos de esto de la linea cuentan.
const PIERCE_CORRIDOR_HALF_WIDTH: float = 48.0
## Minimo de candidatos para molestarse en buscar filas (con pocos, al mejor score).
const PIERCE_MIN_CANDIDATES: int = 3
## Tiempo maximo de intercepcion: mas alla, el lead es especulativo (tiro directo).
const LEAD_MAX_TIME: float = 0.9
## Amortiguacion de la componente LATERAL de la velocidad del blanco. El zigzag de
## los runners es sinusoidal con media ~0: liderarlo al 100% produce overshoot.
const LEAD_DAMPING: float = 0.65


## UNA pasada O(n) sobre el grupo "enemies": arma la lista de candidatos en rango
## con todo lo que el scoring necesita, ordenada por distancia y recortada a
## MAX_CANDIDATES. `origin` = quien dispara; `ref_pos` = jugador/lider (peligro).
static func gather_candidates(enemies: Array, origin: Vector2, ref_pos: Vector2, max_range: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var range_sq: float = max_range * max_range
	for enemy in enemies:
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var pos: Vector2 = (enemy as Node2D).global_position
		var dist_sq: float = origin.distance_squared_to(pos)
		if dist_sq > range_sq:
			continue
		var velocity: Vector2 = Vector2.ZERO
		if enemy is CharacterBody2D:
			velocity = (enemy as CharacterBody2D).velocity
		var hp_value = enemy.get("current_health")
		var elite = enemy.get("_elite_kind")
		result.append({
			"enemy": enemy,
			"pos": pos,
			"dist_sq": dist_sq,
			"ref_dist_sq": ref_pos.distance_squared_to(pos),
			"velocity": velocity,
			"hp": int(hp_value) if hp_value != null else 1,
			"is_marked": enemy.has_meta(&"companion_mark"),
			"is_elite": elite != null and elite != &"",
			"max_range": max_range,
		})
	result.sort_custom(func(a, b): return a["dist_sq"] < b["dist_sq"])
	if result.size() > MAX_CANDIDATES:
		result.resize(MAX_CANDIDATES)
	return result


## Score base comun: cercania al que dispara, bonus de amenaza (cerca del
## jugador/lider Y acercandose a el) y bonus de marca del Policia.
static func score_common(candidate: Dictionary, ref_pos: Vector2) -> float:
	var max_range: float = candidate.get("max_range", 500.0)
	var dist: float = sqrt(float(candidate["dist_sq"]))
	var score: float = 1.0 / (1.0 + dist / maxf(1.0, max_range))
	if float(candidate["ref_dist_sq"]) < DANGER_RADIUS * DANGER_RADIUS:
		var to_ref_pos: Vector2 = ref_pos - candidate["pos"]
		if to_ref_pos != Vector2.ZERO and (candidate["velocity"] as Vector2).dot(to_ref_pos) > 0.0:
			score *= DANGER_WEIGHT
	if candidate["is_marked"]:
		score *= MARK_BONUS
	return score


## Objetivo para balas directas y explosivos: el mejor score comun.
static func pick_projectile_target(candidates: Array[Dictionary], ref_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -INF
	for candidate in candidates:
		var score: float = score_common(candidate, ref_pos)
		if score > best_score:
			best_score = score
			best = candidate
	return best


## Objetivo para el laser (alto daño single-target): premia vida alta y elites,
## para no gastar el nuke en un cachorro de 6 HP.
static func pick_laser_target(candidates: Array[Dictionary], ref_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -INF
	for candidate in candidates:
		var score: float = score_common(candidate, ref_pos) * (1.0 + float(candidate["hp"]) / 100.0)
		if candidate["is_elite"]:
			score *= ELITE_BONUS_LASER
		if score > best_score:
			best_score = score
			best = candidate
	return best


## Direccion para armas con pierce (boomerang): la "fila" con mas valor.
## Bins angulares ponderados por score (+ medio bin a los vecinos) y centroide de
## los enemigos dentro del corredor del bin ganador. Con pocos candidatos, al
## mejor score simple. Devuelve Vector2.ZERO si no hay candidatos.
static func pick_pierce_direction(candidates: Array[Dictionary], origin: Vector2, ref_pos: Vector2) -> Vector2:
	if candidates.is_empty():
		return Vector2.ZERO
	if candidates.size() < PIERCE_MIN_CANDIDATES:
		var single: Dictionary = pick_projectile_target(candidates, ref_pos)
		return origin.direction_to(single["pos"])

	# 1) Pesa cada bin angular con el score de sus enemigos.
	var bins: Array[float] = []
	bins.resize(ANGULAR_BINS)
	bins.fill(0.0)
	for candidate in candidates:
		var angle: float = origin.angle_to_point(candidate["pos"])
		var bin_index: int = wrapi(int(round(angle / TAU * ANGULAR_BINS)), 0, ANGULAR_BINS)
		var score: float = score_common(candidate, ref_pos)
		bins[bin_index] += score
		bins[wrapi(bin_index - 1, 0, ANGULAR_BINS)] += score * 0.5
		bins[wrapi(bin_index + 1, 0, ANGULAR_BINS)] += score * 0.5

	var best_bin: int = 0
	for i in ANGULAR_BINS:
		if bins[i] > bins[best_bin]:
			best_bin = i
	var bin_direction: Vector2 = Vector2.RIGHT.rotated(TAU * float(best_bin) / float(ANGULAR_BINS))

	# 2) Centroide de los enemigos dentro del corredor de esa direccion.
	var centroid: Vector2 = Vector2.ZERO
	var count: int = 0
	for candidate in candidates:
		var offset: Vector2 = (candidate["pos"] as Vector2) - origin
		if offset.dot(bin_direction) <= 0.0:
			continue
		var lateral: float = absf(offset.cross(bin_direction))
		if lateral <= PIERCE_CORRIDOR_HALF_WIDTH:
			centroid += candidate["pos"]
			count += 1
	if count == 0:
		return bin_direction
	return origin.direction_to(centroid / float(count))


## Posicion para zonas (catnip): centroide del racimo mas valioso. Cuenta vecinos
## dentro de `radius` SOLO entre candidatos (<= 20x20 distancias). Devuelve
## Vector2.INF si no hay candidatos (el llamador usa su fallback).
static func pick_area_position(candidates: Array[Dictionary], radius: float, ref_pos: Vector2) -> Vector2:
	if candidates.is_empty():
		return Vector2.INF
	var radius_sq: float = radius * radius
	var best_index: int = 0
	var best_score: float = -INF
	var best_members: Array[Vector2] = []
	for i in candidates.size():
		var center: Vector2 = candidates[i]["pos"]
		var members: Array[Vector2] = []
		var cluster_score: float = 0.0
		for j in candidates.size():
			if center.distance_squared_to(candidates[j]["pos"]) <= radius_sq:
				members.append(candidates[j]["pos"])
				cluster_score += score_common(candidates[j], ref_pos)
		if cluster_score > best_score:
			best_score = cluster_score
			best_index = i
			best_members = members
	if best_members.is_empty():
		return candidates[best_index]["pos"]
	var centroid: Vector2 = Vector2.ZERO
	for pos in best_members:
		centroid += pos
	return centroid / float(best_members.size())


## Direccion de tiro LIDERADA: resuelve el intercept cuadratico |P + V*t| = s*t.
## Antes de resolver, amortigua la componente lateral de la velocidad del blanco
## (el zigzag tiene media ~0). Fallback a tiro directo si no hay solucion o el
## tiempo de intercepcion supera LEAD_MAX_TIME.
static func intercept_direction(origin: Vector2, target_pos: Vector2, target_velocity: Vector2, projectile_speed: float) -> Vector2:
	var to_target: Vector2 = target_pos - origin
	if to_target == Vector2.ZERO:
		return Vector2.RIGHT
	var direct: Vector2 = to_target.normalized()
	if projectile_speed <= 1.0 or target_velocity == Vector2.ZERO:
		return direct

	# Radial completa + lateral amortiguada.
	var radial: Vector2 = direct * target_velocity.dot(direct)
	var lateral: Vector2 = (target_velocity - radial) * LEAD_DAMPING
	var velocity: Vector2 = radial + lateral

	# |P + V*t|^2 = (s*t)^2  ->  (V.V - s^2) t^2 + 2 P.V t + P.P = 0
	var a: float = velocity.dot(velocity) - projectile_speed * projectile_speed
	var b: float = 2.0 * to_target.dot(velocity)
	var c: float = to_target.dot(to_target)
	var t: float = -1.0
	if absf(a) < 0.001:
		# Velocidades casi iguales: ecuacion lineal.
		if absf(b) > 0.001:
			t = -c / b
	else:
		var discriminant: float = b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var sqrt_d: float = sqrt(discriminant)
			var t1: float = (-b - sqrt_d) / (2.0 * a)
			var t2: float = (-b + sqrt_d) / (2.0 * a)
			t = minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	if t <= 0.0 or t > LEAD_MAX_TIME:
		return direct
	return (to_target + velocity * t).normalized()
