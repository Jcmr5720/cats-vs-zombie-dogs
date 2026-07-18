class_name RunPhaseConfig
extends RefCounted
## Configuracion CENTRAL de las partidas rapidas por fases (~5 minutos por mapa).
## TODOS los tiempos, composiciones, presupuestos de amenaza y limites viven aqui
## (mismo espiritu que GameBalance: una sola fuente de verdad, sin constantes
## magicas repartidas). El PhaseDirector lee esta tabla y el EnemySpawner recibe
## el perfil de la fase activa via set_phase_profile().
##
## Presupuesto de amenaza: cada enemigo tiene un threat_cost (EnemyData). El
## spawner suma el coste de los enemigos VIVOS que genero y no genera mas si la
## suma superaria el presupuesto de la fase. El presupuesto "se recupera" solo:
## cada muerte libera su coste (ventanas de respiro tras momentos intensos).

enum Phase { INTRO, COMMON_ENEMIES, SPECIAL_ENEMIES, HEAVY_ENEMIES, MINIBOSS, BOSS, ELITE_BOSS, VICTORY, DEFEAT }

# --- Tiempos de fase (segundos desde el inicio; configurables) -------------------
const COMMON_START: float = 20.0
const SPECIAL_START: float = 60.0
const HEAVY_START: float = 110.0
const MINIBOSS_START: float = 155.0
const BOSS_START: float = 200.0
const ELITE_START: float = 255.0
## A los 5:00 se detienen los spawns comunes y arranca la furia final.
const FINAL_FURY_START: float = 300.0
## Limite absoluto: si el jefe sigue vivo aqui, derrota.
const ABSOLUTE_LIMIT: float = 330.0

# --- Arranque inmediato (seccion 2 del diseño) -----------------------------------
# Fase re-balance: manada inicial mas grande y corredores antes — el primer
# minuto era demasiado tranquilo.
const OPENING_PACK_MIN: int = 12
const OPENING_PACK_MAX: int = 16
const OPENING_RUNNERS_TIME: float = 6.0
const OPENING_RUNNERS_COUNT: int = 5

# --- Presion global de proyectiles/zonas (los comprueban los comportamientos) ----
const MAX_ENEMY_PROJECTILES: int = 10
const MAX_HAZARD_ZONES: int = 4

# --- Coop: el presupuesto sube UNA sola vez (el resto del escalado coop ya vive
# --- en GameBalance/EnemySpawner). ------------------------------------------------
const BUDGET_COOP_MULT: float = 1.3

# --- Rutas de datos de enemigos por id (el spawner y los jefes cargan por aqui;
# --- sin escaneo de directorios: funciona igual en builds exportadas) -------------
const ENEMY_DATA_PATHS: Dictionary = {
	&"zombie_dog": "res://data/enemies/normal_zombie_dog.tres",
	&"runner_zombie_dog": "res://data/enemies/runner_zombie_dog.tres",
	&"pup_zombie_dog": "res://data/enemies/pup_zombie_dog.tres",
	&"pack_zombie_dog": "res://data/enemies/pack_zombie_dog.tres",
	&"flanker_zombie_dog": "res://data/enemies/flanker_zombie_dog.tres",
	&"howler_zombie_dog": "res://data/enemies/howler_zombie_dog.tres",
	&"spitter_zombie_dog": "res://data/enemies/spitter_zombie_dog.tres",
	&"infection_carrier_dog": "res://data/enemies/infection_carrier_dog.tres",
	&"tank_zombie_dog": "res://data/enemies/tank_zombie_dog.tres",
	&"charger_zombie_dog": "res://data/enemies/charger_zombie_dog.tres",
	&"splitter_zombie_dog": "res://data/enemies/splitter_zombie_dog.tres",
	&"hunter_zombie_dog": "res://data/enemies/hunter_zombie_dog.tres",
	&"boss_guardian": "res://data/enemies/minions/boss_guardian.tres",
	&"boss_healer": "res://data/enemies/minions/boss_healer.tres",
	&"boss_exploder": "res://data/enemies/minions/boss_exploder.tres",
}

static var _enemy_data_cache: Dictionary = {}


## Carga (con cache) el EnemyData de un id de la tabla anterior.
static func load_enemy_data(id: StringName) -> Resource:
	if _enemy_data_cache.has(id):
		return _enemy_data_cache[id]
	var path: String = ENEMY_DATA_PATHS.get(id, "")
	if path == "":
		return null
	var data: Resource = load(path)
	_enemy_data_cache[id] = data
	return data


# --- Nombres de fase para el HUD (español; nunca "minions") -----------------------
const PHASE_NAMES: Dictionary = {
	Phase.INTRO: "Entrada",
	Phase.COMMON_ENEMIES: "Horda comun",
	Phase.SPECIAL_ENEMIES: "Enemigos especiales",
	Phase.HEAVY_ENEMIES: "Enemigos pesados",
	Phase.MINIBOSS: "Mini-boss",
	Phase.BOSS: "Boss",
	Phase.ELITE_BOSS: "Boss elite",
	Phase.VICTORY: "Victoria",
	Phase.DEFEAT: "Derrota",
}


## Perfil de spawn de una fase:
##   weights    id de enemigo -> peso relativo de aparicion
##   interval   segundos base entre spawns (el score solo lo ajusta suave)
##   budget     presupuesto de amenaza (suma de threat_cost de vivos del spawner)
##   max_alive  tope de vivos generados por el spawner en esta fase
##   tier_caps  tope de vivos simultaneos por categoria (&"special"/&"heavy")
##   type_caps  tope de vivos simultaneos por id concreto
static func phase_profile(phase: int) -> Dictionary:
	match phase:
		Phase.INTRO:
			return {
				"weights": {&"zombie_dog": 0.80, &"runner_zombie_dog": 0.20},
				"interval": 0.72, "budget": 24.0, "max_alive": 24,
				"tier_caps": {&"special": 0, &"heavy": 0}, "type_caps": {},
			}
		Phase.COMMON_ENEMIES:
			return {
				"weights": {&"zombie_dog": 0.62, &"runner_zombie_dog": 0.10, &"pack_zombie_dog": 0.18, &"pup_zombie_dog": 0.10},
				"interval": 0.62, "budget": 34.0, "max_alive": 36,
				"tier_caps": {&"special": 0, &"heavy": 0}, "type_caps": {},
			}
		Phase.SPECIAL_ENEMIES:
			return {
				"weights": {
					&"zombie_dog": 0.35, &"pack_zombie_dog": 0.12, &"pup_zombie_dog": 0.08,
					&"flanker_zombie_dog": 0.20, &"howler_zombie_dog": 0.08,
					&"spitter_zombie_dog": 0.10, &"infection_carrier_dog": 0.07,
				},
				"interval": 0.60, "budget": 46.0, "max_alive": 46,
				"tier_caps": {&"special": 10, &"heavy": 0},
				"type_caps": {&"howler_zombie_dog": 1, &"spitter_zombie_dog": 3, &"infection_carrier_dog": 2},
			}
		Phase.HEAVY_ENEMIES:
			return {
				"weights": {
					&"zombie_dog": 0.18, &"pack_zombie_dog": 0.10, &"pup_zombie_dog": 0.07,
					&"flanker_zombie_dog": 0.14, &"howler_zombie_dog": 0.07,
					&"spitter_zombie_dog": 0.08, &"infection_carrier_dog": 0.06,
					&"tank_zombie_dog": 0.09, &"charger_zombie_dog": 0.07,
					&"splitter_zombie_dog": 0.08, &"hunter_zombie_dog": 0.06,
				},
				"interval": 0.60, "budget": 58.0, "max_alive": 50,
				"tier_caps": {&"special": 10, &"heavy": 4},
				"type_caps": {
					&"howler_zombie_dog": 1, &"spitter_zombie_dog": 3, &"infection_carrier_dog": 2,
					&"tank_zombie_dog": 2, &"charger_zombie_dog": 2, &"splitter_zombie_dog": 3,
					&"hunter_zombie_dog": 2,
				},
			}
		Phase.MINIBOSS:
			# Mismo abanico que la fase pesada, pero con la horda reducida 30-40%
			# (ventana de lectura del mini-boss) y menos presupuesto.
			return {
				"weights": {
					&"zombie_dog": 0.24, &"pack_zombie_dog": 0.10, &"pup_zombie_dog": 0.08,
					&"flanker_zombie_dog": 0.14, &"howler_zombie_dog": 0.06,
					&"spitter_zombie_dog": 0.07, &"infection_carrier_dog": 0.05,
					&"tank_zombie_dog": 0.09, &"charger_zombie_dog": 0.06,
					&"splitter_zombie_dog": 0.06, &"hunter_zombie_dog": 0.05,
				},
				"interval": 1.15, "budget": 34.0, "max_alive": 30,
				"tier_caps": {&"special": 6, &"heavy": 3},
				"type_caps": {
					&"howler_zombie_dog": 1, &"spitter_zombie_dog": 2, &"infection_carrier_dog": 2,
					&"tank_zombie_dog": 2, &"charger_zombie_dog": 2, &"splitter_zombie_dog": 2,
					&"hunter_zombie_dog": 1,
				},
			}
		Phase.BOSS:
			# Horda fuerte reducida: pocos comunes para XP y habilidades.
			return {
				"weights": {&"zombie_dog": 0.70, &"pup_zombie_dog": 0.30},
				"interval": 1.7, "budget": 14.0, "max_alive": 14,
				"tier_caps": {&"special": 0, &"heavy": 0}, "type_caps": {},
			}
		Phase.ELITE_BOSS:
			return {
				"weights": {&"zombie_dog": 0.60, &"runner_zombie_dog": 0.10, &"pup_zombie_dog": 0.30},
				"interval": 1.55, "budget": 16.0, "max_alive": 16,
				"tier_caps": {&"special": 0, &"heavy": 0}, "type_caps": {},
			}
	# Furia final / victoria / derrota: sin spawns comunes.
	return {
		"weights": {}, "interval": 999.0, "budget": 0.0, "max_alive": 0,
		"tier_caps": {}, "type_caps": {},
	}


## Fase que corresponde a un tiempo de partida (sin contar victoria/derrota).
static func phase_for_time(seconds: float) -> int:
	if seconds < COMMON_START:
		return Phase.INTRO
	if seconds < SPECIAL_START:
		return Phase.COMMON_ENEMIES
	if seconds < HEAVY_START:
		return Phase.SPECIAL_ENEMIES
	if seconds < MINIBOSS_START:
		return Phase.HEAVY_ENEMIES
	if seconds < BOSS_START:
		return Phase.MINIBOSS
	if seconds < ELITE_START:
		return Phase.BOSS
	return Phase.ELITE_BOSS


static func phase_name(phase: int) -> String:
	return PHASE_NAMES.get(phase, "")
