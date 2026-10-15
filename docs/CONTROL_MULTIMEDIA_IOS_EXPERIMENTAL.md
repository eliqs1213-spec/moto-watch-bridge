# Control multimedia de iOS · prueba experimental 0.8.4.6 (846)

## Objetivo

Determinar si el Moto Watch Fit puede controlar el reproductor activo del
iPhone sin que iWatch ejecute comandos a través de Spotify SDK o Web API.
**Esta versión no activa ni implementa AMS, AVRCP o HID.** Es una prueba
de observación de los botones y de la lista GATT que CoreBluetooth puede ver.

## Lo que ya está confirmado

- El reloj envía a la característica de notificación Motorola F8F0 órdenes
  `24/07`: Siguiente, Anterior y Play/Pausa. iWatch las reenvía a Spotify.
- Las notificaciones iOS al reloj siguen funcionando aun cuando Spotify
  deja de responder a las órdenes. Eso confirma tráfico hacia el reloj,
  pero no prueba que los botones lleguen siempre desde el reloj.
- El iPhone publica Apple Media Service (AMS) como servidor GATT cuando
  está disponible. El accesorio debe actuar como cliente AMS; explorar
  servicios GATT expuestos por el *reloj* no detecta AMS del iPhone.
- iOS maneja HID a nivel del sistema y puede no exponer esos servicios
  a aplicaciones CoreBluetooth. No hallar UUID 1812 NO prueba ausencia
  de HID ni de perfiles multimedia clásicos.

Referencias oficiales:
- AMS: https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleMediaService_Reference/Specification/Specification.html
- HID y CoreBluetooth: https://developer.apple.com/forums/thread/69814
- Remote Commands en apps iOS: https://developer.apple.com/documentation/mediaplayer/mpremotecommand

## Prueba reversible en el iPhone

1. Instalar el IPA **de la rama experimental**, no reemplazar `main`
   hasta validar. Requiere firma del IPA si procede de Actions.
2. Conectar el Moto Watch Fit, iniciar Spotify y comprobar que funciona.
3. Entrar en iWatch → Ajustes y diagnóstico → Control multimedia de iOS.
4. Leer el estado "N servicios visibles · HID observado/no visible".
   No inferir compatibilidad AMS desde ese resultado.
5. Activar **Observar botones sin controlar Spotify (90 s)**.
   Durante esos 90 segundos, Siguiente, Anterior y Play/Pausa se
   *registran*, pero iWatch no ejecuta esas órdenes en Spotify.
   Los metadatos siguen su lógica normal.
6. Bloquear el iPhone y pulsar **Siguiente una vez**. Después
   desbloquear y revisar Registro persistente; buscar "OBSERVACIÓN".
7. Si Spotify cambia de pista SIN que iWatch reenvíe el comando,
   existe alguna ruta de control independiente y debemos identificarla.
   Si no cambia de pista, la conexión actual no demuestra una ruta nativa.
8. Esperar 90 segundos o desactivar el interruptor. Confirmar que los
   controles normales regresaron. No hacer más pruebas si el reloj o la
   app se comportan de forma inesperada.

### Límites de interpretación

- Registro "OBSERVACIÓN" significa que iWatch recibió el botón Motorola.
  No implica que Apple AMS esté disponible en el reloj.
- Ausencia de "OBSERVACIÓN" con iPhone bloqueado puede deberse a
  suspensión o entrega diferida de CoreBluetooth, no necesariamente
  a desconexión del reloj.
- El modo es voluntario, temporal, no persistente y se cancela al
  desconectar. No altera colas BLE, Spotify, metadatos, batería,
  notificaciones ni consultas de Salud fuera de la prueba.
- No se deben enviar escrituras desconocidas ni intentar emular un
  teclado/dispositivo HID desde iWatch.

## Próximo paso según el resultado

- **Control nativo observado:** caracterizar el canal (AMS, HID o
  accesorio gestionado por el sistema) antes de tocar el firmware.
- **Sin control nativo observado:** verificar si el firmware ofrece un
  modo accesorio BLE central compatible con AMS o un modo HID soportado.
  Para ello haría falta documentación o una captura de Android y
  pruebas de emparejamiento sin invadir otros perfiles.

No publicar capturas de bugreports completas, tokens, datos personales
ni el registro completo sin revisar si contiene información privada.
