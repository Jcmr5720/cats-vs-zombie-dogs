# FASE 06.5 - Pulido visual de mapas, objetivos y victoria

Pulido encima de FASE 06. No agrega progresion permanente, guardado, tienda,
Steam, logros ni assets externos. Todo sigue hecho con formas, dibujo procedural,
colores, transparencias y tweens.

## Problemas detectados

- Los mapas ya existian, pero se sentian demasiado cercanos entre si.
- `MapData` no tenia suficientes parametros visuales para ajustar biomas sin tocar codigo.
- `MapDecoration` dibujaba pocos tipos de props por mapa.
- `MapBackground` seguia siendo una cuadricula urbana casi igual para todos.
- Objetivos, victoria y Game Over funcionaban, pero eran demasiado planos.

## Cambios por mapa

### Barrio Gatuno

- Fondo urbano nocturno con marcas de calle, guiones viales y ventanas lejanas.
- Decoracion: cajas, alcantarillas, senales y marcas pequenas.
- Paleta: azul/gris oscuro con cyan y amarillo suave.
- Objetivo: sobrevivir y derrotar al Rottweiler Alfa.

### Parque Abandonado

- Fondo verde oscuro con senderos diagonales y charcos sutiles.
- Decoracion: arbustos, bancos, manchas de pasto/tierra y detalles organicos.
- Paleta: verdes oscuros, marron apagado y verde zombi suave.
- Objetivo: rescatar 2 gatos y sobrevivir.

### Callejon Industrial

- Fondo de placas metalicas con lineas de riesgo.
- Decoracion: contenedores, tuberias, codos, franjas y marcas industriales.
- Paleta: gris oscuro, amarillo industrial, naranja y rojo suave.
- Objetivo: derrotar 2 mini-jefes.

## MapData visual

Campos agregados a `scripts/maps/map_data.gd`:

- `secondary_color`
- `hazard_color`
- `decoration_accent_color`
- `pattern_type`
- `pattern_strength`
- `decoration_density`
- `decoration_scale_min`
- `decoration_scale_max`
- `ambient_detail_count`
- `road_line_enabled`
- `hazard_line_enabled`
- `intro_message`
- `victory_message`
- `game_over_message`

Los recursos actualizados estan en `data/maps/`.

## MapBackground

`scripts/systems/background_grid.gd` ahora dibuja patrones segun `pattern_type`:

- `streets`: marcas de calle, dashes y ventanas lejanas.
- `park_paths`: senderos, charcos y textura organica.
- `industrial`: placas metalicas y lineas de advertencia.

Se mantiene en `_draw()` para evitar crear nodos extra.

## Decoracion

`scripts/maps/map_decoration.gd` ahora recibe el `MapData` completo y se instancia
desde `scenes/maps/MapDecoration.tscn`. Usa:

- densidad por mapa
- escala minima/maxima
- color de acento decorativo
- color hazard
- cantidad de detalles ambientales
- exclusion cerca del origen para no tapar al jugador al inicio

La decoracion sigue siendo visual: sin colisiones y sin afectar gameplay.

## HUD, intro y objetivos

El HUD ahora:

- muestra intro animada con nombre del mapa y objetivo
- muestra objetivo con formato mas claro
- muestra tiempo como progreso `actual / requerido`
- muestra jefe como `Pendiente` o `Derrotado`
- muestra gatos y mini-jefes con contadores directos
- muestra mensajes cortos al derrotar jefe/mini-jefe

## Victoria

La pantalla de victoria ahora:

- usa `victory_message` del mapa
- muestra subtitulo con nombre del mapa
- entra con tween
- agrega confeti geometrico simple
- resume tiempo, eliminados, gatos rescatados, companeros activos, armas, jefes,
  mini-jefes y nivel alcanzado

## Game Over

Game Over ahora muestra:

- mensaje por mapa (`game_over_message`)
- nombre del mapa
- tiempo sobrevivido
- eliminados
- gatos rescatados
- armas activas
- nivel alcanzado
- instruccion para reintentar con R

## Como probar

- **Partida A:** F1, revisar Barrio Gatuno: calles, cajas, alcantarillas, objetivo de jefe.
- **Partida B:** F2, revisar Parque Abandonado: senderos, arbustos, bancos, objetivo de rescate.
- **Partida C:** F3, revisar Callejon Industrial: placas, lineas hazard, tuberias, mini-jefes.
- **Partida D:** esperar un RescuePoint y verificar contraste en cada mapa.
- **Partida E:** revisar que enemigos, XP, proyectiles y jefes sigan por encima del fondo.
- **Partida F:** ganar y revisar `ZONA ASEGURADA` / mensaje de mapa + resumen.
- **Partida G:** perder y revisar Game Over con resumen.
- **Partida H:** presionar R y confirmar que no se duplica decoracion.
- **Partida I:** cambiar F1/F2/F3 y confirmar que no quedan residuos visuales.

## Riesgos conocidos

- Validado headless, falta playtest visual largo con ojos humanos.
- La decoracion sigue siendo procedural liviana; si se aumenta mucho la densidad puede
  competir con XP/proyectiles.
- Parque e Industrial todavia no tienen jefe unico propio; sus objetivos no lo exigen.
- No hay menu real de seleccion de mapa, solo `current_map_data` y F1/F2/F3.

## Listo para Fase 07

Estamos mas cerca, pero recomiendo una micro pasada de playtest visual real antes de
Fase 07: comprobar legibilidad de RescuePoints, XP y jefes en los tres mapas durante
una partida con muchos enemigos. Si eso se siente bien, Fase 07 ya puede ser el bucle
entre mapas/recompensa sin tocar persistencia todavia.
