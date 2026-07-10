class_name MapData
extends Resource
## Define un mapa/bioma de forma data-driven: identidad visual, modificadores de
## dificultad, tiempos de eventos y objetivos de partida. El MapManager lo lee y lo
## reparte a los sistemas (fondo, EnemySpawner, RescueSpawner, WaveEventManager).
## Pensado para extenderse: agregar un mapa = crear un .tres, sin tocar codigo.

const BossData = preload("res://scripts/bosses/boss_data.gd")
const ObstacleData = preload("res://scripts/maps/obstacle_data.gd")

@export var id: StringName = &"map"
@export var display_name: String = "Zona"
@export var description: String = ""

@export_group("Identidad visual")
## Color base del suelo (lo recibe el fondo de cuadricula).
@export var background_color: Color = Color(0.12, 0.13, 0.17, 1.0)
@export var secondary_color: Color = Color(0.09, 0.10, 0.13, 1.0)
## Color de las lineas de la cuadricula/decoracion.
@export var grid_color: Color = Color(0.2, 0.22, 0.28, 1.0)
## Color de acento del bioma (decoracion, marcas).
@export var accent_color: Color = Color(0.5, 0.5, 0.55, 1.0)
@export var hazard_color: Color = Color(0.9, 0.65, 0.18, 1.0)
@export var decoration_accent_color: Color = Color(0.5, 0.5, 0.55, 1.0)
## Estilo de decoracion procedural: &"neighborhood" / &"park" / &"industrial".
@export var biome: StringName = &"neighborhood"
@export var pattern_type: StringName = &"streets"
@export_range(0.0, 1.0, 0.01) var pattern_strength: float = 0.45
@export_range(0.0, 1.0, 0.01) var decoration_density: float = 0.36
@export var decoration_scale_min: float = 0.7
@export var decoration_scale_max: float = 1.35
@export var ambient_detail_count: int = 2
@export var road_line_enabled: bool = true
@export var hazard_line_enabled: bool = false

@export_group("Ambiente (FASE VISUAL 2)")
## Tinte multiplicativo global del mundo (CanvasModulate). Blanco = sin capa.
## Mantener cerca de 1.0 para no perder legibilidad.
@export var ambient_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Color de la niebla baja del bioma (bancos translucidos que derivan).
@export var fog_color: Color = Color(0.7, 0.75, 0.72, 1.0)
## Intensidad de la niebla 0..1 (0 = sin niebla).
@export_range(0.0, 1.0, 0.01) var fog_strength: float = 0.0
## Intensidad de la vignette base del mapa (0 = sin vignette).
@export_range(0.0, 0.6, 0.01) var vignette_strength: float = 0.30
## Color de la vignette base.
@export var vignette_color: Color = Color(0.01, 0.01, 0.03, 1.0)

@export_group("Modificadores de dificultad")
## Multiplica el difficulty_score final del EnemySpawner.
@export var difficulty_modifier: float = 1.0
## Multiplica el peso de aparicion de runners.
@export var runner_probability_modifier: float = 1.0
## Multiplica la vida de los enemigos del mapa.
@export var enemy_health_modifier: float = 1.0
## Multiplica la velocidad de los enemigos del mapa.
@export var enemy_speed_modifier: float = 1.0
## Multiplica los tiempos entre rescates (<1 = mas frecuentes, >1 = menos).
@export var rescue_spawn_modifier: float = 1.0
## Distancia extra a la que aparecen los rescates (mapas peligrosos).
@export var rescue_distance_bonus: float = 0.0

@export_group("Eventos del mapa")
## Tiempo de aparicion del jefe principal (segundos). 0 = sin jefe programado.
@export var boss_spawn_time: float = 600.0
## Tiempos de aparicion de mini-jefes (segundos).
@export var miniboss_times: PackedFloat32Array = PackedFloat32Array([180.0, 420.0])
## BossData del jefe de este mapa (opcional). Si es null, usa el del BossSpawner.
@export var boss_data: BossData

@export_group("Obstaculos (Fase 08.75)")
## Tipos de obstaculo disponibles en este mapa (data-driven).
@export var obstacle_types: Array[ObstacleData] = []
## Densidad 0..1: fraccion de max_obstacles que se intenta colocar.
@export_range(0.0, 1.0, 0.01) var obstacle_density: float = 0.5
## Tope de obstaculos colisionables (rendimiento).
@export var max_obstacles: int = 40
## Distancia minima entre centros de obstaculos.
@export var min_obstacle_distance: float = 130.0
## Radio libre alrededor del punto de inicio del jugador (sin obstaculos).
@export var safe_radius_around_player: float = 260.0
## Radio libre alrededor de rescates (lo usa el RescueSpawner para validar).
@export var safe_radius_around_rescue: float = 150.0
## Radio del area alrededor del origen donde se reparten los obstaculos.
@export var obstacle_field_radius: float = 1600.0
## Permite bloques grandes (casas/muros). Si false, solo props pequeños/medios.
@export var allow_large_blocks: bool = true
## Trazado de calles: &"none" / &"cross" (deja avenidas centrales libres).
@export var road_layout_type: StringName = &"none"
## Semiancho de las avenidas libres cuando road_layout_type = &"cross".
@export var road_half_width: float = 150.0

@export_group("Objetivos de partida")
## Duracion objetivo del mapa (informativa + objetivo de supervivencia).
@export var duration_seconds: float = 600.0
## Objetivo: sobrevivir N segundos (0 = no aplica).
@export var survive_seconds: float = 600.0
## Objetivo: derrotar al jefe principal.
@export var require_defeat_boss: bool = false
## Objetivo: rescatar N gatos (0 = no aplica).
@export var rescue_cats_required: int = 0
## Objetivo: derrotar N mini-jefes (0 = no aplica).
@export var defeat_minibosses_required: int = 0
## Texto opcional para el HUD (si vacio, el MapManager lo arma solo).
@export var objective_description: String = ""
@export var victory_message: String = "Zona asegurada"
@export var game_over_message: String = "Colonia perdida"
