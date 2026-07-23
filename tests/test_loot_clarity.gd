extends Node2D
## FASE 13 — Valida la CLARIDAD del sistema de loot:
##   godot --headless --path . res://tests/TestLootClarity.tscn
##
## 1) El catalogo (LootCatalog) cubre TODOS los power-ups y armas reales: efecto
##    numerico, categoria oficial, rareza y rasgos.
## 2) Los textos de cara al jugador no usan jerga tecnica ni ids internos.
## 3) Las cajas tienen identidad completa (nombre, color, icono, prompt).
## 4) El cableado en arbol funciona: la caja crea su prompt/icono y el pickup su
##    tarjeta de informacion.

const MapInteractableScript := preload("res://scripts/maps/map_interactable.gd")
const PowerUpPickupScript := preload("res://scripts/loot/power_up_pickup.gd")
const WeaponPickupScript := preload("res://scripts/loot/weapon_pickup.gd")
const WeaponManagerScript := preload("res://scripts/weapons/weapon_manager.gd")

## Palabras prohibidas de cara al jugador (lenguaje sencillo, seccion 9).
const JARGON: Array[String] = ["cooldown", "proc chance", "stack", "modifier", "multiplier", "MUTACION:"]

var _failures: Array[String] = []
var _checks: int = 0
var _reported: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_covers_powerups()
	_test_catalog_covers_weapons()
	_test_crates_catalog()
	_test_tips()
	await _test_tree_wiring()
	_finish()


func _check(condition: bool, name: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(name)
		print("  [FALLO] %s" % name)


# --- 1/2: catalogo completo ----------------------------------------------------

func _test_catalog_covers_powerups() -> void:
	var all: Array = PowerUpRegistry.load_powerups(true) + PowerUpRegistry.load_mutations()
	_check(all.size() >= 18, "el registro carga los 18 power-ups")
	for data in all:
		var id: String = str(data.id)
		_check(LootCatalog.effect_line(data.effect_id()) != "",
			"%s tiene linea de efecto numerico" % id)
		var category: StringName = LootCatalog.powerup_category(data)
		_check(category in [&"upgrade", &"companion", &"mutation"],
			"%s cae en una categoria oficial" % id)
		_check(LootCatalog.category_label(category) not in ["", "objeto", "power-up"],
			"%s tiene etiqueta de categoria clara" % id)
		_check(LootCatalog.rarity_label(data.rarity) != "",
			"%s tiene etiqueta de rareza" % id)
		for word in JARGON:
			_check(not data.display_name.contains(word) and not data.description.contains(word),
				"%s sin jerga '%s'" % [id, word])
		# La descripcion es UNA frase corta para la tarjeta.
		_check(data.description.length() > 0 and data.description.length() <= 90,
			"%s con descripcion corta" % id)


func _test_catalog_covers_weapons() -> void:
	var paths: Array = WeaponManagerScript.WEAPON_REGISTRY.duplicate()
	for path in paths.duplicate():
		var data = load(path)
		if data != null and data.evolution != null:
			_check(LootCatalog.is_evolved_weapon(data.evolution),
				"%s: su evolucion se detecta como evolucionada" % data.id)
	for path in paths:
		var data = load(path)
		_check(data != null, "carga %s" % path)
		if data == null:
			continue
		_check(LootCatalog.weapon_traits(data).count("·") == 2,
			"%s tiene 3 rasgos" % data.id)
		_check(LootCatalog.WEAPON_TYPE_ICON.has(data.weapon_type),
			"%s tiene icono por tipo" % data.id)
		_check(LootCatalog.rarity_label(data.rarity) != "",
			"%s tiene rareza catalogada" % data.id)


func _test_crates_catalog() -> void:
	for role in [&"weapon_crate", &"supply_crate", &"special_crate"]:
		_check(LootCatalog.is_crate_role(role), "%s es rol de caja" % role)
		_check(LootCatalog.crate_label(role).begins_with("Caja"), "%s tiene nombre de caja" % role)
		_check(LootCatalog.crate_prompt(role).contains("Golpéala"),
			"%s tiene prompt de apertura" % role)
	_check(not LootCatalog.is_crate_role(&"howl_post"), "howl_post NO es caja")
	# La leyenda del minimapa cubre todos los tipos de botin.
	var legend_kinds: Array = []
	for entry in preload("res://scripts/ui/minimap/minimap_config.gd").LEGEND_ENTRIES:
		legend_kinds.append(entry[0])
	for kind in [&"crate_weapon", &"crate_supply", &"crate_special", &"loot_weapon",
			&"loot_powerup", &"loot_mutation", &"loot_core"]:
		_check(legend_kinds.has(kind), "leyenda del minimapa incluye %s" % kind)


func _test_tips() -> void:
	for tip_id in [&"crate", &"weapon", &"upgrade", &"mutation", &"core", &"swap", &"build_panel"]:
		_check(LootCatalog.tip_text(tip_id) != "", "consejo '%s' definido" % tip_id)


# --- 4: cableado en arbol ------------------------------------------------------

func _test_tree_wiring() -> void:
	# Caja de armas: al entrar al arbol construye icono flotante + prompt.
	var crate := MapInteractableScript.spawn(&"weapon_crate", self, Vector2(100, 100))
	# Pickup de power-up: construye su tarjeta de informacion.
	var powerup: PowerUpData = PowerUpRegistry.load_powerups(true)[0]
	var pickup := PowerUpPickupScript.spawn(powerup, self, Vector2(400, 400))
	# Pickup de arma: tarjeta con nombre/rasgos.
	var weapon = load("res://data/weapons/yarn_bomb.tres")
	var wpickup := WeaponPickupScript.spawn(weapon, self, Vector2(700, 700))
	for i in 5:
		await get_tree().process_frame

	_check(is_instance_valid(crate), "la caja de armas entra al arbol")
	if is_instance_valid(crate):
		var has_prompt: bool = false
		var has_icon: bool = false
		for child in crate.get_children():
			if child is Label and (child as Label).text.contains("Golpéala"):
				has_prompt = true
			if child is IconDrawer:
				has_icon = true
		_check(has_prompt, "la caja construye su prompt de proximidad")
		_check(has_icon, "la caja construye su icono flotante")
		_check(crate.minimap_loot_kind() == &"crate_weapon", "la caja se anuncia al minimapa")

	_check(is_instance_valid(pickup), "el power-up entra al arbol")
	if is_instance_valid(pickup):
		var card_found: bool = _find_card_text(pickup, powerup.display_name)
		_check(card_found, "la tarjeta del power-up muestra su nombre")
		_check(_find_card_text(pickup, LootCatalog.category_label(LootCatalog.powerup_category(powerup))),
			"la tarjeta del power-up muestra su categoria")
		_check(pickup.minimap_loot_kind() == &"loot_powerup", "el power-up se anuncia al minimapa")

	_check(is_instance_valid(wpickup), "el arma del suelo entra al arbol")
	if is_instance_valid(wpickup):
		_check(_find_card_text(wpickup, weapon.display_name), "la tarjeta del arma muestra su nombre")
		_check(_find_card_text(wpickup, "Arma"), "la tarjeta del arma muestra su categoria")
		_check(wpickup.minimap_loot_kind() == &"loot_weapon", "el arma se anuncia al minimapa")


## Busca recursivamente un Label cuyo texto contenga `needle`.
func _find_card_text(root: Node, needle: String) -> bool:
	if root is Label and (root as Label).text.contains(needle):
		return true
	for child in root.get_children():
		if _find_card_text(child, needle):
			return true
	return false


func _finish() -> void:
	if _reported:
		return
	_reported = true
	print("")
	if _failures.is_empty():
		print("TestLootClarity: OK (%d comprobaciones)" % _checks)
	else:
		print("TestLootClarity: %d/%d FALLOS" % [_failures.size(), _checks])
		for f in _failures:
			print("  - %s" % f)
	get_tree().quit(0 if _failures.is_empty() else 1)
