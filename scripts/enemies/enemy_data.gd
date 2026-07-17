class_name EnemyData
extends Resource

@export var id: StringName = &"enemy"
@export var display_name: String = "Zombie Dog"
@export var max_health: int = 20
@export var speed: float = 90.0
@export var contact_damage: int = 10
@export var xp_value: int = 3

@export_group("Clasificacion (Partidas rapidas por fases)")
## Categoria de amenaza: &"common" (horda), &"special" (tactico), &"heavy" (puntual).
@export var tier: StringName = &"common"
## Rol: &"" = enemigo normal; &"boss_minion" = esbirro invocado por un jefe.
@export var role: StringName = &""
## Comportamiento especial (rama en enemy.gd). &"" = persecucion clasica.
## Valores: flanker, howler, spitter, infection_carrier, pack, armored,
## charger, splitter, hunter, boss_guardian, boss_healer, boss_exploder.
@export var behavior: StringName = &""
## Coste en el presupuesto de amenaza del spawner (fase 7 del diseño).
@export var threat_cost: float = 1.0
## Peso base de aparición (a dificultad 0).
@export var spawn_weight: float = 1.0
## Cuánto crece el peso por cada punto de dificultad. Positivo = aparece
## más a medida que sube la presión (p.ej. los runners). 0 = constante.
@export var weight_growth: float = 0.0
@export var body_color: Color = Color(0.42, 0.6, 0.3, 1)
@export var accent_color: Color = Color(0.28, 0.42, 0.2, 1)
@export var eye_color: Color = Color(0.85, 0.1, 0.1, 1)
@export var visual_scale: Vector2 = Vector2.ONE
