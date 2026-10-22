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
