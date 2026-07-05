extends SceneTree
## Smoke headless de UI/flujo solicitado en la tanda de pulido:
## - El titulo del menu principal no se solapa con botones.
## - Historia expone un CheckBox real para omitir cinematicas.
## - Historia tiene boton de abandonar campana y el inicio pasa por prompt.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_main_menu_title_clear()
	_test_story_controls()
	_test_free_play_story_gates()
	_test_shelter_inventory_controls()
	print("test_ui_flow: OK")
	var audio: Node = root.get_node_or_null("AudioManager")
	if audio == null:
		audio = root.get_node_or_null("/root/AudioManager")
	assert(audio != null, "autoload AudioManager disponible para cierre limpio")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	for _i in 5:
		await process_frame
	quit(0)


func _test_main_menu_title_clear() -> void:
	var scene: Control = load("res://scenes/menus/MainMenu.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var title := _find_label(scene, "Cats vs Zombie Dogs")
	assert(title != null, "menu principal tiene titulo")
	var title_rect: Rect2 = title.get_global_rect().grow(4.0)
	for button in _collect_buttons(scene):
		assert(not title_rect.intersects(button.get_global_rect()),
			"titulo no se solapa con boton %s" % button.text)
	scene.queue_free()
	await process_frame
	print("  main menu: titulo separado de botones")


func _test_story_controls() -> void:
	var scene: Control = load("res://scenes/menus/StoryMenu.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var checkbox := _find_checkbox(scene, "Omitir cinematicas")
	assert(checkbox != null, "checkbox real para omitir cinematicas")
	var abandon := _find_button(scene, "Abandonar campaña")
	assert(abandon != null, "boton Abandonar campana existe")
	abandon.pressed.emit()
	await process_frame
	assert(abandon.text == "Confirmar abandono", "abandonar campana pide confirmacion")
	var play := _find_button(scene, "Jugar capitulo")
	assert(play != null, "boton Jugar capitulo existe")
	play.pressed.emit()
	await process_frame
	var prompt_button := _find_button(scene, "Facil")
	assert(prompt_button != null, "jugar abre prompt de dificultad antes de iniciar")
	scene.queue_free()
	await process_frame
	print("  historia: checkbox, abandono y prompt de dificultad OK")


func _test_free_play_story_gates() -> void:
	var scene: Control = load("res://scenes/menus/MapSelectMenu.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var fake_save := FakeSave.new()
	scene.set("_save", fake_save)
	fake_save.cleared = 0
	assert(scene.call("_is_free_play_map_unlocked", &"neighborhood"), "barrio libre al inicio")
	assert(not scene.call("_is_free_play_map_unlocked", &"park"), "parque bloqueado antes de capitulo 2")
	fake_save.cleared = 1
	assert(scene.call("_is_free_play_map_unlocked", &"park"), "parque disponible al desbloquear capitulo 2")
	assert(not scene.call("_is_free_play_map_unlocked", &"industrial_alley"), "industrial bloqueado antes de capitulo 3")
	fake_save.cleared = 2
	assert(scene.call("_is_free_play_map_unlocked", &"industrial_alley"), "industrial disponible al desbloquear capitulo 3")
	scene.queue_free()
	fake_save.free()
	await process_frame
	print("  partida libre: gates por historia OK")


func _test_shelter_inventory_controls() -> void:
	var scene: Control = load("res://scenes/shelter/ShelterMenu.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var inventory := _find_button(scene, "Inventario")
	assert(inventory != null, "refugio tiene boton Inventario")
	var panel := scene.get("_inventory_panel") as PanelContainer
	assert(panel != null, "refugio construye panel de inventario")
	assert(not panel.visible, "inventario inicia oculto")
	inventory.pressed.emit()
	await process_frame
	assert(panel.visible, "boton Inventario abre el panel")
	scene.queue_free()
	await process_frame
	print("  refugio: inventario accesible OK")


func _find_label(node: Node, text: String) -> Label:
	if node is Label and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_label(child, text)
		if found != null:
			return found
	return null


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_checkbox(node: Node, text: String) -> CheckBox:
	if node is CheckBox and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_checkbox(child, text)
		if found != null:
			return found
	return null


func _collect_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_buttons(child))
	return out


class FakeSave:
	extends Node
	var cleared: int = 0

	func get_value(key: String, default_value: Variant = null) -> Variant:
		if key == "story_chapters_cleared":
			return cleared
		return default_value
