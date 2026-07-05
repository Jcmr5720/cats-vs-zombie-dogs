extends Node
## Autoload "Missions": misiones persistentes con recompensa de sardinas.
## El progreso vive en el SaveManager (claves mission_stat_* / mission_done_*) y
## se escribe en memoria al instante; el disco se toca en los save() normales
## (fin de partida, menus), nunca por kill. Los sistemas de juego reportan eventos
## con add()/report_peak(); al completarse una mision se abonan las sardinas UNA
## sola vez y el HUD muestra un toast (grupo "hud").
##
## Tipos de stat:
## - contador (add): kills, elite_kills, boss_kills, cats_rescued, victories.
## - pico (report_peak): combo_peak (mejor racha), plague_peak (mayor Plaga ganada).

const MISSIONS: Array[Dictionary] = [
	{"id": &"kills_1", "stat": &"kills", "target": 500, "reward": 40, "name": "Exterminador I", "desc": "Elimina 500 perros zombi"},
	{"id": &"kills_2", "stat": &"kills", "target": 2500, "reward": 120, "name": "Exterminador II", "desc": "Elimina 2500 perros zombi"},
	{"id": &"kills_3", "stat": &"kills", "target": 10000, "reward": 400, "name": "Exterminador III", "desc": "Elimina 10000 perros zombi"},
	{"id": &"elites_1", "stat": &"elite_kills", "target": 25, "reward": 60, "name": "Cazador de elites", "desc": "Elimina 25 enemigos elite"},
	{"id": &"elites_2", "stat": &"elite_kills", "target": 150, "reward": 220, "name": "Pesadilla de elites", "desc": "Elimina 150 enemigos elite"},
	{"id": &"bosses_1", "stat": &"boss_kills", "target": 3, "reward": 80, "name": "Mata-jefes", "desc": "Derrota 3 jefes o mini-jefes"},
	{"id": &"bosses_2", "stat": &"boss_kills", "target": 15, "reward": 260, "name": "Terror de la manada", "desc": "Derrota 15 jefes o mini-jefes"},
	{"id": &"cats_1", "stat": &"cats_rescued", "target": 15, "reward": 60, "name": "Colonia unida", "desc": "Rescata 15 gatos"},
	{"id": &"cats_2", "stat": &"cats_rescued", "target": 60, "reward": 200, "name": "Madre de gatos", "desc": "Rescata 60 gatos"},
	{"id": &"combo_1", "stat": &"combo_peak", "target": 30, "reward": 50, "name": "Zarpazo imparable", "desc": "Alcanza una racha de 30 bajas"},
	{"id": &"combo_2", "stat": &"combo_peak", "target": 60, "reward": 160, "name": "Huracan felino", "desc": "Alcanza una racha de 60 bajas"},
	{"id": &"wins_1", "stat": &"victories", "target": 1, "reward": 30, "name": "Primera zona segura", "desc": "Gana tu primera partida"},
	{"id": &"wins_2", "stat": &"victories", "target": 10, "reward": 180, "name": "Guardian de la ciudad", "desc": "Gana 10 partidas"},
	{"id": &"plague_1", "stat": &"plague_peak", "target": 3, "reward": 140, "name": "Domador de plagas", "desc": "Gana una partida en Plaga 3 o mas"},
	{"id": &"plague_2", "stat": &"plague_peak", "target": 5, "reward": 450, "name": "Leyenda de nueve vidas", "desc": "Gana una partida en Plaga 5"},
	# Modo Historia (Fase 09).
	{"id": &"story_1", "stat": &"story_chapter_peak", "target": 3, "reward": 120, "name": "Primera vuelta", "desc": "Completa el Capitulo 3 de la Historia"},
	{"id": &"story_2", "stat": &"story_chapter_peak", "target": 6, "reward": 400, "name": "La gata que abre camino", "desc": "Completa la campaña"},
	{"id": &"story_3", "stat": &"story_extreme", "target": 1, "reward": 500, "name": "Leyenda en Extremo", "desc": "Gana un capitulo de la Historia en Extremo"},
]


## Suma `amount` a un stat contador y evalua las misiones de ese stat.
func add(stat: StringName, amount: int = 1) -> void:
	var save: Node = _save()
	if save == null or amount <= 0:
		return
	var key: String = "mission_stat_%s" % stat
	var value: int = int(save.get_value(key, 0)) + amount
	save.set_value(key, value, false)
	_check_completions(stat, value)


## Registra un valor de pico (racha maxima, mayor Plaga ganada): solo sube.
func report_peak(stat: StringName, value: int) -> void:
	var save: Node = _save()
	if save == null:
		return
	var key: String = "mission_stat_%s" % stat
	if value <= int(save.get_value(key, 0)):
		return
	save.set_value(key, value, false)
	_check_completions(stat, value)


func get_stat(stat: StringName) -> int:
	var save: Node = _save()
	return int(save.get_value("mission_stat_%s" % stat, 0)) if save != null else 0


func is_done(mission_id: StringName) -> bool:
	var save: Node = _save()
	return save != null and bool(save.get_value("mission_done_%s" % mission_id, false))


## Lista de misiones con su progreso actual, para la UI de Progreso.
func get_missions_view() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in MISSIONS:
		var view := m.duplicate()
		view["progress"] = mini(get_stat(m["stat"]), int(m["target"]))
		view["done"] = is_done(m["id"])
		out.append(view)
	return out


func _check_completions(stat: StringName, value: int) -> void:
	var save: Node = _save()
	if save == null:
		return
	for m in MISSIONS:
		if m["stat"] != stat or value < int(m["target"]) or is_done(m["id"]):
			continue
		save.set_value("mission_done_%s" % m["id"], true, false)
		if save.has_method("add_sardines"):
			save.add_sardines(int(m["reward"]))
		_toast(str(m["name"]), int(m["reward"]))


func _toast(mission_name: String, reward: int) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"level_up")
	for hud in get_tree().get_nodes_in_group("hud"):
		if is_instance_valid(hud) and hud.has_method("show_mission_toast"):
			hud.show_mission_toast(mission_name, reward)


func _save() -> Node:
	return get_node_or_null("/root/SaveManager")
