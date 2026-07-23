extends Node
## Decide QUE suelta cada fuente de botin (FASE 12). Sustituye al UpgradeManager:
## mismas tablas de sorteo, pero sin UI y sin pausar el juego.
##
## No spawnea por iniciativa propia: le piden botin las cajas (map_interactable),
## los enemigos al morir (enemy.gd) y los jefes. Este nodo solo sortea y suelta.
##
## Reglas heredadas del sistema de cartas que SIGUEN vigentes:
## - El peso de rareza lo sube la Caja de Suministros del Refugio, solo en Modo
##   Historia (en Partida libre el reto es puro).
## - Los power-ups de companero no entran en la tabla si no has rescatado ninguno.
##
## Regla nueva: PITY TIMER. Si el jugador pasa demasiado tiempo sin recoger nada,
## el siguiente drop de enemigo esta garantizado. Recorta la varianza (que es lo
## que rompe los soaks) sin subir la media.

const PowerUpPickup := preload("res://scripts/loot/power_up_pickup.gd")
const WeaponPickup := preload("res://scripts/loot/weapon_pickup.gd")
const WeaponData = preload("res://scripts/weapons/weapon_data.gd")

## Probabilidad de que un enemigo COMUN suelte un power-up. Calibrado para 5-8
## drops en una run de ~5 min (~500 muertes comunes). Es la primera palanca que
## hay que bajar si el soak "build" gana demasiado rapido.
const COMMON_DROP_CHANCE: float = 0.012
## Segundos sin recoger ningun power-up tras los que el siguiente drop de enemigo
## se garantiza.
const PITY_SECONDS: float = 45.0

signal loot_dropped(kind: StringName, pos: Vector2)

var _run_time: float = 0.0
var _last_powerup_time: float = 0.0
var _shelter_rarity_cached: float = -1.0
## Multiplicador de cantidad de drops. En coop los dos jugadores se reparten UN
## presupuesto compartido; se sube menos de 2x porque el equipo ya rinde mas.
var _loot_multiplier: float = 1.0


func _ready() -> void:
	add_to_group("loot_director")
	if _is_coop():
		_loot_multiplier = CoopConfig.LOOT_MULTIPLIER


func _process(delta: float) -> void:
	_run_time += delta


# --- Sorteos ----------------------------------------------------------------

## Arma que deberia contener una caja. Si el jugador tiene hueco sale una que le
## FALTE; si el inventario esta lleno sale un DUPLICADO de una suya, que al
## recogerse la sube de nivel. Asi las armas siguen llegando a nivel maximo y
## quedan elegibles para evolucionar.
func roll_weapon(rng: RandomNumberGenerator = null) -> WeaponData:
	var wm: Node = _weapon_manager()
	if wm == null:
		return null

	var candidates: Array = wm.get_available_new_weapons()
	if candidates.is_empty():
		# Inventario lleno (o ya tiene todas): un duplicado mejorable.
		for weapon in wm.get_upgradable_weapons():
			candidates.append(weapon.data)
	if candidates.is_empty():
		return null

	var weights: Array[float] = []
	for data in candidates:
		weights.append(maxf(0.05, float(data.rarity_weight)))
	return candidates[_weighted_pick(weights, rng)] as WeaponData


## Power-up normal (stat o companero). `source` solo se usa para telemetria.
func roll_powerup(_source: StringName = &"enemy", rng: RandomNumberGenerator = null) -> PowerUpData:
	var pool: Array = PowerUpRegistry.load_powerups(_has_any_companion())
	pool = _filter_by_stacks(pool)
	if pool.is_empty():
		return null
	var weights: Array[float] = []
	for data in pool:
		weights.append(_drop_weight(data))
	return pool[_weighted_pick(weights, rng)] as PowerUpData


## Mutacion (premio de jefe). Respeta max_stacks: no repite una ya recogida.
func roll_mutation(rng: RandomNumberGenerator = null) -> PowerUpData:
	var pool: Array = _filter_by_stacks(PowerUpRegistry.load_mutations())
	if pool.is_empty():
		return null
	var weights: Array[float] = []
	for data in pool:
		weights.append(_drop_weight(data))
	return pool[_weighted_pick(weights, rng)] as PowerUpData


# --- Sueltas ----------------------------------------------------------------

func drop_weapon(parent: Node, pos: Vector2, rng: RandomNumberGenerator = null) -> Node2D:
	var data: WeaponData = roll_weapon(rng)
	if data == null or parent == null:
		return null
	RunTelemetry.count(&"weapons_dropped")
	loot_dropped.emit(&"weapon", pos)
	return WeaponPickup.spawn(data, parent, pos)


func drop_powerup(parent: Node, pos: Vector2, source: StringName = &"enemy",
		rng: RandomNumberGenerator = null) -> Node2D:
	var data: PowerUpData = roll_powerup(source, rng)
	if data == null or parent == null:
		return null
	_last_powerup_time = _run_time
	RunTelemetry.count(&"powerups_dropped")
	loot_dropped.emit(&"powerup", pos)
	return PowerUpPickup.spawn(data, parent, pos, _pop())


func drop_mutation(parent: Node, pos: Vector2, rng: RandomNumberGenerator = null) -> Node2D:
	var data: PowerUpData = roll_mutation(rng)
	if data == null or parent == null:
		return null
	RunTelemetry.count(&"mutations_dropped")
	loot_dropped.emit(&"mutation", pos)
	return PowerUpPickup.spawn(data, parent, pos, _pop())


## Nucleo de evolucion de los jefes. Si NINGUN arma es elegible (nadie llego a
## nivel maximo con su requisito) cae a una mutacion, para que el premio del jefe
## nunca se desperdicie.
func drop_evolution_core(parent: Node, pos: Vector2) -> Node2D:
	if parent == null:
		return null
	var wm: Node = _weapon_manager()
	if wm == null or not _has_evolvable_weapon(wm):
		return drop_mutation(parent, pos)
	RunTelemetry.count(&"evolution_cores_dropped")
	loot_dropped.emit(&"evolution_core", pos)
	var node := Area2D.new()
	node.set_script(load("res://scripts/loot/evolution_core.gd"))
	node.position = pos
	node.set("pop_velocity", _pop())
	parent.add_child.call_deferred(node)
	return node


## Tirada de drop de un enemigo comun al morir. Devuelve true si solto algo.
## Los elites llaman con `guaranteed`.
func try_drop_from_enemy(parent: Node, pos: Vector2, guaranteed: bool = false) -> bool:
	if parent == null:
		return false
	var chance: float = COMMON_DROP_CHANCE * _loot_multiplier
	# Pity: demasiado tiempo sin recoger nada garantiza el siguiente drop.
	var pity: bool = _run_time - _last_powerup_time >= PITY_SECONDS
	if not guaranteed and not pity and randf() >= chance:
		return false
	if pity and not guaranteed:
		RunTelemetry.count(&"pity_powerup_granted")
	return drop_powerup(parent, pos, &"elite" if guaranteed else &"enemy") != null


# --- Utilidades -------------------------------------------------------------

## Sorteo ponderado. Con `rng` es DETERMINISTA (lo usan las cajas, cuyo contenido
## forma parte del guion de la semilla); sin el usa el azar global.
func _weighted_pick(weights: Array[float], rng: RandomNumberGenerator = null) -> int:
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return 0
	var roll: float = (rng.randf() if rng != null else randf()) * total
	for index in weights.size():
		roll -= weights[index]
		if roll <= 0.0:
			return index
	return weights.size() - 1


## Peso final: el del .tres, mas el bono de rareza del Refugio para lo no comun.
func _drop_weight(data: PowerUpData) -> float:
	var weight: float = maxf(0.01, data.drop_weight)
	if data.rarity != &"common":
		weight *= 1.0 + _shelter_rarity_bonus()
	return weight


## Quita del pool lo que ya alcanzo su tope de repeticiones en esta run.
func _filter_by_stacks(pool: Array) -> Array:
	var player: Node = _player()
	if player == null:
		return pool
	var owned = player.get("owned_powerups")
	if not (owned is Array):
		return pool
	var result: Array = []
	for data in pool:
		if data.max_stacks > 0 and owned.has(data.effect_id()):
			continue
		result.append(data)
	return result


func _shelter_rarity_bonus() -> float:
	# El Refugio solo mejora la rareza en Modo Historia (Partida libre = puro).
	if not _is_story_run():
		return 0.0
	if _shelter_rarity_cached < 0.0:
		_shelter_rarity_cached = 0.0
		var shelter: Node = get_node_or_null("/root/Shelter")
		if shelter != null and shelter.has_method("get_bonus"):
			_shelter_rarity_cached = clampf(float(shelter.get_bonus("upgrade_rarity_bonus")), 0.0, 0.10)
	return _shelter_rarity_cached


func _has_any_companion() -> bool:
	return not get_tree().get_nodes_in_group("companions").is_empty()


func _has_evolvable_weapon(wm: Node) -> bool:
	var player: Node = _player()
	var owned: Array = []
	if player != null:
		var raw = player.get("owned_powerups")
		if raw is Array:
			owned = raw
	if int(wm.get("_evolutions_done")) >= wm.MAX_EVOLUTIONS_PER_RUN:
		return false
	for weapon in wm.get_evolution_ready_weapons():
		var requirement: StringName = weapon.data.evolution_requirement
		if requirement == &"" or owned.has(requirement):
			return true
	return false


## Rebote inicial del pickup al salir, para que no aparezca clavado en el sitio.
func _pop() -> Vector2:
	return Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 130.0)


func _player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _weapon_manager() -> Node:
	return get_tree().get_first_node_in_group("weapon_manager")


func _is_story_run() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_story_run") and gf.is_story_run()


func _is_coop() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_coop") and gf.is_coop()
