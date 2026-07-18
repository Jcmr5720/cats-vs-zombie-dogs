extends Node
## QA visual de la renovación tipográfica: captura el HUD en cada estado
## (combate, boss, cartas, victoria, derrota), el panel de cartas coop y la
## variante de accesibilidad "Muy grande". Guarda PNGs en user://ui_shots/,
## con la resolución actual en el nombre. Render REAL (NO --headless):
##   godot --path . --resolution 1280x720 res://tests/TypographyScreenshot.tscn

const CARDS: Array[Dictionary] = [
	{"name": "Garra afilada", "description": "Aumenta el daño de tus armas un 15%.",
		"rarity": &"common", "type_label": "Stat", "affects": "Daño"},
	{"name": "Última oportunidad", "description": "Revive una vez con el 50% de vida máxima.",
		"rarity": &"epic", "type_label": "Mejora", "affects": "Supervivencia"},
	{"name": "Bumerán gatuno", "description": "Nueva arma: bumerán que atraviesa enemigos.",
		"rarity": &"rare", "type_label": "Arma", "affects": "Arsenal"},
]

const SUMMARY: Dictionary = {
	"victory": true, "victory_message": "VICTORIA", "map_name": "Callejón Industrial",
	"time": 312.0, "kills": 487, "cats": 3, "level": 14, "bosses": 1,
	"sardines_earned": 220, "total_sardines": 1240,
}

var _suffix: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	var size: Vector2i = DisplayServer.window_get_size()
	_suffix = "_%dx%d" % [size.x, size.y]

	await _capture_hud_states("")

	# Variante de accesibilidad: texto Muy grande (y restaurar al final).
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null:
		var original: String = str(settings.get_value("text_size", "normal"))
		settings.set_value("text_size", "muy_grande")
		await get_tree().process_frame
		await _capture_hud_states("_grande")
		settings.set_value("text_size", original)

	# Panel de cartas coop (dos columnas simultáneas).
	await _capture_coop_cards()

	print("typography_screenshot: FIN — %s" % ProjectSettings.globalize_path("user://ui_shots"))
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0)


func _capture_hud_states(tag: String) -> void:
	var hud: CanvasLayer = (load("res://scenes/ui/HUD.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	# Estado de combate: stats, tiempo, fase, objetivo, armas, racha.
	hud.on_health_changed(64, 100)
	hud.on_experience_changed(35, 60)
	hud.on_level_changed(7)
	hud.on_time_updated(154.0)
	hud.on_companions_changed(2, 4)
	hud.set_objective_text("Sobrevive")
	hud.set_phase_info("Enemigos pesados · 2:26")
	hud.on_weapons_changed([
		{"color": Color(1.0, 0.7, 0.3), "weapon_type": &"projectile", "level": 3, "display_name": "Pistola Gatuna"},
		{"color": Color(0.5, 0.9, 1.0), "weapon_type": &"boomerang", "level": 2, "display_name": "Bumerán"},
	])
	hud.show_combo(12)
	hud.show_event_message("Compañero unido", 30.0)
	await _shot(hud, "hud_combate" + tag)

	# Boss: barra + aviso de impacto.
	hud.show_boss_bar("Mastín del Pantano Élite", 1400)
	hud.show_announcement("¡MINI-JEFE!", 30.0)
	await _shot(hud, "hud_boss" + tag)
	hud.hide_boss_bar()

	# Cartas de mejora (en juego real el árbol está pausado durante la elección;
	# el panel y sus tweens solo procesan en pausa). Sin avisos superpuestos.
	hud.show_combo(0)
	if hud.get("_combo_label") != null:
		(hud.get("_combo_label") as Label).visible = false
	if hud.get("_announcement_label") != null:
		(hud.get("_announcement_label") as Label).visible = false
	if hud.get("event_label") != null:
		(hud.get("event_label") as Label).visible = false
	get_tree().paused = true
	hud.show_upgrade_selection(CARDS.duplicate(true))
	hud.set_upgrade_actions(2, 1)
	await _shot(hud, "hud_cartas" + tag)
	hud.hide_upgrade_selection()
	get_tree().paused = false

	# Victoria y derrota.
	hud.show_victory(SUMMARY)
	await _shot(hud, "hud_victoria" + tag)
	hud.get_node("VictoryPanel").visible = false
	var defeat := SUMMARY.duplicate()
	defeat["victory"] = false
	defeat["victory_message"] = "COLONIA PERDIDA"
	hud.show_defeat(defeat)
	await _shot(hud, "hud_derrota" + tag)

	hud.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_coop_cards() -> void:
	var panel: Control = Control.new()
	panel.set_script(load("res://scripts/ui/coop_upgrade_panel.gd"))
	add_child(panel)
	await get_tree().process_frame
	panel.call("open_for", 1, CARDS.duplicate(true))
	panel.call("open_for", 2, CARDS.duplicate(true))
	await _shot(panel, "coop_cartas")
	panel.queue_free()
	await get_tree().process_frame


func _shot(_owner: Node, name: String) -> void:
	for _i in 10:
		await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/%s%s.png" % [name, _suffix])
	print("typography_screenshot: %s%s listo" % [name, _suffix])
