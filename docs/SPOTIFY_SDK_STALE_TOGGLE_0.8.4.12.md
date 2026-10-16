# iWatch 0.8.4.12 (build 852) — Estado de Spotify SDK estancado

## Captura recibida (15/10/2026, 21:26 ARG)

- **Activar controles Spotify** aparecía habilitado.
- **Reproductor:** `Controles desactivados`.
- **Fuente de metadatos:** `Desactivado`.
- **Spotify:** `Spotify App Remote · reproduciendo`.
- **SDK conectado:** `Sí`; **eventos del SDK:** `Suscripto`.
- **Último dato nativo:** `9:15:20 PM` (~11 minutos antes).

Esta inconsistencia apunta a un defecto de refresco de estado en iWatch.
No prueba si el firmware recibió la última trama musical; no implica
necesariamente pérdida del enlace BLE.

## Causa de código identificada

`SpotifyBridge.setEnabled(true)` consultaba directamente
`refreshPlaybackInfo(force:true)`. Esa función retornaba de inmediato
cuando el SDK decía `hasNativeMetadata=true`, incluso si el dato era
anterior a apagar/reencender controles. La UI quedaba en «Desactivado»
aunque el switch estuviera encendido.

A su vez, el bucle foreground consultaba `getPlayerState` al SDK cada
6 s, pero una suscripción activa sin nuevos callbacks no activaba
independientemente el respaldo Web API.

## Correcciones (sin desconectar BLE)

1. Al reactivar controles Spotify, la UI marca «Reactivando…» y solicita
   **estado SDK nuevo**, no un GET Web sujeto a un return prematuro.
2. Si no llega una confirmación nativa posterior a la reactivación en
   4 s, un único respaldo Web API verifica la reproducción.
3. `SpotifyNativeFreshnessPolicy` considera fresco solo un evento SDK
   válido de los últimos **20 s**. Cuando está suscripto pero estancado,
   se permite consulta Web normal en primer plano.
4. Se protege la prioridad nativa con `sdkMetadataRevision`: un callback
   SDK recibido mientras aguardamos HTTP descarta el resultado Web viejo.
5. `controlEpoch` cancela respuestas HTTP iniciadas antes de desactivar
   o reactivar controles.
6. Registro/diagnóstico muestra «Metadatos SDK vigentes: Sí/No», y se
   agregaron checks de 11 min sin evento, reloj en primer plano, sin
   SDK conectado y sin ningún callback.

Conserva las mejoras de `0.8.4.11` (transición natural, cierre
ANUNCIO/ESTADO, recuperación con fuente musical fresca) y la protección
404 de `0.8.4.10`. No altera prioridades de notificaciones, Salud ni
batería Motorola.

## Prueba física

1. Instalar `0.8.4.12 build 852`, sin conectar otra app BLE al reloj.
2. Reproducir una canción en Spotify, confirmar `F8F1 listo`.
3. En Ajustes, desactivar y activar controles Spotify una sola vez.
4. `Reproductor` y `Fuente de metadatos` NO deben permanecer
   indefinidamente en «Desactivado». Si el SDK no responde en 4 s,
   debe registrarse intento Web API.
5. Dejar terminar una canción con iWatch visible, y comprobar título
   en iWatch y reloj tras ~8 s.
6. Si el reloj no actualiza, capturar `MUSICA-SEQ`,
   `MUSICA-AUTO`, `SPOTIFY` y `MUSICA-DIAG` (manual).
   La confirmación GATT sigue sin demostrar actualización visual.

## Límites

No se ha validado en el reloj real. El SDK/Web API pueden carecer de
estado de un reproductor activo. El error 404 de Spotify Connect puede
persistir hasta abrir Spotify y elegir el iPhone. No hay garantía de
consulta periódica si iOS suspende la app. `Retry-After` para 429
sigue pendiente; no retransmitir automáticamente NEXT/PREV.
