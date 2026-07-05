# Fase 10 - Identidad visual, arte procedural y VFX

## Resumen

Esta fase eleva la presentacion sin usar assets externos y sin agregar mecanicas grandes. El proyecto mantiene dibujo procedural con `Polygon2D`, `Line2D`, `_draw()` y controles custom.

## Cambios principales

- Se agrego `scripts/ui/theme_colors.gd` como referencia de paleta.
- Se agrego `scripts/ui/icon_drawer.gd` para iconos geometricos propios.
- El HUD usa iconos dibujados para armas, companeros y cartas de mejora.
- Options incluye calidad visual, efectos intensos y sombras.
- Feedback aplica limites distintos por calidad visual.
- Companions recibieron sombra simple para mayor profundidad.
- Se documenta la direccion de arte en `docs/FASE_10_ART_DIRECTION.md`.

## Jugador

El jugador ya cuenta con cuerpo felino procedural, outline, sombra, cola, orejas, ojos, bufanda, indicador de direccion, breathing idle, bounce de movimiento, flash de dano y feedback de level up por audio/evento. Debe seguir siendo la entidad mas reconocible de la pantalla.

## Companeros

Los companions se configuran por `CompanionData` y rol:

- Policia: azul/gris, gorra/placa, postura firme.
- Medico: claro/crema, cruz, efectos verdes/cyan.
- Ingeniero: naranja/amarillo, casco/herramienta, proyectiles mas pesados.

Estados visibles: activo, herido, derribado y reviviendo. Se agrego sombra procedural bajo el visual.

## Enemigos y jefes

Los perros zombis usan piezas separadas: cuerpo, hocico, ojos, orejas, cola, collar, dientes, heridas arcade y animacion torpe. Runners se distinguen por `EnemyData` con escala/color/velocidad. El jefe mantiene aura, ojos brillantes, telegrafo de embestida, cambio de fase y muerte con escala/fade.

## Armas y VFX

- Pistola Gatuna: proyectil limpio con halo/trail.
- Ovillo Explosivo: proyectil irregular y explosion circular.
- Sardina Boomerang: silueta tipo boomerang/pez y estela.
- Puntero Laser: linea brillante con fade e impacto.
- Rascador Giratorio: orbital con giro, spark y trail.
- Granada Catnip: area transparente con pulso.

Los efectos pasan por `Feedback`, que limita conteo para proteger FPS.

## Iconos y UI

Los iconos nuevos se dibujan por codigo en `IconDrawer`: gato, companero, salud, XP, sardina, armas, jefe, mapa y mejora. El HUD reduce texto en barras inferiores y las cartas de mejora usan icono visual grande mas rareza.

## Mapas

Los mapas ya usan `MapDecoration` y `Obstacle` para decoracion procedural por bioma:

- Barrio Gatuno: autos, edificios, senales y detalles urbanos.
- Parque: arbustos, bancas, manchas organicas.
- Industrial: contenedores, barriles, tuberias y peligro.

La regla es mejorar lectura sin aumentar obstaculos ni romper pathing.

## Performance

- `Feedback.max_active_effects` cambia por calidad visual.
- Baja: menos efectos activos y efectos intensos pueden apagar VFX cosmeticos.
- Media: limite equilibrado.
- Alta: mas efectos permitidos.
- No se agregan particulas pesadas ni assets grandes.
- F8 sigue siendo la herramienta para revisar FPS/conteos.

## Como agregar nuevos visuales

1. Elegir color desde `ThemeColors` o desde el `Data` del sistema.
2. Dibujar con formas simples y silueta clara.
3. Agregar sombra/outline solo si mejora lectura.
4. Pasar efectos temporales por `Feedback`.
5. Mantener limites de nodos y evitar trabajo complejo por frame.
6. Documentar cualquier asset final futuro sin hacerlo dependencia.

## Riesgos conocidos

- Algunos textos antiguos muestran mojibake por codificacion previa; evitar introducir mas caracteres no ASCII.
- La opcion de sombras queda preparada a nivel Settings/Feedback, pero algunas sombras de escena son nodos estaticos y no se ocultan globalmente aun.
- Los iconos son provisionales avanzados, no arte final de produccion.

## Faltante para arte final real

- Sprites finales licenciados o propios.
- Animaciones frame a frame o rigs dedicados.
- Revision completa de tipografia.
- Pase de color final por captura de gameplay real.
- Mas VFX especializados por jefe/evento si el rendimiento lo permite.
