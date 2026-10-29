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

## Configurar las funciones

Abre Isla desde su icono de la barra de menús y entra en **Ajustes**. En la isla, la rueda de ajustes y el menú secundario ofrecen también acceso.

| Función | Configuración y permiso |
| --- | --- |
| Música | Activa Apple Music. Acepta Automatización de Music si quieres controlarla desde Isla. |
| Calendario | Activa Calendario y concede acceso a los calendarios que quieras consultar. |
| IA | Inicia sesión en tus propias aplicaciones y activa las conexiones de Codex, Cursor o Claude. La disponibilidad de datos depende de cada servicio. |
| Avisos | La luna permite sonido y señal visual, solo señal visual o ningún aviso. La chincheta mantiene la isla abierta. |
| Pantallas | Elige mostrarla en todas las pantallas o en la principal. |
| Efecto de tapa | Actívalo si tu MacBook tiene sensor compatible y concede Grabación de pantalla. No funciona igual en todos los modelos. |
| Capturas | Opción independiente: puede usar Escritorio/capturas y copiar al portapapeles. Actívala solo si quieres cambiar tu flujo de capturas; las capturas no se añaden a la bandeja. |

## Actualizar

Sal de Isla desde su menú antes de sustituir la aplicación. Descarga el nuevo ZIP, descomprímelo y reemplaza la copia de Aplicaciones. Los datos y ajustes son propios de cada usuario. Cambiar de identidad de firma, por ejemplo al pasar a una compilación propia, puede hacer que macOS vuelva a solicitar permisos.

## Verificar la descarga

Opcionalmente, descarga también **SHA256SUMS.txt**, guárdalo junto a **Isla.zip**, entra en esa carpeta desde Terminal y ejecuta:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

Debe indicar `Isla.zip: OK`. Esta comprobación detecta diferencias respecto al archivo publicado; no sustituye la notarización ni una revisión del código.
