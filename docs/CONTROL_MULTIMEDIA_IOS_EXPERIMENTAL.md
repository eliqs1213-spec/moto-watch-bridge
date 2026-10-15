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

## Hallazgo de nRF Connect (15 de octubre de 2026)

En el **Moto Watch Fit** conectado a nRF Connect desde iPhone se observaron
los siguientes valores de Device Information:

| Campo | Valor observado |
| --- | --- |
| Manufacturer Name | `RivieraWaves SAS` |
| Model Number | `RW-BLE-1.0` |
| Hardware Revision | `1.0.0` |
| Firmware Revision | `6.1.2` |
| Software Revision | `6.3.0` |
| System ID | `1234 56FF FE9A BCDE` |
| PnP ID | `025E 0440 0000 03` |

**Hallazgo externo:** el repositorio de investigación del Samsung Galaxy Fit3
`Astroisback/Fit3Free` documenta exactamente los mismos valores y los
mismos UUID propietarios `1B7E8251-2877-41C3-B46E-CF057C562023` y
`8AC32D3F-5CB9-4D44-BEC2-EE689169F626`, y los identifica como
valores por defecto del fabricante de la pila Bluetooth en su contexto.
Fuente:
https://github.com/Astroisback/Fit3Free/blob/master/README.md

**Interpretación conservadora:** estos campos **no prueban** que el firmware
general del Motorola sea la versión 6.1.2/6.3.0, ni que los dos wearables
compartan firmware completo o compatibilidad AMS/HID. Podrían representar
valores por defecto de una implementación BLE común. No dirigir escrituras
ni asumir semántica multimedia en los UUID coincidentes.

La documentación oficial de Apple define que AMS es publicado por el
**iPhone** y que el **accesorio** debe actuar como cliente del servicio.
iWatch no puede convertir su central BLE en un accesorio que emite AMS
hacia la instancia local del propio iOS usando APIs públicas:
https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleMediaService_Reference/Specification/Specification.html

**Siguiente evidencia útil:** verificar el modelo y la versión auténtica
en Ajustes → Acerca de del propio reloj (sin publicar el número de serie)
y ejecutar la prueba observacional de esta rama. Si no existe control
nativo, investigar documentación o tráfico que demuestre una operación
AMS desde el firmware, no inferirla de la lista GATT del reloj.

### Actualización crítica sobre los UUID compartidos

Al investigar la coincidencia también se encontró que **el servicio
`1B7E8251-2877-41C3-B46E-CF057C562023` y la característica
`8AC32D3F-5CB9-4D44-BEC2-EE689169F626` se utilizan explícitamente en
código público de Infineon/Cypress para ejemplos Bluetooth "Hello Sensor"**,
independientes de Samsung y Motorola:

- https://github.com/Infineon/mtb-example-btsdk-ble-hello-client-20736/blob/master/hello_sensor.h
- https://github.com/Infineon/linux-example-btstack-hello-sensor

La misma característica aparece como indicador del estado Wi-Fi en el manual
del módulo Argox WM100-BW:
https://manuals.plus/argox/wm100-bw-combo-module-manual

**Corrección de interpretación previa:** aunque Fit3Free especula que
`1B7E8251` sería un canal Samsung Accessory Protocol, **no se debe
identificar así el canal del Motorola por coincidencia del UUID**. Estos
identificadores pueden haber sido copiados de ejemplos SDK y no demuestran
hardware compartido, un protocolo Samsung, HID, AMS, ni un mecanismo de
actualización de firmware. La semántica del canal Motorola permanece
desconocida. No enviar escrituras exploratorias a esa característica.

La coincidencia de las cadenas RivieraWaves/RW-BLE/6.1.2/6.3.0, junto con
los valores de ejemplo System ID y PnP ID, apunta a **valores por defecto
de la pila BLE**; no identifica el firmware principal. El reloj declara
independientemente su firmware `V1.73.20`.

## Identificación del firmware principal (video del reloj, 15/10/2026)

En Ajustes → Acerca de, **el propio Moto Watch Fit** muestra:

- Dispositivo: `Moto Watch Fit`
- Modelo: `XT2541-1`
- Número de versión: `V1.73.20`

Fuente: video compartido en conversación; **no publicar el número de serie ni
la dirección Bluetooth que aparecen en el video**.

Motorola confirma el modelo comercial `XT2541-1` en documentación oficial:
https://help.motorola.com/hc/apps/settings/legal/accessory/en-us/T1258144410.html

El manual oficial de Moto Watch Fit documenta controles musicales remotos
mediante la app de Android y aclara que su aplicación complementaria es solo
para Android. Eso **no certifica** AMS/HID en iOS ni acredita que se pueda
activar con un paquete Motorola:
https://en-us.support.motorola.com/app/answers/detail/a_id/185697/~/user-guide---moto-watch-fit

La versión `V1.73.20` es la información que el reloj presenta; NO
confundirla con las revisiones genéricas de la pila BLE que expone nRF
(`6.1.2` y `6.3.0`). No se obtuvo un protocolo de activación AMS/HID.

## Próximo paso según el resultado

- **Control nativo observado:** caracterizar el canal (AMS, HID o
  accesorio gestionado por el sistema) antes de tocar el firmware.
- **Sin control nativo observado:** verificar si el firmware ofrece un
  modo accesorio BLE central compatible con AMS o un modo HID soportado.
  Para ello haría falta documentación o una captura de Android y
  pruebas de emparejamiento sin invadir otros perfiles.

No publicar capturas de bugreports completas, tokens, datos personales
ni el registro completo sin revisar si contiene información privada.
