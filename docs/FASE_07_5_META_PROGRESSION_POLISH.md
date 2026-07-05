# FASE 07.5 - Pulido de meta progresion, economia y recompensas

Pulido encima de FASE 07. No agrega Steam, logros, tienda real, multiplayer, audio
final ni menu principal completo. Ajusta economia, claridad del resumen, UI de
mejoras permanentes, robustez del save y protecciones contra doble recompensa.

## Nueva formula de Sardinas

```text
sardinas =
  base_por_mapa
  + tiempo_sobrevivido_segundos / 12
  + enemigos_eliminados * 0.15
  + gatos_rescatados * 8
  + companeros_vivos_final * 5
  + mini_jefes_derrotados * 18
  + jefes_derrotados * 45
  + bonus_objetivos
  + bonus_victoria
```

Multiplicadores: Barrio x1.00, Parque x1.15, Callejon Industrial x1.30, mas Mochila
de Sardinas si aplica. Morir antes de 30s limita recompensa baja; sobrevivir 60s o
mas garantiza una recompensa minima decente.

## Costos y limites

- Garras Afiladas: base 40, growth 1.35, max +30% dano inicial
- Patas Ligeras: base 35, growth 1.35, max +16% velocidad inicial
- Nueve Vidas: base 45, growth 1.40, max +50 vida maxima
- Instinto Felino: base 50, growth 1.42, max +24% XP
- Mochila de Sardinas: base 60, growth 1.45, max +40% Sardinas
- Llamado de la Colonia: base 55, growth 1.40, max primer rescate 20s antes
- Mecanica Gatuna: base 55, growth 1.40, max -10% cooldown inicial

La dificultad suma `permanent_power_score * 0.12`.

## UI y resumen

El resumen final muestra desglose de Sardinas por fuente, multiplicador de mapa y
Sardinas totales despues de cobrar. El panel de mejoras muestra nombre, categoria,
nivel, costo, efecto actual, efecto siguiente y estados `Comprar`, `No alcanza` o
`MAX`.

## Guardado y doble recompensa

- `_run_ended` y `_run_rewards_claimed` evitan doble recompensa.
- R reinicia despues de cobrar; M solo abre/cierra mejoras.
- El desbloqueo de mapa ahora se guarda despues de `unlock_map`.
- Save corrupto crea `cats_vs_zombie_dogs_save_corrupt_backup.json`.
- `reset_save()` requiere `debug_enable_save_reset = true`; para tests existe
  `force_reset_save_for_tests()`.

## Pruebas

- Morir antes de 30s: recompensa baja.
- Sobrevivir 3 minutos: recompensa mayor.
- Ganar mapa: bonus victoria y desglose.
- M tras terminar: comprar mejora, ver efecto actual/siguiente.
- Intentar comprar sin Sardinas: bloqueado.
- R varias veces: no duplica Sardinas.
- Cerrar y abrir Godot: progreso persiste.

## Recomendacion

Listo para playtest de economia. Si 4-5 runs se sienten justas, Fase 08 deberia ser
menu principal / seleccion real de mapa y vista de meta progresion antes de iniciar run.
