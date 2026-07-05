class_name WorldSeedManager
extends RefCounted
## Utilidades de seed para mapas procedurales. La seed global se combina con el
## bioma, coordenadas de chunk y salts de capa para que cada decision sea estable.


static func resolve_seed(map_data: MapData, override_seed: int = 0) -> int:
	if override_seed != 0:
		return abs(override_seed)
	var key: String = str(map_data.id if map_data != null else &"map")
	return abs(hash("cats-vs-zombie-dogs:%s" % key))


static func chunk_seed(world_seed: int, biome: StringName, coord: Vector2i, salt: int = 0) -> int:
	return abs(hash("%d:%s:%d:%d:%d" % [world_seed, str(biome), coord.x, coord.y, salt]))


static func layer_rng(world_seed: int, biome: StringName, coord: Vector2i, layer: StringName) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_seed(world_seed, biome, coord, hash(str(layer)))
	return rng


static func rand01(world_seed: int, biome: StringName, coord: Vector2i, salt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_seed(world_seed, biome, coord, salt)
	return rng.randf()


static func global_noise01(world_seed: int, biome: StringName, x: int, y: int, salt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("%d:%s:g:%d:%d:%d" % [world_seed, str(biome), x, y, salt]))
	return rng.randf()
