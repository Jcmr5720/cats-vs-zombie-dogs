class_name ChapterData
extends Resource
## Capitulo del Modo Historia (Fase 09), data-driven: agregar un capitulo = crear
## un .tres en data/story/ y sumarlo a StoryCampaign.CHAPTER_PATHS. El capitulo
## une narrativa (paneles de cinematica) con un MapData jugable y su recompensa.

@export var id: StringName = &"chapter"
## Numero de capitulo 1..6 (define el orden y el desbloqueo).
@export var number: int = 1
@export var title: String = "Capitulo"
## Frase corta que resume el capitulo (se muestra en la pantalla de Historia).
@export var tagline: String = ""
## Mapa que se juega en este capitulo (los caps 1-3 reusan los mapas base).
@export var map: MapData
## Paneles de la cinematica de entrada: [{title, body, kind}]. kind decide el
## fondo procedural (&"city", &"dogs", &"cats", &"hero", &"storm", &"park",
## &"park_dark", &"factory", &"dawn").
@export var cinematic_panels: Array[Dictionary] = []
## Paneles del final de la campaña (solo el capitulo 6 los define).
@export var ending_panels: Array[Dictionary] = []
## Sardinas base al completar por primera vez (se multiplica por la dificultad).
@export var first_clear_reward: int = 80
## Color de acento del capitulo (tinta la cinematica y su nodo en el menu).
@export var accent_color: Color = Color(1.0, 0.6, 0.2)
