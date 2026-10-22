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

## Prueba real 895 y corrección 896 (22 de octubre de 2026)
- La persona probó **iWatch build 895 en el Moto Watch Fit real**: la interfaz indicó **«Sin respuesta 20/05»**. Esa observación por sí sola no demuestra que no haya llegado un paquete.
- La revisión de una **captura Motorola HCI original anterior** (únicamente análisis local) identificó un intercambio íntegro con CRC-16/XMODEM válido:
  - Solicitud `20/05` = `MotoFt.FileTransmission` versión 1, `max_data_size=16384`, **14 bytes de paquete**.
  - Respuesta **`20/85`**, no `20/05`; campos `file_protocol_version=1`, campo #3 = 5120 y `max_data_size=16384`, **17 bytes de paquete**.
  - Esos mensajes fueron observados sobre **Bluetooth Classic RFCOMM** en el registro Android, no sobre la característica F8F0/F8F1 BLE de iWatch. Otros comandos de transferencia visibles en la misma sesión: `20/02` inicio, `20/82` respuesta, `20/04` fragmento, `20/84` ACK, `20/03` cierre y `20/83` ACK.
- La versión 895 pedía por BLE el tamaño 1024, en lugar de los 16384 de Motorola, y **escuchaba erróneamente `20/05` en vez de `20/85`**. Eso podía producir un resultado de *sin respuesta* incluso si el reloj emitió `20/85` por F8F0.
- **Build 896** replica la solicitud `20/05` de la captura y reconoce/valida `20/85` mediante CRC, versión, campo #3 y tamaño negociado. Las pruebas de Swift incluyen los dos marcos oficiales saneados y rechazan comandos/CRC erróneos. No se envía ninguna imagen ni se altera una esfera.
- Una segunda prueba física con 896 determinará si el reloj emite `20/85` por **GATT LE**. No extrapolar la respuesta Classic observada a LE.
- Si el resultado vuelve a ser silencio, priorizar una captura oficial de cambio de foto y evaluación de **puente Windows/Android** para implementar el canal RFCOMM; CoreBluetooth iOS no expone SPP/RFCOMM arbitrario en aplicaciones corrientes.


## Resultado en reloj real — build 896: sin respuesta 20/85

- El usuario volvió a ejecutar **Probar envío de fotos por LE** sobre Moto Watch Fit usando la build **896**, ahora con solicitud oficial `20/05` (`max_data_size=16384`) y parser correcto de respuesta `20/85`.
- **Resultado: «Sin respuesta por 20/85»**. Las builds 895 y 896 no han registrado negociación válida del servicio de archivos sobre **F8F1/F8F0 por BLE**.
- No consta ACK de nivel aplicación FILE, no hubo `20/82` de aceptación de archivo, no hubo envío de fotografías ni cambios de esfera. Mantener deshabilitada la ruta de archivo LE y **no** iniciar bloques `20/04` arbitrarios.
- Este resultado no demuestra imposibilidad matemática de otros transportes o estados, pero **la implementación oficial observada usa solicitud SPP/Classic** y la captura RFCOMM anterior muestra negociación `20/05→20/85` sobre Classic.

### Nueva ruta prioritaria: puente Motorola Edge 60

Objetivo del producto: **Inicio → Personalizar esfera → Enviar foto** en iWatch. Arquitectura candidata:

```text
iWatch iPhone
   │ seleccionar y exportar fotografía JPEG / 390×450
   │ envío autenticado y explícito por red local Wi-Fi
   ▼
Moto Edge 60 (aplicación auxiliar Android)
   │ conexión Bluetooth Classic / RFCOMM autorizada
   │ MotoFt: negociar → comenzar archivo → datos → verificar → completar
   │ MotoWatchface: registrar foto en álbum → seleccionar esfera
   ▼
Moto Watch Fit
```

Precauciones:
- La aplicación Moto Watch original ya dispone de una ruta Classic conocida, pero **se requiere captura de instalación de una FOTO**, no extrapolar el OTA de firmware.
- Una app auxiliar Android no puede llamar libremente a interfaces Java internas de otra app firmada si no están exportadas; quizá tenga que implementar su propio cliente RFCOMM y mensajes MotoFt.
- Confirmar emparejamiento Classic, anuncio SDP/UUID y quién inicia el RFCOMM durante **la instalación de una foto**, ya que la captura OTA no basta.
- Compartir fotografía en red local únicamente a un dispositivo elegido con código de emparejamiento de un solo uso; no crear servidor público ni subir fotos a un backend.
- El puente no debe tocar firmware/OTA, no debe enviar fotos ni cambiar la esfera sin acción explícita y aceptación verificable.
- **Windows es opción secundaria:** su API pública soporta RFCOMM, pero un diagnóstico anterior del reloj emparejado listaba 0 servicios Classic disponibles. No asumir conectividad efectiva sin test.

### Prueba que desbloquea el desarrollo
Con la APK Moto Watch oficial en Motorola Edge 60, capturar HCI mientras se **instala una foto nueva como esfera**. Comparar canal L2CAP/RFCOMM, UUID/PSM, `20/05`, `20/02`, `20/04`, `20/03`, ACK `20/8x` y `AddAlbumWatchFaceRsp`. Si se encuentra un flujo reproducible, implementar un MVP Android aislado y el botón iWatch que use el puente por Wi-Fi local.


## Prueba Windows real: OPEN_SPP aceptado por ATT, sin respuesta FileTransmission (22/10/2026)
- El usuario ejecutó el diagnóstico con el reloj real. Windows encontró 7 servicios GATT, se suscribió a F8F0 y escribió por F8F1 la solicitud `OPEN_SPP 12/19 type=1`.
- El reloj notificó `AA 06 00 00 12 19 08 04 A0 54`, trama correlacionada con CRC válido. Su semántica como éxito de apertura sigue sin confirmarse.
- La herramienta escribió `20/05 FileTransmission` (versión 1, `max_data_size=16384`) y recibió ACK ATT, pero **no recibió respuesta `20/85` tras 12 segundos**. SDP general y consulta explícita del UUID `FC9DF9F0-4899-11EE-BE56-0242AC120002` devolvieron cero servicios, antes y después.
- Conclusión acotada: la negociación de archivo **no está demostrada por GATT**; no se enviaron datos de archivo. No repetir envíos exploratorios. Próximo paso: capturar una instalación real de esfera dinámica desde la app oficial en Android y distinguir transporte, framing, paquete y ACKs.
- Guía de captura acotada, con controles de privacidad: [CAPTURA_HCI_ESFERA_DINAMICA_MOTO_WATCH_FIT.md](CAPTURA_HCI_ESFERA_DINAMICA_MOTO_WATCH_FIT.md). No subir HCI crudo a GitHub; compartir solo en privado si el usuario está de acuerdo.
