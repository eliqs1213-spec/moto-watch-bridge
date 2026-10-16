# Cambios

Las versiones listadas corresponden a compilaciones de desarrollo. Consultar [estado actual](docs/ESTADO_ACTUAL.md) para distinguir las ramas de `main` y la validación pendiente.

## 0.8.4.26 · build 866 (candidata)

- Gráficos específicos por métrica en Salud: tendencias con cobertura, dispersión de pulso/oxígeno, distribución de estrés, pasos/calorías por día y horario de sueño con al menos tres noches verificadas.
- Se corrigió la interpretación de sueño fragmentado: bloques separados, intervalos sin sueño y suma real; las consultas parciales no alimentan las recomendaciones de Feli ni Ayuno.
- Consulta experimental retrospectiva 31/08 para localizar descansos anteriores cuando el firmware devuelve primero el más reciente. **No validado contra reloj físico; no se agregan minutos faltantes artificialmente**.
- Caso a reproducir: Moto Watch **4 h 08**, iWatch **2 h 59** tras una noche interrumpida, diferencia de **1 h 09**.
- PR [#26](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/26). Requiere compilación y prueba real antes de considerarlo resuelto.

## 0.8.4.25 · build 865 (candidata)

- Inicio como primera pestaña: reloj ilustrativo con hora actual del iPhone, batería recibida por Motorola 10/01, estados BLE y Spotify, reintento de App Remote y guía de mediciones.
- Feli como mascota chibi discreta **solo dentro de Salud**, con animaciones accesibles e interpretaciones conservadoras de sueño, estrés, pasos y otras mediciones con cobertura de datos.
- Ayuno como pestaña independiente, sin mascota: cronómetro y objetivo configurable, horario sugerido tras tres o más noches disponibles, avisos locales optativos e historial de inicio y corte reales.
- Se mantiene el panel iWatch de diagnóstico, protocolo BLE, Spotify SDK/Web API y Atajos sin cambios a sus motores.
- Temas de watchfaces, clima BLE y WidgetKit con problemas de firma continúan pendientes. PR [#25](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/25); exige compilación y validación en dispositivo.

## 0.8.4.24 · build 864

- Apariencia automática/clara/oscura, tarjetas recientes de Salud y diagnósticos de extensión WidgetKit.
- Un fallo `CODESIGNING / Invalid Page` confirmado en extensión de build 862; no se considera solucionado.

## 0.8.4.5 · build 845

- Rediseño de iWatch con tarjetas para conexión, batería, música y búsqueda del teléfono.
- Ajustes y diagnóstico en una hoja separada; controles anteriores conservados.
- Lógica y ciclo de vida de Spotify conservados respecto de 0.8.4.4.
- Pruebas sintéticas y compilación iPhone aprobadas en [Actions](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/38676992260).

## 0.8.4.4 · build 844

- Restauración de Spotify a su comportamiento anterior a la optimización: SDK prioritario, Web de respaldo, consultas de 6 s en primer plano y método de envío musical original.
- Conserva mejoras de Salud, portada de hoy y prioridad de avisos.

## 0.8.4.2–0.8.4.3

- Portada de Salud limitada al día actual; detalles abren hoy, manteniendo selección histórica.
- Ajustes intermedios de Spotify por demora de metadatos; la restauración completa posterior es la referencia vigente.

## 0.8.4.1 · build 841

- Prioridad de notificaciones, cola temporal para cortes breves y recuperación de escrituras bloqueadas.
- Actualización automática de Salud por categoría; pasos y calorías comparten respuesta.
- Oxígeno integrado consulta solo la serie A confirmada.
- Búsqueda/reconexión y consultas auxiliares acotadas; registro guardado por lotes.
- Se intentó reducir consultas/reenvíos de Spotify; esos cambios musicales se retiraron en 0.8.4.4 a pedido del usuario.

## 0.8.4 · build 840

- Integración de pasos, ritmo cardíaco, oxígeno A, estrés, calorías activas y sueño en tarjetas con último valor y fechas.
- Consulta y guardado secuencial desde «Actualizar».
- Histórico por día/semana/mes, contadores sin sumas repetidas, sueño con sesiones separadas.
- Migración compatible del JSON de salud y pruebas de persistencia/deduplicación.

## 0.8.3.6–0.8.3.9

- Lecturas de estrés, candidatos de oxígeno/calorías y sesiones de sueño.
- Comparaciones de valor/hora en el reloj para identificar series; confirmación de oxígeno A y calorías activas.
- Soporte de cursor pequeño en oxígeno y múltiples descansos en sueño.

## Desarrollo anterior

- Pasos y ritmo cardíaco, ensamblado de respuestas fragmentadas y diagnóstico.
- Spotify SDK/Web, notificaciones por Atajos, reconexión, batería y búsqueda del teléfono.
- Notas originales disponibles en [archivo histórico](docs/archive/README.md); sus instrucciones y límites describen versiones anteriores, no el estado actual.

## Cierre de documentación y limpieza · sin cambio de versión

- README y documentación de arquitectura, compilación, estado y próximos pasos actualizados.
- Retiradas copias Swift/recursos/configuración de raíz que no se compilaban.
- Reglas mal subidas como `download` colocadas en `.gitignore`.
- Retirado helper de App Groups no referenciado por el proyecto actual.
- Notas anteriores y antiguo importador parcial conservados como archivo histórico.
- Se mantienen código funcional de la app, versión 0.8.4.5 y `index.html`.
