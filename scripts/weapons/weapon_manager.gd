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
	"res://data/weapons/hairball_launcher.tres",
	"res://data/weapons/claw_wave.tres",
]
const STARTING_WEAPON: String = "res://data/weapons/cat_pistol.tres"

## Tope de evoluciones de arma por partida (no trivializar jefes). Migrado desde
## el antiguo UpgradeManager: desde FASE 12 la evolucion la dispara el nucleo que
## sueltan los jefes, asi que el contador vive donde vive el inventario.
const MAX_EVOLUTIONS_PER_RUN: int = 2

signal weapons_changed(snapshots: Array)
signal synergies_changed(states: Array)

@export var max_weapons: int = 4

var _player: Node2D
var _hud: Node
var _weapons: Array[Node2D] = []
## Evoluciones ya realizadas en esta run (tope MAX_EVOLUTIONS_PER_RUN).
var _evolutions_done: int = 0

# Modificadores globales acumulados por upgrades de stats clasicos.
var _global_damage: float = 1.0
var _global_cooldown: float = 1.0
var _global_range: float = 1.0
var _global_extra_projectiles: int = 0
var _external_damage: float = 1.0  # bono del jugador (p.ej. Vinculo felino)
# Multiplicadores de mejoras permanentes (Fase 07), fijados al iniciar la partida.
var _permanent_damage: float = 1.0
var _permanent_cooldown: float = 1.0
# Multiplicador de dano coop (Fase Coop 1.5): con 2 jugadores disparando el dano
# total no debe duplicarse; se reduce el dano por jugador (~0.85). 1.0 = solo.
var _coop_damage: float = 1.0

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
	# Coop: SOLO el WeaponManager del jugador principal (P1) se conecta al HUD, para
	# que la barra de armas no la pise el P2 (que tambien tiene su propio manager).
	# player_id ya esta fijado (P1=1 por defecto; P2=2 antes de entrar al arbol).
	var is_primary: bool = int(_player.get("player_id")) <= 1 if _player != null else true
	if is_primary:
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
	# FASE 13: confirmacion clara de arma nueva (con su espacio) + sonido propio.
	_loot_toast(LootCatalog.category_toast(&"weapon"),
		"%s añadida al espacio %d" % [data.display_name, _weapons.size()],
		LootCatalog.weapon_traits(data), LootCatalog.category_color(&"weapon"))
	_play_sfx(LootCatalog.category_sfx(&"weapon"))
	return true


func level_up_weapon(weapon_id: StringName) -> bool:
	var weapon := get_weapon(weapon_id)
	if weapon == null or weapon.is_max_level():
		return false
	# Capturar ANTES de subir: describe lo que se acaba de ganar.
	var gained: String = weapon.next_level_description()
	weapon.level_up()
	_emit_weapons_changed()
	# FASE 13: la subida de nivel de UN arma se anuncia con lo que cambia.
	_loot_toast("ARMA MEJORADA", "%s · Nv. %d" % [weapon.data.display_name, weapon.level],
		gained, LootCatalog.category_color(&"weapon"))
	_play_sfx(&"powerup_collect")
	return true


## Sustituye el arma `weapon` por `data` CONSERVANDO SU SLOT: libera la vieja y
## mete la nueva en el mismo indice, asi que funciona aunque el maximo este lleno.
## Base comun de evolve_weapon() y replace_weapon(); no emite juice ni valida nada.
func _swap_slot(weapon: Node2D, data: WeaponData) -> bool:
	if weapon == null or data == null:
		return false
	var index: int = _weapons.find(weapon)
	if index >= 0:
		_weapons.remove_at(index)
	weapon.queue_free()

	var new_weapon := WEAPON_BASE_SCENE.instantiate() as Node2D
	if new_weapon == null:
		return false
	add_child(new_weapon)
	new_weapon.call("setup", data, self, _player)
	_weapons.insert(clampi(index, 0, _weapons.size()), new_weapon)
	_emit_weapons_changed()
	return true


## Quita un arma del inventario y devuelve su WeaponData (null si no la tenia).
## Lo usa el intercambio en el suelo (FASE 12) para volver a soltar la descartada.
func remove_weapon(weapon_id: StringName) -> WeaponData:
	var weapon := get_weapon(weapon_id)
	if weapon == null:
		return null
	var data: WeaponData = weapon.data
	var index: int = _weapons.find(weapon)
	if index >= 0:
		_weapons.remove_at(index)
	weapon.queue_free()
	_emit_weapons_changed()
	return data


## Cambia `old_id` por `data` conservando el slot y devuelve el WeaponData
## descartado, para que quien llama pueda dejarlo en el suelo. Devuelve null si el
## intercambio no era valido (arma inexistente o ya tienes la nueva).
func replace_weapon(old_id: StringName, data: WeaponData) -> WeaponData:
	var weapon := get_weapon(old_id)
	if weapon == null or data == null or has_weapon(data.id):
		return null
	var discarded: WeaponData = weapon.data
	if not _swap_slot(weapon, data):
		return null

	# Feedback deliberadamente MAS SUAVE que el de la evolucion: un intercambio es
	# una decision tactica frecuente, no el momento de la partida.
	Feedback.shake(0.25)
	if is_instance_valid(_player):
		Feedback.hit_effect(_player.global_position, data.visual_color, 0.35, 1.6)
	_loot_toast("ARMA CAMBIADA", "%s → %s" % [discarded.display_name, data.display_name],
		"%s quedó en el suelo" % discarded.display_name, LootCatalog.category_color(&"weapon"))
	_play_sfx(LootCatalog.category_sfx(&"weapon"))
	return discarded


## Arma del inventario que se sacrificaria en un intercambio: la de MENOR nivel y,
## a igualdad, la del slot mas antiguo. Determinista y casi siempre lo que el
## jugador quiere soltar. Devuelve null si no hay armas.
func get_swap_candidate() -> Node2D:
	var best: Node2D = null
	for weapon in _weapons:
		if not is_instance_valid(weapon):
			continue
		if best == null or int(weapon.level) < int(best.level):
			best = weapon
	return best


## Evoluciona el arma elegible mas avanzada (FASE 12: lo dispara el nucleo de
## evolucion que sueltan los jefes, ya no una carta). Elegible = nivel maximo,
## con evolucion definida, que aun no esta en juego y cuyo requisito de power-up
## el jugador ya recogio. Respeta el tope de evoluciones por partida.
func evolve_best_weapon() -> bool:
	if _evolutions_done >= MAX_EVOLUTIONS_PER_RUN:
		return false
	var owned: Array = []
	if is_instance_valid(_player):
		var raw = _player.get("owned_powerups")
		if raw is Array:
			owned = raw

	var best: Node2D = null
	for weapon in get_evolution_ready_weapons():
		var requirement: StringName = weapon.data.evolution_requirement
		if requirement != &"" and not owned.has(requirement):
			continue
		if best == null or int(weapon.level) > int(best.level):
			best = weapon
	if best == null:
		return false
	return evolve_weapon(best.data.id)


## Evoluciona un arma a su WeaponData de evolucion (data.evolution), conservando
## el "slot": se libera el arma vieja y la nueva entra aunque el maximo este lleno.
## La validacion de requisitos (nivel maximo + power-up) la hace evolve_best_weapon();
## aqui solo se ejecuta el reemplazo con juice.
func evolve_weapon(weapon_id: StringName) -> bool:
	var weapon := get_weapon(weapon_id)
	if weapon == null or weapon.data == null or weapon.data.evolution == null:
		return false
	var evolved: WeaponData = weapon.data.evolution as WeaponData
	if evolved == null or has_weapon(evolved.id):
		return false

	# El nombre del arma base se captura antes del swap (que libera el nodo).
	var base_name: String = weapon.data.display_name
	if not _swap_slot(weapon, evolved):
		return false
	_evolutions_done += 1

	# Juice: la evolucion es EL momento de la partida (hitstop + shake + destello).
	Feedback.hitstop(0.14, 0.08)
	Feedback.shake(0.8)
	if is_instance_valid(_player):
		Feedback.hit_effect(_player.global_position, Color(1.0, 0.85, 0.3, 0.95), 0.5, 2.4)
		Feedback.hit_effect(_player.global_position, evolved.visual_color, 0.35, 1.8)
	# FASE 13: la evolucion se explica completa: de que arma viene y que gana.
	_loot_toast(LootCatalog.category_toast(&"core"),
		"%s → %s" % [base_name, evolved.display_name],
		evolved.description, LootCatalog.category_color(&"core"))
	_play_sfx(LootCatalog.category_sfx(&"core"))
	return true


## Armas del jugador listas para evolucionar: nivel maximo + evolucion definida +
## la evolucion aun no esta en juego. El requisito de carta lo valida quien llama.
func get_evolution_ready_weapons() -> Array:
	var result: Array = []
	for weapon in _weapons:
		if not is_instance_valid(weapon) or weapon.data == null:
			continue
		if not weapon.is_max_level() or weapon.data.evolution == null:
			continue
		var evolved: WeaponData = weapon.data.evolution as WeaponData
		if evolved != null and not has_weapon(evolved.id):
			result.append(weapon)
	return result


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
		if data == null or has_weapon(data.id):
			continue
		# No re-ofrecer un arma base si su evolucion ya esta en juego.
		var evolved := data.evolution as WeaponData
		if evolved != null and has_weapon(evolved.id):
			continue
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


## Multiplicador de dano coop por jugador (Fase Coop 1.5). Lo fija PlayerManager en
## coop (0.85); en solo nunca se llama y queda en 1.0.
func set_coop_damage_mult(multiplier: float) -> void:
	_coop_damage = clampf(multiplier, 0.5, 1.0)


func global_damage_mult() -> float:
	return _global_damage * _external_damage * _permanent_damage * _coop_damage


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


## Toast de botin del HUD (FASE 13). Se busca el HUD por grupo (no _hud: el
## manager del P2 no esta conectado a el) y se pasa el player_id para que en
## coop el aviso salga en la mitad correcta.
func _loot_toast(header: String, title: String, body: String, accent: Color) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("show_loot_toast"):
		return
	var pid: int = int(_player.get("player_id")) if is_instance_valid(_player) else 1
	hud.show_loot_toast(header, title, body, accent, pid)


func _play_sfx(sound_name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(sound_name)
