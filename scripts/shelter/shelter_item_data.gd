class_name ShelterItemData
extends Resource
## Objeto comprable del Refugio Felino (Fase 10), data-driven: agregar un objeto =
## crear un .tres en data/shelter_items y sumarlo a ShelterManager.ITEM_PATHS.
## Solo los objetos COLOCADOS en un slot otorgan su bonus.
##
## Tipos de efecto (los agrega ShelterBonusCalculator con topes de balance):
##   &"player_damage_pct"     : +% daño inicial del jugador.
##   &"player_speed_pct"      : +% velocidad inicial del jugador.
##   &"player_health_flat"    : +vida maxima inicial (plano).
##   &"companion_health_flat" : +vida maxima de compañeros (plano).
##   &"medic_heal_flat"       : +curacion del Gato Medico (plano).
##   &"engineer_damage_pct"   : +% daño del Gato Ingeniero.
##   &"police_damage_pct"     : +% daño del Gato Policia.
##   &"sardine_pct"           : +% Sardinas ganadas al final de la run.
##   &"upgrade_rarity_pct"    : +probabilidad de cartas raras/epicas.
##   &"rescue_first_seconds"  : el primer rescate aparece N s antes (piso 15 s).
##   &"rescue_distance_pct"   : los rescates aparecen un % mas cerca.
##   &"damage_reduction_pct"  : -% daño recibido por el jugador.

@export var id: StringName = &"item"
@export var display_name: String = "Objeto"
@export var description: String = ""
## Categoria: &"entrenamiento" / &"companeros" / &"economia" / &"rescate" / &"defensa".
@export var category: StringName = &"entrenamiento"
## Precio de compra (nivel 1).
@export var price: int = 80
## Nivel maximo (la compra deja el objeto en nivel 1).
@export var max_level: int = 5
## Costo de subir a nivel 2; crece con cost_growth por nivel.
@export var upgrade_base_cost: int = 50
@export var upgrade_cost_growth: float = 1.5
@export var effect_type: StringName = &"player_damage_pct"
## Valor del efecto que aporta CADA nivel.
@export var effect_value_per_level: float = 0.03
@export var visual_color: Color = Color(0.6, 0.45, 0.3)
@export var accent_color: Color = Color(1.0, 0.75, 0.3)
## Tamaño visual dentro del slot (para el dibujo procedural).
@export var size: Vector2 = Vector2(52, 44)
## Slots concretos permitidos ademas de los de su categoria (vacio = por categoria).
@export var allowed_slots: Array[StringName] = []
## Condicion de desbloqueo (reservado; vacio = siempre disponible).
@export var unlock_condition: StringName = &""
## Orden dentro de la tienda.
@export var sort_order: int = 0
