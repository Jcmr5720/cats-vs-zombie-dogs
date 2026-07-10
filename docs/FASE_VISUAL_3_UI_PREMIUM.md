# FASE VISUAL 3 — UI premium, HUD, menús y presentación Steam

Estado real de partida: gran parte de la UI premium YA existía por fases
anteriores (Fase 08 menús + Fase 08.5 HUD minimalista + rediseño Steam de
MenuTheme). Esta fase **auditó todo el stack de UI contra el estándar premium,
cerró los huecos reales y documentó el sistema** en lugar de rehacer lo que ya
cumplía.

## Dirección UI (vigente, definida en MenuTheme)

- Paneles oscuros (`PANEL_BG` 0.085/0.10/0.145) con bordes de acento y sombra.
- Paleta única alineada con ThemeColors: naranja gato (acción), cian (info),
  verde pútrido (zombi/éxito), púrpura (sistema), dorado (sardinas), rojo
  (peligro).
- Tipografía por escala (`FS_DISPLAY` 52 → `FS_MICRO` 11), radios 12 px,
  espaciado por tokens (GAP_XS..XL).
- Todo procedural: formas, tweens e IconDrawer; cero assets externos.

## Auditoría: qué ya cumplía (verificado, sin tocar)

- **Menú principal**: fondo atmosférico animado (estrellas, luna, skyline con
  ventanas, silueta de gato, huellas), jerarquía primaria/secundaria/terciaria
  de botones, focus inicial.
- **Selector de mapas**: tarjetas por zona con preview del bioma, objetivo,
  dificultad, récords por dificultad, badges Bloqueado/Completado, segmentos
  Solo/Coop y dificultad.
- **HUD**: minimalista (vida/XP/nivel + tiempo + objetivo + chips de armas y
  compañeros), boss bar, combo, toasts de misión, barra fantasma de vida.
- **Cartas de mejora**: rareza con color/borde/glow, icono por tipo, textos
  compactados, animación de entrada, hover con escala, selección P2 con mando
  y foco inicial en la primera carta.
- **Resumen de partida**: títulos "ZONA ASEGURADA"/"COLONIA PERDIDA", mosaico
  de stat-cards (sardinas/puntuación, tiempo, enemigos, gatos, nivel, jefes),
  récord ★, desglose plegable, botones Reintentar/Menú con foco inicial.
- **Refugio/tienda y Estadísticas**: ya sobre MenuTheme (top bar, chips,
  paneles, stat-cards).
- **Opciones**: pestañas Vídeo/Juego/Audio/Datos con scroll y volver siempre
  visible (+ toggles visuales de la fase 2.5).

## Huecos cerrados en esta fase

1. **Logo compuesto del menú principal** (`main_menu.gd`): el título pasó de
   un Label plano de un color a un logo de tres piezas — "Cats" naranja,
   "vs" rojo pequeño con rotación ligera, "Zombie Dogs" verde pútrido — cada
   una con contorno y sombra propios, sobre una **marca de garra** de tres
   tajos diagonales dibujada en el fondo. Mantiene el sway vertical.
2. **Foco de gamepad visible en TODAS las variantes de botón**
   (`menu_theme.gd`): el estado `focus` ahora fuerza borde claro de 2 px con
   el acento aclarado; antes los botones `ghost` tenían foco invisible
   (focus == normal), rompiendo la navegación con mando en el menú principal
   (Mejoras/Progreso/Opciones) y otros.
3. **Pestaña "Controles" en Opciones** (`options_menu.gd`): referencia de
   controles P1/P2/pausa/atajos en pares título-valor, con nota de que el
   remapeo llegará en fase futura.
4. **Foco inicial donde faltaba**: selector de mapas (segmento Solo) y
   opciones (primer control de la pestaña activa, también al cambiar de
   pestaña). Ya lo tenían: menú principal, pausa, cartas, fin de partida.

## Gamepad / teclado — cobertura actual

| Pantalla | Foco inicial | Volver |
|---|---|---|
| Menú principal | Historia | — |
| Selector de mapas | Modo Solo | ESC / botón |
| Cartas de mejora | Carta 1 | (elección obligatoria) |
| Pausa | Continuar | ESC |
| Fin de partida | Reintentar | ESC → menú |
| Opciones | Primer control de pestaña | ESC / botón |

## Rendimiento y seguridad

- Sin overlays nuevos ni tweens persistentes: el logo son 3 Labels y 6 líneas
  en el `_draw()` ya existente; la pestaña Controles es contenido estático.
- Ninguna lógica de guardado, coop, jefes ni refugio tocada.
- Validación headless: compilación de los 4 scripts de UI editados, menú 600
  frames y MainLevel 1800 frames sin errores.

## Riesgos conocidos

- El foco automático en Opciones marca el primer toggle al entrar/cambiar de
  pestaña; con mouse es un realce leve (consistente con el resto del juego).
- El logo compuesto usa rotación en un Label dentro de HBox: en resoluciones
  muy estrechas el "vs" puede rozar las palabras vecinas (separación 14 px).
- El remapeo de controles no existe; la pestaña es solo referencia.

## Qué queda para FASE VISUAL 4

- Remapeo real de teclas/botones en la pestaña Controles.
- Pestaña "Accesibilidad" dedicada (hoy sus opciones viven en Vídeo/Juego:
  shake, números de daño, viñeta, luces).
- Ilustración/key-art del refugio y del selector (hoy previews procedurales).
- Transiciones entre pantallas (slide/fade direccional).
- Localización (hoy solo español).
- Capsule art e iconografía final para la página de Steam.
