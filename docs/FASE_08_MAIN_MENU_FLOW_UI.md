# FASE 08 - Main menu, seleccion de mapa y flujo UI

Fase de integracion sobre 07.5. El objetivo ya no es solo que la economia exista,
sino que el jugador pueda recorrerla con claridad desde que abre el juego hasta que
termina una run.

## Flujo completo

`MainMenu -> MapSelect -> MainLevel -> Resumen final -> Mejoras / Reintento / MainMenu`

- `MainMenu.tscn` es ahora la escena principal del proyecto.
- `GameFlow` conserva el mapa elegido y decide a que escena cambiar.
- `MapManager` sigue siendo quien cobra la run, evita doble recompensa y decide
  `R`, `M` y `ESC` al terminar.

## Menus

### Main menu

- Muestra CTA principal (`Jugar`) y accesos a `Mejoras`, `Estadisticas`,
  `Opciones` y `Salir`.
- Añade un panel de progreso visible: Sardinas, runs, victorias y mejora destacada.
- Fondo mas vivo: skyline, luna, huellas y silueta felina.

### Selector de mapa

- Cada mapa vive en una tarjeta propia.
- Estados visibles: `Disponible`, `Bloqueado`, `Completado`.
- Se enseÃ±a dificultad, duracion, objetivo, mejor tiempo y multiplicador de recompensa.
- Si un mapa esta bloqueado, enseÃ±a su requisito en la misma tarjeta.

### Meta progression menu

- Reutiliza `MetaUpgradePanel` para no duplicar la logica de compra.
- El panel ahora tiene tarjetas mas anchas, comparacion actual/siguiente, categoria,
  progreso por nivel y feedback visual claro al comprar.

### Stats menu

- Lee `SaveManager` sin asumir que todos los campos existen.
- Muestra runs, victorias, Sardinas actuales, Sardinas ganadas, kills, bosses,
  mini-bosses, gatos rescatados y mejor nivel.
- Resume por mapa: mejor tiempo + estado desbloqueado/completado.

### Options menu

- Usa el autoload `Settings`.
- Expone pantalla completa, shake on/off, intensidad de shake, numeros de dano y FPS.
- El reset de progreso pide confirmacion doble antes de llamar `SaveManager.reset_progress()`.

## HUD y resumen de run

- El panel de armas deja mas claro que el gato puede acumular hasta 4 armas.
- Cuando entra una arma nueva, su ranura hace pulso visual y aparece un mensaje.
- El resumen final muestra:
  - resultado
  - tiempo, kills, gatos, companeros, nivel
  - arsenal usado
  - Sardinas ganadas
  - desglose de la recompensa
  - Sardinas totales tras cobrar

## Diseno visual

- Se reforzo la lectura del estilo oscuro / arcade / gatuno sin assets externos.
- Los perros zombis ganaron mas silueta: collar, puas, cicatriz, pupilas y baba.
- El panel meta usa mejor los colores de categoria para que no se vea como una lista plana.

## Pausa

- `PauseMenu` se instancia desde el HUD.
- `ESC` durante gameplay abre/cierra la pausa.
- Si hay cartas de level up visibles, la pausa no interfiere.
- Si la partida ya termino, `ESC` vuelve a menu via `MapManager`, no abre pausa.
- Desde pausa:
  - `Continuar`
  - `Opciones` rapidas
  - `Volver al menu principal` con confirmacion

## Autoloads activos

- `Feedback` -> efectos visuales globales
- `SaveManager` -> progreso, economia y estadisticas
- `MetaProgression` -> mejoras permanentes y formula de Sardinas
- `Settings` -> ajustes globales y overlay de FPS
- `GameFlow` -> navegacion entre menus y gameplay

## Como probar cada pantalla

1. **MainMenu**
   - Abrir el proyecto.
   - Confirmar titulo, CTA `Jugar` y accesos a `Mejoras`, `Estadisticas`, `Opciones`.
2. **MapSelectMenu**
   - Entrar en `Jugar`.
   - Revisar los 3 mapas, estados y requisitos de bloqueo.
3. **MetaProgressionMenu**
   - Abrir `Mejoras` desde menu o `M` tras una run.
   - Confirmar Sardinas, categoria, costo, efecto actual y siguiente.
4. **StatsMenu**
   - Abrir `Estadisticas`.
   - Confirmar que lee datos del save sin errores.
5. **OptionsMenu**
   - Abrir `Opciones`.
   - Cambiar shake, FPS o fullscreen y volver.
   - Probar la doble confirmacion de reset.
6. **PauseMenu**
   - Iniciar una run.
   - Pulsar `ESC`, luego `ESC` otra vez para reanudar.
   - Abrir confirmacion de salida al menu.
7. **Post-run**
   - Terminar una run.
   - Verificar `R`, `M` y `ESC`.

## Criterio de exito cubierto

- El juego abre en menu principal.
- El selector real de mapas respeta desbloqueos.
- Estadisticas y meta progresion leen el save existente.
- La run vuelve a menu con `ESC`, reinicia con `R` y abre mejoras con `M`.
- La UI de progresion y recompensa es mas legible que en 07/07.5.

## Riesgos conocidos

- Validado en headless; falta playtest visual completo dentro del editor para ajuste fino
  de espaciados y sensacion.
- Las mejoras visuales siguen siendo geometricas; no sustituyen arte final.

## Pendiente natural para 08.5 / 09

- Playtest visual y de UX con ojos humanos para pulir espaciados y ritmo de navegacion.
- Profundizar estadisticas historicas si se quiere mas metagame.
- Mejorar ilustracion/arte final de menus y criaturas cuando la base de producto ya este estable.
