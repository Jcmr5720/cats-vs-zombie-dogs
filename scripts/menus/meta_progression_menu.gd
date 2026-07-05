extends Control
## Pantalla de mejoras permanentes desde el menu (Fase 08). REUTILIZA el panel
## existente (MetaUpgradePanel) para no duplicar la logica de compra: lo instancia,
## lo abre y le superpone un boton Volver. Usa el mismo SaveManager/MetaProgression.

const MenuTheme = preload("res://scripts/menus/menu_theme.gd")
const META_PANEL_SCENE := preload("res://scenes/ui/MetaUpgradePanel.tscn")

var _panel: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = META_PANEL_SCENE.instantiate()
	add_child(_panel)
	# El boton "Cerrar" del panel vuelve al menu principal (evita doble boton Volver).
	_panel.set("on_close", Callable(GameFlow, "return_to_main_menu"))
	if _panel.has_method("open"):
		_panel.open()

	MenuTheme.add_fade_in(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameFlow.return_to_main_menu()
