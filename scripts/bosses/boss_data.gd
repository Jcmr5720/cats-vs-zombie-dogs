class_name BossData
extends Resource
## Define un jefe o mini-jefe de forma data-driven, al estilo de EnemyData pero con
## mas parametros (fases, patrones, recompensa). El comportamiento concreto lo
## resuelven boss.gd (jefe principal) y mini_boss.gd (mini-jefe) segun `boss_type`.

## "boss" = jefe principal con fases y patrones; "miniboss" = elite robusto simple.
@export var id: StringName = &"boss"
@export var display_name: String = "Jefe"
@export var boss_type: StringName = &"boss"

@export_group("Combate")
@export var max_health: int = 1200
@export var move_speed: float = 70.0
@export var contact_damage: int = 18
@export var attack_damage: int = 28
@export var attack_cooldown: float = 4.0
@export var attack_range: float = 900.0
## Empuje aplicado al jugador/companeros al impactar por contacto o embestida.
@export var knockback: float = 240.0

@export_group("Recompensa")
@export var xp_reward: int = 120

@export_group("Presentacion")
@export var visual_color: Color = Color(0.45, 0.3, 0.55, 1.0)
@export var accent_color: Color = Color(1.0, 0.85, 0.25, 1.0)
@export var visual_scale: float = 1.0

@export_group("Dificultad / fases")
## Umbrales de vida (0..1) que disparan cambios de fase. Ej: [0.6, 0.3].
@export var phase_thresholds: PackedFloat32Array = PackedFloat32Array([0.6, 0.3])
## Tiempo orientativo de aparicion en segundos (lo usa WaveEventManager/debug).
@export var spawn_time: float = 600.0
## Cuanto sube la vida por punto de difficulty_score (con tope en el script).
@export var difficulty_multiplier: float = 0.08
