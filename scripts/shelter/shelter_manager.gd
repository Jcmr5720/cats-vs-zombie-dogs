extends Node
## Autoload "Shelter" (Fase 10): gestiona el Refugio Felino. Carga los objetos
## disponibles, valida compras/mejoras/colocaciones contra el SaveManager y
## expone las bonificaciones activas (solo objetos COLOCADOS) al resto del juego.
##
## Persistencia: diccionario "shelter" en el save (purchased_items, item_levels,
## placed_slots, seen_tutorial, total_spent). Compatible con saves antiguos:
## si falta, se crean valores por defecto.

const ShelterItemData = preload("res://scripts/shelter/shelter_item_data.gd")
const ShelterBonusCalculator = preload("res://scripts/shelter/shelter_bonus_calculator.gd")

signal shelter_items_changed()
signal shelter_item_purchased(item_id: StringName)
signal shelter_item_upgraded(item_id: StringName, level: int)
signal shelter_item_placed(slot_id: StringName, item_id: StringName)
signal shelter_bonus_changed()

const ITEM_PATHS: Array[String] = [
	"res://data/shelter_items/combat_scratcher.tres",
	"res://data/shelter_items/agility_treadmill.tres",
	"res://data/shelter_items/training_bag.tres",
	"res://data/shelter_items/colony_beds.tres",
	"res://data/shelter_items/medical_station.tres",
	"res://data/shelter_items/tool_table.tres",
	"res://data/shelter_items/watch_post.tres",
	"res://data/shelter_items/sardine_storage.tres",
	"res://data/shelter_items/supply_box.tres",
	"res://data/shelter_items/meow_radio.tres",
	"res://data/shelter_items/shelter_map.tres",
	"res://data/shelter_items/cardboard_barricade.tres",
]

## Slots fijos del refugio: cada uno acepta ciertas categorias. El slot libre
## acepta todo: crea la decision de que activar cuando sobran objetos.
const SLOTS: Array[Dictionary] = [
	{"id": &"training_1", "label": "Entrenamiento 1", "categories": [&"entrenamiento"]},
	{"id": &"training_2", "label": "Entrenamiento 2", "categories": [&"entrenamiento"]},
	{"id": &"companions_1", "label": "Compañeros 1", "categories": [&"companeros"]},
	{"id": &"companions_2", "label": "Compañeros 2", "categories": [&"companeros"]},
	{"id": &"economy_1", "label": "Economia 1", "categories": [&"economia"]},
	{"id": &"rescue_1", "label": "Rescate 1", "categories": [&"rescate"]},
	{"id": &"defense_1", "label": "Defensa 1", "categories": [&"defensa"]},
	{"id": &"free_1", "label": "Libre", "categories": [&"entrenamiento", &"companeros", &"economia", &"rescate", &"defensa"]},
]

var _items: Array[ShelterItemData] = []
var _items_by_id: Dictionary = {}


func _ready() -> void:
	for path in ITEM_PATHS:
		var item: ShelterItemData = load(path)
		if item != null:
			_items.append(item)
			_items_by_id[str(item.id)] = item
	_items.sort_custom(func(a: ShelterItemData, b: ShelterItemData) -> bool: return a.sort_order < b.sort_order)


# --- Acceso a datos ------------------------------------------------------------

func get_items() -> Array[ShelterItemData]:
	return _items


func get_unlocked_items() -> Array[ShelterItemData]:
	var out: Array[ShelterItemData] = []
	for item in _items:
		if is_unlocked(item.id):
			out.append(item)
	return out


func get_item(item_id: StringName) -> ShelterItemData:
	return _items_by_id.get(str(item_id))


func is_unlocked(item_id: StringName) -> bool:
	var item := get_item(item_id)
	if item == null:
		return false
	var condition: String = str(item.unlock_condition).strip_edges()
	if condition == "":
		return true
	var save := _save_manager()
	if condition.begins_with("chapter_"):
		return _story_chapters_cleared(save) >= _condition_number(condition, "chapter_")
	if condition.begins_with("story_chapter_"):
		return _story_chapters_cleared(save) >= _condition_number(condition, "story_chapter_")
	if condition.begins_with("ch"):
		return _story_chapters_cleared(save) >= _condition_number(condition, "ch")
	if condition.begins_with("feature:"):
		var feature_id: String = condition.substr("feature:".length())
		return Array(save.get_value("unlocked_features", []) if save != null else []).has(feature_id)
	return true


func get_unlock_text(item_id: StringName) -> String:
	var item := get_item(item_id)
	if item == null:
		return ""
	var condition: String = str(item.unlock_condition).strip_edges()
	if condition == "":
		return ""
	if condition.begins_with("chapter_"):
		return "Completa capitulo %d" % _condition_number(condition, "chapter_")
	if condition.begins_with("story_chapter_"):
		return "Completa capitulo %d" % _condition_number(condition, "story_chapter_")
	if condition.begins_with("ch"):
		return "Completa capitulo %d" % _condition_number(condition, "ch")
	if condition.begins_with("feature:"):
		return "Desbloqueo especial"
	return "Bloqueado"


func get_slots() -> Array[Dictionary]:
	return SLOTS


func get_slot(slot_id: StringName) -> Dictionary:
	for slot in SLOTS:
		if slot["id"] == slot_id:
			return slot
	return {}


# --- Estado guardado -----------------------------------------------------------

func _save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")


## Diccionario "shelter" del save, siempre con estructura completa.
func _state() -> Dictionary:
	var sm := _save_manager()
	var raw: Variant = sm.get_value("shelter", {}) if sm != null else {}
	var state: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	if not state.has("purchased_items"):
		state["purchased_items"] = []
	if not state.has("item_levels"):
		state["item_levels"] = {}
	if not state.has("placed_slots"):
		state["placed_slots"] = {}
	if not state.has("seen_tutorial"):
		state["seen_tutorial"] = false
	if not state.has("total_spent"):
		state["total_spent"] = 0
	return state


func _write_state(state: Dictionary, persist: bool = true) -> void:
	var sm := _save_manager()
	if sm != null:
		sm.set_value("shelter", state, persist)


func is_purchased(item_id: StringName) -> bool:
	return Array(_state()["purchased_items"]).has(str(item_id))


## Nivel del objeto (1 al comprarse; 0 si no esta comprado).
func get_level(item_id: StringName) -> int:
	if not is_purchased(item_id):
		return 0
	return maxi(1, int(Dictionary(_state()["item_levels"]).get(str(item_id), 1)))


func get_placed_slots() -> Dictionary:
	return Dictionary(_state()["placed_slots"]).duplicate()


func get_item_in_slot(slot_id: StringName) -> StringName:
	return StringName(str(Dictionary(_state()["placed_slots"]).get(str(slot_id), "")))


## Slot donde esta colocado el objeto (&"" si no esta colocado).
func get_slot_of_item(item_id: StringName) -> StringName:
	var placed: Dictionary = _state()["placed_slots"]
	for slot_id in placed:
		if str(placed[slot_id]) == str(item_id):
			return StringName(str(slot_id))
	return &""


func is_placed(item_id: StringName) -> bool:
	return get_slot_of_item(item_id) != &""


func has_seen_tutorial() -> bool:
	return bool(_state()["seen_tutorial"])


func mark_tutorial_seen() -> void:
	var state := _state()
	state["seen_tutorial"] = true
	_write_state(state)


func get_total_spent() -> int:
	return int(_state()["total_spent"])


# --- Compra y mejora -----------------------------------------------------------

func can_purchase(item_id: StringName) -> bool:
	var item := get_item(item_id)
	var sm := _save_manager()
	if item == null or sm == null or is_purchased(item_id) or not is_unlocked(item_id):
		return false
	return sm.get_sardines() >= item.price


func purchase(item_id: StringName) -> bool:
	if not can_purchase(item_id):
		return false
	var item := get_item(item_id)
	var sm := _save_manager()
	if not sm.spend_sardines(item.price):
		return false
	var state := _state()
	state["purchased_items"].append(str(item_id))
	state["item_levels"][str(item_id)] = 1
	state["total_spent"] = int(state["total_spent"]) + item.price
	_write_state(state)
	shelter_item_purchased.emit(item_id)
	shelter_items_changed.emit()
	return true


## Costo de subir al siguiente nivel; -1 si no comprado o ya al maximo.
func get_upgrade_cost(item_id: StringName) -> int:
	var item := get_item(item_id)
	var level: int = get_level(item_id)
	if item == null or level <= 0 or level >= item.max_level:
		return -1
	return int(round(item.upgrade_base_cost * pow(item.upgrade_cost_growth, level - 1)))


func can_upgrade(item_id: StringName) -> bool:
	var sm := _save_manager()
	var cost: int = get_upgrade_cost(item_id)
	return sm != null and cost > 0 and sm.get_sardines() >= cost


func upgrade(item_id: StringName) -> bool:
	if not can_upgrade(item_id):
		return false
	var cost: int = get_upgrade_cost(item_id)
	var sm := _save_manager()
	if not sm.spend_sardines(cost):
		return false
	var state := _state()
	var new_level: int = get_level(item_id) + 1
	state["item_levels"][str(item_id)] = new_level
	state["total_spent"] = int(state["total_spent"]) + cost
	_write_state(state)
	shelter_item_upgraded.emit(item_id, new_level)
	shelter_items_changed.emit()
	if is_placed(item_id):
		shelter_bonus_changed.emit()
	return true


# --- Colocacion ----------------------------------------------------------------

## True si el objeto puede ir en ese slot (categoria compatible o slot explicito).
func slot_accepts(slot_id: StringName, item_id: StringName) -> bool:
	var item := get_item(item_id)
	var slot := get_slot(slot_id)
	if item == null or slot.is_empty():
		return false
	if not item.allowed_slots.is_empty() and item.allowed_slots.has(slot_id):
		return true
	return Array(slot["categories"]).has(item.category)


## Coloca un objeto comprado en un slot libre y compatible. Si el objeto ya
## estaba en otro slot, se muda (nunca puede estar en dos a la vez).
func place_item(slot_id: StringName, item_id: StringName) -> bool:
	if not is_purchased(item_id) or not is_unlocked(item_id) or not slot_accepts(slot_id, item_id):
		return false
	var state := _state()
	var placed: Dictionary = state["placed_slots"]
	# Slot ocupado por OTRO objeto: rechazar (hay que quitarlo primero).
	var current: String = str(placed.get(str(slot_id), ""))
	if current != "" and current != str(item_id):
		return false
	# Quitar el objeto de su slot anterior (mudanza).
	for other_slot in placed.keys():
		if str(placed[other_slot]) == str(item_id):
			placed.erase(other_slot)
	placed[str(slot_id)] = str(item_id)
	state["placed_slots"] = placed
	_write_state(state)
	shelter_item_placed.emit(slot_id, item_id)
	shelter_items_changed.emit()
	shelter_bonus_changed.emit()
	return true


func remove_from_slot(slot_id: StringName) -> bool:
	var state := _state()
	var placed: Dictionary = state["placed_slots"]
	if not placed.has(str(slot_id)):
		return false
	placed.erase(str(slot_id))
	state["placed_slots"] = placed
	_write_state(state)
	shelter_items_changed.emit()
	shelter_bonus_changed.emit()
	return true


# --- Bonificaciones ------------------------------------------------------------

## Diccionario de bonus activos (solo objetos colocados), con topes de balance.
func get_bonuses() -> Dictionary:
	var state := _state()
	return ShelterBonusCalculator.compute(_items_by_id, state["item_levels"], state["placed_slots"])


func get_bonus(key: String) -> float:
	return float(get_bonuses().get(key, 0.0))


## Poder del refugio para la dificultad dinamica (solo objetos colocados).
func get_power_score() -> float:
	var state := _state()
	return ShelterBonusCalculator.power_score(_items_by_id, state["item_levels"], state["placed_slots"])


func _story_chapters_cleared(save: Node) -> int:
	if save == null or not save.has_method("get_value"):
		return 0
	return clampi(int(save.get_value("story_chapters_cleared", 0)), 0, 6)


func _condition_number(condition: String, prefix: String) -> int:
	var raw: String = condition.substr(prefix.length())
	return maxi(0, raw.to_int() if raw.is_valid_int() else 0)
