extends Node2D
## Orquesta las armas activas del jugador (Fase 04). Sustituye al antiguo AutoWeapon:
## el jugador empieza con la Pistola Gatuna y puede sumar hasta 4 armas distintas,
## cada una como un WeaponBase hijo. Mantiene los modificadores globales de stats
## (los upgrades de dano/cooldown/rango/proyectil del pool clasico) y calcula las
## sinergias con companeros una vez por frame para que las armas las consulten.

const WeaponData = preload("res://scripts/weapons/weapon_data.gd")
const WEAPON_BASE_SCENE = preload("res://scenes/weapons/WeaponBase.tscn")

## Registro de todas las armas disponibles del juego (para cartas y para sumar).
const WEAPON_REGISTRY: Array[String] = [
	"res://data/weapons/cat_pistol.tres",
	"res://data/weapons/yarn_bomb.tres",
	"res://data/weapons/sardine_boomerang.tres",
	"res://data/weapons/laser_pointer.tres",
	"res://data/weapons/spin_scratcher.tres",
	"res://data/weapons/catnip_grenade.tres",
]
const STARTING_WEAPON: String = "res://data/weapons/cat_pistol.tres"

signal weapons_changed(snapshots: Array)
signal synergies_changed(states: Array)

@export var max_weapons: int = 4

var _player: Node2D
var _hud: Node
var _weapons: Array[Node2D] = []

# Modificadores globales acumulados por upgrades de stats clasicos.
var _global_damage: float = 1.0
var _global_cooldown: float = 1.0
var _global_range: float = 1.0
var _global_extra_projectiles: int = 0
var _external_damage: float = 1.0  # bono del jugador (p.ej. Vinculo felino)
# Multiplicadores de mejoras permanentes (Fase 07), fijados al iniciar la partida.
var _permanent_damage: float = 1.0
var _permanent_cooldown: float = 1.0

# Estado de sinergias, recalculado por frame.
var _has_police: bool = false
var _has_medic: bool = false
var _has_engineer: bool = false
var _active_companions: int = 0
## Firma del ultimo estado de sinergias emitido (para no spamear la senal por frame).
var _last_synergy_signature: String = ""
var _player_ref: Node2D


func _ready() -> void:
	add_to_group("weapon_manager")
	_player = get_parent() as Node2D
	_player_ref = _player
	# El HUD se localiza por grupo para no depender de rutas fragiles.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		if hud.has_method("on_weapons_changed"):
			weapons_changed.connect(hud.on_weapons_changed)
		if hud.has_method("on_synergies_changed"):
			synergies_changed.connect(hud.on_synergies_changed)
	_hud = hud
	# Arma inicial.
	var starting: WeaponData = load(STARTING_WEAPON)
	if starting != null:
		add_weapon(starting)


func _process(_delta: float) -> void:
	_recompute_synergies()


# --- Gestion de armas -------------------------------------------------------

func add_weapon(data: WeaponData) -> bool:
	if data == null or not can_add_weapon() or has_weapon(data.id):
		return false
	var weapon := WEAPON_BASE_SCENE.instantiate() as Node2D
	if weapon == null:
		return false
	add_child(weapon)
	weapon.call("setup", data, self, _player)
	_weapons.append(weapon)
	_emit_weapons_changed()
	# Game feel: aviso corto de arma nueva (Fase 04.5).
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("Arma: %s" % data.display_name)
	return true


func level_up_weapon(weapon_id: StringName) -> bool:
	var weapon := get_weapon(weapon_id)
	if weapon == null or weapon.is_max_level():
		return false
	weapon.level_up()
	_emit_weapons_changed()
	# Game feel: aviso corto de mejora de arma (Fase 04.5).
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("%s Nv. %d" % [weapon.data.display_name, weapon.level])
	return true


func has_weapon(weapon_id: StringName) -> bool:
	return get_weapon(weapon_id) != null


func get_weapon(weapon_id: StringName) -> Node2D:
	for weapon in _weapons:
		if is_instance_valid(weapon) and weapon.data != null and weapon.data.id == weapon_id:
			return weapon
	return null


func can_add_weapon() -> bool:
	return _weapons.size() < max_weapons


func get_weapon_count() -> int:
	return _weapons.size()


## Suma de niveles de todas las armas activas (lo usa la dificultad dinamica).
func get_total_weapon_levels() -> int:
	var total: int = 0
	for weapon in _weapons:
		if is_instance_valid(weapon):
			total += int(weapon.level)
	return total


## WeaponData de armas que el jugador AUN no tiene (para cartas de "nueva arma").
func get_available_new_weapons() -> Array:
	var result: Array = []
	if not can_add_weapon():
		return result
	for path in WEAPON_REGISTRY:
		var data: WeaponData = load(path)
		if data != null and not has_weapon(data.id):
			result.append(data)
	return result


## Armas que el jugador tiene y que aun pueden subir de nivel.
func get_upgradable_weapons() -> Array:
	var result: Array = []
	for weapon in _weapons:
		if is_instance_valid(weapon) and not weapon.is_max_level():
			result.append(weapon)
	return result


func get_weapon_snapshots() -> Array:
	var result: Array = []
	for weapon in _weapons:
		if is_instance_valid(weapon) and weapon.has_method("get_snapshot"):
			result.append(weapon.get_snapshot())
	return result


# --- Modificadores globales (upgrades de stats clasicos) --------------------

func multiply_damage(multiplier: float) -> void:
	_global_damage = clampf(_global_damage * multiplier, 0.5, 4.0)


func multiply_cooldown(multiplier: float) -> void:
	_global_cooldown = clampf(_global_cooldown * multiplier, 0.45, 2.0)


func multiply_range(multiplier: float) -> void:
	_global_range = clampf(_global_range * multiplier, 0.5, 1.8)


func add_projectiles(amount: int) -> void:
	_global_extra_projectiles = clampi(_global_extra_projectiles + amount, 0, 3)


func set_external_damage_multiplier(multiplier: float) -> void:
	_external_damage = max(0.1, multiplier)


func set_permanent_damage_mult(multiplier: float) -> void:
	_permanent_damage = max(0.1, multiplier)


func set_permanent_cooldown_mult(multiplier: float) -> void:
	_permanent_cooldown = clampf(multiplier, 0.5, 1.0)


func global_damage_mult() -> float:
	return _global_damage * _external_damage * _permanent_damage


func global_cooldown_mult() -> float:
	return _global_cooldown * _permanent_cooldown


func global_range_mult() -> float:
	return _global_range


func global_extra_projectiles() -> int:
	return _global_extra_projectiles


# --- Sinergias con companeros ----------------------------------------------

func _recompute_synergies() -> void:
	_has_police = false
	_has_medic = false
	_has_engineer = false
	_active_companions = 0
	for companion in get_tree().get_nodes_in_group("companions"):
		if not is_instance_valid(companion):
			continue
		if companion.has_method("is_downed") and companion.is_downed():
			continue
		_active_companions += 1
		var comp_data = companion.get("companion_data")
		if comp_data == null:
			continue
		match comp_data.role:
			&"police":
				_has_police = true
			&"medic":
				_has_medic = true
			&"engineer":
				_has_engineer = true

	# Sinergia defensiva Medico + Rascador Giratorio: reduccion SUTIL del dano al
	# jugador (no invencibilidad). Solo si el medico esta activo y existe el orbital.
	if is_instance_valid(_player_ref) and _player_ref.has_method("set_synergy_damage_reduction"):
		var reduction: float = 0.08 if _has_medic and has_weapon(&"spin_scratcher") else 0.0
		_player_ref.set_synergy_damage_reduction(reduction)

	_emit_synergies_if_changed()


## Lista de sinergias VISIBLES para el HUD/cartas. Solo se listan las que el
## jugador podria activar (tiene el arma implicada); cada una marca si esta activa
## y que companero requiere. Asi el HUD puede mostrar "activa" / "requiere X".
func get_synergy_states() -> Array:
	var states: Array = []
	if has_weapon(&"cat_pistol"):
		states.append({
			"name": "Policia + Pistola",
			"active": _has_police,
			"requirement": "Requiere Gato Policia activo",
			"effect": "+10% dano de la Pistola Gatuna",
		})
	if has_weapon(&"yarn_bomb") or has_weapon(&"catnip_grenade"):
		states.append({
			"name": "Ingeniero + Area",
			"active": _has_engineer,
			"requirement": "Requiere Gato Ingeniero activo",
			"effect": "+10% area y dano de explosivos/zonas",
		})
	if has_weapon(&"spin_scratcher"):
		states.append({
			"name": "Medico + Rascador",
			"active": _has_medic,
			"requirement": "Requiere Gato Medico activo",
			"effect": "-8% dano recibido por el jugador",
		})
	# Colonia: solo se muestra si ya hay al menos un companero en juego.
	if _active_companions > 0:
		states.append({
			"name": "Colonia unida",
			"active": _active_companions >= 3,
			"requirement": "3 companeros activos",
			"effect": "-5% cooldown de todas las armas",
		})
	return states


func _emit_synergies_if_changed() -> void:
	var states: Array = get_synergy_states()
	var signature: String = ""
	for s in states:
		signature += "%s:%s|" % [s["name"], "1" if s["active"] else "0"]
	if signature != _last_synergy_signature:
		_last_synergy_signature = signature
		synergies_changed.emit(states)


## +10% dano: policia->pistola, ingeniero->explosivo/area, medico->orbital.
func synergy_damage_mult(data: WeaponData) -> float:
	var mult: float = 1.0
	if _has_police and data.id == &"cat_pistol":
		mult *= 1.10
	if _has_engineer and data.weapon_type in [&"explosive", &"area"]:
		mult *= 1.10
	if _has_medic and data.weapon_type == &"orbital":
		mult *= 1.10
	return mult


## Con 3+ companeros activos, todas las armas reducen su cooldown 5%.
func synergy_cooldown_mult() -> float:
	return 0.95 if _active_companions >= 3 else 1.0


## Ingeniero amplia el area de explosivos y zonas.
func synergy_area_mult(data: WeaponData) -> float:
	if _has_engineer and data.weapon_type in [&"explosive", &"area"]:
		return 1.10
	return 1.0


func _emit_weapons_changed() -> void:
	weapons_changed.emit(get_weapon_snapshots())
