> Documento histórico. Sus instrucciones corresponden a una etapa anterior. Consultar la [guía vigente](../../README.md) y el [estado actual](../ESTADO_ACTUAL.md).

# iWatch — Etapa 8.2.3: Spotify iOS SDK prioritario y metadatos con respaldo Web

## Objetivo

Controles y metadatos de Spotify usan **Spotify iOS SDK (App Remote)** cuando se conecta.
Si App Remote no está disponible, la app usa la **Spotify Web API** existente. No se
introducen Atajos para música; Atajos para WhatsApp e Instagram siguen como antes.

## Cambios principales

- Control desde el reloj: Play/Pausa, Siguiente y Anterior usan primero `SPTAppRemotePlayerAPI`
  si está conectado y iWatch está activa. Si el SDK NO llegó a emitir un comando,
  se recurre a Web API. No repetimos automáticamente un comando que el SDK pudo haber ejecutado.
- Metadatos prioritariamente nativos: título, artista, álbum, duración,
  progreso y estado de reproducción vienen de `SPTAppRemotePlayerState` y se
  envían al reloj por el protocolo Motorola de música.
- Metadatos Web API de respaldo: `GET /me/player` cuando el SDK esté
  desconectado o falle obtener/suscribir sus eventos.
- Evita respuestas atrasadas: si App Remote reporta nueva pista mientras una
  consulta Web está pendiente, esa respuesta Web NO pisa la pista del SDK.
- Al establecer App Remote, solicita estado actual sin esperar al próximo cambio de pista.
- iWatch muestra **Fuente de metadatos** para verificar SDK/Web API en pruebas.
- Cuando Web API no tiene reproductor activo, para Play puede buscar un único
  iPhone disponible en Spotify Connect; si lo hay, intenta transferencia con `play: true`.
  No elige automáticamente parlantes ni otro teléfono.
- Respuestas HTTP 404 temporales no borran por sí solas los metadatos musicales.
- Se conservan de la etapa 8.2.1: reconexión BLE; consulta Motorola de batería
  `10/01` al completar cada conexión; aviso local con porcentaje; Find Phone;
  notificaciones de WhatsApp e Instagram por Atajos.

## Instalar

1. Reemplazar la carpeta `ios-native` del repositorio con la de este ZIP.
2. Esperar la acción **Compilar Moto Watch Bridge iOS** en GitHub Actions.
3. Descargar el artifact **MotoWatchNativeProbe-unsigned** e instalar el IPA con Sideloadly.
4. En iWatch: mantener `Activar controles Spotify` activado y autorizar Web API
   si fuese necesario. Tocar **Activar SDK Spotify** para la sesión App Remote.
5. Observar `Spotify SDK`, `Fuente de metadatos` y `Última canción`.

## Pruebas recomendadas

1. Con iWatch y Spotify abiertos: reproducir, cambiar y pausar/reanudar desde el reloj.
   Verificar `Fuente de metadatos: Spotify iOS SDK · App Remote`.
2. Bloquear el iPhone; probar los botones del reloj. Cuando iOS haya desconectado
   App Remote, las consultas/comandos deben usar la Web API en las oportunidades
   de ejecución concedidas por iOS.
3. Pausar Spotify por varios minutos, intentar Play en reloj y revisar el registro.
   Si Spotify iOS está suspendido y no aparece un dispositivo Spotify Connect,
   ni SDK ni Web API garantizan poder despertarlo desde el fondo.
4. Alejar y acercar el reloj: confirmar consulta automática de batería Motorola `10/01`,
   notificación con porcentaje y recuperación de música.
5. Recibir WhatsApp e Instagram con el teléfono bloqueado.

## Validación del paquete

Los archivos Swift pasaron el analizador sintáctico local de Swift (`swiftc -frontend -parse`).
**No es una compilación Xcode completa ni una prueba en el reloj físico.** GitHub Actions,
la firma del IPA y la validación real en iPhone quedan pendientes.
