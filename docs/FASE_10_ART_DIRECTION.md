# Fase 10 - Direccion de arte

Proyecto: Cats vs Zombie Dogs  
Motor: Godot 4.7  
Estilo: 2D top-down arcade, caricaturesco, oscuro pero colorido.

## Identidad

Cats vs Zombie Dogs debe leerse como una defensa felina rapida, comica y clara. El mundo es nocturno y algo peligroso, pero los gatos, sardinas, XP y armas deben brillar sobre el fondo. Los perros zombis son mutantes exagerados, no gore realista.

## Paleta

- Fondo: azules casi negros y grises frios.
- UI: paneles oscuros, texto claro, acentos cyan, naranja y morado.
- Jugador: dorado/crema con acento cyan para reconocerlo en hordas.
- Companeros: policia azul/gris, medico blanco/verde, ingeniero naranja/amarillo.
- Perros zombis: verdes, grises y rojos apagados; ojos amarillos o verdosos.
- Runners: tonos mas vivos y silueta delgada para detectar velocidad.
- Jefes: rojos, verdes intensos o acentos brillantes, aura y mayor escala.
- XP: cyan/azul.
- Sardinas: amarillo/dorado.
- Peligro: rojo apagado, naranja industrial o amarillo de advertencia.

La paleta compartida vive en `scripts/ui/theme_colors.gd`.

## Reglas visuales

- La silueta manda: cada entidad importante debe reconocerse aunque sea pequena.
- El jugador siempre debe tener mas contraste que enemigos normales.
- Los companeros deben distinguirse por color, sombrero/marca de rol y proyectil.
- Los enemigos deben verse torpes o veloces segun rol, no solo cambiar de color.
- Las armas deben tener VFX distintos por forma: bala, explosion, sardina, laser, orbital, nube.
- Las sombras son elipses simples bajo entidades/obstaculos para profundidad.
- Los outlines se reservan para jugador, companions, enemigos, jefes, XP y proyectiles importantes.
- Evitar gore realista, texturas pesadas, shaders caros y exceso de particulas.

## Tamanos y jerarquia

- Jugador: mediano, claro, con indicador de direccion.
- Companeros: ligeramente menores que jugador, roles claros.
- Enemigos normales: masa visual baja-media.
- Runners: mas delgados y legibles en movimiento.
- Mini-jefes: mas grandes, borde/aura, aparicion y muerte visibles.
- Jefe: gran escala, aura, ojos brillantes, telegrafo de embestida.
- Obstaculos: deben decorar y orientar el bioma sin tapar lectura de combate.
- HUD: datos esenciales arriba, iconos abajo; detalles van a pausa o tooltips.

## Que debe destacar

- Vida baja, level up, jefe, rescate, revive y proyectiles peligrosos.
- XP y sardinas deben ser atractivos pero menos importantes que amenazas.
- Cartas de mejora deben tener rareza visible y un icono grande.

## Que queda en segundo plano

- Piso, grid, detalles ambientales, props decorativos y sombras.
- Texto largo en combate.
- Efectos repetidos de dano cuando hay hordas grandes.
