# iWatch 0.8.4.20 — build 860 — prueba HTTP real durante bloqueo

## Hallazgo de la 859 (registro 2026-10-16 UTC)
- 04:16:27 el SDK App Remote conectó automáticamente en primer plano.
- 04:18:09, cambio natural de canción a El Final Es En Donde Partí (La Renga), 24/01 reconocido por BLE.
- 04:18:34 bloquea iPhone; tres `BG-EXPERIMENTO` reportan `0 ms` (04:18:34, 04:18:43, 04:18:53). Eso NO demuestra una consulta HTTP: `refreshPlaybackInfo()` podía retornar temprano si `nativeMetadataIsFresh` del SDK era verdadero.
- 04:20:32 un comando real NEXT por BLE logra actualizar la canción con iPhone bloqueado; no consta actualización espontánea anterior.

## Cambios de la 860
- Nuevo `SpotifyBridge.probeWebPlaybackWhileBackgrounded()` intenta GET `/me/player` realmente, independientemente del flag de frescura de SDK, solo si iWatch está en segundo plano, Spotify autorizado y controles habilitados.
- Registrar `[SPOTIFY] BG-HTTP: GET /me/player iniciado` antes de la consulta y resultado explícito desde `[BG-EXPERIMENTO]`: HTTP 200, HTTP 204, error HTTP, error de transporte u operación omitida/descartada. HTTP 200 contiene título/artist y si hubo cambio; no confundir con pantalla confirmada.
- Cuando Web responde con 204 o no hay pista/dispositivo, conservar última canción y no fabricar estado PLAY/PAUSE.
- Si durante el GET llegó un callback SDK nuevo, la respuesta HTTP anterior se descarta. También descartar al volver a foreground, desactivar controles, cancelar task o cambiar de sesión.
- Se conserva la ventana limitada de consultas 0/9/18 s después de bloquear, más consultas solo ante eventos F8F0 reales elegibles, con cooldown. No se agrega polling infinito, fake BLE, silencio ni extensiones artificiales de audio.
- No se cambia Spotify App Remote (la 859 conecta), comandos play/pausa/next, firmware BLE, batería, widget ni Dynamic Island.

## Prueba de aceptación
1. Instalar IPA sin firmar build 860 con el método habitual; no desinstalar la 859 antes de comprobar que se conservarán los datos.
2. Abrir Spotify reproduciendo y iWatch, confirmar SDK conectado y canción visible.
3. En Music Auto Sync pulsar `Iniciar prueba`, bloquear iPhone con canción reproduciendo.
4. Esperar al menos 40–60 segundos, mirando el reloj, sin tocar botones. Si dentro de los primeros 20 s ocurre un cambio natural, es especialmente útil; si cambia después de 20 s NO se espera sondeo continuo.
5. Desbloquear y pegar registro persistente; buscar `[SPOTIFY] BG-HTTP` y `[BG-EXPERIMENTO] Resultado bloqueo 1/3`, `2/3`, `3/3` con HTTP/latencia. No afirmar éxito si aparece `OMITIDA`, 204 o error.
6. Separar observación visual en reloj de confirmación de escritura BLE; esta última no demuestra firmware.

## Límites
iOS suspende apps; una Live Activity no concede ejecución permanente. Estas tres consultas NO garantizan mantener el título actualizado durante minutos con teléfono bloqueado. Solo sirven para medir si la ventana inicial puede recuperar el cambio de canción. Para cambios tardíos necesitamos un disparador legítimo, por ejemplo evento Bluetooth espontáneo; ningún evento inventado está permitido.

## Reversión
La build 859 es referencia estable para conexión automática del SDK; PR experimentada y separada.