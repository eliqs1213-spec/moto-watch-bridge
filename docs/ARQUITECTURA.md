# Arquitectura y protocolo

## Fuentes de la aplicación

`ios-native/project.yml` genera `MotoWatchNativeProbe.xcodeproj`. La aplicación compila `Sources/`, los atributos compartidos de ActivityKit y el sonido de búsqueda; la extensión compila `BatteryWidgets/` y los mismos atributos. Las antiguas copias Swift de la raíz no eran fuentes de este proyecto.

| Componente | Responsabilidad |
| --- | --- |
| `MotoWatchBridgeApp.swift` | Ciclo de vida y pestañas. La pestaña iWatch conserva sus controles avanzados en una hoja de ajustes. |
| `WatchBLEManager.swift` | CoreBluetooth, restauración, reconexión, lectura/escritura Motorola, ensambladores y cola de salida. |
| `WatchTrafficPolicy.swift` | Prioridad estable de tráfico, destino/vencimiento de avisos y calendario de consultas de salud. |
| `SpotifyAppRemoteBridge.swift` | Sesión y eventos del SDK Spotify; credenciales de sesión en Keychain. |
| `SpotifyBridge.swift` | Autorización Web API, respaldo musical y coordinación de controles/metadatos. |
| `NotificationShortcutIntent.swift` | Entrada de avisos desde Atajos; encola, no acredita visualización. |
| `WatchNotificationProtocol.swift` | Codificación de avisos; se comprueba que el paquete quepa en el MTU de escritura. |
| `PhoneFinder.swift` | Sonido de búsqueda del teléfono y aviso de respaldo. |
| `WatchConnectionAlerts.swift` | Avisos locales de conexión/batería. Son distintos de los mensajes reenviados al reloj. |
| `BatteryLiveActivityManager.swift` | Actividad en vivo con batería real disponible; no sondea Bluetooth por sí misma. |
| `HealthDashboardSync.swift` | Consultas secuenciales, calendario automático visible/activo y guardado de lecturas válidas. |
| `WatchHealthSync.swift` | Pasos y calorías desde una respuesta, más índice/bloques de ritmo cardíaco cuando corresponde. |
| `WatchStressProbe.swift` | Lectura de estrés. |
| `WatchVitalsProbe.swift` | Oxígeno y contadores de diagnóstico; la consulta integrada de oxígeno usa solo A. |
| `WatchSleepProbe.swift` | Recorrido limitado de sesiones de sueño. |
| `WatchHealthProtocol.swift` | Protobuf acotado, CRC, fechas, selectores y ensamblado de tramas de salud. |
| `WatchHealthStore.swift` | JSON local, migración compatible, unión de muestras/sesiones y consultas por reloj/día. |
| `HealthHistoryView.swift` | Portada de hoy, detalles día/semana/mes y acceso a diagnóstico. |

## Bluetooth

Servicio: `FC9DF9F0-4899-11EE-BE56-0242AC120002`.

- Recepción: `FC9DF8F0-4899-11EE-BE56-0242AC120002`.
- Escritura con respuesta: `FC9DF8F1-4899-11EE-BE56-0242AC120002`.

La sesión se declara lista cuando la característica de recepción notifica y existe una característica escribible. La app registra `bluetooth-central` y un identificador de restauración. No desconectar ese enlace ni desuscribir la característica como mecanismo de ahorro: también se usan para botones y avisos.

La cola termina una escritura antes de iniciar otra. Los avisos tienen prioridad; después música, salud y batería. Los mensajes musicales conservan su secuencia y pausa, pero esa pausa no bloquea los avisos. El resultado de una escritura BLE no confirma que el firmware haya dibujado la notificación.

Las consultas de salud validan tramas `AA`, longitud varint y CRC-16/XMODEM antes de interpretar Protobuf. Las respuestas grandes pueden llegar en notificaciones ATT fragmentadas; se reúnen antes de validar CRC. El ensamblador limita tamaño y tiempo de retención; no aumentar límites ni aceptar CRC inválidos para hacer aparecer una lectura. El decodificador de botones tiene su propio formato y validación.

## Rutas conocidas de salud

| Categoría | Consulta | Regla de integración |
| --- | --- | --- |
| Pasos y calorías | `30/06` | Campo 2: pasos. Campo 9: calorías activas. No etiquetar campo 3 como calorías. |
| Ritmo cardíaco | Índice `31/06`, bloque `31/07` | Ventana de 24 h, cursores/selectores validados, deduplicación por hora. |
| Sueño | Índice `31/08`, sesión `31/09` | Selector observado `[08 01]`; avance por final de sesión + 1 s, máximo 16 sesiones. |
| Oxígeno A | Índice `31/0B`, bloque `31/0C` | Serie confirmada. Admite cursor temporal o pequeño/ordinal según validación. |
| Estrés | Índice `31/0D`, bloque `31/0E` | Compara selector, límites y fecha. |
| Candidato B | `31/11` / `31/12` | Solo diagnóstico; no incorporarlo como oxígeno al histórico. |

La consulta de sueño acepta duración de minutos en float32 (campo 6), inicio/fin en campos 4/5. No asigna semántica a etapas aún no identificadas. Rechaza superposiciones ambiguas. La duración informada puede diferir del tiempo transcurrido entre inicio y fin.

Los índices con indicadores observados 1/2 no se interpretan como un simple booleano. El recorrido disponible no garantiza un histórico completo del reloj. No enviar confirmaciones que borren datos o avancen cursores permanentes sin conocer el protocolo.

## Persistencia y fechas

El archivo de salud sigue en Application Support, `WatchHealth/history-v1.json`. No cambiar nombre/ruta ni reemplazar silenciosamente un archivo que no se pudo decodificar.

- Campos nuevos opcionales para leer versiones anteriores.
- Clave por identificador de reloj y día local; no mezclar dispositivos.
- Pasos/calorías conservan snapshots y usan el último contador del día. No sumarlos entre consultas.
- Las muestras tienen identificadores estables y fecha original; sincronizar no cambia la hora de medición.
- Sueño se atribuye al día de despertar y suma sesiones independientes, sin duplicar las repetidas.
- Las tarjetas de portada filtran por hoy. La ausencia es «sin datos», no cero ni el último valor de ayer.
- El JSON se escribe de forma atómica con protección de archivo. Si no puede cargarse, se conserva para evitar sobrescribirlo.

El calendario automático de consultas vive en memoria; el histórico sí persiste. No hay servidor de salud ni integración con Apple Salud en este desarrollo.

## Datos sensibles

No incluir capturas crudas de Bluetooth/bugreports, mediciones personales, identificadores reales, tokens ni secretos en fixtures o documentación. Los tests deben usar datos sintéticos. El registro de avisos contiene origen/tamaño, no remitente ni texto. Los avisos pendientes se mantienen en memoria y no se guardan en el JSON de salud ni en disco.

## Puente web

`index.html` sigue siendo una herramienta independiente para Bluefy. Esta limpieza no cambia su contenido ni su ruta. Evitar que esté conectado al mismo reloj mientras se prueba la app nativa.
