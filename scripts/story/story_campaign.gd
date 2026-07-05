class_name StoryCampaign
extends RefCounted
## Definicion estatica de la campaña (Fase 09): rutas de capitulos, tabla de
## dificultad global y helpers de progreso sobre el SaveManager. Todo es puro y
## sin estado: la fuente de verdad vive en el save (story_chapters_cleared,
## story_difficulty, story_clear_<id>_d<tier>).

# Preload explicito (no depender de la cache global de class_name: los tests
# headless con -s corren sin escaneo previo del proyecto).
const ChapterData = preload("res://scripts/story/chapter_data.gd")

const CHAPTER_PATHS: Array[String] = [
	"res://data/story/chapter_1.tres",
	"res://data/story/chapter_2.tres",
	"res://data/story/chapter_3.tres",
	"res://data/story/chapter_4.tres",
	"res://data/story/chapter_5.tres",
	"res://data/story/chapter_6.tres",
]

const TOTAL_CHAPTERS: int = 6

## Dificultad global de la campaña. pressure multiplica la presion del spawner,
## health/speed/damage a los enemigos, y reward al total de sardinas en victoria.
const DIFFICULTIES: Array[Dictionary] = [
	{"id": &"facil", "name": "Facil", "pressure": 0.80, "health": 0.85, "speed": 0.97, "damage": 0.80, "reward": 1.0, "color": Color(0.55, 0.9, 0.42)},
	{"id": &"intermedio", "name": "Intermedio", "pressure": 1.00, "health": 1.00, "speed": 1.00, "damage": 1.00, "reward": 1.3, "color": Color(0.45, 0.85, 1.0)},
	{"id": &"dificil", "name": "Dificil", "pressure": 1.30, "health": 1.25, "speed": 1.05, "damage": 1.20, "reward": 1.7, "color": Color(1.0, 0.7, 0.25)},
	{"id": &"extremo", "name": "Extremo", "pressure": 1.70, "health": 1.50, "speed": 1.10, "damage": 1.50, "reward": 2.2, "color": Color(1.0, 0.35, 0.3)},
]


static func load_chapters() -> Array[ChapterData]:
	var out: Array[ChapterData] = []
	for path in CHAPTER_PATHS:
		var chapter := load(path) as ChapterData
		if chapter != null:
			out.append(chapter)
	return out


static func get_difficulty(tier: int) -> Dictionary:
	return DIFFICULTIES[clampi(tier, 0, DIFFICULTIES.size() - 1)]


## Clave de save del first-clear de un capitulo en un tier concreto.
static func clear_key(chapter_id: StringName, tier: int) -> String:
	return "story_clear_%s_d%d" % [chapter_id, tier]


static func chapters_cleared(save: Node) -> int:
	if save == null or not save.has_method("get_value"):
		return 0
	return clampi(int(save.get_value("story_chapters_cleared", 0)), 0, TOTAL_CHAPTERS)


## El capitulo N esta desbloqueado si completaste el N-1 (el 1 siempre lo esta).
static func is_chapter_unlocked(save: Node, number: int) -> bool:
	return number <= mini(chapters_cleared(save) + 1, TOTAL_CHAPTERS)


static func is_tier_cleared(save: Node, chapter_id: StringName, tier: int) -> bool:
	if save == null or not save.has_method("get_value"):
		return false
	return bool(save.get_value(clear_key(chapter_id, tier), false))


static func get_story_difficulty(save: Node) -> int:
	if save == null or not save.has_method("get_value"):
		return 1
	return clampi(int(save.get_value("story_difficulty", 1)), 0, DIFFICULTIES.size() - 1)


static func is_campaign_completed(save: Node) -> bool:
	return chapters_cleared(save) >= TOTAL_CHAPTERS


## Primer capitulo desbloqueado sin first-clear en el tier dado (para el boton
## "Continuar historia"). Si todo esta hecho, devuelve el ultimo capitulo.
static func first_pending_chapter(save: Node, chapters: Array[ChapterData], tier: int) -> ChapterData:
	for chapter in chapters:
		if not is_chapter_unlocked(save, chapter.number):
			break
		if not is_tier_cleared(save, chapter.id, tier):
			return chapter
	return chapters[chapters.size() - 1] if not chapters.is_empty() else null
