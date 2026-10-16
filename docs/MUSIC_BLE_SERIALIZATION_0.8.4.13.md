# iWatch 0.8.4.13 (build 853) — Music Sync: evitar secuencias superpuestas

## Observación en el Moto Watch Fit, 15/10/2026 (Argentina)
- iWatch sí mostró la canción nueva tras un cambio natural, pero el reloj
  quedó en el tema anterior.
- `01:47:44Z`: ANUNCIO 24/01 y ESTADO 24/01 recibieron ACK GATT.
- `01:47:49Z`: coincidieron una verificación automática 5 s después del
  cambio y el botón «Resincronizar reproductor». La cola anunció que
  **sustituyó 3 paquetes musicales pendientes**, mientras otro ANUNCIO
  estaba en vuelo. Esto prueba superposición de escritores musicales.
- El usuario vio refrescar el título inmediatamente al pulsar resincronizar.
  Los eventos simultáneos impiden atribuir la actualización visual
  exclusivamente al envío manual.

## Cambios
1. `WatchMusicSequencePolicy.shouldCoalesce`: evita volver a crear
   ANUNCIO/ESTADO para **la misma pista + artista + álbum + PLAY/PAUSA**
   si ya hay paquete musical en vuelo o en cola. Cambios de canción
   o de reproducción sí pasan y sustituyen tramas aún no empezadas.
2. Si el usuario pulsa «Resincronizar reproductor» con el mismo tema
   en vuelo, **se difiere una sola resincronización manual** hasta que
   el paquete ESTADO haya sido confirmado. No se pierde la pulsación
   ni se interrumpe el cierre del mensaje anterior.
3. El botón manual cancela la verificación automática pendiente de los
   cinco segundos para que las dos acciones no compitan. Es posible
   que una verificación ya ejecutada llegue en paralelo: la cola
   coalescedora controla ese segundo punto.
4. Cada nueva secuencia registra su **origen**: `cambio automático`,
   `verificación automática`, `manual`, `recuperación`,
   `heartbeat` o `indirecto`; solo trazas simples, sin captura
   HEX continua ni contenido privado adicional.
5. Pruebas sintéticas de eventos duplicados, PLAY/PAUSA durante
   escrituras y capacidad de reanunciar tras el ACK.
6. No se cambian el protocolo 24/01 (CRC, 0x08 02, estado vacío),
   la prioridad de notificaciones, batería, Salud, la Web API
   ni los comandos de los botones.

## Prueba propuesta (no marca de solución)
1. Instalar 0.8.4.13 (build 853) cuando la CI termine.
2. Reproducir Spotify manualmente; esperar un cambio natural con
   iWatch en primer plano, sin pulsar comandos.
3. Anotar si cambió la canción del reloj inmediatamente, después
   de 5 s, o no cambió. Esperar unos 10 segundos adicionales.
4. Solo entonces pulsar «Resincronizar reproductor» y confirmar
   si actualiza el reloj.
5. Compartir el registro persistente: buscar `MUSICA` con origen,
   `MUSICA-SEQ`, `MUSICA-AUTO`, `MUSICA-DIAG` y `ERROR`.
6. Repetir 2–3 cambios naturales y Play/Pausa/Siguiente con el
   iPhone bloqueado, sabiendo que iOS limita ejecución en fondo.

## Límites
La escritura GATT confirmada NO prueba que el firmware actualice la
pantalla, y no hay un ACK visual en este protocolo.
La superposición observada es un defecto concreto, pero este ajuste
todavía no demuestra que resuelva todos los cambios naturales.
No volver a introducir reintentos automáticos ilimitados ni
reiniciar Bluetooth como método de recuperación.
