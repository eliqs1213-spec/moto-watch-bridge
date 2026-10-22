# Diagnóstico para instalar temas dinámicos en Windows

El objetivo es instalar **esferas dinámicas completas del Moto Watch Fit XT2541-1**: hora, recursos gráficos, clima, pasos/actividad e indicadores. Esta carpeta contiene diagnósticos; **todavía no es un instalador de temas**.

## Qué sabemos

- La APK oficial Moto Watch 2.1.0.017 enruta el servicio de archivos `ServiceId.FILE=0x20` por SPP/Classic.
- Dos pruebas de iWatch enviando `20/05` por GATT no recibieron respuesta de negociación.
- La consulta SDP remota desde Windows devolvió `Success` y **0 servicios RFCOMM** en el estado actual.
- La descompilación de la APK aporta una nueva pista: antes de conectar el socket RFCOMM, el flujo `FileSender.sendFile → BandProxy.requestSpp → SppManager.requestSpp` llama a `BandProxy.openSppRemote(true)`. Eso envía por GATT `GeneralSetting.OPEN_SPP` (SID `0x12`, CID `0x19`) con `MotoSetting.OperateBt.type=1`, para solicitar que se abra el canal Classic.

Por eso el programa ahora tiene dos modos.

## Requisitos

- Windows 10/11 con Bluetooth LE y Classic.
- .NET SDK 8: https://dotnet.microsoft.com/download/dotnet/8.0
- Moto Watch Fit emparejado en Windows.

## Modo A — solo lectura

Desde PowerShell en la raíz del repositorio:

```powershell
dotnet run --project tools/watchfaces/windows-rfcomm/RfcommProbe.csproj
```

Consulta los servicios RFCOMM remotos sin enviar comandos.

## Modo B — solicitar apertura de SPP

```powershell
dotnet run --project tools/watchfaces/windows-rfcomm/RfcommProbe.csproj -- --request-spp
```

Este modo hace lo siguiente:
1. Consulta los servicios RFCOMM disponibles.
2. Se conecta por BLE al servicio Motorola `FC9DF9F0-4899-11EE-BE56-0242AC120002`.
3. Intenta habilitar notificaciones F8F0 para observar respuestas.
4. Envía **una única solicitud** `AA 06 00 00 12 19 08 01 05 04` por F8F1 y espera dos segundos.
5. Consulta SDP general y también busca explícitamente el UUID RFCOMM `FC9DF9F0-4899-11EE-BE56-0242AC120002`, antes y después de la solicitud. Si llega la respuesta `12/19` con `OperateBt type=4`, la identifica como respuesta correlacionada, pero no la etiqueta como éxito porque el significado del valor aún no está confirmado.

**Alcance de seguridad:** este comando solo pide abrir el canal SPP; no envía JPEG, no manda comandos `MotoFt` de transferencia, no instala temas y no toca firmware/OTA. Sin embargo, sí cambia temporalmente el estado de conexión Bluetooth y podría interrumpir otra conexión activa. Antes de ejecutarlo, apagá temporalmente Bluetooth desde **Ajustes** tanto en el iPhone como en el Edge 60 (si están cerca o emparejados con el reloj); cerrar las apps no garantiza que liberen el enlace BLE. Mantené Bluetooth activo en Windows y no elimines el emparejamiento. Si GATT devuelve `Unreachable`, la herramienta reintentará una vez y luego saldrá sin enviar el comando; dejá los teléfonos con Bluetooth apagado y volvé a probar.

Un ACK de escritura ATT significa que la característica BLE aceptó la escritura, no que el reloj haya aceptado la solicitud a nivel Motorola. La salida de F8F0 y las consultas SDP general + por UUID son diagnósticos complementarios. Que el SDP general esté vacío no descarta por sí solo una respuesta Motorola por BLE.

## Autocomprobación local

```powershell
dotnet run --project tools/watchfaces/windows-rfcomm/RfcommProbe.csproj -- --self-test
```

Verifica los bytes y el CRC de la solicitud sin activar Bluetooth ni enviar nada.

## Lo que falta para instalar un tema

Aunque SPP se active, todavía hay que implementar y verificar la secuencia MotoFt (negociación, envío de archivo, ACK de bloques, finalización) y el protocolo de instalación de una esfera dinámica. La APK incluye recursos JSON para esferas y widgets, pero no está demostrado que copiarlos directamente al reloj sea suficiente. No utilizar el flujo OTA ni sobrescribir archivos `.res`.
