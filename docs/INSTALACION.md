# Instalar Isla y compartirla con un amigo

## Descargar la aplicación

1. Comprueba en ** → Acerca de este Mac** que el chip sea Apple M1 o posterior y que macOS sea 15 o posterior.
2. Abre [Releases](https://github.com/joanferreres/Isla/releases) y descarga **Isla.zip**, dentro de los archivos de la versión. No descargues «Source code» si solo quieres instalar la app.
3. Descomprime el ZIP con el descompresor integrado de macOS. Mueve **Isla.app** a **Aplicaciones** y ábrela desde esa carpeta.

Si el repositorio es privado, necesitas una invitación del propietario y entrar en GitHub con la cuenta invitada. Para compartir sin dar acceso al código, el propietario puede enviar el ZIP por AirDrop o un enlace de descarga.

## Primer aviso de macOS

La firma personal no equivale a una firma de Developer ID ni a la notarización de Apple. Si el aviso indica desarrollador no identificado o que Apple no puede comprobar la aplicación:

1. Intenta abrir **Isla.app** una vez y cierra el aviso.
2. Ve inmediatamente a **Ajustes del Sistema → Privacidad y seguridad** y baja hasta **Seguridad**.
3. Si aparece **Abrir igualmente**, comprueba que se refiere a Isla y confirma la apertura.

Apple indica que la opción está disponible aproximadamente una hora después del intento. [Instrucciones oficiales de Apple](https://support.apple.com/en-euro/guide/mac-help/mh40617/27/mac/27).

Si el texto es «This application can’t be opened» o no aparece el botón, no des por hecho que es este mismo bloqueo: sigue [Solución de problemas](PROBLEMAS.md). No es necesario desactivar Gatekeeper para todo el Mac. Un Mac administrado por una empresa puede tener restricciones adicionales.

## Permisos de macOS (checklist)

Concede solo lo que uses. Ruta base: **Ajustes del Sistema → Privacidad y seguridad**.

| Permiso | Pasos | Para qué |
| --- | --- | --- |
| **Automatización → Music** | Privacidad y seguridad → **Automatización** → Isla → marca **Music** | Carátula, controles, playlists, volumen y presets del EQ (AppleScript). Sin esto, Música no responde. |
| **Accesibilidad** | Privacidad y seguridad → **Accesibilidad** → activa **Isla** | Mandos Graves/Medios/Agudos, cambio de presets en la ventana EQ de Música y añadir canciones del catálogo a playlists. |
| **Calendarios** | Privacidad y seguridad → **Calendarios** → permite a Isla | Eventos del día y recordatorio previo. Isla solo lee. |
| **Grabación de pantalla** | Privacidad y seguridad → **Grabación de pantalla y de sistema** | Solo el efecto visual al cerrar la tapa. No guarda vídeo. |
| **Llavero** | Acepta el diálogo de macOS cuando Isla o Claude/Cursor lo pidan | Leer sesión OAuth de Claude Code / Cursor Safe Storage; guardar API keys de Claude y ChatGPT para el EQ con IA. |
| **Archivos / capturas** (opcional) | Al activar capturas en Ajustes de Isla | Guardar en `Escritorio/capturas` y copiar al portapapeles. |

### Orden recomendado

1. Instala **Isla.app** en **Aplicaciones** y ábrela una vez (si Gatekeeper avisa, [Abrir igualmente](#primer-aviso-de-macos)).
2. Menú de Isla → **Ajustes → Módulos** → activa **Apple Music** y reproduce una canción en la app Música.
3. Si macOS pide controlar Música, acepta; si no, ve a **Automatización** y marca **Music** para Isla.
4. Abre el tocadiscos y gira un mando del EQ. Si pide Accesibilidad, actívala y vuelve a intentarlo.
5. (Opcional) **EQ con IA**: interruptor en Ajustes → Música, o estilo **Claude** en el tocadiscos. Guarda keys en el llavero o usa `claude auth login`.
6. (Opcional) Calendario, efecto de tapa y capturas: actívalos y concede Calendarios / Grabación de pantalla cuando lo pidan.

Isla **no** usa el micrófono. El porcentaje de batería Bluetooth solo aparece si el altavoz lo publica; no hay un interruptor aparte en Privacidad.

## Configurar las funciones

Abre Isla desde su icono de la barra de menús y entra en **Ajustes**. En la isla, la rueda de ajustes y el menú secundario ofrecen también acceso.

| Función | Configuración y permiso |
| --- | --- |
| Música | Activa Apple Music. Concede **Automatización → Music**. |
| EQ con IA | En **Ajustes → Módulos → Música**: interruptor **EQ con IA** y keys de Claude/ChatGPT (llavero). También con el estilo **Claude** del tocadiscos. Orden: OAuth Claude Code → key Claude → key ChatGPT. |
| Tocadiscos | Pulsa el disco junto a la luna. El botón verde lo abre a pantalla completa. Sobre el vinilo, arrastra o desliza dos dedos a la izquierda para avanzar y a la derecha para retroceder. Mantén pulsado ⌘ para ver los diez ambientes. El fader vertical ajusta el volumen de Música. Si la salida Bluetooth publica su batería, el porcentaje aparece junto a ⌘. Gira los mandos para ajustar el ecualizador o pulsa la flecha circular sobre ellos para volver a sonido plano. La primera vez, activa Isla en **Accesibilidad** y vuelve a girar el mando. |
| Archivos | Arrastra archivos de Finder al notch para abrir la bandeja. Suelta en la bandeja para guardar un acceso al original, o en AirDrop para elegir un destinatario. Arrastra un archivo desde la bandeja para usarlo en otra app. |
| Añadir a playlist | En **Inicio**, pulsa el icono de lista con un signo + al lado de los controles de la canción. También está en el tocadiscos junto a ⌘. Elige una playlist editable de Música. Para algunas canciones del catálogo, Isla usa la ventana principal de Música y el permiso de **Accesibilidad**. |
| Tocadiscos en el escritorio | Actívalo desde el menú de Isla. Arrastra el encabezado para moverlo. La flecha abre el tocadiscos completo y la × lo oculta. Isla recuerda su posición. |
| Calendario | Activa Calendario y concede acceso a los calendarios que quieras consultar. |
| IA | Inicia sesión en tus propias aplicaciones y activa las conexiones de Codex, Cursor o Claude. macOS puede pedir acceso al **llavero**. La disponibilidad de datos depende de cada servicio. |
| Avisos | La luna permite sonido y señal visual, solo señal visual o ningún aviso. La chincheta mantiene la isla abierta. |
| Pantallas | Elige mostrarla en todas las pantallas o en la principal. |
| Efecto de tapa | Actívalo si tu MacBook tiene sensor compatible y concede **Grabación de pantalla**. No funciona igual en todos los modelos. |
| Capturas | Opción independiente: puede usar Escritorio/capturas y copiar al portapapeles. Actívala solo si quieres cambiar tu flujo de capturas; las capturas no se añaden a la bandeja. |

## Actualizar

A partir de 0.8.9, Isla comprueba GitHub una vez por semana (0.8.8 lo hacía a diario) y avisa de nuevas versiones estables publicadas con un ZIP. El aviso aparece una sola vez por versión: **Más tarde** lo cierra, pero conserva el acceso a la descarga desde el menú y Ajustes. **Buscar actualizaciones…** fuerza una consulta manual. El modo luna sin avisos evita el diálogo automático, sin ocultar la disponibilidad en Ajustes o el menú.

Puedes desactivar **Avisarme de nuevas versiones** en **Ajustes → General → Actualizaciones**. Solo se consulta información pública de las releases, sin enviar sesiones de IA ni credenciales. Las descargas se abren en GitHub y la instalación sigue siendo manual. Las versiones 0.8.7 y anteriores necesitan instalar la versión actual una vez para recibir los avisos futuros.


Sal de Isla desde su menú antes de sustituir la aplicación. Descarga el nuevo ZIP, descomprímelo y reemplaza la copia de Aplicaciones. Los datos y ajustes son propios de cada usuario. Cambiar de identidad de firma, por ejemplo al pasar a una compilación propia, puede hacer que macOS vuelva a solicitar permisos.

## Verificar la descarga

Opcionalmente, descarga también **SHA256SUMS.txt**, guárdalo junto a **Isla.zip**, entra en esa carpeta desde Terminal y ejecuta:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

Debe indicar `Isla.zip: OK`. Esta comprobación detecta diferencias respecto al archivo publicado; no sustituye la notarización ni una revisión del código.

### Widget nativo del tocadiscos

Abre **Editar widgets** desde el escritorio, busca **Isla** y arrastra **Tocadiscos** al escritorio. Está disponible en tamaño pequeño y mediano. Muestra la canción actual, coloca el brazo sobre el disco mientras se reproduce y, al pulsarlo, abre el tocadiscos de Isla.
