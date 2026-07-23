extends Node2D
## Dummy de pruebas: registra el daño recibido (lo usan los tests de zonas).

var damage_taken: int = 0


func take_damage(amount: int, _knockback_dir: Vector2 = Vector2.ZERO) -> void:
	damage_taken += amount
