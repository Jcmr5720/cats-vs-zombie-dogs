extends SceneTree
## Herramienta del pipeline (ETAPA ARTISTICA 1): genera la hoja de PRUEBA
## tecnica del gato (NO es arte final; es un munequito de validacion con
## marcas magenta) en assets/art/characters/players/test/test_cat_sheet.png.
##
## Uso (paso 1 de 2; despues correr --import y make_test_frames.gd):
##   Godot --headless --path . --script res://scripts/visual/tools/make_test_sprite.gd

const CELL: int = 128
const COLS: int = 4
const ROWS: int = 2  # fila 0: idle, fila 1: run
const OUT_PATH := "res://assets/art/characters/players/test/test_cat_sheet.png"


func _initialize() -> void:
	var img := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for col in COLS:
		_draw_frame(img, col, 0, false)
		_draw_frame(img, col, 1, true)
	var abs_path: String = ProjectSettings.globalize_path(OUT_PATH)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err: int = img.save_png(abs_path)
	print("test_cat_sheet.png -> %s (err=%d)" % [abs_path, err])
	quit(0 if err == OK else 1)


## Frame de prueba: cuerpo circular naranja + orejas triangulares + patas que
## alternan (run) o respiracion (idle) + cruz magenta de "esto es un TEST".
func _draw_frame(img: Image, col: int, row: int, running: bool) -> void:
	var ox: int = col * CELL
	var oy: int = row * CELL
	var center := Vector2(64, 64)
	var t: float = float(col) / float(COLS)
	# Cuerpo: radio que respira en idle; inclinado fijo en run.
	var radius: float = 30.0 + (sin(t * TAU) * 3.0 if not running else 0.0)
	var body := Color(0.96, 0.7, 0.38)
	var outline := Color(0.17, 0.1, 0.06)
	_disc(img, ox, oy, center, radius + 3.0, outline)
	_disc(img, ox, oy, center, radius, body)
	# Orejas (triangulos aproximados con discos decrecientes).
	for side in [-1.0, 1.0]:
		for k in 6:
			var p := center + Vector2(side * (14.0 + float(k) * 1.5), -radius + 2.0 - float(k) * 3.0)
			_disc(img, ox, oy, p, 7.0 - float(k), outline if k < 2 else body)
	# Patas: en run alternan adelante/atras por frame; en idle fijas.
	var step: float = (sin((t + 0.25 * float(col % 2)) * TAU) * 10.0) if running else 0.0
	_disc(img, ox, oy, center + Vector2(-12.0 + step, 44.0), 7.0, outline)
	_disc(img, ox, oy, center + Vector2(12.0 - step, 44.0), 7.0, outline)
	# Ojos.
	_disc(img, ox, oy, center + Vector2(-9, -6), 4.0, Color(0.1, 0.2, 0.14))
	_disc(img, ox, oy, center + Vector2(9, -6), 4.0, Color(0.1, 0.2, 0.14))
	# Marca de TEST: cruz magenta arriba-izquierda + numero de frame (barritas).
	for i in 9:
		_px(img, ox + 8 + i, oy + 12, Color.MAGENTA)
		_px(img, ox + 12, oy + 8 + i, Color.MAGENTA)
	for f in col + 1:
		for yy in 6:
			_px(img, ox + 24 + f * 4, oy + 9 + yy, Color.MAGENTA)
	# Linea de suelo de referencia (pivote): y = 112 dentro de la celda.
	for x in range(40, 88):
		_px(img, ox + x, oy + 112, Color(1, 0, 1, 0.5))


func _disc(img: Image, ox: int, oy: int, center: Vector2, radius: float, color: Color) -> void:
	var r: int = int(ceil(radius))
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if Vector2(x, y).length() <= radius:
				_px(img, ox + int(center.x) + x, oy + int(center.y) + y, color)


func _px(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, color)
