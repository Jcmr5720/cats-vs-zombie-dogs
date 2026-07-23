class_name LootCatalog
extends RefCounted
## FASE 13 — Fuente UNICA de presentacion del loot: categorias oficiales, rarezas,
## colores, iconos, lineas de efecto numerico, rasgos de armas, cajas y consejos
## de tutorial. HUD, minimapa, pickups y cajas leen SIEMPRE de aqui para que el
## mismo objeto se nombre y se dibuje igual en todas partes.
##
## Este archivo NO implementa efectos ni toca el balance: solo describe. Las
## magnitudes de EFFECT_LINES son un espejo de player.apply_upgrade() (la unica
## fuente de verdad mecanica); si alli cambia un numero, hay que actualizarlo aqui.

## Categorias OFICIALES de cara al jugador. Nunca mostrar "objeto" o "power-up"
## si existe una de estas. La forma del icono distingue ademas del color (regla
## anti-daltonismo de toda la fase).
const CATEGORY_INFO: Dictionary = {
	&"weapon": {
		"label": "Arma", "color": Color(1.0, 0.82, 0.4),
		"icon": &"weapon_projectile", "toast": "NUEVA ARMA", "sfx": &"weapon_found",
	},
	&"upgrade": {
		"label": "Mejora", "color": Color(0.55, 0.9, 1.0),
		"icon": &"upgrade", "toast": "MEJORA OBTENIDA", "sfx": &"powerup_collect",
	},
	&"companion": {
		"label": "Mejora de compañero", "color": Color(0.62, 1.0, 0.72),
		"icon": &"companion", "toast": "MEJORA DE COMPAÑERO", "sfx": &"powerup_collect",
	},
	&"mutation": {
		"label": "Mutación", "color": Color(0.95, 0.55, 1.0),
		"icon": &"star", "toast": "MUTACIÓN ACTIVADA", "sfx": &"mutation_activate",
	},
	&"core": {
		"label": "Núcleo de evolución", "color": Color(0.85, 0.55, 1.0),
		"icon": &"star", "toast": "ARMA EVOLUCIONADA", "sfx": &"evolution_complete",
	},
}

## Rareza -> etiqueta y color. Solo presentacion: el peso real del sorteo sigue
## siendo drop_weight / rarity_weight en los .tres.
const RARITY_INFO: Dictionary = {
	&"common": {"label": "común", "color": Color(0.78, 0.82, 0.88)},
	&"rare": {"label": "poco común", "color": Color(0.55, 0.9, 1.0)},
	&"epic": {"label": "épica", "color": Color(0.8, 0.55, 1.0)},
	&"legendary": {"label": "legendaria", "color": Color(1.0, 0.82, 0.3)},
}

## Efecto numerico principal en lenguaje llano. ESPEJO de player.apply_upgrade():
## si cambia una magnitud alli, cambiarla aqui. Un test comprueba que todos los
## power-ups del registro tienen linea.
const EFFECT_LINES: Dictionary = {
	&"weapon_damage": "+10 % de daño con todas las armas",
	&"weapon_cooldown": "Tus armas disparan un 10 % más rápido",
	&"player_speed": "+6 % de velocidad al moverte",
	&"max_health": "+15 de vida máxima (y te cura esos puntos)",
	&"extra_projectile": "+1 proyectil en las armas que disparan balas",
	&"weapon_range": "+10 % de alcance con tus armas",
	&"pickup_range": "Recoges experiencia desde un 25 % más lejos",
	&"companion_damage": "+10 % de daño de tus compañeros",
	&"companion_cooldown": "Tus compañeros atacan un 10 % más rápido",
	&"medic_boost": "El gato médico cura 2 puntos más",
	&"colony_protection": "Tus compañeros reciben un 10 % menos de daño",
	&"quick_revive": "Levantas a los compañeros caídos un 20 % más rápido",
	&"colony_bond": "+5 % de daño para ti con 2 o más compañeros activos",
	&"mut_split_shots": "+2 proyectiles en las armas que disparan balas",
	&"mut_savage_power": "+35 % de daño con todas las armas",
	&"mut_frenzy": "Todas tus armas disparan un 30 % más rápido",
	&"mut_iron_hide": "+40 de vida máxima y un 10 % menos de daño recibido",
	&"mut_wind_paws": "+15 % de velocidad y recoges experiencia desde mucho más lejos",
}

## Cajas: identidad completa por rol. El nucleo NO es una caja (no aparece aqui:
## lo sueltan los jefes ya abierto).
const CRATE_INFO: Dictionary = {
	&"weapon_crate": {
		"label": "Caja de armas", "color": Color(0.95, 0.75, 0.35),
		"icon": &"weapon_projectile", "hint": "Contiene un arma",
	},
	&"supply_crate": {
		"label": "Caja de suministros", "color": Color(0.55, 0.85, 0.95),
		"icon": &"plus", "hint": "Contiene una mejora",
	},
	&"special_crate": {
		"label": "Caja especial", "color": Color(0.85, 0.55, 1.0),
		"icon": &"star", "hint": "Mejora rara o mutación",
	},
}

## Consejos de tutorial (una vez por perfil, reiniciables desde Opciones→Juego).
## La clave del guardado es "tip_seen_" + id.
const TIPS: Dictionary = {
	&"crate": "Golpea las cajas para conseguir equipo.",
	&"weapon": "Las armas añaden nuevas formas de atacar.",
	&"upgrade": "Las mejoras aumentan permanentemente tu poder durante esta partida.",
	&"mutation": "Las mutaciones cambian reglas importantes de tu build.",
	&"core": "Los núcleos evolucionan automáticamente un arma compatible.",
	&"swap": "Mantén la tecla indicada para cambiar un arma. La descartada quedará en el suelo.",
	&"build_panel": "Pulsa B para revisar tu build (armas, mejoras y mutaciones).",
}

## Icono del HUD por tipo de arma (mismo mapa que usaba el HUD; centralizado).
const WEAPON_TYPE_ICON: Dictionary = {
	&"projectile": &"weapon_projectile",
	&"explosive": &"weapon_explosive",
	&"boomerang": &"weapon_boomerang",
	&"laser": &"weapon_laser",
	&"orbital": &"weapon_orbital",
	&"area": &"weapon_area",
}


# --- Categorias ---------------------------------------------------------------

## Categoria OFICIAL de un PowerUpData: stat -> mejora; companion -> mejora de
## compañero; mutation -> mutacion.
static func powerup_category(data) -> StringName:
	if data == null:
		return &"upgrade"
	match data.category:
		&"companion":
			return &"companion"
		&"mutation":
			return &"mutation"
	return &"upgrade"


static func category_label(category: StringName) -> String:
	return str(CATEGORY_INFO.get(category, CATEGORY_INFO[&"upgrade"])["label"])


static func category_color(category: StringName) -> Color:
	return CATEGORY_INFO.get(category, CATEGORY_INFO[&"upgrade"])["color"]


static func category_icon(category: StringName) -> StringName:
	return CATEGORY_INFO.get(category, CATEGORY_INFO[&"upgrade"])["icon"]


static func category_toast(category: StringName) -> String:
	return str(CATEGORY_INFO.get(category, CATEGORY_INFO[&"upgrade"])["toast"])


static func category_sfx(category: StringName) -> StringName:
	return CATEGORY_INFO.get(category, CATEGORY_INFO[&"upgrade"])["sfx"]


# --- Rareza -------------------------------------------------------------------

static func rarity_label(rarity: StringName) -> String:
	return str(RARITY_INFO.get(rarity, RARITY_INFO[&"common"])["label"])


static func rarity_color(rarity: StringName) -> Color:
	return RARITY_INFO.get(rarity, RARITY_INFO[&"common"])["color"]


## Linea "Categoria + rareza" para tarjetas: "Mejora poco común", "Arma rara"...
static func kind_line(category: StringName, rarity: StringName) -> String:
	return "%s %s" % [category_label(category), rarity_label(rarity)]


# --- Efectos ------------------------------------------------------------------

## Efecto numerico principal de un power-up ("+10 % de daño..."). Cadena vacia si
## el id no esta catalogado (el test de la fase lo impide para el registro real).
static func effect_line(effect_id: StringName) -> String:
	return str(EFFECT_LINES.get(effect_id, ""))


## Linea de estado actual -> resultado tras recoger, cuando se puede calcular
## algo concreto del jugador. Cadena vacia si no aporta nada.
static func powerup_state_line(data, player: Node) -> String:
	if data == null:
		return ""
	if data.effect_id() == &"max_health" and player != null:
		var current = player.get("max_health")
		if current != null:
			return "Vida máxima: %d → %d" % [int(current), mini(int(current) + 15, 220)]
	if data.is_mutation():
		return "Solo puede conseguirse una vez"
	if data.max_stacks > 0:
		return "Puedes conseguir esta mejora %d veces" % data.max_stacks
	return "Se puede recoger varias veces"


# --- Armas --------------------------------------------------------------------

static func weapon_icon(weapon_type: StringName) -> StringName:
	return WEAPON_TYPE_ICON.get(weapon_type, &"weapon_projectile")


## True si el WeaponData es una forma evolucionada (para la insignia del HUD).
static func is_evolved_weapon(data) -> bool:
	return data != null and data.rarity == &"legendary"


## Rasgos principales de un arma en 3 palabras clave: "Daño alto · Alcance corto
## · Explota en área". Para tarjetas y el panel de comparacion.
static func weapon_traits(data) -> String:
	if data == null:
		return ""
	var parts: Array[String] = []
	var damage: int = int(data.damage)
	if damage >= 16:
		parts.append("Daño alto")
	elif damage >= 9:
		parts.append("Daño medio")
	else:
		parts.append("Daño bajo")
	var weapon_range: float = float(data.range)
	if weapon_range >= 550.0:
		parts.append("Alcance largo")
	elif weapon_range >= 350.0:
		parts.append("Alcance medio")
	else:
		parts.append("Alcance corto")
	match data.weapon_type:
		&"projectile":
			parts.append("Disparo rápido" if float(data.cooldown) <= 0.6 else "Disparo directo")
		&"explosive":
			parts.append("Explota en área")
		&"boomerang":
			parts.append("Atraviesa enemigos")
		&"laser":
			parts.append("Rayo instantáneo")
		&"orbital":
			parts.append("Gira a tu alrededor")
		&"area":
			parts.append("Zona de daño")
	return " · ".join(parts)


## Aviso de evolucion en lenguaje llano (nunca "weapon evolution eligible").
static func weapon_evolution_hint(data) -> String:
	if data == null or data.evolution == null:
		return ""
	return "Esta arma puede evolucionar"


# --- Cajas --------------------------------------------------------------------

static func is_crate_role(role: StringName) -> bool:
	return CRATE_INFO.has(role)


static func crate_label(role: StringName) -> String:
	return str(CRATE_INFO.get(role, {}).get("label", "Caja"))


static func crate_color(role: StringName) -> Color:
	return CRATE_INFO.get(role, {}).get("color", Color(0.9, 0.8, 0.5))


static func crate_icon(role: StringName) -> StringName:
	return CRATE_INFO.get(role, {}).get("icon", &"plus")


static func crate_hint(role: StringName) -> String:
	return str(CRATE_INFO.get(role, {}).get("hint", ""))


## Prompt de proximidad de una caja: "Caja de armas — Golpéala para abrirla".
static func crate_prompt(role: StringName) -> String:
	return "%s — Golpéala para abrirla" % crate_label(role)


# --- Tutorial -----------------------------------------------------------------

static func tip_text(tip_id: StringName) -> String:
	return str(TIPS.get(tip_id, ""))
