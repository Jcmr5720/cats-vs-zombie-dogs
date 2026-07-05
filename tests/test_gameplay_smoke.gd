extends SceneTree
## Smoke corto de partida: carga MainLevel, deja avanzar fisica/procesos unos
## frames y sale por cierre ordenado de audio para detectar errores de runtime.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var scene: Node = load("res://scenes/levels/MainLevel.tscn").instantiate()
	root.add_child(scene)
	for _i in 240:
		await process_frame
	var audio: Node = root.get_node_or_null("AudioManager")
	if audio == null:
		audio = root.get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	scene.queue_free()
	await process_frame
	print("test_gameplay_smoke: OK")
	quit(0)
