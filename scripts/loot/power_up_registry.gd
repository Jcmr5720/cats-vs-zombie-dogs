class_name PowerUpRegistry
extends RefCounted
## Registro de todos los power-ups del juego (FASE 12). Mismo patron que
## WeaponManager.WEAPON_REGISTRY y PermanentUpgradeManager.UPGRADE_PATHS: la lista
## es explicita para que un .tres a medio hacer no entre en la tabla de drops por
## accidente. Un test comprueba que la lista y el contenido del disco coinciden.

const POWERUP_PATHS: Array[String] = [
	"res://data/powerups/weapon_damage.tres",
	"res://data/powerups/player_speed.tres",
	"res://data/powerups/max_health.tres",
	"res://data/powerups/weapon_range.tres",
	"res://data/powerups/weapon_cooldown.tres",
	"res://data/powerups/pickup_range.tres",
	"res://data/powerups/extra_projectile.tres",
	"res://data/powerups/companion_damage.tres",
	"res://data/powerups/companion_cooldown.tres",
	"res://data/powerups/medic_boost.tres",
	"res://data/powerups/colony_protection.tres",
	"res://data/powerups/quick_revive.tres",
	"res://data/powerups/colony_bond.tres",
]

const MUTATION_PATHS: Array[String] = [
	"res://data/powerups/mutations/mut_split_shots.tres",
	"res://data/powerups/mutations/mut_savage_power.tres",
	"res://data/powerups/mutations/mut_frenzy.tres",
	"res://data/powerups/mutations/mut_iron_hide.tres",
	"res://data/powerups/mutations/mut_wind_paws.tres",
]


## Power-ups normales (stat + companero). `has_companion` filtra los que solo
## tienen sentido con un companero rescatado, igual que hacia el pool de cartas.
static func load_powerups(has_companion: bool = true) -> Array:
	var result: Array = []
	for path in POWERUP_PATHS:
		var data: PowerUpData = load(path) as PowerUpData
		if data == null:
			push_warning("PowerUpRegistry: no se pudo cargar %s" % path)
			continue
		if data.requires_companion and not has_companion:
			continue
		result.append(data)
	return result


static func load_mutations() -> Array:
	var result: Array = []
	for path in MUTATION_PATHS:
		var data: PowerUpData = load(path) as PowerUpData
		if data != null:
			result.append(data)
	return result


static func get_by_id(powerup_id: StringName) -> PowerUpData:
	for path in POWERUP_PATHS + MUTATION_PATHS:
		var data: PowerUpData = load(path) as PowerUpData
		if data != null and data.id == powerup_id:
			return data
	return null
