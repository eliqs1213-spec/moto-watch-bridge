# Captura HCI de instalación de esfera dinámica — Moto Watch Fit XT2541-1

Fecha de investigación: 22/10/2026.

## Por qué dejamos de insistir con el envío GATT

La prueba real en Windows logró suscribirse a F8F0 y enviar la orden `OPEN_SPP`. El reloj respondió a `12/19` con `08 04`, pero la solicitud `20/05 FileTransmission` enviada por F8F1 no obtuvo respuesta `20/85` en 12 segundos. El SDP general y la consulta RFCOMM por UUID también devolvieron cero servicios. El ACK ATT solo confirma la escritura BLE, no que el firmware haya aceptado la negociación.

La APK oficial enruta `ServiceId.FILE=0x20` por su ruta SPP. La siguiente evidencia necesaria es una captura del tráfico real durante una instalación desde la app oficial Android, no más envíos a ciegas por GATT.

## Captura acotada desde Motorola Edge 60

1. En **Ajustes → Acerca del teléfono**, buscá **Número de compilación** y tocá siete veces. Confirmá el PIN si Android lo solicita. Si Opciones para desarrolladores ya está habilitado, omití este paso.
2. Entrá en **Ajustes → Sistema → Opciones para desarrolladores** (el nombre/ubicación puede variar) y activá **Registro de búsqueda HCI de Bluetooth** / **Enable Bluetooth HCI snoop log**.
3. Apagá y volvé a encender Bluetooth para que el registro entre en vigor.
4. Dejá conectado únicamente el Moto Watch Fit y abrí la app oficial Moto Watch. Para evitar datos ajenos, cerrá o desconectá otros accesorios Bluetooth y no abras notificaciones/mensajería durante la prueba.
5. Anotá la hora de inicio. En la app oficial, elegí una **esfera dinámica nueva de la galería/catálogo** (no una foto y, de ser posible, una que aún no esté instalada), descargala/sincronizala y aplicala al reloj. Esperá a que la app indique que terminó y aguardá unos 10 segundos. Anotá la hora final.
6. En Opciones para desarrolladores elegí **Crear informe de errores / Take bug report**, seleccioná informe completo si pregunta y esperá a que Android genere el ZIP. Puede tardar varios minutos.
7. En la PC, abrí el ZIP del informe y buscá el registro HCI bajo una ruta similar a `FS/data/misc/bluetooth/logs/btsnoop_hci.log` o un nombre `btsnoop_hci_*.log`. La ruta exacta varía por versión de Android. Extraé **solo el archivo btsnoop**, no hace falta compartir el informe ZIP completo.
8. Antes de desactivar el registro, verificá que la captura cubra la hora anotada. Después podés apagar HCI snoop para que no siga acumulando tráfico.

Si la app no ofrece descargar una esfera dinámica nueva y solo permite cambiar entre esferas ya presentes en el reloj, no hagas una selección repetida como sustituto: anotá esa limitación, porque un simple cambio de esfera puede enviar únicamente metadatos de selección y no el paquete del tema.

## Privacidad

El HCI snoop puede contener direcciones Bluetooth, datos de otros accesorios y tráfico de notificaciones. Hacé una captura corta, con pocos dispositivos conectados. **No subas el informe ni el HCI crudo a GitHub ni al repositorio público.** Para esta investigación, compartí únicamente el archivo btsnoop en este chat si te sentís cómodo; si preferís no compartirlo, podemos preparar un filtrado local antes de revisarlo.

## Qué vamos a identificar

- Si la instalación usa RFCOMM/SPP o GATT.
- La secuencia real de negociación y los ACKs.
- Si el paquete es un ZIP, JSON/recursos u otro formato.
- Tamaño, bloques, checksum y confirmación final de la instalación.
- La diferencia entre transferir recursos, registrar la esfera y seleccionarla como actual.

No se enviará ni modificará firmware OTA. Hasta obtener esta captura no se habilitará en iWatch un botón que afirme instalar un tema dinámico.
