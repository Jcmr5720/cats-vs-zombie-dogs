class_name WeaponData
extends Resource
## Define un arma del jugador de forma data-driven. El comportamiento concreto lo
## resuelve WeaponBase segun `weapon_type`. Los niveles escalan estos valores base
## mediante reglas en WeaponBase (ver `_effective_*`), por eso aqui solo viven los
## valores de NIVEL 1.

## Tipos soportados por WeaponBase:
##   &"projectile" : bala directa al enemigo mas cercano.
##   &"explosive"  : proyectil que explota en area al impactar.
##   &"boomerang"  : proyectil que atraviesa varios enemigos (pierce).
##   &"laser"      : rayo instantaneo (Line2D) al enemigo mas cercano.
##   &"orbital"    : objetos que giran alrededor del jugador y danan al tocar.
##   &"area"       : zona temporal que dana por tics (catnip).
@export var id: StringName = &"weapon"
@export var display_name: String = "Arma"
@export var description: String = ""
@export var weapon_type: StringName = &"projectile"

@export_group("Combate")
@export var damage: int = 8
@export var cooldown: float = 0.55
@warning_ignore("shadowed_global_identifier")
@export var range: float = 500.0
@export var projectile_speed: float = 600.0
@export var projectile_count: int = 1
@export var spread_degrees: float = 12.0
@export var area_radius: float = 0.0
@export var duration: float = 0.0
@export var pierce: int = 0
@export var knockback: float = 120.0
@export var tick_interval: float = 0.4

@export_group("Evolucion")
## WeaponData en el que evoluciona esta arma al alcanzar nivel maximo habiendo
## elegido la carta de stat `evolution_requirement` en la run. null = no evoluciona.
## (Tipo Resource y no WeaponData para evitar referencia circular de tipos.)
@export var evolution: Resource
## Id de la carta de stat requerida (p.ej. &"extra_projectile"). Vacio = sin requisito.
@export var evolution_requirement: StringName = &""

@export_group("Presentacion / progresion")
@export var visual_color: Color = Color(1.0, 0.95, 0.7, 1.0)
@export var rarity: StringName = &"common"
@export var rarity_weight: float = 1.0
@export var max_level: int = 5
## Si es true, los stats generales del jugador (+dano/-cooldown/+rango/+proyectil)
## afectan a esta arma. Las orbitales/area tambien escuchan dano y cooldown.
@export var scales_with_global_stats: bool = true
