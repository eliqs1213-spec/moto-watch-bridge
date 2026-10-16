# Próxima sesión

**Nueva rama:** `feature/health-intelligent-charts-0866` ([PR #26](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/26)), sobre la build 865. Falta CI y prueba real de la consulta de sueño segmentado.

## Prueba obligatoria de sueño interrumpido

- [ ] Anotar horarios aproximados de primera y segunda sesión (incluido si cruzaron medianoche). El reloj muestra 4 h 08 y la app 2 h 59; diferencia 1 h 09. No asumir cuál bloque falta hasta examinar el diagnóstico.
- [ ] En Salud > Diagnóstico > Sueño, elegir el día de despertar, consultar y copiar el reporte completo 31/08 y 31/09, con sesiones devueltas, indicator, cursor y estado final.
- [ ] Comparar suma y cantidad de sesiones con la interfaz del Moto Watch; si hay desajuste marcar el día «parcial». No fabricar 69 minutos.
- [ ] Verificar que los gráficos inteligentes y la sugerencia de Ayuno excluyen consultas parciales.
- [ ] Probar sueño de una sola sesión, dos sesiones, período sin lecturas y transiciones de medianoche, respetando zona horaria.
- [ ] Confirmar que Spotify y Bluetooth no sufren regresiones por esta consulta.

## Historial anterior

**Candidata actual:** 0.8.4.25 (865), rama `feature/home-dashboard-stable-0865`, [PR #25](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/25).

## Validaciones prioritarias de 865

- [ ] Conseguir ejecución verde de Actions con IPA unsigned descargable. Confirmar versión 865 antes de instalar.
- [ ] Abrir Inicio: hora de iPhone, vista ilustrativa, batería real BLE, estados SDK/Web sin falsos «Conectado» y botón de recuperación.
- [ ] Verificar que la guía no presenta una recuperación de lecturas como medición manual instantánea.
- [ ] Ver Salud con Feli chibi **solo aquí**, estados calma/estrés/sueño, tamaño compacto, reducir movimiento y estadísticas que muestran cobertura real.
- [ ] Ver Ayuno separado sin mascota, cambiar horarios y duración, probar cierre/reapertura con tiempo real persistido, registrar corte temprano y al concluir.
- [ ] Dar o denegar permiso de notificaciones locales y comprobar recordatorios de inicio/fin sin duplicados.
- [ ] Verificar los controles musicales desde el Moto Watch con pantalla visible y bloqueada, incluidos fallback Web 404 y posterior reconexión.
- [ ] Investigar firma WidgetKit con instalador auténtico; [evidencia y pasos](PROBLEMAS_CONOCIDOS.md).
- [ ] Mantener pendientes el watchface instalado y datos meteorológicos Motorola hasta identificar su protocolo.

## Historial de pendientes anteriores

Punto de partida: app **0.8.4.5 (845)**, código en `codex/iwatch-design`; documentación y limpieza en `codex/repo-docs-cleanup`. [Estado y ramas](ESTADO_ACTUAL.md).

## Prioridades acordadas

1. Las notificaciones son prioritarias. Mantener enlace y restauración BLE; no ahorrar batería desconectando el reloj.
2. Spotify debe conservar la respuesta anterior a la optimización. El intento de espaciar sus consultas produjo demora y se revirtió. No volver a aplicar ese cambio por ahorro sin acordarlo.
3. Salud muestra hoy por defecto. Las lecturas anteriores siguen accesibles en el histórico.
4. Solo datos del Moto Watch; sin Apple Salud. No inventar muestras, categorías ni entrenamientos.

## Comprobación en dispositivo

- [ ] Revisar tarjetas y hoja de ajustes de iWatch en tamaño de texto normal/grande y modo claro/oscuro. Comprobar que todos los controles sigan accesibles.
- [ ] Cambiar canción, pausar/reanudar y usar anterior/siguiente desde el reloj. Confirmar que los metadatos recuperaron la rapidez previa con SDK conectado y con respaldo Web.
- [ ] Recibir WhatsApp con iPhone bloqueado, Spotify reproduciendo y una consulta de salud en curso. Anotar demora y estado de Atajos.
- [ ] Probar Instagram por separado; confirmar los campos entregados por la automatización.
- [ ] Cortar y recuperar el enlace brevemente: comprobar orden de avisos pendientes, ausencia de duplicados y vencimiento tras 2 minutos. No confundir «encolado» con visualización.
- [ ] Comprobar que una desconexión manual detenga la reconexión y cancele avisos pendientes.
- [ ] Verificar Salud al abrir, al volver del segundo plano y al pasar medianoche. Donde no hay mediciones de hoy, no deben aparecer valores de ayer.
- [ ] Comprobar actualización manual y automática sin duplicados; salir de Salud y confirmar que se detenga el sondeo automático de esa pantalla.
- [ ] Revisar guardado integrado de estrés/oxígeno/calorías/sueño tras relanzar la app, conservando el histórico anterior.
- [ ] Repetir sueño con varios descansos y comprobar que el total no se duplique tras actualizar.
- [ ] Probar búsqueda del teléfono y actividad en vivo con el iPhone bloqueado.

Usar la versión y hora exactas al reportar fallos, pero no subir mensajes ni datos personales al repositorio. Comparar consumo con un uso parecido durante un período suficiente; no atribuir un porcentaje de ahorro sin medirlo.

## Funciones todavía pendientes

- Identificar y sincronizar entrenamientos/registros de ejercicio.
- Identificar etapas del sueño antes de mostrarlas como profundo/ligero/REM.
- Investigar descarga histórica más amplia/paginación si el reloj la permite, sin borrar registros del dispositivo.
- Mejorar la continuidad de avisos dentro de lo que permitan iOS y Atajos; no prometer recepción universal.
- Revisar la fijación de versión del SDK Spotify para reproducibilidad, sin cambiarla en este cierre de limpieza.
- Evaluar pruebas de interfaz en simulador/macOS cuando haya un entorno disponible.

## Integración del repositorio

Los PR #2 a #7 siguen apilados y no están en `main`. Revisar/validar la cadena y las bases antes de integrar; no borrar ramas de trabajo como parte de la limpieza de archivos. El PR de documentación se apoya en #7. La última compilación publicada no es evidencia de que los PR hayan sido fusionados.
