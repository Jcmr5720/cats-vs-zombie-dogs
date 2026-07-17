extends RefCounted
## Fuente de terreno del minimapa (Fase correccion). Reconstruye el trazado REAL
## del mundo (calles, senderos, lago, via de tren, manzanas) llamando a las MISMAS
## funciones puras y deterministas que usa el generador del mapa
## (BiomeLayoutGenerator/CityPlan) con la MISMA seed resuelta: la geometria del
## radar coincide 1:1 con el mundo, sin recorrer nodos de la escena.
##
## Rendimiento: cada chunk se genera UNA vez y se cachea (el layout es un
## diccionario pequeno); el presupuesto por tick limita cuantos chunks nuevos se
## calculan por frame. La cache se poda lejos del jugador al superar el maximo.

const CHUNK_SIZE := Vector2(1024.0, 1024.0)

var _map: MapData
var _seed: int = 0
var _layouts: Dictionary = {}
var _resolved: bool = false


## Resuelve MapData + seed desde el MapChunkManager real de la escena (via el
## MapManager, mismo acceso defensivo que usa el overlay F8 del HUD). Devuelve
## true cuando el terreno ya puede generarse.
func resolve(tree: SceneTree) -> bool:
	if _resolved:
		return true
	if tree == null:
		return false
	for manager in tree.get_nodes_in_group("map_manager"):
		if not is_instance_valid(manager):
			continue
		var spawner = manager.get("_obstacle_spawner")
		if spawner == null or not is_instance_valid(spawner):
			continue
		if not (spawner.has_method("get_resolved_seed") and spawner.has_method("get_map_data")):
			continue
		var world_seed: int = int(spawner.get_resolved_seed())
		var map_data = spawner.get_map_data()
		if world_seed != 0 and map_data != null:
			_seed = world_seed
			_map = map_data
			_resolved = true
			return true
	return false


func is_resolved() -> bool:
	return _resolved


func biome() -> StringName:
	return _map.biome if _map != null else &"neighborhood"


## Layout cacheado del chunk (o {} si aun no se genero).
func layout_for(coord: Vector2i) -> Dictionary:
	return _layouts.get(coord, {})


## Garantiza los layouts de los chunks que tocan el rect de mundo dado, generando
## como maximo `budget` nuevos por llamada. Devuelve true si se genero alguno
## (el consumidor debe redibujar).
func ensure_region(world_rect: Rect2, budget: int) -> bool:
	if not _resolved:
		return false
	var from := Vector2i(floori(world_rect.position.x / CHUNK_SIZE.x), floori(world_rect.position.y / CHUNK_SIZE.y))
	var to := Vector2i(floori(world_rect.end.x / CHUNK_SIZE.x), floori(world_rect.end.y / CHUNK_SIZE.y))
	var generated: bool = false
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var coord := Vector2i(x, y)
			if _layouts.has(coord):
				continue
			_layouts[coord] = BiomeLayoutGenerator.generate(_map, coord, _seed)
			generated = true
			budget -= 1
			if budget <= 0:
				_prune(world_rect.get_center())
				return true
	if generated:
		_prune(world_rect.get_center())
	return generated


## Poda la cache: al pasar el maximo, elimina los chunks mas lejanos del centro.
func _prune(center_world: Vector2) -> void:
	const CACHE_MAX: int = 160
	if _layouts.size() <= CACHE_MAX:
		return
	var center := Vector2i(floori(center_world.x / CHUNK_SIZE.x), floori(center_world.y / CHUNK_SIZE.y))
	var coords: Array = _layouts.keys()
	coords.sort_custom(func(a, b) -> bool:
		return Vector2(a - center).length_squared() > Vector2(b - center).length_squared())
	for i in mini(coords.size(), _layouts.size() - CACHE_MAX + 16):
		_layouts.erase(coords[i])
