extends Node
## QA visual del Sistema Minimapa: lanza MainLevel con render REAL y captura el
## minimapa en solo (normal y ampliado) y en coop de pantalla dividida, con
## jefe/mini-jefe/rescate/elite colocados cerca para verlos en el radar.
## Guarda PNGs en user://ui_shots/.
##   godot --path . res://tests/MinimapScreenshot.tscn   (NO --headless)

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"

var _level: Node


class EliteStub:
	extends Node2D
	var _elite_kind: StringName = &"gigante"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	var gf: Node = get_node_or_null("/root/GameFlow")
	gf.set("game_mode", "solo")
	_level = (load(MAIN_LEVEL) as PackedScene).instantiate()
	add_child(_level)
	for _i in 40:
		await get_tree().process_frame

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		_spawn_stub(["enemies", "boss"], player.global_position + Vector2(900, -500))
		_spawn_stub(["enemies", "miniboss"], player.global_position + Vector2(-600, 400))
		_spawn_stub(["rescue_points"], player.global_position + Vector2(400, 700))
		var elite := EliteStub.new()
		elite.add_to_group("enemies")
		_level.add_child(elite)
		elite.global_position = player.global_position + Vector2(-300, -200)
		# Jefe lejisimo extra para ver la flecha de borde.
		_spawn_stub(["enemies", "boss"], player.global_position + Vector2(20000, 8000))
	await get_tree().create_timer(1.0).timeout
	await _shot("minimap_solo")

	# Ampliado via la accion real de input.
	var ev := InputEventAction.new()
	ev.action = "minimap_expand"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.5).timeout
	await _shot("minimap_solo_expandido")

	# Coop: nivel nuevo en pantalla dividida, jugadores separados.
	_level.queue_free()
	await get_tree().process_frame
	gf.set("game_mode", "local_coop")
	_level = (load(MAIN_LEVEL) as PackedScene).instantiate()
	add_child(_level)
	for _i in 40:
		await get_tree().process_frame
	var p1: Node2D
	var p2: Node2D
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.get("player_id")) <= 1:
			p1 = p
		else:
			p2 = p
	if p1 != null and p2 != null:
		p2.global_position = p1.global_position + Vector2(900, 300)
	await get_tree().create_timer(1.0).timeout
	await _shot("minimap_coop")

	print("minimap_screenshot: FIN — %s" % ProjectSettings.globalize_path("user://ui_shots"))
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0)


func _spawn_stub(groups: Array, pos: Vector2) -> Node2D:
	var n := Node2D.new()
	for g in groups:
		n.add_to_group(g)
	_level.add_child(n)
	n.global_position = pos
	return n


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/%s.png" % shot_name)
	print("minimap_screenshot: %s listo" % shot_name)
