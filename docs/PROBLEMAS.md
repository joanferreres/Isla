# Solución de problemas

## «This application can’t be opened» y no aparece «Abrir igualmente»

Ese mensaje genérico no permite saber la causa. Publicar el mismo ZIP en GitHub no resuelve por sí solo el bloqueo. Antes de cambiar permisos o quitar protecciones:

1. Confirma que el Mac tiene chip Apple Silicon y macOS 15 o posterior. Puedes verlo en ** → Acerca de este Mac**.
2. Descarga otra vez **Isla.zip** desde [Releases](https://github.com/joanferreres/Isla/releases), descomprímelo con macOS y mueve la app a **Aplicaciones**. No intentes abrir el ZIP como aplicación.
3. Si sigue fallando, abre Terminal y ejecuta:

```bash
open "/Applications/Isla.app"
```

Copia el mensaje completo, incluido cualquier número de error. Si no aporta detalle, comprueba el ejecutable y su firma:

```bash
ls -l "/Applications/Isla.app/Contents/MacOS/Isla"
file "/Applications/Isla.app/Contents/MacOS/Isla"
codesign --verify --deep --strict --verbose=2 "/Applications/Isla.app"
```

El ejecutable distribuido debe existir, tener permiso de ejecución y ser `arm64`. La comprobación de firma debe terminar correctamente; no demuestra que esté notarizada por Apple. Si el archivo o la firma no coinciden, vuelve a descargar y extraer el ZIP en lugar de resignarlo a ciegas.

Envía el modelo/chip, la versión exacta de macOS y el mensaje de error al propietario del repositorio. Revisa el texto antes de publicarlo y elimina rutas personales o datos de cuenta que no sean necesarios. Como alternativa puedes [compilar desde el código](COMPILAR.md) en tu Mac; esto requiere las herramientas de desarrollo.

## Aviso de desarrollador no identificado

Sigue el apartado de [primer aviso de macOS](INSTALACION.md#primer-aviso-de-macos). El botón se muestra después de intentar abrir la app y puede estar limitado por la administración del equipo. No introduzcas comandos para desactivar la seguridad del sistema completo.

## La app está abierta pero no veo una ventana

Isla vive en la barra superior y no se presenta como una ventana normal del Dock. Usa el icono de Isla en la barra de menús para abrirla o entrar en ajustes. Comprueba la selección de pantallas y prueba con el puntero dentro del notch o justo debajo.

## No aparece la carátula o no funcionan los controles

Activa Música en ajustes, reproduce una canción y comprueba el permiso de Automatización de Music en **Ajustes del Sistema → Privacidad y seguridad**. El comportamiento de otras fuentes multimedia puede variar.

## No veo eventos

Activa Calendario, revisa el permiso y los calendarios seleccionados. Si lo has denegado, cámbialo manualmente en los ajustes de privacidad de macOS. La app no debe pedirlo de forma repetida.

## No aparecen límites de una IA

Debes iniciar sesión con tu propia cuenta en la aplicación correspondiente y activar la conexión. Una sesión caducada o un cambio del servicio puede impedir la lectura. No envíes tokens, archivos de autenticación ni contraseñas para pedir ayuda.

## El efecto de tapa no aparece

Requiere un sensor compatible y el permiso de Grabación de pantalla. Algunos modelos no se han probado. El efecto se atenúa de arriba abajo, acompaña la apertura inversa y se retira al mantener la tapa quieta unos tres segundos; si no ocurre, informa del modelo y macOS. La captura se usa durante el efecto y no guarda vídeo.

## Validación pendiente

La versión 0.8.9 pasa 120 pruebas automatizadas y su ZIP tiene firma válida al extraerlo en el Mac de desarrollo. Sigue pendiente confirmar el recorrido de los clics físicos en otros equipos y diagnosticar el fallo de apertura comunicado en un MacBook M4. No se presenta la distribución por GitHub como una solución ya comprobada a ese error.

## No aparece el aviso de actualización

- La versión instalada debe ser 0.8.8 o posterior. Las anteriores no tienen comprobador: instala la nueva una vez desde Releases.
- Comprueba **Ajustes → General → Actualizaciones → Avisarme de nuevas versiones** y prueba **Buscar actualizaciones**.
- El aviso automático no se repite si ya pulsaste **Más tarde** para esa versión; puedes descargarla desde Ajustes o el menú.
- El modo luna sin avisos suprime el diálogo automático. La disponibilidad sigue mostrándose en Ajustes y el menú.
- Una nueva versión debe publicarse como release estable con una etiqueta superior y un archivo **Isla.zip**. Un commit nuevo, una prerelease o un borrador no bastan.
- Sin conexión o con límites de GitHub, la consulta automática no interrumpe el trabajo; reintenta manualmente cuando vuelvas a tener acceso.
