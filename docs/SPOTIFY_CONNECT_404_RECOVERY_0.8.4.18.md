# iWatch 0.8.4.18 / build 858 — Spotify Connect 404, pausa y pulsaciones retenidas

## Registro del dispositivo (16/10/2026 UTC)
- 03:43:15 → iWatch pasa a `background` con Live Activity; tres consultas en los
  siguientes 20 s no mantienen el sondeo periódico durante 3+ min bloqueado.
- 03:46:25 → Moto Watch emite PLAY/PAUSA; Spotify indica
  `Ella Es un Angel - Pappo`, pasa a PAUSA.
- 03:46:30 → Web API devuelve `404 Not found`, aunque el comando se había
  solicitado desde el reloj y la conectividad BLE seguía activa. La app
  intenta `play` posteriormente; `/me/player/devices` no reconoce iPhone.
- 03:46:39 y 03:47:09 → SIGUIENTE recibe `404 NO_ACTIVE_DEVICE`, entra
  a protección 20 s, o el comando es retenido.
- 03:47:12 → una nueva acción explícita Play consigue transferir la
  reproducción al iPhone. 03:47:21 → NEXT funciona y se reanuncian metadatos.
- 03:48:32 → usuario vuelve al primer plano sin nuevos inicios del proceso.

## Cambios
1. Clasificar **404 genérico en endpoints conocidos de comando Spotify**
   como posible pérdida del dispositivo Connect (el mensaje API puede ser
   simplemente `Not found.`). No reenviar automáticamente el comando
   fallido ni limpiar el título.
2. Durante los 20 s de protección de NEXT/PREV, una pulsación **nueva**
   en el reloj puede iniciar a lo sumo un GET `/me/player` cada 4 s.
   Solo si devuelve un **dispositivo Connect con ID** y el evento tiene
   menos de 6 s, se libera el bloqueo y se ejecuta el comando solicitado.
   Nunca repetir comandos antiguos ni saltar canciones a ciegas.
3. Si dos PLAY/PAUSA se acumularan ya en la cola, se conserva solamente
   el primero; se registra el segundo descartado (evita secuencias de
   pausa/reproducción tardías).
4. Diagnósticos diferenciados: 404 de comando, sondeo de recuperación
   por pulsación BLE, dispositivo ausente, sondeo vencido, reactivación.
5. Tests sintéticos de 404, cooldown de sondeo, ejecución exclusiva,
   antigüedad de pulsación y no confundir 401/429/500 con 404.
6. No cambia BLE, salud, batería, WidgetKit ni la Actividad en vivo.

## Restricciones reales
- Ninguna consulta HTTP puede despertar por sí sola a iWatch cada vez que
  cambia una pista con la pantalla bloqueada.
- Spotify Web API no puede obligar a que un iPhone ausente aparezca en
  Spotify Connect; solo se intenta transferir reproducción ante un
  **PLAY explícito**, a un único iPhone reconocido y no restringido.
- El manejo de 404 mejora la experiencia, pero no garantiza todos los
  comandos durante una pausa larga ni la actualización natural de metadatos.

## Prueba de aceptación en iPhone (build 858)
1. Iniciar Spotify, vincular watch, activar controles (no hace falta experimento
   Live Activity para probar botones), bloquear iPhone.
2. Con Spotify funcionando, NEXT una vez: cambia canción y actualiza título.
3. Pausa una vez desde Moto Watch; confirmar que realmente se detuvo.
4. Esperar 10–30 s, presionar Play **una sola vez** desde el reloj; comprobar
   si reanuda sin abrir iPhone. Si no, esperar unos segundos y presionar de
   nuevo, SIN hacer ráfagas.
5. Al volver música, presionar NEXT una vez, comprobar título. Si hay
   404, enviar log `RELOJ`, `SPOTIFY`, `MUSICA` y `BLE`.
6. No interpretar `BLE confirmó escritura` como confirmación de pantalla.
7. Mantener la build 857 como referencia si la 858 empeora algo.

## Código
- `SpotifyBridge.swift`: recuperación segura desde pulsación reciente.
- `SpotifyCommandQueuePolicy.swift`: política determinista.
- `SpotifyContinuityChecks.swift`: tests.
