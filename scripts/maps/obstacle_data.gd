class_name ObstacleData
extends Resource
## Define un tipo de obstaculo de mapa de forma data-driven (Fase 08.75). El
## ObstacleSpawner instancia Obstacle.tscn y lo configura con uno de estos recursos.
## Todo es geometrico (formas + _draw), sin assets externos.
##
## `category` decide como se dibuja (carro, muro, arbol, contenedor, barril...).
## El tamaño se aleatoriza entre min_size y max_size para variedad.

## Identificador legible (solo para depuracion).
@export var id: StringName = &"obstacle"
## Estilo de dibujo: &"car", &"wall", &"house", &"container", &"barrel", &"tree",
## &"bench", &"rock", &"crate", &"fence", &"pipe", &"bush", &"sign".
@export var category: StringName = &"crate"

@export_group("Tamaño")
## Tamaño minimo/maximo del cuerpo (px). El obstaculo elige un valor intermedio.
@export var min_size: Vector2 = Vector2(34, 34)
@export var max_size: Vector2 = Vector2(40, 40)
## Rotacion aleatoria maxima (radianes). 0 = siempre alineado.
@export var max_rotation: float = 0.0

@export_group("Colores")
@export var body_color: Color = Color(0.30, 0.32, 0.38)
@export var detail_color: Color = Color(0.55, 0.60, 0.68)
@export var outline_color: Color = Color(0.10, 0.11, 0.14)
@export var accent_color: Color = Color(0.85, 0.7, 0.3)

@export_group("Colision y peso")
## Si es false, es pura decoracion (sin colision) y no cuenta para el cap colisionable.
@export var collidable: bool = true
## Forma de colision: &"rect" o &"circle".
@export var collision_shape: StringName = &"rect"
## Radio de bloqueo aprox. para validar spawns/steering (multiplo del semi-tamaño).
@export var block_scale: float = 1.0
## Peso relativo al elegir tipos para un mapa.
@export var spawn_weight: float = 1.0
## Offset de z-index (los altos, como arboles/casas, tapan un poco a los enemigos).
@export var z_offset: int = 0

@export_group("Interaccion con proyectiles (Fase 08.9)")
## Los proyectiles basicos chocan y se detienen contra este obstaculo.
@export var blocks_projectiles: bool = true
## El laser se detiene en este obstaculo (si es false, lo atraviesa).
@export var blocks_laser: bool = true

@export_group("Destructible (opcional)")
@export var destructible: bool = false
@export var health: int = 30
## XP que suelta al romperse (0 = nada).
@export var xp_reward: int = 0
## Barril/objeto que explota al romperse y daña a los enemigos cercanos.
@export var explosive: bool = false
@export var explosion_radius: float = 90.0
@export var explosion_damage: int = 22
