extends SceneTree
## Test headless de generacion de mundo (correr con: godot --headless -s tests/test_world_gen.gd).
## Verifica la seed por run (Fase 1) y el determinismo del layout por seed.


func _init() -> void:
	_test_run_seed()
	_test_layout_determinism()
	_test_road_continuity()
	_test_park_trail_continuity()
	_test_chunk_generation_all_biomes()
	_test_no_footprint_overlaps()
	print("test_world_gen: OK")
	quit(0)


## Ningun par de obstaculos debe solaparse (AABB de su footprint real) y cada
## footprint debe vivir integro dentro de su chunk (garantia cross-chunk).
func _test_no_footprint_overlaps() -> void:
	var maps := [
		"res://data/maps/neighborhood_map.tres",
		"res://data/maps/park_map.tres",
		"res://data/maps/industrial_alley_map.tres",
	]
	for seed_value in [111111111, 987654321]:
		for path in maps:
			var mgr := Node2D.new()
			mgr.set_script(load("res://scripts/maps/map_chunk_manager.gd"))
			root.add_child(mgr)
			mgr.obstacle_scene = load("res://scenes/maps/Obstacle.tscn")
			mgr.world_seed = seed_value
			mgr.generate(load(path), Vector2.ZERO)
			var rects: Array[Rect2] = []
			for chunk in mgr.get_children():
				var obstacles: Node = chunk.get_node_or_null("Obstacles")
				if obstacles == null:
					continue
				var chunk_rect := Rect2((chunk as Node2D).position, Vector2(1024.0, 1024.0))
				for obs in obstacles.get_children():
					var size: Vector2 = obs.get_footprint_size()
					var c: float = absf(cos((obs as Node2D).rotation))
					var s: float = absf(sin((obs as Node2D).rotation))
					var he := Vector2(c * size.x + s * size.y, s * size.x + c * size.y) * 0.5
					var global_pos: Vector2 = (chunk as Node2D).position + (obs as Node2D).position
					var aabb := Rect2(global_pos - he, he * 2.0)
					assert(chunk_rect.grow(0.5).encloses(aabb),
						"footprint fuera de su chunk en %s seed %d: %s" % [path, seed_value, aabb])
					rects.append(aabb)
			for i in rects.size():
				for j in range(i + 1, rects.size()):
					assert(not rects[i].grow(-0.5).intersects(rects[j].grow(-0.5)),
						"solape en %s seed %d: %s vs %s" % [path, seed_value, rects[i], rects[j]])
			print("  sin solapes: %s seed=%d obstaculos=%d" % [path, seed_value, rects.size()])
			mgr.queue_free()


## Genera chunks reales (con obstaculos instanciados) en los 3 biomas.
func _test_chunk_generation_all_biomes() -> void:
	var maps := [
		"res://data/maps/neighborhood_map.tres",
		"res://data/maps/park_map.tres",
		"res://data/maps/industrial_alley_map.tres",
	]
	for path in maps:
		var mgr := Node2D.new()
		mgr.set_script(load("res://scripts/maps/map_chunk_manager.gd"))
		root.add_child(mgr)
		mgr.obstacle_scene = load("res://scenes/maps/Obstacle.tscn")
		mgr.world_seed = 555555555
		mgr.generate(load(path), Vector2.ZERO)
		assert(mgr.get_active_chunk_count() > 0, "chunks generados en %s" % path)
		assert(mgr.get_active_obstacle_count() > 0, "obstaculos generados en %s" % path)
		print("  %s -> chunks=%d obstaculos=%d" % [path, mgr.get_active_chunk_count(), mgr.get_active_obstacle_count()])
		mgr.queue_free()


## Los chunks vecinos deben compartir exactamente las mismas lineas viales globales:
## la via en la frontera local 1024 del chunk (x,y) es la via local 0 del chunk (x+1,y).
func _test_road_continuity() -> void:
	var plan := load("res://scripts/maps/city_plan.gd")
	for seed_value in [111111111, 424242424]:
		for cx in range(-3, 3):
			var a: Dictionary = plan.roads_for_chunk(seed_value, &"neighborhood", Vector2i(cx, 0))
			var b: Dictionary = plan.roads_for_chunk(seed_value, &"neighborhood", Vector2i(cx + 1, 0))
			var a_border: Array = a["v_roads"].filter(func(r: Dictionary) -> bool: return absf(float(r["local_pos"]) - 1024.0) < 0.5)
			var b_border: Array = b["v_roads"].filter(func(r: Dictionary) -> bool: return absf(float(r["local_pos"])) < 0.5)
			assert(a_border.size() == b_border.size(), "misma via de frontera en ambos chunks")
			for i in a_border.size():
				assert(a_border[i]["kind"] == b_border[i]["kind"], "misma clase de via en la frontera")
				assert(int(a_border[i]["index"]) == int(b_border[i]["index"]), "mismo indice global de linea")
		# La avenida garantizada cada 4 indices debe existir siempre.
		var av: Dictionary = plan.road_at_line(seed_value, &"neighborhood", &"v", 8)
		assert(not av.is_empty() and av["kind"] == &"avenue", "avenida garantizada en indices multiplos de 4")


## El sendero del parque es funcion global de X: mismo Y en la frontera de chunks.
func _test_park_trail_continuity() -> void:
	var plan := load("res://scripts/maps/city_plan.gd")
	for seed_value in [123456789, 999999999]:
		for row in range(-2, 3):
			var border_x: float = 5.0 * 1024.0
			var y1: float = plan.park_trail_y(seed_value, row, border_x)
			var y2: float = plan.park_trail_y(seed_value, row, border_x)
			assert(is_equal_approx(y1, y2), "el sendero es una funcion pura de x")


func _test_run_seed() -> void:
	var gf_script := load("res://scripts/systems/game_flow_manager.gd")
	var gf: Node = gf_script.new()
	var s1: int = gf.get_run_seed()
	assert(s1 != 0, "la seed de run nunca debe ser 0")
	assert(gf.get_run_seed() == s1, "la seed debe ser estable durante la run")
	gf.free()


func _test_layout_determinism() -> void:
	var generator := load("res://scripts/maps/biome_layout_generator.gd")
	var map_data = load("res://data/maps/neighborhood_map.tres")
	var a: Dictionary = generator.generate(map_data, Vector2i(3, -2), 123456789)
	var b: Dictionary = generator.generate(map_data, Vector2i(3, -2), 123456789)
	assert(str(a) == str(b), "misma seed + mismo chunk => mismo layout")
	var c: Dictionary = generator.generate(map_data, Vector2i(3, -2), 987654321)
	assert(str(a) != str(c), "seeds distintas => layouts distintos")
