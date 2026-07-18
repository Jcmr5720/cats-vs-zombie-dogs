extends RefCounted
## Configuracion central del minimapa (Sistema Minimapa). TODOS los numeros y
## colores viven aqui: tamanos del panel, radio de mundo visible, cadencias de
## refresco y estilo por tipo de entidad. Cambiar un valor aqui afecta a todo el
## sistema sin tocar controller/registry/markers.
##
## Nota de diseno: los mapas del juego son procedurales e ILIMITADOS (no hay
## bordes de mundo), asi que el minimapa es un RADAR centrado en el jugador con
## un radio de mundo fijo, no una foto del mapa completo.

# --- Panel -----------------------------------------------------------------------
## Lado del minimapa normal (px de UI).
const SIZE: float = 176.0
## Lado del minimapa ampliado (accion "minimap_expand").
const SIZE_EXPANDED: float = 292.0
## Lado en coop (mitades mas estrechas; el ampliado tambien se reduce).
const SIZE_COOP: float = 156.0
const SIZE_COOP_EXPANDED: float = 236.0
## Distancia desde el borde superior de la pantalla (deja libre el panel de
## objetivo del HUD, que ocupa y=12..70).
const TOP_MARGIN: float = 78.0
## Margen interior: los iconos se sujetan a este borde cuando algo queda fuera.
const EDGE_MARGIN: float = 9.0

# --- Radio de mundo (radar) --------------------------------------------------------
## Radio del mundo visible en el radar normal (px de mundo). La camara muestra
## ~1000 px de ancho, asi que 1250 da contexto util sin volverse ruido.
const WORLD_RADIUS: float = 1250.0
## Radio con el minimapa ampliado (cubre la distancia de XP compartida del coop).
const WORLD_RADIUS_EXPANDED: float = 2600.0

# --- Cadencias de refresco (rendimiento) --------------------------------------------
## Cada cuanto se recalculan los puntos baratos (zombies/obstaculos). Los iconos
## importantes (jugadores/jefes/rescates/companeros) se actualizan cada frame
## porque son ≤ ~15 nodos.
const DOT_INTERVAL: float = 0.12
## Con el rendimiento en critico (PerformanceManager) el radar baja de marcha.
const DOT_INTERVAL_CRITICAL: float = 0.30

# --- Hordas grandes ------------------------------------------------------------------
## A partir de este numero de enemigos vivos se agrupan en celdas (un punto por
## celda, mas grande cuanto mas enemigos) en vez de un punto por enemigo.
const CLUSTER_THRESHOLD: int = 90
## Lado de la celda de agrupado, en px del MINIMAPA.
const CLUSTER_CELL: float = 7.0
## Tope duro de enemigos procesados por refresco (proteccion absoluta).
const MAX_ENEMY_SCAN: int = 400

# --- Estilo por tipo de entidad -------------------------------------------------------
## Jugador en solo (spec: marcador azul con orientacion). En coop cada jugador
## usa su color de identidad de la pantalla dividida (CoopConfig) para no chocar
## con el codigo de color ya establecido (P1 ambar ▲ / P2 azul ●).
const PLAYER_SOLO_COLOR := Color(0.35, 0.62, 1.0)
const PLAYER_2_SOLO_FALLBACK := Color(0.45, 0.95, 0.55)
const COMPANION_COLOR := Color(0.55, 0.9, 1.0)
const ENEMY_COLOR := Color(0.85, 0.25, 0.22, 0.9)
const ENEMY_ELITE_COLOR := Color(1.0, 0.32, 0.1)
## Categorias de las Partidas rapidas: especiales (rombo naranja), pesados
## (cuadrado grande granate) y esbirros del jefe (rombo pequeño del color del
## jefe, para que se lean como "suyos").
const ENEMY_SPECIAL_COLOR := Color(1.0, 0.6, 0.15, 0.95)
const ENEMY_HEAVY_COLOR := Color(0.8, 0.12, 0.32, 0.95)
const BOSS_MINION_COLOR := Color(1.0, 0.25, 0.45, 0.95)
const MINIBOSS_COLOR := Color(1.0, 0.2, 0.15)
const BOSS_COLOR := Color(1.0, 0.12, 0.1)
const RESCUE_COLOR := Color(1.0, 0.85, 0.3)

const BG_COLOR := Color(0.045, 0.055, 0.085, 0.78)
const BORDER_COLOR := Color(0.32, 0.36, 0.45, 0.9)

## Tamanos de punto (px del minimapa).
const ENEMY_DOT: float = 3.0
const ENEMY_ELITE_DOT: float = 5.0
const ENEMY_SPECIAL_DOT: float = 5.0
const ENEMY_HEAVY_DOT: float = 7.0
const BOSS_MINION_DOT: float = 4.5

# --- Terreno (Fase correccion: estructura del mapa en el radar) -----------------------
## Cadencia del tick de terreno (asegurar chunks + decidir redibujado).
const TERRAIN_INTERVAL: float = 0.2
## Chunks nuevos generados como maximo por tick (el arranque llena el radar en
## 1-2 ticks; antes con 3 podia tardar varios segundos en modo ampliado).
const TERRAIN_CHUNK_BUDGET: int = 12
## Fondo oscuro del panel = zona "exterior"; las vias claras = transitable.
## Alfas subidos (0.13-0.25 -> 0.22-0.34): los caminos se perdian bajo los
## puntos de la horda y parecian "no cargar".
const ROAD_AVENUE_COLOR := Color(0.80, 0.83, 0.92, 0.32)
const ROAD_STREET_COLOR := Color(0.80, 0.83, 0.92, 0.22)
const PATH_COLOR := Color(0.88, 0.82, 0.62, 0.30)
const RAIL_COLOR := Color(0.75, 0.62, 0.45, 0.34)
const WATER_COLOR := Color(0.30, 0.50, 0.72, 0.42)
## Siluetas de estructuras (edificios, muros, contenedores, coches grandes).
const STRUCT_COLOR := Color(0.60, 0.64, 0.76, 0.38)
## Tintes de zona (solo modo ampliado): plazas/parques y patios/estacionamientos.
const ZONE_COLOR := Color(0.45, 0.70, 0.50, 0.11)
const YARD_COLOR := Color(0.72, 0.68, 0.50, 0.10)
## Silueta minima (px de MUNDO, lado mayor del footprint) por modo: el radar
## compacto muestra solo la estructura principal; el ampliado baja el umbral.
const SILHOUETTE_MIN_SIZE: float = 64.0
const SILHOUETTE_MIN_SIZE_EXPANDED: float = 40.0
## Tope de siluetas dibujadas por refresco.
const MAX_SILHOUETTES: int = 120
