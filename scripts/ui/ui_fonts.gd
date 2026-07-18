class_name UIFonts
extends RefCounted
## Fuente única de la identidad tipográfica (rediseño Steam).
## Tres familias con roles fijos — ver assets/fonts/README.md:
##  - Fredoka (variable, eje wght): PRINCIPAL. HUD, botones, títulos, tarjetas.
##  - Nunito Sans (variable, eje wght): LECTURA. Descripciones, ajustes, diálogos.
##  - Lilita One: IMPACTO. Logo, BOSS/VICTORIA/DERROTA. Solo textos cortos.
## Los pesos se instancian desde el eje variable con FontVariation (un archivo
## por familia) y se cachean: pedir dos veces el mismo peso devuelve el mismo
## recurso, sin regeneración ni stuttering.
##
## Fallback de glifos: Lilita → Fredoka → Nunito Sans → sans-serif del sistema.
## Así nombres de jugador, símbolos de mando o traducciones futuras nunca
## muestran cuadros vacíos.

const FREDOKA_PATH := "res://assets/fonts/Fredoka-VariableFont.ttf"
const NUNITO_PATH := "res://assets/fonts/NunitoSans-VariableFont.ttf"
const LILITA_PATH := "res://assets/fonts/LilitaOne-Regular.ttf"

## Ningún texto del juego debe bajar de este tamaño (legibilidad en 720p y
## pantalla dividida), ni siquiera con la escala de accesibilidad "Pequeño".
const MIN_FONT_SIZE := 10

## Escala global de tamaño de texto (accesibilidad). La fija UITheme desde el
## ajuste "text_size" de Settings; el resto del código usa scaled().
static var text_scale: float = 1.0

static var _bases: Dictionary = {}
static var _cache: Dictionary = {}


## Fredoka en un peso del eje variable (500 Medium, 600 SemiBold, 700 Bold).
static func fredoka(weight: int = 500) -> Font:
	return _variation(FREDOKA_PATH, weight)


## Nunito Sans para lectura (400 Regular, 600 SemiBold, 700 Bold).
static func nunito(weight: int = 400) -> Font:
	return _variation(NUNITO_PATH, weight)


## Lilita One (peso único). Reservada a impactos cortos.
static func lilita() -> Font:
	_setup()
	return _bases[LILITA_PATH]


## Fredoka con cifras tabulares (tnum): el temporizador y los contadores no
## cambian de ancho con cada dígito. Si la fuente no trae la feature, el flag
## es inocuo.
static func fredoka_numeric(weight: int = 600) -> Font:
	var key := "num|%d" % weight
	if not _cache.has(key):
		var v := _variation(FREDOKA_PATH, weight).duplicate() as FontVariation
		v.opentype_features = {"tnum": 1}
		_cache[key] = v
	return _cache[key]


## Aplica la escala de accesibilidad respetando el tamaño mínimo legible.
static func scaled(size: int) -> int:
	return maxi(MIN_FONT_SIZE, int(round(size * text_scale)))


# --- Interno -------------------------------------------------------------------

static func _variation(path: String, weight: int) -> Font:
	var key := "%s|%d" % [path, weight]
	if _cache.has(key):
		return _cache[key]
	_setup()
	var v := FontVariation.new()
	v.base_font = _bases[path]
	# OJO: la clave debe ser "weight" (nombre que Godot mapea al eje wght);
	# con "wght" la coordenada se ignora y la fuente queda en su peso por
	# defecto (en Fredoka variable, 300 Light).
	v.variation_opentype = {"weight": weight}
	_cache[key] = v
	return v


## Carga las tres familias una sola vez y encadena los fallbacks sobre los
## recursos base (heredados por todas las variaciones de peso).
static func _setup() -> void:
	if not _bases.is_empty():
		return
	var fredoka_base: Font = load(FREDOKA_PATH)
	var nunito_base: Font = load(NUNITO_PATH)
	var lilita_base: Font = load(LILITA_PATH)
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["sans-serif"])
	nunito_base.fallbacks = [system]
	fredoka_base.fallbacks = [nunito_base]
	lilita_base.fallbacks = [fredoka_base]
	_bases = {
		FREDOKA_PATH: fredoka_base,
		NUNITO_PATH: nunito_base,
		LILITA_PATH: lilita_base,
	}
