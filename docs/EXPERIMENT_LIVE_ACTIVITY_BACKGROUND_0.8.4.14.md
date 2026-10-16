# iWatch 0.8.4.14 (build 854) — experimento optativo Live Activity + música bloqueada

## Observación verificada (Moto Watch Fit / iWatch 0.8.4.13)
- **Primer plano:** tres cambios naturales de canción actualizan título y artista del reloj.
- **Bloqueo:** NEXT, PREV y PLAY/PAUSA desde el Moto Watch siguen funcionando,
  y los metadatos se actualizan después de esas órdenes.
- **Bloqueo, cambio natural:** la pantalla del reloj queda con el título anterior.
  El comportamiento persistió incluso después de activar Spotify iOS SDK.
- **Desbloquear:** iWatch consulta y actualiza el nuevo título inmediatamente.

## Fundamento / límites
- Apple Core Bluetooth: en iOS 26 o posterior, iniciar una **Actividad en vivo**
  con un `CBManager` ya instanciado permite algunas capacidades Bluetooth
  que normalmente son exclusivas de primer plano, incluso al pasar a fondo:
  https://developer.apple.com/documentation/corebluetooth
- Esto **NO concede ejecución general indefinida** ni convierte a Spotify Web
  API en una suscripción push. Sin evento BLE ni tiempo concedido, iWatch
  puede quedar suspendida y no saber que cambió la canción.
- Spotify recomienda desconectar App Remote al pasar al segundo plano:
  https://developer.spotify.com/documentation/ios/concepts/application-lifecycle
- No usar audio falso, timer permanente, abuso de BGTaskScheduler, sondeo
  continuo de batería ni BLE sintético para forzar un despertar.

## Diseño aislado: no afecta 0.8.4.13
- Rama `experiment/live-activity-bg-music-0854` basada en
  `fix/music-sequence-coalescing-0853`; PR separada en **draft**.
- Ajustes → **Music Auto Sync · experimento de segundo plano** →
  **Iniciar prueba**, únicamente si iOS ≥ 26, reloj conectado y
  controles Spotify activos.
- Reutiliza Actividad en vivo de batería REAL (sin inventar porcentaje);
  debe aparecer antes de bloquear. **Detener prueba** también finaliza
  esa actividad compartida.
- Ventana corta y acotada mediante `UIApplication.beginBackgroundTask`:
  hasta 3 lecturas Web API al pasar a fondo (t=0,9,18 segundos),
  interrumpidas si iOS no permite más tiempo, iWatch vuelve al primer
  plano, el usuario detiene o se pierde la conexión.
- Solo si iOS entrega un evento **auténtico** F8F0 durante el bloqueo,
  permite una consulta Spotify oportunista tras cooldown de 35 segundos,
  sin duplicar los comandos de música que ya tienen su propio refresh.
- El mismo `refreshPlaybackInfo` alimenta Music Sync existente
  (`24/01 ANUNCIO/ESTADO`), sin tocar formato, secuencia, prioridad
  de notificaciones, batería, Salud ni comandos del reloj.
- Traza de verificación: `BG-EXPERIMENTO`, con hora de entrada/salida,
  si había Actividad en vivo, número de sondeos permitidos por iOS,
  tiempo de ejecución y llegada de notificaciones BLE reales.
  La ausencia de esos eventos durante varios minutos es un resultado
  válido que demuestra límites de iOS, no una falla del widget.

## Prueba controlada
1. Confirmar que 0.8.4.13 se conserva como IPA estable de referencia.
2. Instalar experimental 0.8.4.14 **solo en el iPhone de prueba**.
3. iOS 26+; conectar Moto Watch Fit; iniciar Spotify manualmente.
4. En Ajustes iniciar **Music Auto Sync · experimento de segundo plano**.
5. Ver Actividad en vivo en pantalla bloqueada; si iOS no la permite,
   no seguir esperando mejoras del experimento.
6. Elegir canción de ~3 minutos, sin cambiarla manualmente; bloquear
   iWatch con el botón lateral; dejar terminar canción.
7. Mirar título en reloj. Desbloquear y **antes de otros comandos**
   copiar registro persistente, buscar `BG-EXPERIMENTO`,
   `MUSICA-SEQ`, `MUSICA-AUTO` y `BLE-TX`.
8. Comparar cuándo entró en background, últimas lecturas Web que iOS
   permitió y presencia/ausencia de notificaciones BLE reales.
9. Detener prueba. Si no hay mejora o consumo elevado, volver a 8.4.13.

## Criterios de aceptación
- No romper comandos existentes con pantalla bloqueada.
- No cortar transacciones musicales ni sobrescribir canciones antiguas.
- Sin lecturas sintéticas de batería, sin reproducción silenciosa.
- Reportar claramente si iOS suspendió la aplicación.
- **No declarar resuelto el cambio natural bloqueado** hasta que
  las pruebas reales muestren al menos tres cambios consecutivos
  sin intervención; un ACK GATT no es evidencia visual.
