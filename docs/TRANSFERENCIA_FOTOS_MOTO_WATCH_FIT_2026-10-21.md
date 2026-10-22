# Moto Watch Fit XT2541-1 — transferencia de fotografías desde iWatch
Fecha: 21/10/2026–22/10/2026. Investigación offline; sin modificar firmware ni transferir imágenes al reloj.

## Meta
**Enviar una fotografía desde el editor de iWatch al Moto Watch Fit y convertirla en la esfera principal.** No confundir esta operación con seleccionar un ID de esfera preinstalada mediante `26/04`.

## Hallazgos verificables en la APK oficial de Motorola (2.1.0.017)
- `classes4.dex` contiene `com.motorola.bluetooth.sdk.band.FileSender`, `FileResolverImpl.sendFile` y `FileTransferTask`; la API recibe un archivo o bytes, nombre y un valor `FileUri`. El protocolo de archivo utiliza mensajes `MotoFt.FtSend`, `MotoFt.FileData` y comprobación/respuesta; el código oficial usa checksum MD5 del contenido.
- `FileUri.WF_URI_CUSTOM` se serializa como **`WF://custom`** y es usado por el flujo de fotografías en `gs1.f` (cancelación de envíos de imagen del reloj) y otros flujos. `DEVICE_ALBUM_IMAGE` se serializa como **`device_album_image`** y también aparece en el módulo de álbumes. Son rutas *distintas* y no deben intercambiarse sin reconstruir cuál usa el modelo XT2541-1 durante una transferencia real.
- `WatchFaceResolverImpl.addWatchFaceAlbum(wfId, count, List<String> filenames)` arma `MotoWatchface.AddAlbumWatchFace`, con setters `setWfId`, `setCount` y `addAllName`. Por ejemplo, el método ofuscado `gs1.s` prepara este mensaje y la aplicación recibe `AddAlbumWatchFaceRsp`.
- `i80.onSendSuccess`/ `onSendFailed` son callbacks de transferencia con lógica de actualización y registro de fotos en el álbum. Esto demuestra que el envío de archivo y la instalación/selección son **etapas separadas**.
- Identificación en archivos de APK, no en un paquete Bluetooth capturado durante carga de fotografía. La observación previa de cambio de esfera `26/04` solo prueba selección de una existente.
- Hay una ruta RFCOMM/Classic comprobada para **OTA de firmware**, pero NO prueba que **fotografías** utilicen Classic. El canal BLE/Classic de fotografías sigue sin verificar.

## Restricción iPhone
- CoreBluetooth puede manejar los servicios GATT del reloj, tal como funciona en iWatch actualmente, pero no permite abrir una sesión arbitraria SPP/RFCOMM de Bluetooth Classic.
- ExternalAccessory requiere accesorio MFi autorizado. Referencias oficiales: https://developer.apple.com/accessories/ y https://developer.apple.com/library/archive/qa/qa1657/_index.html
- Si el flujo de fotos se transporta mediante el GATT Motorola F8F1, será factible investigar una implementación directa. Si se transporta solo por RFCOMM sin interfaz MFi, iWatch necesitará un puente externo compatible o una vía alternativa soportada por el dispositivo.

## Cambio de código integrado en iWatch 0.8.4.54 (894)
- Editor de esferas agrega **Comprobar catálogo del Moto Watch**, mediante paquete `AA 04 00 00 26 01 4D 52` previamente observado en Android, con prioridad baja en la cola BLE existente y estado de respuesta.
- La consulta solo lee catálogo; **no envía archivos** ni declara el proceso de instalación completado. No se muestra un falso botón «Enviar al reloj».
- No se alteran las funciones de clima, música, salud ni el flujo OTA.

## Evidencia que falta para habilitar envío real
Captura única, acotada y local, desde la aplicación oficial Moto Watch en el Motorola Edge:

1. Con el reloj conectado a Android, activar «Habilitar registro HCI Bluetooth» en las opciones de desarrollador.
2. En Moto Watch seleccionar una foto nueva, cambiarle estilo y pulsar **Establecer como actual**; anotar inicio y fin.
3. Guardar el bugreport/captura y compartirla de forma privada para analizar **canal**, `FileUri`, nombre, tamaño, MD5, delimitación por bloques, ACK de transferencia y confirmación de `AddAlbumWatchFaceRsp`.
4. Verificar el archivo exacto que se envió: JPEG, PNG, ZIP u otro; reconstruir orden real de comandos, reintentos y selección final.
5. Solo entonces incorporar «Enviar al Moto Watch» en iWatch, con guardas de tamaño, cancelación, progreso y validación de respuesta. Mantener la esfera actual hasta éxito confirmado.

**No subir el HCI/bugreport crudo al repositorio público**: contiene direcciones, notificaciones y metadatos personales. Ninguna operación de firmware debe formar parte de la carga de fotos.

## Investigación adicional — inicio de transferencia y canal SPP
- Análisis estático de `classes4.dex`: `FileSender.sendFile(File, name, FileUri, task)` prepara una tarea, comprueba `BandProxy.isRequirePending()` y tiene un camino explícito `BandProxy.requestSpp()` antes de iniciar la transferencia. `BandProxy.requestSpp()` delega en `SppManager.requestSpp()`.
- Otro camino continúa a `FileSender.getTransmission()` y negocia `MotoFt.FileTransmission` (`file_protocol_version`, `max_data_size`). La existencia de ambos caminos significa que **no podemos declarar la transferencia siempre Classic ni suponer que GATT sirve para enviar fotografías**. La captura del flujo fotográfico es la evidencia decisiva.
- `band/moto_ft.proto` contiene `FileTransmission`, `FtSend` (task_id, uri, file_path, file_size, md5, etc.), `FileData` y respuestas de verificación. `band/moto_watchface.proto` define `AddAlbumWatchFace` con lista de nombres y `CurrWatchFace`. El protocolo tiene etapas y acuses; NO es válido enviar un PNG como un único comando `26/04`.
- Una captura HCI previa disponible mostraba lecturas `26/01` y tráfico RFCOMM relacionado con otras operaciones, **no la instalación de una nueva fotografía**. No permite atribuir ese tráfico SPP a la foto.
- Se creó un analizador offline de bugreport que solo emite conteos/tamaños de grupos Motorola 21/22/26 y actividad SPP, sin direcciones ni datos de usuario. Un resumen de conteos por sí solo no basta para reconstruir paquetes completos: después de confirmar el canal hará falta revisar la captura original de forma privada.
### Estado de la aplicación
- La build 894 permite comprobar el catálogo 26/01. **No hay una instalación de fotos desde iWatch comprobada todavía**. No habilitar un botón de aplicar que únicamente seleccione una esfera antigua o reporte éxito tras un ACK ATT.

## Prueba Bluetooth LE controlada — iWatch 0.8.4.55 (895)

La versión experimental agrega **Inicio → Personalizar esfera → Probar envío de fotos por LE**, pero la acción es **solo la primera negociación** (no transfiere ninguna fotografía ni cambia una esfera). Motivo:

- La descompilación propia de la APK Moto Watch 2.1.0.017 confirmó `FileSender.sendFile()` → `BandProxy.isRequirePending()` → **`BandProxy.requestSpp()`** antes de `getTransmission()`. Esto prueba que la ruta usada por la app Android solicita SPP/Classic, aunque no excluye que el firmware acepte negociación por LE.
- `ServiceId.FILE = 0x20`, `FileCommand.TRANSMISSION = 0x05`. En `FileSender.getTransmission()`, `MotoFt.FileTransmission {file_protocol_version=1, max_data_size=1024}` se envía como `20/05` con envoltorio Motorola `AA` y CRC16-XMODEM.
- El paquete BLE mide **13 bytes**; iWatch lo escribe por F8F1, verifica ACK ATT y espera **12 segundos desde el ACK** una respuesta `20/05` por F8F0. Una respuesta solo se considera prueba de negociación si longitud/CRC y campos de versión/tamaño son válidos. No se considera transferencia ni instalación.
- Una prueba fallida **no** desencadena envíos de `FtSend`, `FtChunk`, `AddAlbumWatchFace`, ni comandos OTA. Sin reintentos automáticos. Las otras funciones permanecen operativas.
- Protocolo reconstruido en `band/moto_ft.proto`: `FtSend` (task ID, URI, filename, tamaño, MD5), `FtChunk` (ID, contenido, offset/índice/CRC según versión), `FtComplete` y `FileTransmission`. Se requiere respuesta real del reloj y captura de subida oficial para implementar la secuencia restante.
- **Interpretación:** respuesta positiva por LE permite investigar la etapa siguiente; silencio/rechazo es evidencia contra esa ruta, no prueba lógica de imposibilidad. Un ACK ATT **no** significa que el firmware haya admitido negociación.
- Tests sintéticos para framing, CRC, respuesta válida/inválida añadidos a GitHub Actions, build 895.

### Prueba adicional: mapeo directo del canal de archivos en el Android oficial

En `classes4.dex` de Moto Watch 2.1.0.017, el método `BandProxy.getUUID(serviceId)` compara `ServiceId.FILE = 0x20` y devuelve **`LeServiceConstant.UUID_SPP`**. El inicializador de `LeServiceConstant` declara `UUID_SPP=fc9df9f0-4899-11ee-be56-0242ac120002`, `UUID_DEVICE=fc9df8f0-4899-11ee-be56-0242ac120002`, `UUID_FUNCTIONALITY=fc9df8f1-4899-11ee-be56-0242ac120002`, `UUID_FITNESS=fc9df8f2-4899-11ee-be56-0242ac120002`. `BandProxy.sendCommand` tiene una rama explícita de `SppConnection` y otra de `LeConnection`/característica GATT.

**Interpretación:** la APK enruta el servicio FILE por su ruta de SPP/Classic, no por la característica GATT F8F1 de iWatch. La prueba `20/05` por F8F1 es por tanto una desviación deliberada y reversible para evaluar el firmware, no una réplica exacta del transporte oficial. Si no hay respuesta, el próximo paso es analizar una captura de envío fotográfico para estudiar una ruta alternativa o un puente autorizado.
