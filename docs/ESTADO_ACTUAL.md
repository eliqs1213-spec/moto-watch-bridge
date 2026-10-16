# Estado actual · 16/10/2026

## Versión candidata y límites comprobados

- App propuesta: **0.8.4.25 / build 865**. Rama `feature/home-dashboard-stable-0865`, [PR #25](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/25) (en revisión). **No confundir con `main`**; todavía requiere build verde e instalación en iPhone.
- Base de los cambios: **0.8.4.24 build 864**, con mejoras de apariencia, Salud y comportamiento Spotify/BLE existente. En 865 no se cambió el protocolo Motorola ni la lógica de emisión musical, excepto aportar el mismo refresco en primer plano cuando Inicio es la pestaña visible.
- **Inicio:** representación ilustrativa del Moto Watch y hora del teléfono; porcentaje de batería real solo si el reloj está conectado y respondió, estados de BLE y Spotify, reintento manual de SDK, guía de medición con lectura posterior. **No promete sincronizar el watchface exacto.**
- **Salud:** seis métricas validadas con su histórico local, chibi animado Feli solo en Salud, resúmenes semanales por categoría que indican cuántos días tienen datos. Un valor del pasado conserva su fecha. Los datos sin medir no se inventan ni se computan como ceros.
- **Ayuno:** una pestaña aparte **sin mascota**; temporizador desde la hora real guardada en `UserDefaults`, duración editable de 8–18 h, notificaciones locales opcionales, registro explícito del corte. Si se dispone de tres noches comparables de los últimos catorce días, se calcula una sugerencia **del horario** a partir de sueño; no una prescripción de duración. Sin HealthKit ni cuentas online.
- **Feli:** dibujado en SwiftUI como chibi pequeño; movimientos suaves con respeto a **Reducir movimiento**, reacción amable basada en registros suficientes. Los dibujos 2D definitivos a partir de fotos quedan como refinamiento visual; las ilustraciones creadas como maquetas NO son assets integrados.
- **WidgetKit:** extensión presente en la instalación de 864 y una actividad ActivityKit activa, pero no se muestra el widget ni contenido en Dynamic Island. Crash de extensión en 862: **CODESIGNING / Invalid Page**. No se demostró que el firmado de Sideloadly 0.70.1 se resuelva con la build 865; [guía](PROBLEMAS_CONOCIDOS.md).
- **Música bloqueada:** iOS puede suspender iWatch sin eventos BLE; no se garantiza que cambios de pista naturales lleguen al reloj con pantalla bloqueada.
- No desinstalar por rutina: se podrían perder registros locales de Salud/Ayuno. No publicar capturas de datos privados ni tokens.

## Validación pendiente de 865

1. Build XcodeGen / Swift / tests sintéticos en Actions, publicación de IPA **unsigned**.
2. Instalación de IPA firmado en dispositivo, batería 10/01, conexión F8F0/F8F1 y prioridad de avisos.
3. Transiciones de pestaña sin duplicación problemática de consultas Spotify, comandos NEXT/PREV/PLAY y recuperación SDK.
4. Histórico por día/semana/mes, Feli sin invadir interface, carga con registros insuficientes.
5. Ayuno empieza/corta con fechas exactas, reanudación después de relanzar, permisos y avisos sin duplicación, sugerencia horaria según 3+ noches.
6. Diagnóstico WidgetKit independiente del funcionamiento de las pestañas.

---

# Historial de estado · 15/10/2026 (build 845)

## Versión y código de referencia de aquel cierre

- App: **0.8.4.5 / build 845**, configurada en `ios-native/project.yml` para aplicación y extensión.
- Código de la última compilación: `8246e4aa45674e4ffcbb235dc8a687d58105f86c`, rama `codex/iwatch-design`.
- [Actions verificado](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/38676992260): pruebas sintéticas aprobadas, compilación iPhone sin firmar y artefacto publicados.
- La rama `codex/repo-docs-cleanup` añade documentación y limpieza sobre ese mismo código, sin cambiar funciones ni versión.
- `main` sigue en `a0fb2c8f8cae6c34010c4493f79b2b6348c50d00`; no asumir que contiene las funciones recientes.

## Salud

La portada siempre muestra **hoy**. Si una categoría no tiene datos de hoy, muestra «Sin registros de hoy», sin reutilizar el último valor de ayer. Cambia de fecha al pasar medianoche o volver a la app. Los detalles abren hoy y permiten elegir otros días, semanas o meses.

Cada tarjeta distingue la fecha/hora de la medición de la fecha/hora de guardado. Consultar no inicia una medición: recupera datos ya disponibles en el reloj. El valor más reciente no implica una medición en vivo.

| Categoría | Implementación y validación disponible |
| --- | --- |
| Pasos | Contador comparado por el usuario con el reloj; guardado confirmado. Se conserva el último contador diario. |
| Ritmo cardíaco | Muestras y última lectura decodificadas; recepción y guardado confirmados. No etiquetar todas las muestras como manuales. |
| Estrés | Valor y hora comparados por el usuario con el reloj. Se guarda en el histórico integrado. |
| Oxígeno | Solo **candidato A**, confirmado por valor/hora. El candidato B no se incorpora al histórico. |
| Calorías | **Calorías activas**, campo 9 de `30/06`, comparadas con la app del reloj. No son calorías totales ni la suma de las consultas. |
| Sueño | Lectura contrastada con el reloj, incluyendo dos descansos en un mismo día. Se suman las sesiones por día de despertar; no se asignan etapas todavía. |
| Entrenamientos | Pendiente de identificar y sincronizar. No hay registros inventados. |

### Actualización automática

Se ejecuta mientras la portada de Salud esté visible, la app activa y el reloj conectado. No hay sondeo permanente de salud en segundo plano.

| Grupo | Intervalo mínimo entre intentos por reloj |
| --- | --- |
| Pasos + calorías | 5 minutos; una sola respuesta `30/06`. |
| Ritmo cardíaco | 15 minutos. |
| Estrés | 15 minutos. |
| Oxígeno A | 15 minutos. |
| Sueño | 1 hora. |

«Actualizar» consulta todas las categorías sin esperar esos intervalos. El coordinador comprueba vencimientos cada 30 s mientras está visible; los intervalos no son un reloj exacto y dependen de conexión y consultas en curso. Las marcas de intentos viven en memoria: un relanzamiento puede consultar todas las categorías nuevamente. No se ejecutan consultas simultáneas de salud. Los datos recibidos se guardan sin borrar otras categorías ni mezclar relojes.

El histórico crece con las consultas y no equivale a una descarga completa de todos los meses anteriores. Las mediciones se buscan en una ventana de hasta 24 horas; sueño recorre sesiones del rango consultado. No se usa Apple Salud.

## Spotify

Se retiraron las optimizaciones que demoraron los metadatos. Desde **0.8.4.4**, `SpotifyBridge.swift`, el envío `sendMusic` y el bucle de consulta conservan el comportamiento anterior a esa optimización, tomado de `f11391d73d1ea4cd93dca14db8978b45063ce0ee`.

- SDK App Remote como fuente prioritaria; Web API como respaldo.
- Eventos nativos y consulta de estado cada 6 s cuando el bucle de `ContentView` está activo y la app en primer plano.
- Filtro musical original: los datos iguales pueden volver a enviarse luego de 25 s; los anuncios de cambio de canción conservan su pausa de 0,8 s.
- Sin reenvío por Web de NEXT/PREV que ya se intentaron mediante el SDK.
- El comportamiento en segundo plano sigue sujeto a los eventos y tiempos que permita iOS.

La mejora de interfaz 0.8.4.5 conserva los callbacks de ciclo de vida y todos los controles. Falta confirmar en el dispositivo la rapidez de metadatos después de la restauración.

## Notificaciones y conexión

Prioridad: avisos → música → salud → batería. Se termina el paquete ya en vuelo antes de enviar el siguiente; los avisos no esperan la pausa entre metadatos musicales. Se conserva el orden entre avisos.

Los mensajes entran por la acción de Atajos. Con reconexión habilitada y un reloj conocido, los avisos aún no enviados pueden esperar **hasta 120 s en memoria**, con un máximo de 100 y destino al mismo reloj. Se descartan al vencer, cambiar de reloj o desconectar manualmente. No sobreviven al cierre del proceso.

«Encolado» no significa «mostrado». La confirmación de escritura Bluetooth tampoco acredita visualización en pantalla. Una escritura con resultado incierto no se repite automáticamente para evitar duplicados. Se recupera el enlace si una escritura queda sin respuesta durante 8 s. La reconexión tras fallos espacia los intentos de 1 a 60 s; el emparejamiento inicial limita cada búsqueda a 20 s.

Se mantiene la suscripción BLE y la restauración de estado. Las consultas auxiliares de batería se espacian a 30 min mientras la app esté activa, además de conexión y consultas manuales. No se midió aún el ahorro real de batería.

## Interfaz, actividad en vivo y búsqueda

iWatch muestra conexión, batería real disponible, música y búsqueda del iPhone. Todos los ajustes anteriores siguen en la hoja «Ajustes y diagnóstico». La actividad en vivo usa la respuesta de batería; el widget fijo es diagnóstico. La implementación actual no necesita App Groups. Búsqueda del teléfono conserva alarma y aviso de respaldo; comprobar su inicio con iPhone bloqueado.

## PR de desarrollo pendientes

Al cierre, los PR están abiertos y apilados, sin fusionar a `main`:

| PR | Rama de trabajo | Base |
| --- | --- | --- |
| [#2](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/2) | `codex/stress-read-probe` | `main` |
| [#3](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/3) | `codex/oxygen-calories-probe` | `codex/stress-read-probe` |
| [#4](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/4) | `codex/sleep-sessions-probe` | `codex/oxygen-calories-probe` |
| [#5](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/5) | `codex/health-dashboard` | `codex/sleep-sessions-probe` |
| [#6](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/6) | `codex/power-notification-priority` | `codex/health-dashboard` |
| [#7](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/7) | `codex/iwatch-design` | `codex/power-notification-priority` |

El PR #1 de pasos/ritmo cardíaco ya fue fusionado. Revisar la cadena antes de integrar o cambiar bases; no cerrar ni borrar ramas por considerarlas duplicadas sin verificar sus dependencias.
