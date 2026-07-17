extends Node
## QA visual del Rework Coop: lanza MainLevel en local_coop con render REAL,
## captura la pantalla dividida en juego, el panel de cartas simultaneo y el
## estado de derribado. Guarda PNGs en user://ui_shots/.
##   godot --path . res://tests/CoopScreenshot.tscn   (NO --headless)

var _p1: Node2D
var _p2: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf != null:
		gf.set("game_mode", "local_coop")
	add_child((load("res://scenes/levels/MainLevel.tscn") as PackedScene).instantiate())

	for _i in 30:
		await get_tree().process_frame
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.get("player_id")) <= 1:
			_p1 = p
		else:
			_p2 = p
	# Separa a los jugadores para ver flechas de companero y ambas camaras.
	if _p1 != null and _p2 != null:
		_p2.global_position = _p1.global_position + Vector2(700, 260)
	for _i in 40:
		await get_tree().process_frame
	await _shot("coop_split_gameplay")

	# Panel de cartas simultaneo (ambos suben de nivel a la vez).
	if _p1 != null and _p2 != null:
		_p1.call("add_experience", 30, true)
		_p2.call("add_experience", 30, true)
	for _i in 20:
		await get_tree().process_frame
	await _shot("coop_cards_simultaneas")

	# Cierra las cartas y captura el derribado.
	var panel: Node = get_tree().get_first_node_in_group("coop_upgrade_panel")
	for _i in 12:
		if panel == null:
			break
		var any: bool = false
		if bool(panel.call("is_open", 1)):
			panel.emit_signal("card_chosen", 1, 0)
			any = true
		if bool(panel.call("is_open", 2)):
			panel.emit_signal("card_chosen", 2, 0)
			any = true
		if not any and not get_tree().paused:
			break
		await get_tree().process_frame
	if _p2 != null:
		_p2.call("take_damage", 9999)
	for _i in 25:
		await get_tree().process_frame
	await _shot("coop_derribado")

	print("coop_screenshot: FIN — %s" % ProjectSettings.globalize_path("user://ui_shots"))
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/%s.png" % shot_name)
	print("coop_screenshot: %s listo" % shot_name)
