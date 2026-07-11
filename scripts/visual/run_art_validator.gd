extends SceneTree
## Punto de entrada headless del validador de arte:
##   Godot --headless --path . --script res://scripts/visual/run_art_validator.gd
## Sale con codigo 1 si hay errores (usable en CI).


func _initialize() -> void:
	var ok: bool = ArtPipelineValidator.run_and_print()
	quit(0 if ok else 1)
