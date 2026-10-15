# iWatch 0.8.4.7 (847) — continuidad de Spotify

## Contexto confirmado en un Moto Watch Fit

El 15/10/2026 el registro mostró que, después de una pausa conocida,
Spotify Web API dejó de informar reproductor activo. iWatch envió un mensaje
musical vacío `24/01` 30 segundos más tarde, aunque la canción había sido
identificada y el reloj seguía conectado.

La misma sesión demostró que el Moto Watch Fit seguía mandando comandos
`24/07`; la Web API los gestionaba y se enviaban metadatos musicales por
`F8F1`. El SDK de Spotify falló por separado. **No atribuir el borrado
automático del panel a un corte general de Bluetooth.**

## Corrección acotada

- La respuesta HTTP 204 / ausencia de dispositivo Connect **no demuestra**
  cierre de Spotify. Si existía una pista validada, pasados 30 s se conservan
  título y metadatos y **no se envía el paquete vacío** al reloj.
- La interfaz indica expresamente `Reproductor no disponible · canción
  conservada`; no se afirma que la canción siga sonando.
- Se invalida el dispositivo/reproducción en caché al perder el estado, para
  evitar que Play/Pausa se base en un valor antiguo.
- Si todavía no existe ninguna pista conocida, después de la tolerancia
  original el estado sin música continúa disponible.
- Si Web API devuelve un `item` pausado pero sin `device`, se acepta como
  metadato válido y se sincroniza.
- Las acciones explícitas de desvincular, apagar controles y probar pantalla
  vacía mantienen su comportamiento anterior.
- Se conserva la prioridad de notificaciones y el flujo BLE/Salud intactos.

## Pruebas automáticas

`ios-native/Tests/SpotifyContinuityChecks.swift` prueba con datos
sintéticos los estados antes y después de 30 s, con o sin pista conocida,
y una tolerancia configurada. La compilación CI ejecuta estas pruebas,
además de la compilación iOS y los checks de Salud existentes.

## Prueba en teléfono (solo cuando se instale una IPA firmada)

1. Conectar iWatch, reproducir música y verificar la canción en el reloj.
2. Pausar Spotify en el iPhone al menos 45–60 s. La pantalla puede seguir
   con la última canción pausada y **no debe recibir `Estado sin música
   enviado: Ausencia de reproductor...`** por timeout.
3. Reanudar Spotify: la canción y el estado deberían actualizarse cuando
   iWatch tenga ejecución de iOS y un estado válido del SDK/Web API.
4. Cambiar canciones desde el reloj en primer plano; después con el iPhone
   bloqueado (sin prometer ejecución ilimitada en segundo plano).
5. Revisar `Registro persistente` si un comando falla, especialmente
   `RELOJ`, `SPOTIFY`, `MUSICA`, `BLE-TX`, `ERROR`.
6. Recibir una notificación y consultar batería para verificar ausencia de
   regresiones. Confirmar que Salud conserva historial.
7. Desactivar controles Spotify voluntariamente y volver a habilitarlos:
   esto **sí** borra/reanuncia el panel según diseño anterior.

## Hallazgo adicional: errores 502 y botones descartados

El registro del 15/10/2026, alrededor de las 15:55 hora argentina,
demostró una segunda causa independiente:

- El reloj envió `SIGUIENTE` correctamente por `24/07`.
- Spotify Web API devolvió `502 Bad Gateway` a esa solicitud.
- Ante nuevas pulsaciones, iWatch registró `Spotify ocupado: comando
  SIGUIENTE no enviado` porque una consulta anterior seguía en progreso.
- La orden que sí se procesó llegó a cambiar de canción después.

### Mejora experimental

- Ante una orden válida recibida cuando Spotify todavía está ocupado,
  mantener hasta **2 pulsaciones pendientes**, ordenadas, con vencimiento
  de **6 s**. Si se supera el límite o vencen, registrar explícitamente
  el descarte (no ejecutar tarde).
- Las pulsaciones conservan el filtro de rebotes actual.
- Clasificar HTTP 429 y 5xx como errores temporales, manteniendo los
  metadatos conocidos.
- **No reintentar automáticamente** Next/Previous/Play-Pause tras
  un 502 ni un timeout: la API podría haber aplicado la orden pese a
  devolver un error y se generarían saltos/pausas duplicados.
- Vaciar la cola al deshabilitar controles o desvincular Spotify;
  no enviar órdenes si ya no existe enlace Bluetooth.

### Validación manual adicional

1. Con Spotify reproduciendo, pulsar Siguiente varias veces con
   separación suficiente para superar el antirrebote.
2. Confirmar en registro `Encolado` y luego `Ejecutando pulsación
   pendiente`, o `Pendiente vencido`, sin cambios tardíos.
3. Observar si falla Web API con 429/502/503: la música del iPhone
   puede seguir, no borrar metadatos ni lanzar saltos automáticos.
4. Confirmar notificaciones y consultas de salud intactas.
5. Repetir con iPhone bloqueado: el límite de ejecución impuesto
   por iOS podría impedir consumir una cola y no se garantiza
   ejecución universal en segundo plano.

**Pendiente:** determinar por qué el firmware no reflejó en pantalla
algunas escrituras musicales F8F1 aunque el envío BLE fue aceptado.
Esta PR se centra en conservar metadatos y en órdenes Web API: no da
por resuelto ese defecto de visualización.

## Alcance y limitaciones

- Esta build se basa en `codex/repo-docs-cleanup` (PR #8), **no** en el
  experimento AMS/HID de PR #9. Son pruebas distintas. No confundir sus IPA.
- No modifica el control universal del iPhone, ni intenta emular AMS/HID.
- No resuelve de forma garantizada los fallos de sesión del Spotify iOS SDK,
  HTTP 404, cortes de red, ni la suspensión de apps por iOS.
- La confirmación de escritura BLE significa que el paquete fue aceptado
  por el transporte, **no** que la pantalla lo mostró.

