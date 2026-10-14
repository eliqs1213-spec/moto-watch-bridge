# iWatch — Etapa 8: Notificaciones desde Atajos de iOS 27

## La novedad

**iOS 27 incorpora en Atajos un disparador «Notificación» para elegir una app y filtrar por título, subtítulo o mensaje.** Lo documenta Apple en https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios . No estaba disponible de la misma forma en iOS más antiguos.

Nuestro objetivo es **WhatsApp/Instagram (avisos reales) → Atajos → App Intent de iWatch → trama Motorola `25/02` → reloj**, sin PC, y sin ejecutar técnicas privadas o interceptar otras aplicaciones.

**IMPORTANTE: AÚN ES EXPERIMENTAL.** La disponibilidad del remitente/título/texto en «Entrada de Atajo» depende del tipo de notificación y de la app que la genera. Si esos datos llegan vacíos, no hay forma de reconstruirlos desde iWatch. También hay que comprobar la ejecución automática y BLE con el iPhone bloqueado. No prometemos recepción fiable.

## Qué contiene esta versión

- Pestaña **Notificaciones** con filtros para WhatsApp e Instagram y prueba local.
- Acción de **Atajos**: **«Enviar notificación al Moto Watch»** con parámetros **Aplicación, Remitente, Mensaje**.
- Codificador BLE Motorola **25/02** basado en las capturas del Motorola Edge con campos protobuf 1, 4, 5, 6, 7, 8, 9, CRC16-XMODEM, sin campos opacos ni datos personales.
- App Intent intenta ejecutar en segundo plano sin forzar abrir iWatch. No se ha confirmado que CoreBluetooth conserve una conexión utilizable durante esa ejecución; si no la hay, devuelve un error.
- Instagram usa un identificador de app tentativo porque **aún no se capturó una notificación real de Instagram**. Primero probar WhatsApp.
- No se guardan nombres ni contenidos de mensajes en el registro persistente de iWatch.
- Se conservan Spotify, BLE, protocolo batería `10/01`, Buscar iPhone y experimentos de la Etapa 7 con ActivityKit/WidgetKit (estos últimos siguen sin mostrar el widget con la firma actual).

## Prueba cero: comprobar si Atajos nos entrega datos

**No requiere instalar esta versión.** En iPhone con iOS 27:

1. Abrí **Atajos → Automatización → + → Notificación**.
2. Elegí la aplicación **WhatsApp**. Si no aparece, detenemos la prueba: no podemos asumir que esté disponible para tu instalación.
3. Creá una automatización sin filtros, inicialmente. Elegí **Ejecutar inmediatamente / sin confirmación**, si la opción está disponible.
4. Añadí una acción de diagnóstico **Mostrar resultado** de la **Entrada de Atajo**. Si podés seleccionar propiedades de la variable, inspeccioná **Aplicación, Remitente, Título, Mensaje/Contenido**. Los nombres visibles dependen de la versión.
5. Pedí que te envíen un WhatsApp mientras el teléfono está desbloqueado y revisá si llega el remitente y el texto.
6. Si obtenés texto, recién ahí pasamos al paso siguiente. Si la entrada sale vacía, enviá una captura de la automatización para investigarlo. **No cambies ajustes de privacidad ni compartas mensajes personales si no querés.**

## Prueba con Etapa 8 instalada

1. Instalá el IPA de GitHub por Sideloadly como en las etapas anteriores y conectá Moto Watch Fit por iWatch. No instales simultáneamente otras instancias de bridge Bluetooth.
2. Abrí la pestaña **Notificaciones** y probá una trama de prueba, para asegurarnos de que el codificador `25/02` de esta versión funciona.
3. En la automatización de WhatsApp, elegí la acción de la app **iWatch → Enviar notificación al Moto Watch**.
4. Asigná **Aplicación** al texto fijo `WhatsApp`.
5. Asigná **Remitente** al remitente/título entregado por la variable **Entrada de Atajo**. Asigná **Mensaje** al contenido/mensaje entregado por esa variable. La pantalla exacta varía según iOS.
6. Probá con iWatch abierta. Después con pantalla bloqueada. En caso de error, mirá el registro de la app (sin pegar contenido privado de chats).
7. Si funciona, repetí para Instagram; es posible que el identificador o tipo de evento requieran adaptar el código.

## Qué NO hace

- No lee por su cuenta el Centro de Notificaciones ni accede al sandbox de WhatsApp o Instagram.
- No intercepta llamadas ni implementa ANCS.
- No garantiza despertar el Bluetooth cuando iOS suspende o termina iWatch.
- No modifica firmware ni cambia las esferas del reloj.
- No soluciona WidgetKit: el registro de widgets con Sideloadly sigue pendiente.

## Código del protocolo y privacidad

Grupo Motorola `25/02` con campos protobuf observados: 1=tipo (1 usado para prueba), 4=1, 5=timestamp Unix, 6=remitente, 7=mensaje, 8=nombre de app, 9=identificador de app. El campo 10 observado en algunas capturas contiene datos opacos y no se reproduce. El codificador limita el texto UTF-8 sin partir caracteres y rechaza tramas mayores al máximo GATT negociado.

**No subir a GitHub** capturas HCI originales ni informes Android completos: contienen datos privados.

## Si la automatización no ejecuta con el iPhone bloqueado

No afirmamos que esa ruta funcione en segundo plano; Shortcuts, App Intents y CoreBluetooth tienen límites. Revisaremos el error y exploraremos otras acciones de Atajos, sin recurrir a servidores ni dejar una PC encendida.
