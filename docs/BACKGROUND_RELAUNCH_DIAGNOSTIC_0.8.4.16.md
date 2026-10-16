# iWatch 0.8.4.16 / build 856 — diagnóstico de cierres tras bloqueo

## Evidencia del teléfono / 8.4.15
- Al bloquear iPhone, el usuario observó que iWatch se reinicia; al abrir
  vuelve a la pantalla principal y recibe otra notificación de batería.
- Registro 2026-10-16T02:46:45Z: `BG-LIFECYCLE` entra a `background`;
  `BG-EXPERIMENTO` informa Live Activity activa y reloj conectado.
- **No** se registran consultas de la ventana experimental al fondo;
  el siguiente `SISTEMA Moto Watch Bridge nativo iniciado` aparece
  a las 02:48:50Z, coincidiendo con el desbloqueo. En otra prueba
  el proceso volvió a iniciarse a los 2 s del bloqueo.
- El registro NO permite determinar si es un crash o terminación de iOS.

## Error potencial real corregido
En el nuevo experimento se interpolaba
`Int(UIApplication.shared.backgroundTimeRemaining)` al registrar el
tiempo de fondo. **UIApplication puede devolver un número especial enorme
(`Double.greatestFiniteMagnitude`)** si no reporta un presupuesto finito.
En Swift convertirlo a `Int` provoca un **trap fatal**; esto podría
explicar entradas BG seguidas de un reinicio sin siquiera registrar la
primera lectura. Ahora se utiliza `remainingTimeLabel`, con límites,
y se persiste el registro antes de comenzar la consulta Spotify.

Esta es una causa probable, **no confirmada** por un informe crash de
iOS. Si persiste, recuperar informe en Ajustes → Privacidad y seguridad
→ Análisis y mejoras → Datos de análisis (buscar iWatch o
MotoWatchNativeProbe; también eventos JetsamEvent), o conectar Xcode.

## Avisos de batería sin nueva conexión
La recuperación del gestor `CBCentralManager` podía conservar la
conexión física y restablecer F8F0/F8F1 tras la muerte de la app.
La lógica de `finishBluetoothSetupIfReady` trataba ese caso como
una nueva sesión y llamaba `sendConnectedAlert`. Se suprimen esos
avisos al restaurar una conexión ya establecida, **sin eliminar** la
lectura 10/01 real ni el aviso en un nuevo `didConnect` físico.

## Prueba física mínima para aislar el reinicio (antes de música)
1. Guardar 8.4.13 como referencia. Instalar 8.4.16 build 856.
2. Iniciar Spotify normalmente, entrar a iWatch, conectar reloj.
3. Sin iniciar aún la prueba, bloquear iPhone durante 20 s y desbloquear.
   ¿Abre la misma pantalla? ¿Se repite `Moto Watch Bridge nativo iniciado`
   tras desbloquear? (La pantalla inicial sola no es prueba suficiente).
4. Activar la prueba **una vez**, esperar «Actividad en vivo iniciada»,
   bloquear 20 s y desbloquear.
5. Copiar `BG-EXPERIMENTO` y `BG-LIFECYCLE`, comparar la duración,
   nuevas entradas `SISTEMA`, consultas «Ventana al bloquear» y
   notificaciones de batería.
6. Si hay un reinicio solo CON experimento, no continuar hasta revisar
   incidente; la prueba es opcional y se puede detener.
7. La sincronización natural tras minutos bloqueado sigue **NO resuelta**,
   independientemente de que el reinicio haya desaparecido.

## Seguridad de versión
- Solo rama draft `experiment/live-activity-bg-music-0854`, sin
  modificar la versión 8.4.13 estable de referencia.
- No hay polling BLE ficticio ni audio silencioso.
