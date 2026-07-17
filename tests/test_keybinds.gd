extends Node
## Pruebas del remapeo de teclado (Settings.apply/set/clear_input_overrides).
##   godot --headless --path . res://tests/TestKeybinds.tscn
## Valida: fijar tecla, conflicto rechazado, conservacion de eventos de mando
## del P2, restauracion de defaults y persistencia del diccionario.

var _failures: Array[String] = []
var _checks: int = 0


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		print("FALLO: ", label)


func _ready() -> void:
	call_deferred("_run")


func _keyboard_codes(action: StringName) -> Array[int]:
	var out: Array[int] = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			out.append(int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode))
	return out


func _joypad_count(action: StringName) -> int:
	var n: int = 0
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion or e is InputEventJoypadButton:
			n += 1
	return n


func _run() -> void:
	await get_tree().process_frame
	var settings: Node = get_node_or_null("/root/Settings")
	_check(settings != null, "autoload Settings presente")
	if settings == null:
		_finish()
		return

	# Estado limpio para el test (y al final se restaura).
	settings.clear_input_overrides()

	# --- 1) Fijar una tecla nueva para P1 arriba (T) ------------------------------
	var ok: bool = settings.set_input_override(&"move_up", KEY_T)
	_check(ok, "override aceptado para move_up")
	var codes: Array[int] = _keyboard_codes(&"move_up")
	_check(codes.size() == 1 and codes[0] == int(KEY_T), "move_up quedo SOLO con la tecla nueva")

	# --- 2) Conflicto: la misma tecla en otra accion se rechaza -------------------
	var rejected: bool = settings.set_input_override(&"move_down", KEY_T)
	_check(not rejected, "tecla en uso rechazada (sin duplicados)")
	_check(_keyboard_codes(&"move_down").size() >= 1 and not _keyboard_codes(&"move_down").has(int(KEY_T)),
		"move_down conserva sus teclas originales")

	# --- 3) P2: remapear teclado NO borra los eventos de mando --------------------
	var joypad_before: int = _joypad_count(&"p2_move_left")
	_check(joypad_before > 0, "p2_move_left tiene evento de mando de fabrica")
	settings.set_input_override(&"p2_move_left", KEY_F)
	_check(_joypad_count(&"p2_move_left") == joypad_before, "el mando del P2 se conserva al remapear")
	var p2_codes: Array[int] = _keyboard_codes(&"p2_move_left")
	_check(p2_codes.size() == 1 and p2_codes[0] == int(KEY_F), "teclado del P2 remapeado a F")

	# --- 4) Persistencia: el diccionario guarda ambos overrides -------------------
	var overrides: Dictionary = settings.get_value("input_overrides", {})
	_check(int(overrides.get("move_up", 0)) == int(KEY_T) and int(overrides.get("p2_move_left", 0)) == int(KEY_F),
		"overrides persistidos en settings")

	# --- 5) Restaurar: vuelve al InputMap de project.godot ------------------------
	settings.clear_input_overrides()
	var restored: Array[int] = _keyboard_codes(&"move_up")
	_check(restored.size() == 2, "move_up restaurado (W + flecha)")
	_check(dict_empty(settings.get_value("input_overrides", {})), "overrides vacios tras restaurar")

	_finish()


func dict_empty(v: Variant) -> bool:
	return typeof(v) == TYPE_DICTIONARY and (v as Dictionary).is_empty()


func _finish() -> void:
	print("test_keybinds: %d checks, %d fallos" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("test_keybinds: OK")
	else:
		for f in _failures:
			print("  - ", f)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0 if _failures.is_empty() else 1)
