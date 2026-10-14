# Moto Watch Bridge — primera aplicación nativa iOS

**Objetivo:** comprobar que el Moto Watch Fit envía **Siguiente, Anterior y Play/Pausa** a una app de iPhone incluso con el teléfono bloqueado.

Esta es la **etapa 1: Bluetooth solamente**. No controla Spotify todavía y no accede a WhatsApp ni Instagram. El sitio `index.html` de Bluefy **no se modifica**.

## 1. Subir al repositorio

Copiá los contenidos de este ZIP **a la raíz de tu repositorio** `moto-watch-bridge`, conservando las carpetas:

- `.github/workflows/build-ios-native.yml`
- `ios-native/project.yml`
- `ios-native/Sources/MotoWatchBridgeApp.swift`
- `ios-native/Sources/WatchBLEManager.swift`
- `ios-native/Sources/WatchProtocol.swift`

No reemplaces ni borres tu archivo `index.html`. Esta app se compila por separado de la web de Bluefy.

Una forma sencilla desde Windows (con Git instalado) es clonar el repositorio, copiar las carpetas `.github` e `ios-native` dentro, y ejecutar:

```powershell
git add .github/workflows/build-ios-native.yml ios-native
git commit -m "Primera app nativa iOS para Moto Watch Fit"
git push
```

## 2. Compilar en GitHub Actions

1. Abrí el repositorio en GitHub, pestaña **Actions**.
2. Elegí **Compilar Moto Watch Bridge iOS**.
3. Tocá **Run workflow** (rama `main`).
4. Esperá a que finalice con check verde.
5. Dentro de esa ejecución, bajá el artefacto **MotoWatchNativeProbe-unsigned**.
6. Descomprimí el ZIP descargado de GitHub: adentro estará `MotoWatchNativeProbe-unsigned.ipa`.

El workflow utiliza un equipo macOS de GitHub. El `.ipa` está **sin firmar** porque las credenciales Apple se aplican localmente desde Windows en el siguiente paso. **Nunca subas tu contraseña de Apple a GitHub.**

## 3. Instalar en iPhone desde Windows

1. Instalá Sideloadly **solo desde** https://sideloadly.io/ .
2. Conectá el iPhone 15 a Windows por cable y pulsá **Confiar** en el iPhone, si te lo pregunta.
3. Abrí Sideloadly y arrastrá `MotoWatchNativeProbe-unsigned.ipa`.
4. Seleccioná tu iPhone. Usá tu cuenta Apple dentro de Sideloadly para que firme e instale la app (no compartas la contraseña con nadie ni la envíes por chat).
5. En el iPhone, si es necesario, activá **Modo desarrollador** en Ajustes > Privacidad y seguridad; confiá en el certificado desde Ajustes > General > VPN y gestión de dispositivos.
6. Abrí **Moto Watch Bridge**, concedé el permiso Bluetooth y conectá el reloj.

Con cuentas Apple gratuitas normalmente hay que renovar la firma aproximadamente cada **7 días**.

## 4. Prueba clave: iPhone bloqueado

- Cerrá el puente de Windows y desconectá Bluefy y el Motorola Edge del reloj.
- En la app nativa, tocá **Conectar reloj**. Esperá el texto **«Escuchando los botones»**.
- Bloqueá el iPhone durante 60 segundos. En ese tiempo pulsá **Siguiente**, luego **Anterior** y luego **Play/Pausa**; separá las pulsaciones por unos cinco segundos.
- Desbloqueá el iPhone y comprobá los contadores y las horas del registro; tocá **Copiar registro** y pegalo en el chat.

**Importante:** no fuerces el cierre de Moto Watch Bridge desde el selector de aplicaciones. iOS puede suspender o terminar una app por diversos motivos aunque tenga modo Bluetooth central.

## Si algo falla

- **GitHub Actions en rojo:** pasá el nombre y texto del paso rojo.
- **Sideloadly no encuentra el iPhone:** revisá el cable, el botón Confiar, y los requisitos de iTunes/iCloud de la versión web de Apple en Windows que publica Sideloadly.
- **Conecta pero no recibe botones:** confirmá que `Notificaciones F8F0 activadas` aparezca en el registro y desconectá los otros dispositivos.
- **No aparecen botones con el teléfono bloqueado:** copiá el registro incluyendo los eventos `SISTEMA` y `RELOJ`, para distinguir falta de recepción frente a entrega demorada al desbloquear.

## Notas técnicas

- CoreBluetooth `UIBackgroundModes = bluetooth-central`.
- `CBCentralManagerOptionRestoreIdentifierKey` para restauración de estado.
- UUID Motorola custom: servicio `FC9DF9F0`, notificaciones `FC9DF8F0` y escritura `FC9DF8F1` (suffix Motorola).
- Protocolo Motorola `AA` + longitud + payload + CRC-16/XMODEM.
- Comandos reconocidos: `AA 06 00 00 24 07 08 02 74 67` (siguiente), `AA 06 00 00 24 07 08 01 17 57` (anterior), `AA 04 00 00 24 07 E9 54` (play/pausa).
- Los registros se guardan localmente en el iPhone, sin servidor de terceros.

**No es una aplicación firmada ni compilada aún:** el workflow realiza la compilación en GitHub. Por ahora el resultado solo ha sido validado en código y formato, no en iPhone real.
