class_name CompanionBalance
## Balance centralizado del sistema de compañeros (Rework de Jugabilidad).
## Todos los valores ajustables viven aqui: nada de numeros magicos dispersos.
## Las formulas de escalado tambien se documentan y calculan aqui.

# --- Supervivencia --------------------------------------------------------------

## Los compañeros reciben este porcentaje del daño normal (0.5 = 50%).
const INCOMING_DAMAGE_FACTOR: float = 0.5
## Invulnerabilidad tras recibir daño (evita daño de contacto cada frame).
const HURT_INVULN_TIME: float = 0.8
## Proteccion (invulnerabilidad total) al revivir o reaparecer.
const REVIVE_PROTECTION_TIME: float = 1.5
## Si nadie lo revive en este tiempo, reaparece solo junto al lider (penalizado).
const DOWNED_AUTO_RESPAWN_TIME: float = 22.0
## Vida con la que reaparece tras el auto-respawn (fraccion de la maxima).
const RESPAWN_HEALTH_PERCENT: float = 0.35
## Al auto-reaparecer pierde su habilidad especial durante este tiempo.
const RESPAWN_ABILITY_LOCKOUT: float = 10.0

# --- IA segura / correa ---------------------------------------------------------

## Distancia blanda al lider: mas alla deja de atacar y entra en modo regreso.
const SOFT_LEASH_DISTANCE: float = 600.0
## Distancia de emergencia: reposicion segura junto al lider.
const EMERGENCY_LEASH_DISTANCE: float = 850.0
## Bonus de velocidad mientras regresa al lider.
const RETURN_SPEED_BONUS: float = 1.28
## Si en modo regreso apenas avanza durante este tiempo, se considera atrapado.
const STUCK_TELEPORT_TIME: float = 2.5
## Radio alrededor del lider donde se busca una posicion segura de reaparicion.
const SAFE_SPOT_RADIUS: float = 84.0
## Distancia minima a un enemigo para considerar segura una posicion.
const SAFE_SPOT_ENEMY_CLEARANCE: float = 70.0

# --- Orden de reagrupamiento ----------------------------------------------------

const REGROUP_DURATION: float = 3.0
const REGROUP_SPEED_BONUS: float = 1.35

# --- Gato Policia ---------------------------------------------------------------

## Pasiva "Objetivo prioritario": intervalo de re-evaluacion de la marca.
const POLICE_MARK_INTERVAL: float = 2.5
## Daño extra que recibe el enemigo marcado (de TODO el equipo).
const POLICE_MARK_DAMAGE_BONUS: float = 0.20
## Radio de busqueda de enemigos especiales para marcar (desde el lider).
const POLICE_MARK_RANGE: float = 520.0
## Habilidad "Barricada policial".
const POLICE_BARRICADE_COOLDOWN: float = 20.0
const POLICE_BARRICADE_DURATION: float = 4.0
const POLICE_BARRICADE_RADIUS: float = 110.0
## Multiplicador de velocidad de los enemigos dentro de la barricada.
const POLICE_BARRICADE_SLOW: float = 0.45
## Cuantos enemigos cerca del lider disparan la barricada automaticamente.
const POLICE_BARRICADE_TRIGGER_COUNT: int = 5
const POLICE_BARRICADE_TRIGGER_RANGE: float = 260.0
## Empujon de emergencia (cooldown interno independiente).
const POLICE_PUSH_COOLDOWN: float = 8.0
const POLICE_PUSH_RANGE: float = 130.0
## Umbral de vida del jugador que activa el modo protector.
const POLICE_PROTECT_THRESHOLD: float = 0.4

# --- Gato Medico ----------------------------------------------------------------

## Habilidad "Emergencia de nueve vidas": se dispara si un jugador baja de esto.
const MEDIC_EMERGENCY_THRESHOLD: float = 0.35
const MEDIC_ABILITY_COOLDOWN: float = 24.0
## Multiplicador de la cura base en la emergencia.
const MEDIC_EMERGENCY_HEAL_MULT: float = 3.0
## Escudo: reduccion de daño temporal que otorga al jugador.
const MEDIC_SHIELD_REDUCTION: float = 0.5
const MEDIC_SHIELD_DURATION: float = 3.0
## El medico canaliza revive de compañeros caidos cercanos a este ritmo (0.6 =
## 60% de la velocidad de un jugador; se SUMA si el jugador tambien esta encima).
const MEDIC_ASSIST_REVIVE_RATE: float = 0.6
const MEDIC_ASSIST_RANGE: float = 170.0

# --- Gato Ingeniero -------------------------------------------------------------

## Habilidad "Zona fortificada" (torreta temporal).
const ENGINEER_TURRET_COOLDOWN: float = 24.0
const ENGINEER_TURRET_DURATION: float = 10.0
const ENGINEER_TURRET_RANGE: float = 380.0
const ENGINEER_TURRET_FIRE_INTERVAL: float = 0.55
## La torreta hace este porcentaje del daño efectivo del ingeniero por disparo.
const ENGINEER_TURRET_DAMAGE_FACTOR: float = 0.8
## Cuantos enemigos en rango disparan la instalacion automatica.
const ENGINEER_TURRET_TRIGGER_COUNT: int = 4
const ENGINEER_TURRET_TRIGGER_RANGE: float = 420.0
## Pasiva "Mantenimiento de campo": arrastra orbes de XP cercanos hacia el lider.
const ENGINEER_ORB_PULL_RADIUS: float = 150.0
const ENGINEER_ORB_PULL_INTERVAL: float = 0.6
const ENGINEER_ORB_PULL_SPEED: float = 420.0

# --- Sinergias ------------------------------------------------------------------

## Policia + Medico: cura por tick a jugadores dentro de la barricada.
const SYNERGY_BARRICADE_HEAL: int = 2
## Medico + Ingeniero: cura periodica de la torreta a aliados cercanos.
const SYNERGY_TURRET_HEAL: int = 2
const SYNERGY_TURRET_HEAL_INTERVAL: float = 2.5
const SYNERGY_TURRET_HEAL_RADIUS: float = 130.0

# --- Escalado -------------------------------------------------------------------
# Formulas reales implementadas (aplicadas por CompanionManager cada 2 s):
#   vida_bonus  = minutos * 4 + max(0, vida_max_jugador - 100) * 0.35
#   daño_escala = clamp(1 + 0.05 * (nivel_jugador - 1), 1.0, 2.0)
# El daño efectivo final = base * upgrades/refugio * daño_escala. La escala vive
# en un factor separado con tope para evitar doble aplicacion e infinito.

const SCALING_UPDATE_INTERVAL: float = 2.0
const HEALTH_PER_MINUTE: float = 4.0
const HEALTH_FROM_PLAYER_FACTOR: float = 0.35
const DAMAGE_PER_PLAYER_LEVEL: float = 0.05
const DAMAGE_SCALE_CAP: float = 2.0


static func health_bonus(minutes: float, player_max_health: int) -> int:
	var from_time: float = maxf(0.0, minutes) * HEALTH_PER_MINUTE
	var from_player: float = maxf(0.0, float(player_max_health - 100)) * HEALTH_FROM_PLAYER_FACTOR
	return int(round(from_time + from_player))


static func damage_scale(player_level: int) -> float:
	return clampf(1.0 + DAMAGE_PER_PLAYER_LEVEL * float(player_level - 1), 1.0, DAMAGE_SCALE_CAP)
