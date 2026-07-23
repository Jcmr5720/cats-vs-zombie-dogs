class_name PowerUpData
extends Resource
## Define un power-up recogible del suelo (FASE 12). Sustituye a las cartas del
## antiguo UpgradeManager: los pools hardcodeados (STAT_POOL / COMPANION_POOL /
## MUTATION_POOL) pasan a ser .tres, igual que las armas y las mejoras permanentes.
##
## CLAVE: este recurso NO implementa efectos. `upgrade_id` es el StringName que se
## pasa a player.apply_upgrade(), asi que el `match` de player.gd sigue siendo la
## UNICA fuente de verdad de lo que hace cada mejora. Anadir un power-up nuevo con
## un efecto ya existente = crear un .tres, sin tocar codigo.

@export var id: StringName = &"powerup"
## StringName que recibe player.apply_upgrade(). Normalmente igual a `id`; se
## separa para poder tener dos pickups distintos con el mismo efecto.
@export var upgrade_id: StringName = &""
@export var display_name: String = "Mejora"
@export var description: String = ""

## Familia del power-up:
##   &"stat"      : afecta al jugador o a todas sus armas.
##   &"companion" : afecta al CompanionManager (compartido en coop).
##   &"mutation"  : premio de jefe, mas potente que un stat normal.
@export var category: StringName = &"stat"

@export_group("Sorteo")
## &"common" | &"rare" | &"epic" | &"legendary". Solo lectura/presentacion: el
## peso real del sorteo es `drop_weight` (el LootDirector le suma el bono de
## rareza del Refugio en Modo Historia).
@export var rarity: StringName = &"common"
## Peso en la tabla de drops (mayor = mas frecuente). Sustituye a RARITY_WEIGHTS.
@export var drop_weight: float = 1.0
## Solo entra en la tabla si el jugador ya rescato algun companero.
@export var requires_companion: bool = false
## Veces que se puede recoger en una run. 0 = ilimitado; las mutaciones usan 1.
@export var max_stacks: int = 0

@export_group("Presentacion")
## A quien impacta, para el mensaje del HUD: "Armas" / "Jugador" / "Companeros".
@export var affects: String = "Jugador"
@export var visual_color: Color = Color(0.55, 0.9, 1.0, 1.0)
## Glifo de IconDrawer para dibujar el pickup en el suelo.
@export var icon_type: StringName = &"upgrade"


## Efecto que se aplicara al jugador. Cae a `id` si no se declaro `upgrade_id`,
## que es el caso normal.
func effect_id() -> StringName:
	return upgrade_id if upgrade_id != &"" else id


func is_mutation() -> bool:
	return category == &"mutation"
