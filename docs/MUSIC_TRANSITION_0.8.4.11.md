# iWatch 0.8.4.11 (build 851) — Cambio natural de canción

## Hallazgo observado en el Moto Watch Fit

El usuario confirmó que, cuando Spotify pasa al siguiente tema automáticamente:
- **iWatch ya muestra la canción correcta**, incluso en primer plano.
- El **Moto Watch Fit conserva los metadatos anteriores**.
- Al abrir de nuevo iWatch, la pantalla musical del reloj sí se actualiza.

No hay que seguir investigando principalmente la detección de la canción;
el área probable de fallo está entre la decisión de enviar `24/01`, la cola
Bluetooth y la interpretación de la secuencia musical.

## Cambios de 851

1. En un cambio real de título/artista/álbum/PLAY/PAUSA, el módulo
   `MusicSyncEngine` ahora **fuerza la secuencia correcta** desde un
   snapshot reciente de SDK o Web API. Esto evita que el filtro BLE basado
   solo en URI + estado descarte cambios válidos de metadatos dentro de 25 s.
2. Cuando el reloj acepta un `ANUNCIO` pero el `ESTADO` de cierre aún
   está pendiente, recibir otra canción **ya no descarta ese estado**.
   Termina el par iniciado y después transmite la canción más reciente.
   No modifica paquetes de WhatsApp, Salud, batería ni su prioridad.
3. En primer plano, 5 s después de un cambio confirmado, se hace **una
   lectura nueva de Spotify** y, solo si valida la misma pista en PLAY,
   se reanuncia como máximo una vez. No se usa el caché a ciegas, no hay
   una cadena de reintentos ni consultas con la app suspendida.
4. Al reabrir iWatch, se permite reanuncio con un intervalo de seguridad
   de 15 s en lugar de 90 s, para reproducir el mecanismo que el usuario
   ya observó que recupera el reloj.
5. Se confirma por registro cuándo finaliza el paquete `ESTADO` en BLE
   (`MUSICA-SEQ`). El ACK BLE no prueba que el firmware haya actualizado
   la pantalla; la UI sigue indicándolo.

## Comportamiento esperado
- Al pasar naturalmente de canción, iWatch actualiza su tarjeta y
  envía `24/01 ANUNCIO` y `ESTADO`.
- Si la app está visible, vuelve a comprobar la canción al cabo de 5 s;
  si sigue siendo la misma, efectúa **un único reanuncio**.
- El flujo manual del reloj y el botón de diagnóstico siguen funcionando.
- Se mantienen las mejoras previas de errores 404, 429/5xx (sin retransmitir
  NEXT/ PREV), continuidad ante HTTP 204, batería, notificaciones y Salud.
- No hay garantías de ejecución al bloquear el iPhone ni de ACK de pantalla.

## Prueba recomendada
1. Instalar `0.8.4.11 build 851` en iPhone; confirmar reloj `F8F1 listo`.
2. Abrir iWatch y Spotify y poner una canción con título corto.
3. Dejar que **termine naturalmente**, sin tocar Siguiente ni forzar datos.
4. Observar iWatch y el reloj, esperar al menos **8 s** después de cambiar.
5. En el registro, buscar la transición `MUSICA`, el
   `MUSICA-SEQ: Etapa ESTADO confirmada` y el
   `MUSICA-AUTO: Verificación única...`.
6. Repetir una vez con iWatch en segundo plano para distinguir la
   suspensión de iOS; **no** asumir que la verificación a 5 s funciona en fondo.
7. Si el reloj continúa en «Poné música», activar una sola vez
   `Resincronizar reproductor` y compartir `MUSICA-DIAG` con precaución:
   los registros HEX pueden revelar títulos y artistas.

## Estado
PR experimental y comprobaciones sintéticas; **sin validación física
todavía**. No fusionar a principal hasta ensayar con el reloj.
