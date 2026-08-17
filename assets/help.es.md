# Get Some Puzzles

En este juego, tu objetivo es colorear las celdas de la cuadrícula en blanco o negro.

Para saber qué celda debe ir en qué color, debes seguir algunas restricciones (las reglas se explican a continuación).

Haz clic (o toca en móvil) en una celda para cambiar su color. Un clic recorre los colores: libre → negro → blanco → libre. En escritorio, el clic derecho recorre en sentido inverso (libre → blanco → negro → libre); en móvil, una pulsación larga hace lo mismo. Arrastrar pinta varias celdas seguidas con el color del ciclo.

Algunos rompecabezas usan un tercer color, el púrpura, con pequeños puntos de colores debajo de las celdas libres que indican qué colores siguen siendo posibles. En esos rompecabezas, el ciclo incluye el púrpura: un clic es libre → negro → blanco → púrpura → libre, y un clic derecho (o pulsación larga) es libre → púrpura → blanco → negro → libre — basta un solo clic derecho para alcanzar el púrpura.

Algunas celdas ya pueden estar rellenas y no podrás cambiarlas, están indicadas por un borde interno más grueso.

No se te mostrará cuando cometas un error, pero cuando la cuadrícula esté llena, tu solución será verificada. Si ganaste, otro rompecabezas comenzará inmediatamente. Si cometiste un error, se resaltará la restricción correspondiente y podrás cambiar tu solución.

Si estás atascado, varios botones están disponibles en la barra superior: **Pista** (el icono de bombilla, ver la sección Pistas más abajo), **Deshacer** (revierte tu último movimiento), **Reiniciar** (restablece la cuadrícula a su estado inicial) y **Pausa**. En modo de validación manual, también aparece un botón **Validar** sobre fondo verde cuando la cuadrícula está completa.

Mientras juegas, tu tiempo se registra (ver la sección de Estadísticas más abajo). Si lo necesitas, el juego se puede pausar y reanudar.

Hay unos 25.000 rompecabezas incluidos en la aplicación. Los rompecabezas que ya resolviste no volverán a aparecer, y verás tu progreso debajo del rompecabezas.

Desde el menú principal (icono arriba a la izquierda), cuando un puzzle está en curso, también puedes elegir **Próximo puzzle** para saltar al siguiente, **Guardar progreso** para apartarlo en una playlist dedicada y retomarlo más tarde, o **Compartir puzzle** para enviárselo a alguien.

## Aprendizaje

Cuando lanzas el juego por primera vez, una secuencia de aprendizaje presenta las restricciones una a una. Cada nueva regla aparece en una pequeña ventana de explicación la primera vez que la encuentras, y el juego te sigue proponiendo puzzles centrados en esa regla hasta que hayas jugado suficientes (5 puzzles por defecto) antes de pasar a la siguiente. Puedes saltar la secuencia en cualquier momento con el botón "Saltar aprendizaje" en la ventana de explicación, o reiniciarla desde el principio en la página Ajustes.

La página **Aprendizaje**, accesible desde el menú principal, lista todas las restricciones con su descripción y la fecha en que las encontraste por primera vez. El botón "Refrescarme la memoria" junto a cada regla lanza una pequeña playlist de puzzles centrados en esa regla — útil para volver a una restricción que no has visto desde hace un tiempo.

## Restricciones

## La página Abrir

La página Abrir es donde eliges qué jugar. Arriba, el menú *Colección* lista los niveles de dificultad (Fácil → Loco), seguidos de tus propios puzzles y las playlists que has creado. A su lado, el botón `+` crea una nueva playlist, el botón de archivo importa puzzles desde un archivo, y el icono de papelera elimina la playlist actual si te pertenece.

La opción *Mezclar* propone los puzzles en orden aleatorio. Más abajo, unos filtros permiten afinar la lista: tamaño de la cuadrícula, restricciones que quieres ver o evitar, y puzzles ya jugados u omitidos. El número que aparece encima del botón Jugar indica cuántos puzzles coinciden con los filtros activos, y un pequeño botón junto a cada filtro restablece el valor por defecto.

## Puzzles personalizados

### Generar puzzles

Abre el menú y toca "Generar" para fabricar nuevos puzzles al vuelo. Elige las dimensiones de la cuadrícula, los tipos de restricciones a incluir o excluir, un límite de tiempo por puzzle, y cuántos puzzles producir. Elige la playlist de destino, luego toca "Generar" — la barra de progreso muestra cuántos ya están hechos. La generación se ejecuta en segundo plano; puedes detenerla en cualquier momento y conservar lo que ya se haya producido.

### Crear puzzles

Abre el menú y toca "Crear" para diseñar tu propio puzzle a mano. Elige las dimensiones y toca "Comenzar" para entrar en el editor. Toca una celda para abrir un menú que permite fijarla en negro o blanco, o asociarle una restricción centrada en esa celda; la restricción añadida aparece, y basta con tocarla para eliminarla. La aplicación intenta resolver el puzzle a medida que realizas las modificaciones. Las celdas con borde verde se encuentran por razonamiento directo, las de borde naranja por eliminación. La barra inferior muestra las dimensiones, el número de restricciones y una puntuación aproximada de dificultad. "Probar" te permite jugar el puzzle para comprobar que funciona, y "Guardar" lo guarda en la playlist elegida.

### Playlists

Los puzzles generados y creados se guardan en playlists. La playlist por defecto es "Mis puzzles", pero puedes crear nuevas desde la página Abrir. También puedes importar puzzles desde un archivo.

## Pistas

Si te quedas atascado, el botón de pista te da un empujoncito progresivo — cada toque revela un poco más. Desde el menú de ajustes, puedes elegir el tipo de ayuda.

El primer toque es el mismo en ambos modos:

- Si has cometido un error, resalta la restricción violada, o la celda incorrecta cuando ninguna restricción lo detecta directamente.
- Si todo lo que has rellenado hasta ahora es correcto, te lo confirma.

Los toques siguientes dependen del modo elegido.

### Celda deducible

El modo por defecto. Tras el diagnóstico de errores, los toques siguientes te guían hacia una deducción precisa:

- Segundo toque: resalta una celda que puedes deducir.
- Tercer toque: también resalta la restricción que justifica la deducción, con una flecha que une ambas.
- Cuarto toque: colorea la celda por ti.

Útil cuando quieres una pista pequeña sin estropearte el reto: párate en el segundo toque si prefieres encontrar la justificación por ti mismo.

### Añadir restricción

En lugar de señalar una celda, el segundo toque añade una nueva restricción al puzzle. Esta regla es coherente con la solución y te da información adicional para avanzar — el puzzle se vuelve más fácil sin que nadie te diga qué celda rellenar.

Tras añadir una restricción, el ciclo vuelve al diagnóstico de errores en el siguiente toque.

## Atajos de teclado

En el escritorio, estas teclas controlan un puzle mientras juegas:

- **U** — deshacer el último movimiento
- **R** — reiniciar el puzle
- **P** — pausar o reanudar
- **H** — mostrar una pista
- **N** — pasar al siguiente puzle
- **Intro** — validar (cuando la validación manual está activada)
- **Esc** — abrir el menú
- **Espacio** — en puzles de 3 colores, alternar entre poner un color y quitar una opción

## Ajustes

La página de ajustes configura cómo el juego comprueba tu trabajo y te ayuda.

**Idioma**: elige el idioma de visualización de la aplicación (inglés, francés o español).

**Tema**: elegir entre Claro, Oscuro, o seguir la configuración del sistema (predeterminado).

**Validación**: elige si la cuadrícula se comprueba manualmente (tocas un botón) o automáticamente (en cuanto se rellena por completo).

**Comprobación en vivo**: cómo se muestran los errores mientras juegas — todas las celdas incorrectas, solo el número de errores, o ninguna indicación hasta que la cuadrícula esté completa.

**Mostrar puntuación**: si la pantalla de puntuación aparece entre puzzles para que puedas valorar lo que acabas de jugar en una escala de cinco niveles (de muy negativo a muy positivo).

**Tipo de pista**: cómo te ayuda el botón de pista — señalando una celda deducible ("Celda deducible") o añadiendo una nueva restricción que simplifica el puzzle ("Añadir restricción"). Mira la sección Pistas más arriba para los detalles.

**Tiempo de inactividad**: si no hay interacción durante el tiempo elegido (o si la aplicación pierde el foco), el cronómetro se pausa automáticamente para no seguir corriendo durante tu ausencia.

**Nivel del jugador** (0-100): orienta los puzzles que se te proponen hacia tu velocidad de razonamiento. Cuanto más alto, más difícil.

**Nivel automático**: cuando está activado, tu nivel se ajusta solo a partir de tus tiempos de resolución. Desactívalo para fijar el nivel a mano.

**Reproducir onboarding**: reinicia la secuencia de introducción desde la fase 0 — útil para volver a ver los diálogos de presentación de las reglas.

**Borrar estadísticas**: elimina las estadísticas por puzzle almacenadas localmente. La acción es irreversible y pide confirmación.

## Estadísticas

El juego registra cuánto tiempo ha pasado antes de que un rompecabezas se resuelva y cuántos fallos se cometieron. Estos datos permanecen en tu dispositivo — no se recopila nada automáticamente. Si resuelves muchos rompecabezas, me encantaría que me enviaras tus estadísticas: las uso para ordenar los rompecabezas por dificultad, y eso ayuda mucho.

La página de estadísticas es accesible desde el menú principal, sección **Progreso**. Arriba, un selector permite cambiar entre la colección actual y todas las colecciones. El botón **Compartir** (o **Abrir** en ordenador) exporta las estadísticas para enviármelas, y el botón **Importar** permite reinyectar un archivo de estadísticas previamente exportado.

También puedes sincronizar tus estadísticas entre dispositivos señalando la aplicación a una carpeta compartida y usando una herramienta de sincronización como Syncthing o Dropbox — consulta la [guía de estadísticas multi-dispositivo](https://leveque.cc/getsomepuzzle/doc/es/crossplay.html) para las instrucciones.

> Muchas gracias.
