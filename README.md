# Isla

<img src="Resources/Isla-icon.png" width="96" alt="Icono de Isla">

Isla convierte el notch del Mac en un espacio compacto para música, calendario, actividad de IA y archivos. Está hecha con SwiftUI y AppKit para macOS.

**[Descargar Isla.zip](https://github.com/joanferreres/Isla/releases/latest/download/Isla.zip)** · **[Instalación](docs/INSTALACION.md)** · **[Solución de problemas](docs/PROBLEMAS.md)** · **[Compilar](docs/COMPILAR.md)**

## Funciones

### Isla dinámica

- Se abre al hacer clic dentro del notch, sin activarse al acercar el puntero.
- Muestra la carátula y los controles cuando Apple Music está reproduciendo.
- Oculta los laterales de música cuando no hay reproducción.
- Divide el espacio entre música, calendario y actividad de IA según el contenido disponible.
- Puede fijarse abierta y mostrarse en la pantalla principal o en todos los monitores.
- El menú secundario permite cambiar el modo de avisos, fijar la isla, abrir Ajustes o salir.

### Apple Music y tocadiscos

- Carátula, canción, artista, reproducción, pausa, pista anterior y pista siguiente.
- Ventana de tocadiscos redimensionable y compatible con pantalla completa.
- Vinilo animado, ondas musicales y brazo móvil. Arrastrar el brazo cambia la posición de la canción.
- Deslizar el disco con dos dedos en el trackpad cambia de pista.
- Mesa de DJ con volumen y controles de graves, medios y agudos, además de un botón para restablecer el sonido.
- Diez ambientes visuales, seleccionables con <kbd>⌘0</kbd> a <kbd>⌘9</kbd>.
- Selector para añadir la canción actual a una playlist editable de Apple Music.
- Indicador discreto de batería cuando el altavoz Bluetooth conectado publica ese dato.
- Reproductor compacto opcional sobre el escritorio, activable desde el menú de Isla.
- Widget nativo de macOS en tamaños pequeño y mediano. Muestra la canción actual y coloca el brazo sobre el disco únicamente durante la reproducción.

### Calendario

- Vista compacta del día y de los próximos eventos.
- Selección de los calendarios que Isla puede mostrar.
- Recordatorio alrededor del notch durante los diez minutos anteriores al siguiente evento.
- El permiso se solicita una vez y puede administrarse después desde Privacidad y seguridad.

### Codex, Cursor y Claude

- Estado y límites disponibles de Codex, Cursor, Claude Code y Claude.
- Selección de qué servicios aparecen en Inicio.
- Indicador circular de consumo y estadísticas de actividad.
- Aviso al terminar una tarea con tres modos: sonido y señal visual, solo señal visual o sin avisos.
- El modo silencioso evita sonidos de finalización sin desconectar las integraciones.

La información disponible depende de cada servicio, de la sesión local y de los datos que publique su API o aplicación.

### Archivos y AirDrop

- Bandeja temporal con miniaturas para archivos arrastrados desde Finder.
- Arrastrar un elemento desde la bandeja a otra aplicación.
- Compartir o enviar por AirDrop desde la propia isla.
- Los accesos conservan el archivo original en su ubicación.

### Pantalla y tapa

- Isla independiente para la pantalla principal o para todos los monitores.
- Efecto opcional al cerrar la tapa en MacBook compatibles.
- La animación sigue el ángulo, retrocede si se vuelve a abrir y desaparece si la tapa queda quieta durante tres segundos.
- La captura de pantalla se activa durante el gesto y no guarda vídeo.

### Capturas y ajustes

- Opción para guardar capturas en `Escritorio/capturas` y copiarlas al portapapeles.
- Ajustes separados para General, Música, Calendario, IA y Pantallas.
- Comprobación manual de nuevas versiones y consulta automática semanal.

## Requisitos

- Mac con Apple Silicon, desde M1 en adelante. La descarga actual es `arm64` y no funciona en Intel.
- macOS 15 o posterior.
- El efecto de tapa requiere un MacBook con sensor compatible.

Isla se prueba principalmente en un MacBook Pro M4. Algunas integraciones usan interfaces de macOS o de servicios externos que pueden cambiar con futuras versiones.

## Instalación

1. Descarga **Isla.zip** desde la [última versión publicada](https://github.com/joanferreres/Isla/releases/latest).
2. Descomprime el archivo y mueve **Isla.app** a **Aplicaciones**.
3. Abre Isla. Si macOS no reconoce al desarrollador, sigue el [manual de instalación](docs/INSTALACION.md#primer-aviso-de-macos).
4. Abre Ajustes y activa únicamente las funciones que quieras usar.

La aplicación tiene una firma personal y no está notarizada por Apple. No hace falta desactivar Gatekeeper. macOS permite autorizarla desde **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente** después de intentar abrirla una vez.

## Permisos

| Permiso | Para qué se usa |
| --- | --- |
| Automatización de Music | Leer la canción y usar los controles de Apple Music. |
| Calendario | Mostrar eventos de los calendarios seleccionados. |
| Accesibilidad | Ajustar el ecualizador y algunas acciones de Apple Music. |
| Grabación de pantalla | Generar el efecto visual durante el movimiento de la tapa. |
| Carpeta de capturas | Guardar capturas si esta opción está activada. |
| Lectura del archivo del widget | Compartir con el widget únicamente la canción y la carátula actuales. |

Isla no incluye cuentas, calendarios, conversaciones, tokens ni claves privadas del autor. Cada instalación utiliza las sesiones y permisos del propietario de ese Mac.

## Widget del tocadiscos

1. Haz clic secundario en el escritorio y abre **Editar widgets**.
2. Busca **Isla**.
3. Arrastra **Tocadiscos** al escritorio en tamaño pequeño o mediano.

El widget se actualiza cuando cambia la canción, al reproducir o pausar y después de instalar una nueva versión. Al pulsarlo abre el tocadiscos completo.

## Actualizaciones

Isla consulta la última release pública una vez por semana. También puedes usar **Buscar actualizaciones…** desde el menú de Isla o desde **Ajustes → General → Actualizaciones**.

Cuando existe una versión superior con un archivo adjunto llamado `Isla.zip`, Isla muestra un aviso y abre la descarga de GitHub. La sustitución de la aplicación sigue siendo manual:

1. Sal de Isla.
2. Descarga y descomprime la nueva versión.
3. Sustituye **Isla.app** dentro de **Aplicaciones**.
4. Abre Isla de nuevo.

La aplicación reinicia su extensión del widget después de una actualización para evitar que macOS conserve la canción de la versión anterior.

Las versiones 0.8.7 o anteriores necesitan una actualización manual inicial. Un commit nuevo en `main` no activa avisos por sí solo. Debe existir una release estable con una versión superior y el archivo **Isla.zip**.

## Versión actual

**Isla 0.8.42**, compilación 72.

El proyecto cuenta con 128 pruebas automatizadas. La compatibilidad física del notch, los sensores y algunos permisos todavía puede variar entre modelos y versiones de macOS.

## Desarrollo

Consulta [COMPILAR.md](docs/COMPILAR.md) para compilar, ejecutar las pruebas y preparar una release. Las licencias y adaptaciones de terceros están en [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) y [Vendor/MediaRemoteAdapter/LICENSE](Vendor/MediaRemoteAdapter/LICENSE).

Isla es un proyecto independiente de Apple, OpenAI, Anthropic, Cursor y las aplicaciones o servicios mencionados.
