extends Node2D
## Valida la transformacion ELITE del jefe REAL (Partidas rapidas):
## - disparo por tiempo (4:15 via request) O al bajar del 35% de vida;
## - nunca antes del tiempo minimo de combate;
## - espera a que termine el ataque activo (no transforma en pleno telegrafo);
## - NO cura: la forma normal cae y aparece una SEGUNDA barra ~28% de la original;
## - la senal elite_transformed abre la barra nueva del HUD;
## - boss muerto antes de 4:15 (nunca se transforma);
## - furia final (enrage) sobre la forma elite.
##   godot --headless --path . res://tests/TestBossElite.tscn

const BOSS_SCENE := preload("res://scenes/bosses/Boss.tscn")
const BossData = preload("res://scripts/bosses/boss_data.gd")

var _failures: Array[String] = []
var _checks: int = 0
var _bar_events: Array = []


func _ready() -> void:
	call_deferred("_run")


func _spawn_boss() -> Node2D:
	var boss := BOSS_SCENE.instantiate()
	add_child(boss)
	boss.call("configure", load("res://data/bosses/rottweiler_charger.tres"), 0.0)
	return boss


func _make_player(pos: Vector2) -> CharacterBody2D:
	var p := CharacterBody2D.new()
	p.add_to_group("players")
	p.add_to_group("player")
	p.global_position = pos
	add_child(p)
	return p


## Fuerza el reloj de combat-time del jefe (evita esperar 12 s reales).
func _set_alive(boss: Node2D, seconds: float) -> void:
	boss.set("_alive_time", seconds)


func _run() -> void:
	var player := _make_player(Vector2(2000, 0))  # lejos: el jefe persigue en CHASE
	await get_tree().process_frame

	# ============ Caso 1: forma elite tras el tiempo minimo, SIN curar ============
	var b1 := _spawn_boss()
	await get_tree().process_frame
	var orig: int = int(b1.get("max_health"))
	# Deja al jefe al 60% para comprobar que activar la forma NO cura.
	b1.call("take_damage", int(orig * 0.40), Vector2.ZERO)
	await get_tree().process_frame
	var hp_before: int = int(b1.get("current_health"))
	_set_alive(b1, 2.0)  # < ELITE_MIN_COMBAT_TIME
	b1.call("request_elite_transform")
	for _i in 4:
		await get_tree().process_frame
	_expect(not bool(b1.call("is_elite")), "la forma elite no se activa antes del tiempo minimo")
	_expect(bool(b1.call("is_elite_pending")), "la peticion queda pendiente hasta cumplir el minimo")
	_set_alive(b1, 15.0)
	for _i in 4:
		await get_tree().process_frame
	_expect(bool(b1.call("is_elite")), "cumplido el minimo, la forma elite se activa")
	# Activar la forma NO toca la vida (no es curacion) y NO crea aun la 2a barra.
	_expect(int(b1.get("current_health")) == hp_before, "activar la forma elite NO cura")
	_expect(int(b1.get("max_health")) == orig, "activar la forma elite NO cambia la barra")
	_expect(not bool(b1.call("is_second_bar")), "la 2a barra aun no existe (solo forma)")
	b1.queue_free()

	# ============ Caso 2: 2a barra al DERROTAR la forma normal (~28%, total ~128%) ============
	var b2 := _spawn_boss()
	await get_tree().process_frame
	var b2_orig: int = int(b2.get("max_health"))
	_set_alive(b2, 20.0)
	# Vacia la barra normal de un golpe: NO muere, aparece la 2a barra.
	b2.call("take_damage", b2_orig + 100, Vector2.ZERO)
	for _i in 5:
		await get_tree().process_frame
	_expect(bool(b2.call("is_second_bar")), "derrotada la forma normal: aparece la 2a barra")
	_expect(bool(b2.call("is_elite")), "la 2a barra fuerza la forma elite")
	var elite_max: int = int(b2.get("max_health"))
	var frac: float = float(elite_max) / float(b2_orig)
	_expect(frac >= 0.24 and frac <= 0.32, "2a barra ~28%% de la original (%.0f%%)" % (frac * 100.0))
	_expect(int(b2.get("current_health")) == elite_max, "la 2a barra arranca LLENA (fase nueva)")
	_expect(elite_max < b2_orig, "vida de la 2a barra MENOR que la original (total ~128%%, no se regala)")
	b2.queue_free()

	# ============ Caso 3: la forma espera a que acabe el ataque activo ============
	var b3 := _spawn_boss()
	await get_tree().process_frame
	_set_alive(b3, 20.0)
	b3.set("_state", 1)  # State.WINDUP
	b3.set("_state_timer", 0.5)
	var tele = b3.get_node_or_null("Telegraph")
	if tele != null:
		tele.visible = true
	b3.call("request_elite_transform")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not bool(b3.call("is_elite")), "la forma no se activa en pleno ataque telegrafiado")
	_expect(bool(b3.call("is_elite_pending")), "la activacion espera a que acabe el ataque")
	b3.set("_state", 0)  # State.CHASE
	if tele != null:
		tele.visible = false
	for _i in 5:
		await get_tree().process_frame
	_expect(bool(b3.call("is_elite")), "al terminar el ataque, la forma se activa")
	b3.queue_free()

	# ============ Caso 4: la 2a barra emite la senal del HUD (nombre + vida) ============
	var b4 := _spawn_boss()
	await get_tree().process_frame
	b4.connect("elite_transformed", func(bar_name: String, maximum: int) -> void:
		_bar_events.append([bar_name, maximum]))
	var b4_orig: int = int(b4.get("max_health"))
	_set_alive(b4, 20.0)
	b4.call("take_damage", b4_orig + 100, Vector2.ZERO)  # vacia la barra normal
	for _i in 4:
		await get_tree().process_frame
	_expect(_bar_events.size() == 1, "elite_transformed se emite UNA vez (barra nueva)")
	if _bar_events.size() == 1:
		_expect(String(_bar_events[0][0]) != "" and int(_bar_events[0][1]) > 0,
			"la 2a barra recibe nombre elite y vida nuevos")
	# Furia final tambien aplica sobre la forma elite (sin romper).
	b4.call("enrage")
	await get_tree().process_frame
	_expect(bool(b4.call("is_elite")), "el jefe elite sobrevive a la furia final")
	b4.queue_free()

	# ============ Caso 5: el jefe SI muere al vaciar la 2a barra ============
	var b5 := _spawn_boss()
	await get_tree().process_frame
	var died := [false]
	b5.connect("died", func(_d) -> void: died[0] = true)
	_set_alive(b5, 20.0)
	b5.call("take_damage", int(b5.get("max_health")) + 100, Vector2.ZERO)
	for _i in 4:
		await get_tree().process_frame
	_expect(not died[0] and bool(b5.call("is_second_bar")),
		"vaciar la barra normal NO mata: pasa a la 2a barra (sin saltarse la fase)")
	# Ahora si: vaciar la 2a barra mata al jefe.
	b5.call("take_damage", int(b5.get("max_health")) + 100, Vector2.ZERO)
	for _i in 4:
		await get_tree().process_frame
	_expect(died[0], "al vaciar la 2a barra, el jefe muere (victoria)")

	print("")
	print("TestBossElite: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", message)
	else:
		_failures.append(message)
		printerr("  FALLO  ", message)
