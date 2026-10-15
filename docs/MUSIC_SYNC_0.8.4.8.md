# Music Sync · diagnóstico controlado v0.8.4.8 (build 848)

## Motivo
Los registros reales del 15/10/2026 mostraron:
- Recepción correcta de botones `24/07` por `F8F0`.
- Lectura correcta de Spotify vía Web API.
- Escritura BLE de varios metadatos `24/01` por `F8F1`.
- **Pantalla musical del Moto Watch Fit sin actualización**, aunque el transporte informó escrituras sin error.

No hay ACK de visualización en el protocolo conocido. La confirmación ATT
de CoreBluetooth **no demuestra** que el firmware aplicó el título.

## Qué hace esta compilación
El botón **Ajustes y diagnóstico → Spotify Premium → Music Sync ·
diagnóstico de metadatos → Resincronizar reproductor**:

1. Exige reloj BLE conectado y controles Spotify habilitados.
2. Solicita una lectura fresca de la canción desde Spotify SDK, o Web API
   cuando no está disponible el SDK (sin reenviar un título antiguo a ciegas).
3. Durante hasta 20 s, si se recibe una canción válida, fuerza una secuencia
   `24/01` de anuncio + estado, aunque la pista no haya cambiado.
4. Registra HEX de **hasta dos tramas musicales** (`MUSICA-DIAG: TX ANUNCIO`
   y `MUSICA-DIAG: TX ESTADO`) y los resultados por escritura
   (`BLE confirmó escritura` o `BLE rechazó`).
5. Si hay un nuevo estado antes de completar un paquete pendiente,
   se registra la sustitución; prevalece la canción más reciente. Se mantiene
   la prioridad existente de notificaciones y no se modifica su cola.
6. La captura expira; no hay sondeo adicional en segundo plano ni
   escrituras a servicios desconocidos.

**Privacidad:** los campos de canción/artista/álbum del paquete pueden
reconstruirse a partir del HEX. Activar la captura solo si se desea,
revisar el log antes de compartirlo. El HEX no incluye tokens OAuth.

## Prueba en el Moto Watch Fit

1. Instalar IPA v0.8.4.8 build 848 con el procedimiento habitual.
   Cerrar la conexión nRF Connect para evitar sesiones concurrentes.
2. Abrir Spotify y reproducir una canción de título corto.
3. Comprobar si el título aparece o no en el reproductor del reloj.
4. Con iWatch abierta, tocar **Resincronizar reproductor** solo una vez.
5. Esperar 5 s; verificar en el reloj si aparece el título.
6. En **Registro persistente**, buscar:
   - `MUSICA-DIAG: TX ANUNCIO` y `TX ESTADO` con HEX.
   - `MUSICA-DIAG: BLE confirmó escritura ANUNCIO/ESTADO`.
   - Errores, tamaños, sustituciones de secuencias.
7. Anotar el resultado visible en el reloj. Un BLE ACK no equivale a
   un ACK de pantalla.
8. Verificar que lleguen WhatsApp y consulta de batería. Salud debe seguir
   disponible sin perder historial local.

No pulsar el botón de prueba **pantalla sin música** durante este ensayo:
envía deliberadamente una trama de reposo aún experimental.

## Qué no resuelve todavía

- No corrige el protocolo `24/01` sin comparar con una **captura original
  completa del Motorola Edge**. La captura histórica disponible valida
  el esquema general, pero no alcanza para afirmar equivalencia byte a byte
  con el firmware actual.
- No inyecta AMS/HID y no otorga control universal iOS.
- No garantiza sincronización ni ejecución de Web API cuando iOS suspenda
  iWatch; errores de Spotify 429/502/503 requieren manejo separado.
- La función de diagnóstico no reescribe firmware y no toca el transporte
  de notificaciones, batería o Salud.

## Fuentes y pruebas
- `ios-native/Sources/WatchMusicProtocol.swift`: codificación Motorola `24/01`.
- `ios-native/Tests/MusicFrameChecks.swift`: verificaciones sintéticas de
  cabecera, longitud, CRC-16/XMODEM, anuncio, pausa y reposo.
- `docs/SPOTIFY_ESTABILIDAD_0.8.4.7.md`: gestión de interrupciones Spotify y cola temporal.

Esta rama se apoya en la PR de estabilidad #10 pero es **independiente de la
PR #9** de AMS/HID. No fusionar antes de validar en el reloj.
