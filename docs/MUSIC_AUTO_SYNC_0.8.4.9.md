# iWatch 0.8.4.9 (849) — Music Auto Sync

## Objetivo y alcance
Activar una recuperación musical automática de bajo tráfico sobre la
**8.4.8 (848)**, que ya incorpora botón de resincronización y diagnóstico
HEX de `24/01`. Es una **versión de prueba**, no una corrección confirmada
del firmware. La aplicación sigue sin recibir ACK visual de la pantalla.

## Arquitectura
- `MusicSyncEngine.swift` coordina actualizaciones de metadatos frescos
  suministrados por `SpotifyBridge` (Web API) o
  `SpotifyAppRemoteBridge` (SDK).
- `MusicAutoSyncPolicy.swift` encapsula la decisión y los intervalos;
  tiene pruebas sintéticas independientes.
- `WatchBLEManager.swift` sigue gestionando la escritura Bluetooth
  `F8F1`, la secuencia `24/01`, prioridad de notificaciones y Salud.
- El motor **no** consulta Spotify por sí mismo ni altera la frecuencia
  de consultas existentes (~6 s cuando la app está activa). No usa
  servicios BLE nuevos, firmware, AMS ni HID.

## Decisiones (automáticas)
| Evento | Acción |
| --- | --- |
| Canción o estado PLAY/PAUSA realmente cambia | Enviar actualización |
| Reloj reconectado y llega una pista **nueva y validada** | Reanunciar `24/01` y estado |
| iWatch vuelve a primer plano | Solicitar estado actual y reanunciar si hace al menos 90 s del anuncio anterior |
| Misma canción durante varios minutos, Spotify confirma reproducción, app visible | Un reanuncio preventivo **como máximo cada 180 s** |
| Pausa prolongada, Spotify informa 204 temporal | Conservar pista como estado desconocido, **sin borrar automáticamente** |
| SDK desconectado | Usar respaldo Web API ya existente, según acceso permitido por iOS |
| Botón manual Resincronizar reproductor | Lectura fresca, reanuncio forzado y captura HEX limitada |
| Reloj desconectado o controles Spotify apagados | No encolar tramas musicales automáticas |
| Error de Spotify / ausencia de canción nueva validada | No reenviar caché antiguo a ciegas |

El reanuncio automático solo sucede tras un estado musical real de Spotify,
no por un temporizador que inyecte paquetes sin saber si la música sigue
sonando. La recuperación pendiente caduca en 30 segundos. Las pruebas
de política validan límites, estados de pausa y segundo plano.

## Qué NO promete
- No se puede confirmar automáticamente que el reloj haya dibujado
  el título. Las trazas confirman transporte BLE, no aplicación del
  comando `24/01` por firmware.
- No hay sondeo continuo con el teléfono bloqueado: iOS puede suspender
  iWatch. La app aprovecha eventos disponibles y la restauración BLE.
- El 429 sigue pendiente de manejo explícito de `Retry-After`; no se
  considera solucionado.
- Los 502/503 pueden seguir ocurriendo en Spotify; no se reintentan
  automáticamente órdenes de control potencialmente ejecutadas.
- Si la secuencia Motorola difiere de la reproducción del paquete de
  iWatch, habrá que investigarlo con captura completa de Android,
  no enviar repetidamente paquetes incorrectos.

## Prueba recomendada en el Moto Watch Fit
1. Instalar **0.8.4.9 build 849**, sin nRF Connect conectado.
2. Abrir Spotify y reproducir una canción. Verificar el reproductor
   del reloj y el estado `Auto Sync` en Ajustes → Spotify Premium.
3. Cambiar canción con el botón del reloj y luego desde Spotify.
   Los metadatos deben actualizarse, sin lluvia de `MUSICA` cada 6 s.
4. Bloquear el teléfono 2–3 min, volver a abrir iWatch y esperar
   el nuevo dato: verificar si el reanuncio recupera la pantalla.
5. Pausar Spotify más de 45 s y reanudar. No debería generarse
   automáticamente `Estado sin música enviado: Ausencia de reproductor...`.
6. Comparar manualmente la pantalla con el registro `MUSICA-AUTO` y
   `MUSICA-DIAG`. Si persiste «No se está reproduciendo música»,
   usar **Resincronizar reproductor** UNA vez y compartir registros
   revisados por privacidad (el HEX revela título/artista/álbum).
7. Comprobar WhatsApp, batería y Salud; no probar simultáneamente
   servicios GATT de nRF ni desconectar el reloj salvo ensayo previsto.

## Ramas
Esta versión se basa en `experiment/music-sync-diagnostics` (PR #11),
que depende de `fix/spotify-playback-continuity` (PR #10); ambas son
independientes del experimento AMS/HID de PR #9. No fusionar sin
validación física.
