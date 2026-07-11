class_name SpriteDirectionResolver
extends RefCounted
## Resuelve la direccion de un vector de movimiento hacia el sufijo de
## animacion y el flip horizontal (ETAPA ARTISTICA 1). Contrato de nombres:
## <animacion>_<sufijo> con sufijos {s, se, e, ne, n, nw, w, sw}. Con espejo
## permitido, las vistas oeste reutilizan las este con flip_h = true, asi el
## artista solo dibuja s, se, e, ne, n (5 de 8) o s, e, n (3 de 4).

## Devuelve {"suffix": String, "flip": bool} para un vector de movimiento.
## direction_count: 1 (sin sufijo), 4 o 8. `allow_flip` activa el espejo E->O.
static func resolve(direction: Vector2, direction_count: int, allow_flip: bool) -> Dictionary:
	if direction_count <= 1 or direction == Vector2.ZERO:
		return {"suffix": "", "flip": false}
	var angle: float = direction.angle()  # 0 = este, PI/2 = sur (y hacia abajo)

	if direction_count == 4:
		# Sectores de 90 grados centrados en E/S/O/N.
		var sector: int = wrapi(int(round(angle / (PI * 0.5))), 0, 4)
		match sector:
			0:
				return {"suffix": "e", "flip": false}
			1:
				return {"suffix": "s", "flip": false}
			2:
				return {"suffix": "e", "flip": true} if allow_flip else {"suffix": "w", "flip": false}
			_:
				return {"suffix": "n", "flip": false}

	# 8 direcciones: sectores de 45 grados.
	var octant: int = wrapi(int(round(angle / (PI * 0.25))), 0, 8)
	var suffixes: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
	var suffix: String = suffixes[octant]
	if allow_flip:
		# Las vistas del lado oeste se espejan desde su equivalente este.
		match suffix:
			"w":
				return {"suffix": "e", "flip": true}
			"sw":
				return {"suffix": "se", "flip": true}
			"nw":
				return {"suffix": "ne", "flip": true}
	return {"suffix": suffix, "flip": false}


## Nombre final de animacion: "run" + {"suffix": "se"} -> "run_se".
## Si los frames no tienen esa variante, cae al nombre sin sufijo.
static func animation_name(frames: SpriteFrames, base: StringName, suffix: String) -> StringName:
	if suffix != "":
		var with_suffix := StringName("%s_%s" % [base, suffix])
		if frames != null and frames.has_animation(with_suffix):
			return with_suffix
	return base
