# ART DIRECTION BIBLE — Cats vs Zombie Dogs

Documento oficial de dirección artística. Toda pieza de arte nueva (dibujada,
generada o procedural) debe medirse contra este documento.

## Identidad

**Fantasía oscura caricaturesca con humor felino.** Gatos heroicos y
expresivos defienden su colonia de perros zombis grotescos pero caricaturescos
en una ciudad postapocalíptica en penumbra. Pintura digital estilizada con
volumen: ni pixel art, ni vector plano, ni hiperrealismo, ni gore realista,
ni estética infantil brillante. Inspiración de *filosofía* (no de diseño):
Ravenswatch, Hades — siluetas fuertes, contraste dramático, lectura instantánea.

## Perspectiva

- **Top-down 3/4**: se ve la parte superior Y el frente del cuerpo
  (aprox. cámara a 50–60° sobre el horizonte).
- El personaje debe leerse en movimiento en cualquier dirección.
- NO vista lateral pura, NO isométrico estricto.
- El suelo se dibuja casi cenital; los props con frente visible y techo corto.

## Iluminación (convención obligatoria, ya implementada en el juego)

- Luz principal **desde arriba-izquierda (NO)**.
- Sombra de forma hacia **abajo-derecha**; sombra de contacto elíptica bajo
  los pies (el juego añade la doble sombra — el sprite NO pinta sombra de suelo).
- Rim light discreto en el borde superior-izquierdo.
- Jefes: iluminación más dramática (rim más fuerte, acentos emisivos).
- Enemigos comunes: menos luminosos que jugadores y objetivos.

## Jerarquía de lectura (de más a menos contraste/saturación)

1. Jugadores → 2. Ataques enemigos peligrosos → 3. Jefes y élites →
4. Enemigos comunes → 5. Compañeros → 6. XP/rescates/interactivos →
7. Decoración → 8. Fondo.

El escenario nunca tapa información: nada del suelo puede usar los colores
reservados de XP (cian), curación (verde claro) o peligro (rojo saturado).

## Lenguaje de formas

### Gatos protagonistas
Triángulos y curvas ágiles; orejas, cola y rostro siempre legibles en la
silueta; pose erguida heroica; equipamiento funcional pequeño (bufanda,
collar, arnés); colores cálidos y limpios. P1 = naranja atigrado con bufanda
azul. P2 = misma base con tinte frío azulado y distintivo propio.

### Perros zombis
Masas pesadas, rotas, asimétricas; espalda arqueada, mandíbula y patas
exageradas; silueta claramente canina incluso podrida; heridas ESTILIZADAS
(parches de color, costuras, mordiscos limpios — no vísceras); colores
pútridos desaturados; ojos y zonas infectadas como únicos puntos brillantes.

### Compañeros
Misma base felina que el jugador, con rol legible a distancia:
- **Policía**: estructura firme, azul marino, gorra y placa dorada.
- **Médico**: formas suaves, blanco apagado + verde, gorro con cruz.
- **Ingeniero**: formas angulares, naranja de obra + casco, tuerca.

### Jefes
Silueta más ANCHA y dominante — proporciones distintas, no un enemigo
escalado; detalles que se lean desde lejos (doble fila de púas, cicatrices
luminosas, arnés roto); aura y color de acento propios; mutaciones únicas
por jefe.

## Paletas (hex aproximado — coinciden con las constantes del juego)

| Grupo | Base | Secundario | Acento |
|---|---|---|---|
| P1 (gato líder) | #F5B361 naranja | #FDEBC7 crema | #33A6F2 bufanda |
| P2 | base + tinte frío #9EC7F2 | — | etiqueta cian |
| Policía | #5CA3F5 | #24386B gorra | #F2D159 placa |
| Médico | #F2F7E6 | #38B873 verde | #E04048 cruz |
| Ingeniero | #F2B85C | #FA9E24 casco | #61290F |
| Zombi normal | #527D4A verde pútrido | #33502E | ojos #F5DC33 |
| Runner | #944D4D músculo sucio | #BD6142 | ojos #FFD940 |
| Cachorro | #807540 ictericia | #665C33 | ojos #80FF66 |
| Mastín (tanque) | #525C70 gris frío | #333D52 | ojos #F25933 |
| Jefe (Rottweiler Alfa) | #52356B púrpura | #29184F púas | ojos #FFC733, nariz #FF3D2E |
| Mini-jefe | #80756B pardo | #524A3D | ojos #FFB340 |

| Bioma / sistema | Suelo/fondo | Acento | Peligro/extra |
|---|---|---|---|
| Barrio Gatuno | #1C1F26 azul noche | #73E6FF cian | #F2B840; ambiente ×(0.84,0.87,1.08) |
| Parque Abandonado | #17241A verde oscuro | #8CE66B | niebla verde-gris; ambiente ×(0.82,0.98,0.86) |
| Callejón Industrial | #211F1A gris cálido | #F2C733 | #FF6B2E; ambiente ×(1.04,0.92,0.84) |
| Refugio | cálido acogedor #262019 | #FF9933 | dorado sardina #FFD15C |
| VFX amigables | XP #61C7FF · curación #94FFB8 · nivel #73DBFF | | |
| VFX enemigos | telégrafo #FF6659 · infección #90EBDC · élites cian/oro/rojo | | |
| Interactivos | rescate #BFFFD9 + color del compañero · sardinas #FFD15C | | |

Reglas duras:
- Jugadores destacan en los 3 biomas (cálido sobre fondos fríos/verdes).
- Verde infección (#90EBDC, frío-menta) ≠ verde curación (#94FFB8, claro y
  brillante) ≠ verde bioma (oscuro desaturado).
- XP cian ≠ charcos tóxicos (verde) ≠ acento del Barrio (cian SOLO en
  decoración de muy baja alfa).
- Rojo saturado = solo peligro real.

## Materiales

Simplificados y pictóricos: 2–3 valores por material + rim. Pelaje en mechones
grandes (no pelo a pelo), metal con brillo duro único, madera/hormigón con
textura sugerida en 3-4 brochazos. Contornos oscuros SUAVES integrados en la
pintura (no línea negra uniforme de cómic).

## Ejemplos descriptivos

- *Gato líder corriendo al NE*: cuerpo inclinado hacia el movimiento, cola en
  látigo detrás, orejas atrás, bufanda ondeando; luz NO define el lomo; la
  panza crema queda en semisombra.
- *Zombi normal*: trote pesado con cabeza baja, mandíbula suelta, una oreja
  mordida, herida de flanco como parche granate; ojos amarillos = único brillo.
- *Jefe fase 3*: aura roja pulsante, púas dobles al contraluz, ojos como
  ascuas, baba luminosa; ocupa 3-4 veces el ancho del jugador en pantalla.
