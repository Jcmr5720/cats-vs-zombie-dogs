# FASE VISUAL 1 — Base artística y mundo

Objetivo: subir la base visual del juego de "prototipo pulido" a una dirección
artística coherente inspirada en la filosofía de Ravenswatch (volumen aparente,
capas, siluetas fuertes, dramatismo y lectura inmediata) sin tocar gameplay,
colisiones, targeting ni sistemas.

## Dirección artística elegida

- **Fantasía oscura / postapocalipsis caricaturesco**: mundo en penumbra
  (fondos ya oscuros de fases previas) con personajes saturados que "iluminan"
  la escena. El contraste personaje-suelo es la herramienta principal de lectura.
- **Luz global implícita desde arriba-izquierda (NO)**: todos los rim lights
  nuevos van en el borde superior-izquierdo y todos los sombreados en el
  inferior-derecho. Es la convención que ya usaban lago/railes del suelo; ahora
  los personajes la comparten. Esto crea volumen sin shaders ni Light2D.
- **Sombras en dos capas**: cada actor proyecta una sombra suave grande
  (alpha ~0.12) + una densa pequeña (alpha ~0.26). El doble nivel despega al
  personaje del suelo (falso ambient occlusion).
- **Contorno unificado**: los gatos (jugador y compañeros) comparten un
  contorno umbra profundo `Color(0.17, 0.10, 0.06)` en lugar de marrones
  medios distintos por escena. Los enemigos siguen derivando su contorno del
  color de datos (`darkened(0.62)`), que ya era coherente.
- **Shading neutro en enemigos**: como los perros se tintan por `EnemyData`,
  el volumen se añade con polígonos de alpha neutra (sombra oscura translúcida
  y rim pálido translúcido) que funcionan sobre cualquier tinte, presente o futuro.

## Qué se rediseñó

### Jugador (`scenes/player/Player.tscn`)
- Doble sombra (SoftShadow + Shadow).
- Rim light superior-izquierdo en cuerpo y cabeza (`RimBody`, `RimHead`).
- Sombreado cálido inferior-derecho (`BodyShade`, `HeadShade`).
- Mechones de mejilla (`CheekTuftLeft/Right`): rompen la silueta de la cabeza,
  lectura felina más fuerte en movimiento.
- Golilla de pecho (`ChestRuff`): pelaje crema dentado bajo la bufanda, look
  más heroico.
- Contorno unificado más profundo (antes marrón medio 0.34/0.21/0.11).
- No se tocó ningún nodo que `player.gd` referencia (Tail, Scarf, EyeLeft/Right,
  FacingIndicator): animación, parpadeo y mirada direccional intactos.

### Enemigos (`scenes/enemies/Enemy.tscn` + `data/enemies/*.tres`)
- Doble sombra.
- `BackRim` y `BellyShade` como **hijos de Body**: heredan el trote (bob) sin
  tocar `enemy.gd`.
- Herida expuesta en el flanco (`Wound` + `WoundCore`) y muesca de mordisco en
  la oreja (`EarNotch`): lectura zombi inmediata, independiente del tinte.
- Paletas más enfermas y menos saturadas:
  - Zombie normal: verde pútrido más apagado.
  - Runner: rojo músculo expuesto más sucio.
  - Cachorro: ictericia más apagada.
  - Mastín (tanque): sin cambios (gris frío + ojos ascua ya funcionaba).
- La diferenciación por tipo ya existente (escala, spikes/collar solo en
  pesados, física distinta) se conserva íntegra.

### Compañeros (`scenes/companions/Companion.tscn` + `companion.gd`)
- Doble sombra, `BodyShade`, `RimBody`, contorno más profundo.
- **Chaleco de rol** (`Visual/Vest`, dos correas laterales): azul marino
  (Policía), blanco sanitario (Médico), naranja de obra (Ingeniero). Se colorea
  en `_apply_visuals()` vía `get_node_or_null` (no rompe escenas sin chaleco).
- Se suma al sistema existente de gorras + marcador de pecho por rol: ahora hay
  tres señales visuales de rol (gorro, chaleco, insignia).

### Jefe principal (`scenes/bosses/Boss.tscn`)
- Aura en tres capas (nueva `AuraOuter` de 118 px): presencia desde lejos.
- Doble fila de púas dorsales (`BackSpikesFar`, más oscura y alta): silueta
  mucho más dominante.
- `BodyShade`, `BodyRim` (rim violeta pálido), `HeadShade` como hijos de
  Body/Head: sobreviven al recolor por `BossData`.
- Cicatrices de flanco (`FlankScar`) y garras (`Claws`).
- Doble sombra más ancha.

### Mini-jefes (`scenes/bosses/MiniBoss.tscn`)
- Púas dorsales nuevas (antes silueta plana de "perro grande").
- `BodyShade`, `BodyRim`, garras y doble sombra.

### Mapas (`scripts/maps/chunk_ground_renderer.gd`)
Todo determinista por seed y dibujado una sola vez por chunk (0 coste/frame):
- **Barrio Gatuno**: hojas secas acumuladas fuera de las vías + marcas de
  garra felina en el pavimento con el color de acento del mapa (firma
  temática del barrio).
- **Parque Abandonado**: hojarasca otoñal (manchas + hojitas) que rompe el
  verde uniforme + grupos de setas (humedad/decadencia).
- **Callejón Industrial**: chatarra menuda (tuercas, esquirlas) + flechas de
  circulación estarcidas con el color de peligro en los corredores de carga.

## Decisiones visuales

1. **Nada de Light2D/shaders todavía**: el volumen se logra con polígonos de
   alpha (rim + shade) y sombras dobles. Es barato, estable y prepara la
   convención de luz para FASE VISUAL 2.
2. **Solo cambios aditivos en escenas**: ningún nodo referenciado por scripts
   fue renombrado ni eliminado. Los nodos nuevos de enemigos/jefes cuelgan de
   piezas animadas para heredar el movimiento gratis.
3. **El color por datos manda**: el shading de enemigos/jefes es neutro
   (negro/blanco translúcido) para que las variantes por `.tres` y los futuros
   jefes sigan funcionando sin tocar escenas.

## Preparado para FASE VISUAL 2 (iluminación/VFX)

- Convención de luz NO ya aplicada en personajes y suelo: colocar una
  DirectionalLight2D/CanvasModulate coherente será directo.
- Las sombras suaves pueden sustituirse por un shader de blob shadow sin tocar
  la estructura (mismo nodo `SoftShadow`).
- Los ojos de zombis/jefes ya tienen "glow" falso (EyeGlow); son el candidato
  natural para glow real (WorldEnvironment 2D HDR) en fase 2.

## Riesgos conocidos

- Los `.tscn` editados a mano se validaron con import headless, pero conviene
  abrirlos una vez en el editor para que Godot reserialice y asigne UIDs.
- El chaleco de compañeros usa `polygons` (multi-polígono): si se edita la
  forma en el editor hay que mantener los índices.
- Las barras/labels default de Companion (StatusLabel, ProgressBar) siguen con
  theme por defecto: se dejan para la fase de UI.

## Cómo probar

1. Ejecutar el juego y empezar partida en cada mapa.
2. Jugador: golilla, mechones, rim superior-izquierdo y doble sombra visibles;
   parpadeo/mirada intactos.
3. Matar perros de cada tipo: herida y oreja mordida visibles; el shading
   acompaña el trote.
4. Rescatar compañeros: chaleco de color distinto por rol.
5. Esperar mini-jefe (2:00-3:00): púas dorsales nuevas.
6. Validación sin editor:
   `Godot_v4.7-stable_win64_console.exe --headless --path . --quit-after 1800`
