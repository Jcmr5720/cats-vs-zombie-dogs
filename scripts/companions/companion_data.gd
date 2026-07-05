class_name CompanionData
extends Resource

@export var id: StringName = &"companion"
@export var display_name: String = "Gato companero"
@export var role: StringName = &"police"
@export var max_health: int = 60
@export var move_speed: float = 220.0
@export var follow_distance: float = 70.0
@export var attack_damage: int = 6
@export var attack_cooldown: float = 0.8
@export var attack_range: float = 420.0
@export var projectile_speed: float = 550.0
@export var heal_amount: int = 4
@export var heal_cooldown: float = 8.0
## Aura de regeneracion pasiva (sostenida): cura esta cantidad cada
## `passive_regen_interval` a aliados/jugador cercanos, incluso fuera de combate.
## El medico usa esto para tener utilidad continua, no solo curas reactivas.
@export var passive_regen: int = 0
@export var passive_regen_interval: float = 2.0
@export var passive_regen_range: float = 220.0
@export var damage_reduction: float = 0.0
@export var revive_time: float = 1.5
@export var revive_health_percent: float = 0.4
@export var visual_color: Color = Color(0.95, 0.72, 0.42, 1)
@export var accent_color: Color = Color(0.18, 0.24, 0.32, 1)
@export var detail_color: Color = Color(0.96, 0.96, 0.96, 1)
@export var projectile_color: Color = Color(1.0, 0.95, 0.7, 1)
@export var spawn_weight: float = 1.0
