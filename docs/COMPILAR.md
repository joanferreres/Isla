# Compilar, probar y preparar una versión

## Herramientas

Necesitas un Mac Apple Silicon, Python 3 y las herramientas de desarrollo de Apple con Swift 6 y un SDK compatible. La compilación de referencia se ha hecho con **Apple Swift 6.4 y SDK macOS 27**. El ejecutable declara macOS 15 como versión mínima; SDK más antiguos pueden no ofrecer todas las APIs usadas.

Comprueba tu entorno:

```bash
xcode-select -p
swift --version
python3 --version
```

Si faltan las herramientas de línea de comandos puedes solicitar su instalación con `xcode-select --install`. Una versión antigua de las herramientas puede requerir actualizar Xcode o macOS.

## Obtener el código

```bash
git clone https://github.com/joanferreres/Isla.git
cd Isla
```

Un repositorio privado requiere acceso concedido por su propietario y autenticación de GitHub. También puedes descargar **Code → Download ZIP**, descomprimirlo y entrar con Terminal en la carpeta que contiene `Package.swift`.

## Probar y compilar

```bash
swift test --scratch-path /tmp/isla-tests --build-system native
bash Scripts/build-app.sh
```

La compilación usa una carpeta temporal para evitar problemas con proyectos guardados en iCloud. Los resultados quedan en **outputs/Isla.app** y **outputs/Isla.zip**, dentro del proyecto.

Opcionalmente puedes elegir carpetas distintas para los resultados y la caché:

```bash
ISLA_OUTPUT_ROOT="$PWD/outputs" ISLA_BUILD_ROOT="/tmp/isla-build-local" bash Scripts/build-app.sh
```

No ejecutes dos compilaciones simultáneas con la misma carpeta de caché. Al terminar, abre `outputs` en Finder, copia **Isla.app** a Aplicaciones y ábrela desde allí. Si tienes otra copia de Isla abierta, sal primero de ella.

No hace falta una cuenta de pago de Apple Developer para esta compilación local. Sin la identidad privada del autor, el script usa firma **ad hoc**. Nunca necesitas copiar su llavero ni su clave. Esto no genera una aplicación notarizada para distribuir sin avisos de seguridad.

## Firma

`Scripts/sign-app.py` reutiliza una identidad personal local si ya existe en `~/Library/Application Support/Isla/Signing`. Sus archivos no están en el repositorio ni deben compartirse. Si no existe, firma de forma ad hoc. Mantener una identidad estable entre actualizaciones ayuda a conservar los permisos; una compilación con otra identidad puede requerir concederlos de nuevo.

El empaquetado conserva los avisos y licencias de terceros y verifica la firma. Para comprobar el ZIP desde una carpeta temporal:

```bash
check_dir="$(mktemp -d /tmp/isla-verify.XXXXXX)"
ditto -x -k outputs/Isla.zip "$check_dir"
codesign --verify --deep --strict --verbose=2 "$check_dir/Isla.app"
```

La firma válida verifica la integridad local. La aceptación de Gatekeeper y la notarización son comprobaciones diferentes.

## Publicar una nueva versión

1. Actualiza `CFBundleShortVersionString` y `CFBundleVersion` en `Resources/Info.plist` y la versión visible en ajustes.
2. Ejecuta las pruebas y compila el paquete.
3. Comprueba el ZIP extraído y prueba la aplicación. Anota qué equipos y funciones has validado realmente.
4. Calcula la suma de verificación desde la carpeta `outputs`:

```bash
cd outputs
shasum -a 256 Isla.zip > SHA256SUMS.txt
```

5. Guarda el código en un commit y crea en GitHub una release con la etiqueta correspondiente, por ejemplo `v0.8.10`, vinculada a ese commit.
6. Adjunta **Isla.zip** y **SHA256SUMS.txt**. Describe novedades, requisitos, firma sin notarización y cualquier comprobación pendiente. No incluyas cuentas, calendarios, sesiones, llaveros ni archivos privados de firma.

El enlace de descarga del README apunta al archivo `Isla.zip` de la última release normal. Una release marcada como prerelease puede no aparecer en ese enlace; en ese caso enlázala expresamente.

## Qué hace que aparezca el aviso

El comprobador de Isla 0.8.8 y posteriores consulta `https://api.github.com/repos/joanferreres/Isla/releases/latest`. Solo ofrece una versión superior a la instalada, con etiqueta numérica como `v0.8.9`, release normal publicada y un archivo adjunto llamado exactamente **Isla.zip**. Las etiquetas sin release, borradores, prereleases y commits nuevos en `main` no activan el aviso.

La versión de `Info.plist`, la etiqueta y la aplicación dentro del ZIP deben coincidir. No reutilices una etiqueta existente para cambiar el binario. Publica una versión nueva. El acceso de escritura al repositorio determina quién puede publicar estas versiones.

La consulta automática se hace como máximo una vez por semana desde 0.8.9 (0.8.8 lo hacía a diario), con una petición condicional cuando hay caché. No hay descargas automáticas ni un proceso de actualización adicional. Se suspende al dormir el Mac y puede desactivarse; la comprobación manual sigue funcionando.
