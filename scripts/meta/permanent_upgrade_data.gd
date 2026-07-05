class_name PermanentUpgradeData
extends Resource
## Define una mejora permanente comprable con Sardinas (Fase 07). Data-driven: agregar
## una mejora = crear un .tres, sin tocar codigo. El efecto lo aplica el sistema
## correspondiente leyendo `effect_type` desde PermanentUpgradeManager.

## Tipos de efecto soportados (los lee PermanentUpgradeManager.get_effect_total):
##   &"player_damage_pct"   : +% dano inicial del jugador (por nivel).
##   &"player_speed_pct"    : +% velocidad inicial (por nivel).
##   &"max_health_flat"     : +vida maxima inicial (plano, por nivel).
##   &"xp_pct"              : +% experiencia ganada (por nivel).
##   &"sardine_pct"         : +% Sardinas ganadas al final (por nivel).
##   &"first_rescue_seconds": segundos antes para el primer rescate (por nivel).
##   &"weapon_cooldown_pct" : -% cooldown inicial de armas (por nivel).
##   &"pickup_range_pct"    : +% radio de recogida de XP (por nivel, Fase 09).
##   &"damage_reduction_pct": -% daño recibido por el jugador (por nivel, Fase 09).
##   &"companion_damage_pct": +% daño de los compañeros (por nivel, Fase 09).
@export var id: StringName = &"upgrade"
@export var display_name: String = "Mejora"
@export var description: String = ""
@export var max_level: int = 10
## Costo del primer nivel (nivel 0 -> 1).
@export var base_cost: int = 30
## Multiplicador de costo por nivel ya comprado (1.5 = +50% cada nivel).
@export var cost_growth: float = 1.5
@export var effect_type: StringName = &"player_damage_pct"
## Valor del efecto que aporta CADA nivel.
@export var effect_value_per_level: float = 0.03
@export var icon_color: Color = Color(1.0, 0.85, 0.4, 1.0)
## Categoria informativa para agrupar en el panel (jugador/armas/economia/colonia).
@export var category: StringName = &"player"
## Capitulo del Modo Historia que desbloquea esta mejora (0 = siempre disponible).
@export var unlock_story_chapter: int = 0
