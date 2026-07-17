class_name CoopConfig
extends RefCounted
## Configuracion central del coop local (Fase Mejora Coop). TODOS los numeros de
## balance/UX cooperativos viven aqui: nada de constantes sueltas repetidas en
## player/spawner/paneles. Cambiar un valor aqui afecta a todo el sistema.

# --- Identidad de jugadores ----------------------------------------------------
const P1_COLOR := Color(0.99, 0.72, 0.28)
const P2_COLOR := Color(0.4, 0.72, 1.0)
## Icono por jugador (apoyo para daltonismo: la forma identifica, no solo el color).
const P1_ICON := "▲"
const P2_ICON := "●"

# --- Reparto de XP (Fase 3) ----------------------------------------------------
## Fraccion que recibe quien RECOGE el orbe (antes 1.0; el 150% de XP total del
## equipo inflaba la progresion frente al modo solo).
const XP_COLLECTOR_SHARE: float = 0.75
## Fraccion que recibe el COMPANERO (antes 0.5). Total del equipo: 110%.
const XP_PARTNER_SHARE: float = 0.35
## Hasta esta distancia el companero recibe el share completo.
const XP_SHARE_FULL_DIST: float = 900.0
## A partir de esta distancia el companero no recibe nada (decae linealmente).
const XP_SHARE_ZERO_DIST: float = 2600.0

# --- Incentivos de cercania (Fase 5) --------------------------------------------
## Radio para el bonus de "juntos": regeneracion lenta compartida.
const PROXIMITY_RADIUS: float = 340.0
## Cada cuantos segundos cura el bonus de cercania.
const PROXIMITY_REGEN_INTERVAL: float = 4.0
## Vida curada por tick a cada jugador cuando estan juntos y activos.
const PROXIMITY_REGEN_AMOUNT: int = 1
## XP directa (sin reparto) para el rescatador al completar un revive.
const RESCUER_XP_REWARD: int = 8

# --- Derribo y rescate (Fase 9) ---------------------------------------------------
## Invulnerabilidad minima al levantarse (evita revivir dentro de dano inevitable).
const REVIVE_INVULN_SECONDS: float = 1.5

# --- Cartas coop (Fase 4) ---------------------------------------------------------
## Seleccion automatica de la carta resaltada tras este tiempo (anti-bloqueo por
## desconexion o inactividad). <= 0 la desactiva.
const CARD_AUTO_PICK_SECONDS: float = 25.0
## Segundos finales en los que se muestra la cuenta atras en el panel.
const CARD_AUTO_PICK_WARN_SECONDS: float = 10.0
## true = en vez de pausar, la partida corre ralentizada mientras se elige.
## false (por defecto) = pausa clasica. Cambiable sin tocar mas codigo.
const CARD_SLOWDOWN_ENABLED: bool = false
const CARD_SLOWDOWN_SCALE: float = 0.25

# --- Pantalla dividida (Fases 1 y 8) -----------------------------------------------
## Zoom base de cada mitad (lo usan la SplitCamera y el spawner para calcular el
## borde visible real de cada mitad en coop).
const SPLIT_BASE_ZOOM: float = 0.95
## Zoom aplicado a la camara del viewport raiz en coop: el raiz queda tapado por el
## split, pero Godot lo sigue dibujando; con zoom extremo su vista cubre ~nada del
## mundo y el render extra se vuelve despreciable.
const ROOT_CAMERA_PARK_ZOOM: float = 16.0


## Fraccion de XP que llega al companero segun la distancia entre jugadores:
## completa hasta XP_SHARE_FULL_DIST, decae lineal a 0 en XP_SHARE_ZERO_DIST.
static func xp_share_at_distance(distance: float) -> float:
	if distance <= XP_SHARE_FULL_DIST:
		return XP_PARTNER_SHARE
	if distance >= XP_SHARE_ZERO_DIST:
		return 0.0
	var t: float = (distance - XP_SHARE_FULL_DIST) / (XP_SHARE_ZERO_DIST - XP_SHARE_FULL_DIST)
	return XP_PARTNER_SHARE * (1.0 - t)


static func player_color(player_id: int) -> Color:
	return P1_COLOR if player_id <= 1 else P2_COLOR


static func player_icon(player_id: int) -> String:
	return P1_ICON if player_id <= 1 else P2_ICON


## Etiqueta corta con icono: "▲J1" / "●J2" (identidad legible sin depender del color).
static func player_tag(player_id: int) -> String:
	return "%sJ%d" % [player_icon(player_id), maxi(1, player_id)]
