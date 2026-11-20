# Informe forense técnico — iWatch / Moto Watch Fit

**Fecha:** 2026-11-20 · **Alcance:** investigación de interoperabilidad, fuentes de iWatch, análisis estático de OTA/APK, observaciones de logs y validación en iPhone.  
**Naturaleza:** reconstrucción documental de resultados reportados y verificados en informes previos; este informe **no** implica que se hayan repetido las capturas HCI ni las pruebas en reloj el 20/11.

## 1. Preguntas investigadas
- Cómo conectar y mantener Moto Watch Fit con iPhone sin Motorola Edge 60.
- Cómo transmitir notificaciones, clima, viento, batería y controles Spotify.
- Si existen rutas HID Classic, Apple Media Service (AMS), RFCOMM, transferencia de archivos/esferas o actualizaciones OTA aprovechables.
- Cómo mantener widget/Live Activity con las restricciones de ejecución en segundo plano de iOS.

## 2. Material y cadena de custodia
Fuente principal histórica: `iWatch-Proyecto-Completo-2026-10-22-CAPTURAS-EDGE-OTA.zip`, conservado fuera de GitHub como archivo anidado en respaldo local. Contiene un `repository-history.bundle`, instantáneas de código, capturas de Edge/OTA, informes de ingeniería inversa y artefactos de investigación. Fuente analítica: `Informe_investigacion_AMS_HID_iWatch_2026-10-30.md`. Fuentes de implementación: ramas y commits del repositorio, workflows GitHub Actions y registros de prueba comunicados desde el dispositivo. Los hashes de objetos técnicos figuran en el inventario.

**Regla probatoria:** «compiló» no implica «funcionó en iPhone»; «ATT aceptó fragmentos» no implica «el firmware procesó el comando»; «código HID presente» no implica «HID anunciado y utilizable».

## 3. OTA y firmware
El informe del 30/10 registró reconstrucción de OTA **20.538.246 bytes**, SHA-256 `d2970669988cf049fb38b90cfb7ae52d127f0cf47afe8c15982876647abe0f77`. Se extrajo `best1502x_b275_user.bin` desde offset `0xF349B`, **2.651.448 bytes**, SHA-256 `c51b2e4bdcdaa244dbd562b16c3893438dd16d97568ef71d2635d4b659bd5071`; se cotejó CRC-32. El análisis recuperó **84 entradas ZIP/DEFLATE** (48.739.281 bytes descomprimidos). Las cadenas apuntan a BES/BEST1502x, Cortex-M33 y FreeRTOS, sin equivaler a inspección física del chip.

La imagen contiene rutas de **HID Classic condicional**: `app_bt_hid_init`, PSM L2CAP `0x0011` y `0x0013`, SDP con 15 atributos y descriptor Consumer Control report ID 3. Se reconstruyeron reportes de volumen `A1 03 40`/`A1 03 80` y liberación `A1 03 00` **estáticamente**, no por captura en aire. El byte de RAM `0x200F2530` condicionaría inicialización HID, pero no se midió su valor real ni se probó un método seguro para cambiarlo. No se recomienda flashear: hay indicios de validación de firma RSA y no existe recuperación comprobada.

## 4. AMS y mensajes Motorola
Búsqueda de UUID oficiales AMS en 84 componentes recuperados: **cero coincidencias** en representaciones binarias habituales. Es un resultado negativo **acotado**, no una prueba de ausencia universal. AMS requiere que el reloj sea cliente GATT del servicio publicado por iOS; implementar una característica en la app iWatch no convierte al reloj en cliente AMS.

La vía operativa de música identificada utiliza mensajes Motorola **`24/07`** (órdenes) y **`24/01`** (metadatos), sobre servicios/características GATT de la familia `F8F0/F8F1/F8F2`. No se encontró puente demostrado desde `24/07` a HID multimedia.

El receptor `SYSTEM_CONTROL` del firmware analizado despacha casos `0x01–0x10`, sin caso `0x11`. El APK puede formar `11/11 FEATURE_LIST_INFO` (bit CAMERA `0x40`), pero no está demostrado que este firmware lo acepte: **no enviarlo como activador HID**.

## 5. APK Android y transporte
La `base.apk` analizada presenta SHA-256 `342097b6171f744cafa8f56babf3f5e49640d1d0e3d47b903cdf896b0bdb1ef7`. Se cotejó el emisor `SYSTEM_CONTROL/FEATURE_LIST_INFO` con el firmware. Las capturas HCI del Edge durante OTA apoyan transporte **Classic RFCOMM** de actualización; no demuestran HID Classic utilizable desde iOS ni AMS. Intentos BLE `20/85` de transferencia de archivos/esferas en builds 895/896 no obtuvieron respuesta válida; las pruebas Windows RFCOMM fueron inconclusas.

## 6. Spotify y ejecución en background
- Builds **853 / 8.4.13**: NEXT/PREV/PAUSA inicialmente funcionaban bloqueado, mientras el título quedaba atrasado.
- **856**: se sospechó una conversión potencialmente fatal `Double` a `Int` de `backgroundTimeRemaining`; sin crash original que cierre causalidad.
- **858**: BLE siguió operativo durante bloqueo; luego Spotify Web API devolvió `404 NO_ACTIVE_DEVICE`, separando falla Spotify Connect de desconexión BLE.
- **859/860**: sincronización espontánea de títulos a largo plazo no demostrada.
- **897**: referencia funcional; metadatos atrasados tras varias canciones.
- **900**: regresión reportada: comandos con teléfono bloqueado sin respuesta y cola que saltó varias canciones.
- **901**: compilación exitosa restaurando motor Spotify 897; no equivale a validación física.
- **920**: usuario confirmó música tras activar «Controles desde el reloj».

El informe del 30/10 encontró desacople en el protocolo: `snapshot.progressMs` codificado en campo 7 de `PlayInfo`, mientras referencia Motorola atribuye campo 7 a `music_album_art`; `PlayPercent` campo 2 no se construía. Debe contrastarse con trazas antes de atribuirle un efecto específico.

## 7. Clima y viento
La temperatura y clima se confirmaron en 897/920. Se documentó `0 mph` en reloj pese a Open-Meteo **8 km/h**. El empaquetado `23/01` y aceptación ATT de 52/52 fragmentos no prueban procesamiento del campo viento por firmware. Preferencia de visualización: km/h. **Pendiente** capturar paquete original del Edge y comparar campo/unidad/escala.

## 8. AccessorySetupKit, BLE y ActivityKit
- **902/904**: reportes `EXC_BREAKPOINT` en `ASAccessorySession init/start`; no se debe describir como error resuelto en esas builds.
- **906–918**: diagnósticos y cambios de autorización/selector.
- **920**: inicialización de `CBCentralManager` pospuesta mientras AccessorySetupKit presenta picker; migración y posterior conexión `Moto Watch Fit 61AD` confirmadas.
- **922 / 0.8.4.75**: restauración automática de accesorio previamente autorizado al abrir app, confirmada por usuario. CI: [run 42943917880](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/42943917880), `success`.
- **922**: error al crear Live Activity: `The operation couldn’t be completed. Target is not foreground`. Se recomienda solicitar inicio sólo en foreground, posponer solicitud si está en background y actualizar actividad existente sin duplicarla. **Corrección no implementada ni validada en este informe.**

## 9. Evidencia negativa y no conclusiones
No se vio GATT HID `1812`, MCS `1848` ni GMCS `1849` en inventarios de builds 882/885; esto no descarta SDP HID Classic. No hay prueba de anuncio SDP HID activo con iPhone, ni valor del byte HID RAM, ni firmware modificado aceptado por bootloader, ni instalación directa de esferas sin Edge 60. No confundir capacidades de firmware compartidas con funciones habilitadas en Moto Watch Fit.

## 10. Próximas pruebas reproducibles
1. Conservar build 920/922 funcional como punto de retorno.
2. Correlacionar por ID de evento recepción F8F0, estado de app, elección SDK/Web, HTTP 404/429 y TX `24/01`, sin tokens ni títulos privados.
3. Ensayar 5/15/30/60 minutos bloqueado; distinguir suspensión iOS, estado BLE y Spotify Connect.
4. Comparar tramas originales de viento Edge vs iWatch con unidades, campos protobuf y respuesta reloj.
5. Corregir inicio ActivityKit exclusivamente en foreground; medir reanudación y actualizaciones.
6. Mantener HID/AMS como investigación pasiva; no flashear ni activar comandos no validados.

## 11. Referencias
- [Inventario y hashes](INVENTARIO_EVIDENCIA.md)
- [Repositorio y documentación previa](../../docs/ESTADO_ACTUAL.md)
- [Apple Media Service Specification](https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleMediaService_Reference/Specification/Specification.html)
- [GitHub Actions build 922](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/42943917880)
