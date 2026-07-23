extends SceneTree
## Utilidad de desarrollo: imprime el guion del Barrio para un rango de semillas,
## para elegir semillas concretas con las que validar a mano cada evento.
##   godot --headless -s tests/seed_scan.gd

func _init() -> void:
	var map = load("res://data/maps/neighborhood_map.tres")
	for world_seed in [1, 7, 11, 42, 99, 555, 1337, 2024, 424242, 987654321]:
		var rs: RunScript = RunScript.generate(map, world_seed)
		print("seed=%-10d evento=%-14s mutacion=%-14s jefe=%-14s apertura=%d"
			% [world_seed, rs.central_event, rs.dominant_mutation, rs.boss_modifier, rs.opening_variant])
	quit(0)
