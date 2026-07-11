extends SceneTree
## Chequeo AUTOMATICO de paquetes en assets/art/_incoming/ (ETAPA ARTISTICA 3).
## Valida solo lo objetivo (dimensiones, alfa, halos aproximados, nombres);
## la consistencia de diseno/anatomia/luz sigue siendo revision humana
## (ART_ASSET_ACCEPTANCE_CHECKLIST.md).
##
##   Godot_console --headless --path . --script res://scripts/visual/tools/incoming_check.gd
##
## Salida: reporte por archivo + resumen. Exit code 1 si hay fallos.

const ROOT := "res://assets/art/_incoming"
## Lados de celda validos (cuadradas) u hojas multiples de estos.
const VALID_CELLS: Array[int] = [64, 128, 192, 256, 384, 512]
## Patron de nombre: <id>_<anim>_<dir>_v##_f##.png o <id>_master_v##.png
var _name_regex := RegEx.new()
var _master_regex := RegEx.new()


func _initialize() -> void:
	_name_regex.compile("^[a-z0-9_]+_(idle|run|attack|hurt|downed|revive|death|ability|basic_attack|special_attack|charge_windup|charge|summon|phase_change)(_(n|ne|e|se|s|sw|w|nw))?_v\\d{2}_f\\d{2}\\.png$")
	_master_regex.compile("^[a-z0-9_]+_master_v\\d{2}\\.png$")

	var pngs: Array[String] = _find_pngs(ROOT)
	if pngs.is_empty():
		print("[incoming_check] Sin PNG en %s — nada que validar (Gate B sigue esperando arte)." % ROOT)
		quit(0)
		return

	var failures: int = 0
	for path in pngs:
		var issues: Array[String] = _check_file(path)
		if issues.is_empty():
			print("OK      %s" % path)
		else:
			failures += 1
			print("FALLA   %s" % path)
			for issue in issues:
				print("        - %s" % issue)
	print("[incoming_check] %d archivos, %d con fallos" % [pngs.size(), failures])
	quit(0 if failures == 0 else 1)


func _check_file(path: String) -> Array[String]:
	var issues: Array[String] = []
	var file_name: String = path.get_file()

	# Nombre segun convencion (los master tienen patron propio).
	if _name_regex.search(file_name) == null and _master_regex.search(file_name) == null:
		issues.append("nombre fuera de convencion (<id>_<anim>_<dir>_v01_f01.png)")
	# Estado de carpeta: raw/clean/aligned.
	if not (path.contains("/raw/") or path.contains("/clean/") or path.contains("/aligned/")):
		issues.append("fuera de raw/, clean/ o aligned/")

	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) != OK:
		issues.append("no se puede cargar como imagen")
		return issues

	# Alfa real.
	if not img.detect_alpha():
		issues.append("sin canal alfa util (fondo opaco)")
	else:
		# Esquinas transparentes (fondo pintado = esquinas opacas).
		var w: int = img.get_width()
		var h: int = img.get_height()
		for corner in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
			if img.get_pixelv(corner).a > 0.05:
				issues.append("esquina opaca (%s): posible fondo sin limpiar" % str(corner))
				break
		# Halo blanco aproximado: pixeles casi transparentes pero muy claros
		# en el contorno (muestreo barato de toda la imagen cada 4 px).
		var halo: int = 0
		for y in range(0, h, 4):
			for x in range(0, w, 4):
				var p: Color = img.get_pixel(x, y)
				if p.a > 0.02 and p.a < 0.35 and p.r > 0.9 and p.g > 0.9 and p.b > 0.9:
					halo += 1
		if halo > 12:
			issues.append("posible halo blanco (%d muestras claras semitransparentes)" % halo)

	# Dimensiones: solo estricto en aligned/ (raw/clean pueden venir sueltos).
	if path.contains("/aligned/"):
		var ok_size: bool = false
		for cell in VALID_CELLS:
			if img.get_width() % cell == 0 and img.get_height() % cell == 0 \
				and img.get_width() <= 2048 and img.get_height() <= 2048:
				ok_size = true
				break
		if not ok_size:
			issues.append("dimensiones %dx%d no son multiplo de celda valida (o exceden 2048)" % [img.get_width(), img.get_height()])
	return issues


func _find_pngs(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = root.path_join(entry)
		if dir.current_is_dir() and not entry.begins_with("."):
			found.append_array(_find_pngs(full))
		elif entry.to_lower().ends_with(".png"):
			found.append(full)
		entry = dir.get_next()
	return found
