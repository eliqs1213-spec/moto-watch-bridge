# Moto Firmware Lab — iPhone (iOS 16.2+)

Aplicación **independiente** de iWatch para examinar de manera observacional el Bluetooth del Moto Watch Fit. Usa un **bundle ID diferente**: `org.motowatchbridge.firmwarelab`.

## Funciones (v0.1.0)
- Escaneo BLE y selección explícita del dispositivo.
- Recuperación de periféricos conectados que exponen el UUID Motorola conocido.
- Enumeración de servicios, características y propiedades GATT.
- Lectura limitada a los campos públicos y estándar de Device Information Service (0x180A): modelo, firmware, hardware, software y fabricante, y Battery Level 0x180F/0x2A19.
- Registro y exportación mediante la hoja de compartir de iOS.
- **Sin ninguna escritura a GATT, suscripción a notificaciones propietarias, comandos OTA, instalación de firmware ni cambio de modo del reloj**.

## Qué NO demuestra
- No identifica necesariamente el SoC, bootloader o particionado.
- La existencia de características WRITE/NOTIFY **no implica** que la app las utilice.
- No puede leer firmware interno mediante CoreBluetooth.
- No garantiza que el reloj implemente HID (servicio 0x1812); solamente lo busca y lo enumera si existe.

## Cómo probar
1. Instalar IPA sin firmar usando AltStore, conservando identificador y extensiones si las hubiera. No tiene extensiones.
2. Cerrar iWatch para evitar operaciones simultáneas de dos centrales BLE.
3. Abrir Moto Firmware Lab y autorizar Bluetooth.
4. Pulsar «Buscar relojes BLE» y elegir el Moto Watch Fit (los nombres publicitarios pueden variar).
5. Exportar diagnóstico y compartir el texto para analizar las UUID y versiones. No incluye credenciales, tokens ni direcciones MAC.

Si el reloj no aparece, comprobar que Bluetooth esté encendido y el dispositivo esté anunciándose. No restablecer de fábrica ni forzar modo OTA.

## Compilar localmente
```sh
cd ios-firmware-lab
xcodegen generate
xcodebuild -project MotoWatchFirmwareLab.xcodeproj \
    -scheme MotoWatchFirmwareLab \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

Repositorio compartido como infraestructura de compilación, pero binario, código fuente, configuración y bundle ID independientes de iWatch.
