class_name ThemeColors
extends RefCounted
## Paleta compartida para mantener coherencia visual sin depender de assets externos.

const BG_DEEP := Color(0.04, 0.05, 0.075, 1.0)
const BG_PANEL := Color(0.08, 0.10, 0.14, 0.94)
const BG_PANEL_SOFT := Color(0.10, 0.12, 0.17, 0.86)

const TEXT := Color(0.90, 0.94, 1.0, 1.0)
const TEXT_DIM := Color(0.62, 0.68, 0.76, 1.0)

const CAT_GOLD := Color(0.97, 0.72, 0.36, 1.0)
const CAT_CREAM := Color(0.99, 0.92, 0.78, 1.0)
const CAT_POLICE := Color(0.28, 0.45, 0.78, 1.0)
const CAT_MEDIC := Color(0.88, 0.94, 0.86, 1.0)
const CAT_ENGINEER := Color(1.0, 0.58, 0.18, 1.0)

const ZOMBIE_GREEN := Color(0.38, 0.58, 0.34, 1.0)
const ZOMBIE_RUNNER := Color(0.52, 0.67, 0.34, 1.0)
const BOSS_RED := Color(0.92, 0.28, 0.24, 1.0)

const XP := Color(0.38, 0.78, 1.0, 1.0)
const SARDINE := Color(1.0, 0.82, 0.30, 1.0)
const HEALTH := Color(0.92, 0.34, 0.38, 1.0)
const CYAN := Color(0.45, 0.86, 1.0, 1.0)
const ORANGE := Color(1.0, 0.58, 0.20, 1.0)
const PURPLE := Color(0.62, 0.44, 0.88, 1.0)
const GOOD := Color(0.58, 1.0, 0.72, 1.0)
const WARNING := Color(1.0, 0.78, 0.36, 1.0)
const DANGER := Color(1.0, 0.48, 0.48, 1.0)

const RARITY_COMMON := Color(0.78, 0.82, 0.88, 1.0)
const RARITY_RARE := Color(0.36, 0.66, 1.0, 1.0)
const RARITY_EPIC := Color(0.78, 0.45, 1.0, 1.0)


static func rarity_color(rarity: StringName) -> Color:
	match rarity:
		&"rare":
			return RARITY_RARE
		&"epic":
			return RARITY_EPIC
		_:
			return RARITY_COMMON


static func state_color(state: StringName) -> Color:
	match state:
		&"hurt":
			return WARNING
		&"downed":
			return DANGER
		&"reviving":
			return GOOD
		_:
			return GOOD
