# iWatch 0.8.4.10 build 850 · guardia para 404 sin Spotify Connect

Se basa en Music Auto Sync 0.8.4.9 (849) y conserva todas sus mejoras,
más la corrección de estabilidad ante ausencia de dispositivo activo.

## Registro que motivó el cambio

El 15 de octubre de 2026, un Moto Watch Fit enviaba normalmente
`SIGUIENTE` mediante `24/07` y respondía batería 95 % mediante
`10/01`, mientras Spotify Web API respondía `HTTP 404
NO_ACTIVE_DEVICE` ante muchos `NEXT` repetidos entre 19:54:04 y
19:54:13Z. Por tanto, **se confirma BLE operativo en ese intervalo**,
pero no un reproductor Spotify Connect disponible. No concluir de ello
que Bluetooth siga conectado minutos después.

## Cambio conservador

- Ante `404` con `NO_ACTIVE_DEVICE` o `device not found`, invalidar
  solamente la identificación del dispositivo de Spotify Connect.
  No borrar la última canción conocida ni desconectar el reloj.
- Bloquear **nuevas órdenes NEXT/PREV durante 20 segundos**. Así no se
  martilla la Web API cuando Spotify no tiene destino. El reloj sigue
  recibiendo otros mensajes y el botón PLAY/PAUSA conserva su recuperación
  de Spotify Connect si el usuario ha abierto la app.
- Limpiar la cola de pulsaciones pendientes para impedir saltos tardíos.
- Desbloquear inmediatamente NEXT/PREV al obtener un estado Web con
  dispositivo activo o al recibir un nuevo estado SDK.
- Mantener separados los fallos 404, 502/503 y 429; no reintentar a
  ciegas órdenes no idempotentes.

El tiempo de bloqueo no garantiza que Spotify vuelva a disponer del
iPhone. Si no aparece un reproductor activo, el usuario debe abrir
Spotify, elegir **Este iPhone** y comenzar a reproducir música.

## Para comprobarlo
1. Confirmar que iWatch muestra `F8F1 listo`.
2. Dejar Spotify cerrado/suspendido hasta reproducir un 404 controlado;
   el registro debe indicar `pausando NEXT/PREV 20 s`.
3. Pulsar Siguiente más veces: la API no debe recibir nuevos `NEXT`
   durante la pausa. No deben aparecer transacciones duplicadas.
4. Abrir Spotify en el iPhone, elegir `Este iPhone` y reproducir.
5. Obtener un estado válido del reproductor con dispositivo activo:
   `dispositivo activo recuperado`; probar Siguiente.
6. Confirmar que WhatsApp, Salud y batería se mantienen intactos.

**Limitación:** no modifica un reproductor sin dispositivo activo,
no implementa AMS/HID, no repara el ACK visual de `24/01` ni promete
ejecución cuando iOS suspende iWatch. `Retry-After` para 429 sigue
pendiente.
