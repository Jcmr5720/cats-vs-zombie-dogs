class_name GameBalance
extends RefCounted
## Curvas CENTRALIZADAS de dificultad y XP (Fase correccion de balance). Todos
## los numeros de escalado viven aqui, separados por componente y con TECHOS
## explicitos, para que el spawner/jefes/mapa no repartan constantes magicas.
##
## Diseño por etapas (documentado, sin saltos bruscos):
## - INICIO (0-3 min): enemigos basicos, ritmo moderado, sin elites ni
##   mini-oleadas; el jugador arma su build sin castigo.
## - MITAD: la presion crece sobre todo por CANTIDAD y variedad; vida sube lenta
##   y constante; dano mas lento que la vida; velocidad casi plana.
## - FINAL: presion alta pero jugable: TODOS los multiplicadores totales
##   (incluyendo mapa/plaga/dificultad/coop) tienen tope.
##
## La "potencia del jugador" entra SUAVIZADA (media movil): elegir una carta no
## dispara la dificultad al instante.

# --- XP / progresion de nivel ---------------------------------------------------
## XP para el primer nivel y crecimiento geometrico por nivel (player.gd).
## Partidas rapidas (~5 min): primer nivel barato (primera carta antes de 0:20
## con la manada inicial) y crecimiento MAS empinado que la curva antigua de
## 20 min (1.35): apunta a ~6-8 elecciones por partida, mas la Mutacion del
## mini-boss (que no consume nivel).
const XP_FIRST_LEVEL: int = 8
const XP_GROWTH: float = 1.5

# --- Score de dificultad ----------------------------------------------------------
## Peso de los minutos sobrevividos (fuente principal y predecible del escalado).
## Subido (1.15 -> 1.6) en la Fase re-balance: la curva era demasiado plana y la
## partida entera se sentia facil.
const TIME_WEIGHT: float = 1.75
## Pesos de la potencia del jugador. NOTA de auditoria: la formula anterior
## contaba el mismo poder TRES veces por subida de nivel (nivel 0.9 + mejora
## elegida 0.35 + nivel de arma 0.18 ≈ +1.43 de score por carta). Ahora el nivel
## pesa menos y las "mejoras elegidas" ya no puntuan aparte.
const LEVEL_WEIGHT: float = 0.50
const WEAPON_WEIGHT: float = 0.45
const WEAPON_LEVEL_WEIGHT: float = 0.10
const COMPANION_WEIGHT: float = 0.50
const DOWNED_COMPANION_WEIGHT: float = -0.25
## Cada cuantos kills se suma 1 punto (antes 35: el propio exito del jugador
## aceleraba demasiado la curva).
const KILLS_DIVISOR: float = 60.0
## Bono plano de score en coop (la UNICA fuente de presion extra de score coop;
## antes ademas se multiplicaba todo el score por 1.25).
const COOP_SCORE_BONUS: float = 2.5
## Tope absoluto del score (la formula anterior no tenia: llegaba a 100+).
const SCORE_CAP: float = 70.0
## Suavizado de la potencia del jugador: constante de tiempo de la media movil
## (segundos) y cadencia de muestreo de los datos caros.
const POWER_SMOOTH_SECONDS: float = 25.0
const POWER_POLL_SECONDS: float = 2.0

# --- Etapas -------------------------------------------------------------------------
## Fin de la etapa de inicio (min). Antes: sin elites ni mini-oleadas. Acortada
## (3.0 -> 1.5) en la Fase re-balance: el arranque era un paseo; la presion de
## borde/oleadas/elites entra mucho antes.
const EARLY_STAGE_MINUTES: float = 1.5

# --- Ritmo de aparicion ----------------------------------------------------------------
const BASE_SPAWN_INTERVAL: float = 0.72
## Reduccion del intervalo por punto de score (antes 0.05: tocaba suelo al min 3).
const INTERVAL_PER_POINT: float = 0.030
## Suelo del intervalo: alto al inicio y baja con los minutos (la cantidad es la
## fuente de presion de MITAD de partida, no del arranque).
const SPAWN_FLOOR_EARLY: float = 0.48
const SPAWN_FLOOR_LATE: float = 0.26
## Minutos entre los que el suelo desciende de EARLY a LATE.
const SPAWN_FLOOR_RAMP_START_MIN: float = 1.5
const SPAWN_FLOOR_RAMP_END_MIN: float = 10.0
## Enemigos vivos permitidos: base + score * pendiente (antes 3.0).
const BASE_MAX_ENEMIES: float = 28.0
const ENEMIES_PER_POINT: float = 2.4

# --- Multiplicadores de enemigos (parte por score + TECHO TOTAL) -------------------------
## La parte por score crece lenta; el TECHO TOTAL acota el producto final con
## TODOS los externos (mapa x plaga x dificultad x coop). Antes no existia techo
## total: en Extremo+Plaga 5+coop la vida pasaba de x7.
const HEALTH_PER_POINT: float = 0.046
const HEALTH_SCORE_CAP: float = 2.45
const HEALTH_TOTAL_CAP: float = 4.50
const DAMAGE_PER_POINT: float = 0.036
const DAMAGE_SCORE_CAP: float = 2.10
const DAMAGE_TOTAL_CAP: float = 2.60
const SPEED_PER_POINT: float = 0.016
const SPEED_SCORE_CAP: float = 1.32
## Velocidad total con techo duro: por encima de esto los enemigos alcanzan
## al jugador (250 px/s) incluso con mejoras de velocidad.
const SPEED_TOTAL_CAP: float = 1.45

# --- Elites (por intervalos, no continuo) --------------------------------------------------
## Sin elites antes de EARLY_STAGE_MINUTES; despues, la probabilidad sube por
## ESCALONES cada ELITE_STEP_MINUTES hasta el tope.
const ELITE_STEP_CHANCE: float = 0.032
const ELITE_STEP_MINUTES: float = 3.0
const ELITE_CHANCE_CAP: float = 0.14

# --- Jefes y mini-jefes -----------------------------------------------------------------
## Tope del factor de vida por score de un jefe: vida = base * min(CAP, 1 + score
## * boss_data.difficulty_multiplier). Con el score tambien acotado, un jefe
## tardio es resistente pero nunca una esponja imposible. (Ademas sobreviven los
## topes absolutos en px de vida: boss.MAX_HEALTH_CAP / mini_boss.MAX_HEALTH_CAP.)
## Bajados en la Fase re-balance (4.0/3.5 -> 3.6/3.2): la dificultad extra viene
## de la HORDA (mas presion y dano), no de convertir al jefe en esponja — la
## partida debe poder cerrarse en la ventana de 5:00-5:30.
const BOSS_HEALTH_SCORE_FACTOR_CAP: float = 3.6
const MINIBOSS_HEALTH_SCORE_FACTOR_CAP: float = 3.2
## Vida extra de jefes en coop (una sola vez, al configurarse).
const BOSS_COOP_HEALTH_MULT: float = 1.45
## Los jefes NO escalan su dano con el score (dano fijo por BossData): techo
## documental de dano dinamico de jefe = 1.0 (no existe esa via de escalado).
const BOSS_DAMAGE_SCORE_MULT: float = 1.0

# --- Presion de proyectiles -------------------------------------------------------------
## No existen enemigos con proyectiles en el juego actual (dano por contacto y
## cargas de jefe). Se deja el techo declarado para cuando existan: multiplicador
## maximo de cadencia/cantidad de proyectiles enemigos.
const ENEMY_PROJECTILE_PRESSURE_CAP: float = 1.0

# --- Coop (multiplicadores de enemigos) ----------------------------------------------------
## Antes: pressure x1.25 (ademas del bono de score) + vida x1.45 + dano x1.15.
## La presion coop ahora entra SOLO por el bono de score; vida/dano moderados.
const COOP_ENEMY_HEALTH_MULT: float = 1.30
const COOP_ENEMY_DAMAGE_MULT: float = 1.10
const COOP_PRESSURE_MULT: float = 1.0


## Progreso 0..1 de la etapa inicial (0 = arranque, 1 = etapa media en curso).
static func early_ramp(minutes: float) -> float:
	return clampf(minutes / EARLY_STAGE_MINUTES, 0.0, 1.0)


## Suelo del intervalo de spawn segun el minuto de partida.
static func spawn_floor(minutes: float) -> float:
	var t: float = clampf((minutes - SPAWN_FLOOR_RAMP_START_MIN) / (SPAWN_FLOOR_RAMP_END_MIN - SPAWN_FLOOR_RAMP_START_MIN), 0.0, 1.0)
	return lerpf(SPAWN_FLOOR_EARLY, SPAWN_FLOOR_LATE, t)


## Multiplicador de vida FINAL: parte por score acotada x externos, con techo total.
static func health_multiplier(score: float, external_mult: float) -> float:
	var by_score: float = minf(HEALTH_SCORE_CAP, 1.0 + score * HEALTH_PER_POINT)
	return minf(HEALTH_TOTAL_CAP, by_score * maxf(0.1, external_mult))


static func damage_multiplier(score: float, external_mult: float) -> float:
	var by_score: float = minf(DAMAGE_SCORE_CAP, 1.0 + score * DAMAGE_PER_POINT)
	return minf(DAMAGE_TOTAL_CAP, by_score * maxf(0.1, external_mult))


static func speed_multiplier(score: float, external_mult: float) -> float:
	var by_score: float = minf(SPEED_SCORE_CAP, 1.0 + score * SPEED_PER_POINT)
	return minf(SPEED_TOTAL_CAP, by_score * maxf(0.1, external_mult))


## Probabilidad de elite por minuto de partida (escalones) + aporte leve del score.
static func elite_chance(minutes: float, score: float) -> float:
	if minutes < EARLY_STAGE_MINUTES:
		return 0.0
	var steps: float = 1.0 + floorf((minutes - EARLY_STAGE_MINUTES) / ELITE_STEP_MINUTES)
	return minf(ELITE_CHANCE_CAP, steps * ELITE_STEP_CHANCE + score * 0.0005)
