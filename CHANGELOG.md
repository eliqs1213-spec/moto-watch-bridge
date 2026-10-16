# Cambios

Las versiones listadas corresponden a compilaciones de desarrollo. Consultar [estado actual](docs/ESTADO_ACTUAL.md) para distinguir las ramas de `main` y la validación pendiente.

## 0.8.4.35 · build 875 (candidata)

- Corrección a partir del segundo video enviado después de instalar 874: Feli todavía pequeño dentro del espacio de la escena; cámara más cercana (1,74 sin accesorios, 2,32 con mate o parrilla).
- Mandíbula, cavidad bucal y lengua ya no se animan con comportamientos desconectados. Cavidad fija en la cabeza, mandíbula inferior articulada, y lengua anclada físicamente a la mandíbula.
- Una sola variable de apertura controla la cavidad, el descenso/giro de la mandíbula y la aparición gradual de la lengua; el cierre la oculta. Evita que parezca flotar, sobre todo en bostezo y festejo.
- Preserva el resto de animaciones 3D, burbujas cercanas y mediciones reales de Salud/Ayuno.
- Pendiente de verificar visualmente el cambio en iPhone tras comprobar CI; compilar no demuestra que la sincronización sea estética ni geométricamente perfecta.

## 0.8.4.34 · build 874 (candidata — evaluación visual pendiente)

- Ajustes directamente basados en el video real de iWatch 873 (46 segundos): Feli aparece minúsculo dentro de una galería con mucho espacio vacío, y el globo de pensamiento queda lejos de su cabeza; en Salud Feli también se ve diminuto en modo compacto.
- Cámara 3D más próxima al beagle (escala ortográfica 2.05) y encuadre más ancho (2.68) en escenas con mate, vacío y festejos para no recortar los accesorios.
- Galería con personaje 3D en escena responsiva de hasta 310 puntos; Salud y Ayuno muestran Feli a 178 puntos expandido y 107 compacto. No se sobreponen a las tarjetas: continúan dentro de Safe Area.
- Nueva vista FeliCharacterStage: sitúa el globo directamente en la misma escena al lado de la cabeza, en lugar de sumarlo como un renglón independiente; escala la burbuja cuando la ventana es pequeña y no intercepta los toques para acariciar.
- Acciones tridimensionales más expresivas: olfato mueve cabeza y hocico a mayor distancia y abre/cierra la nariz; bostezo abre la mandíbula y muestra lengua, estiramiento adelanta ambas patas y baja el pecho; la actividad alterna las cuatro patas, el torso se balancea y avanza lateralmente de forma sutil.
- Mantiene el diseño limón y blanco, escenas de mate/asado, respuestas de estrés, lecturas Bluetooth, oxígeno y sueño de las anteriores versiones.
- CI confirma la compilación del código; la calidad visual y fidelidad al diseño elegido solo se pueden valorar reproduciendo la escena en el iPhone.

## 0.8.4.33 · build 873 (candidata)

- Feli 3D más grande en Salud y Ayuno (de 107/114 a 143/142 puntos) y con cámara más cercana. Las superficies esféricas pasan a una malla con 56–88 segmentos para suavizar facetas visibles; cápsulas y cilindros tienen más segmentos y las orejas se redondean con chaflán. Nariz suavizada.
- Nueva burbuja de pensamiento en Salud, Ayuno y galería, que explica el gesto mediante un texto breve, sin inventar lecturas.
- Estrés: solo lecturas **>= 70/100** muestran «Nivel alto de estrés registrado», valor real y recomendación breve de hacer una pausa y respirar con tranquilidad; promedio alto se distingue de última lectura. El valor 50/100 permanece neutro. La escala es orientativa del Moto Watch y no diagnostica estrés clínico.
- En ese estado Feli gira la cabeza, consulta el reloj, modifica orejas, respiración, mirada y apoyo de patas; conserva el resto de actuaciones 3D.
- Galería actualizada para examinar de cerca todas las escenas y sus burbujas.
- Preserva Ayuno, oxígeno ya validado y sueño 4 h 08 de la versión base. Requiere probar el aspecto en el dispositivo: más segmentos suavizan bordes, pero no equivalen a un rediseño completo mediante una malla 3D profesional.

## 0.8.4.32 · build 872 (candidata, pruebas visuales pendientes)

- Sustituye el avatar 2D que solo movía una pata por un verdadero personaje **3D articulado con SceneKit**, modelado en código con volumen, materiales, iluminación, cámara, perspectiva y controles táctiles sobre geometría tridimensional.
- Beagle limón/blanco basado en referencia: cráneo, hocico, nariz, ojos, franja blanca, orejas largas caídas y arnés naranja; cuerpo, patas anteriores y posteriores, cola, mandíbula y orejas tienen nodos y transformaciones propias.
- Animaciones 3D **distintas**: olfateo baja hocico y cabeza; bostezo abre mandíbula/tongue; estiramiento adelanta ambas patas y baja el pecho; buena actividad alterna las cuatro patas; dormir baja el cuerpo y cierra ojos; relax respira; saludo levanta pata y mueve cola; orejas se mueven independientemente; pancita se recuesta con movimientos propios.
- Animación en Salud al abrir una métrica según última lectura y en Histórico según promedio; en Ayuno escenas de mate 3D, parrilla 3D con vacío, brasas y humo animado, cuenta regresiva y festejo real.
- La galería en Ayuno permite seleccionar 14 actuaciones 3D, no solo cambiar accesorios. Tocar cabeza, orejas o cuerpo intenta seleccionar la zona real mediante SceneKit hit-testing.
- Respeta Reduce Motion y pausa la reproducción en segundo plano. Mantiene el oxígeno validado y la recuperación/guardado de sueño 248 min de 870.
- **Limitación:** es un modelo 3D estilizado generado proceduralmente; no es todavía un modelo 3D artist-authored/rigged fotorealista que iguale exactamente el concept art. Requiere evaluación visual y de rendimiento en iPhone.
- Compilación y IPA de 872 pendientes al crear la candidata.

## 0.8.4.31 · build 871 (candidata)

- El nuevo Feli es un personaje vectorial animado en SwiftUI, NO una imagen estática ni un GIF: pelaje limón y blanco, franja blanca, arnés naranja, orejas largas caídas y piezas animadas independientes (respiración, parpadeos, nariz/olfateo, inclinación, orejas, cola, pata, estiramiento y bostezo). El toque en cabeza, orejas o pancita desencadena gestos y corazones.
- **Salud**: conserva lectura más reciente, histórico y promedio por día (868–869); solo se anima según datos efectivamente almacenados, sin conclusiones clínicas.
- **Ayuno**: Feli acompaña en dock minimizable durante el temporizador y nunca tapa el cronómetro. Al iniciar toma mate feliz; luego descansa, curiosea, imagina un **vacío sobre la parrilla** con brasas animadas, mira el reloj y festeja al alcanzar el objetivo o después de guardar un corte real que cumplió el objetivo.
- Las etapas de Ayuno se activan por porcentaje transcurrido, no por supuestas sensaciones físicas de hambre; muestra frases simbólicas. Completar el objetivo NO corta el ayuno automáticamente. Reduce Motion pausa las animaciones; fuera de la app también se pausan.
- Galería interactiva en Ayuno («Ver todas las animaciones de Feli»): permite elegir las 8 escenas reales y tocar cabeza, orejas o pancita sin falsear sensores ni modificar el historial del ayuno.
- CI valida estados de Ayuno y el pipeline iOS; la apariencia, la escala y la firma en Sideloadly requieren prueba en iPhone.
- Mantiene oxígeno y el guardado de sueño BLE 248 minutos de build 870.

## 0.8.4.30 · build 870 (candidata)

- Corrección basada en datos reales del Moto Watch, **16/10/2026**: el diagnóstico 31/09 entrega una sesión de **248 min (4 h 08)**; Salud conserva un registro antiguo de **179 min (2 h 59)**.
- Diagnóstico de Sueño: cuando termina correctamente con sesiones, las guarda en el historial de Salud automáticamente y muestra el total persistido (antes era exclusivamente una consulta de prueba).
- Persistencia: si el firmware devuelve un total envolvente nuevo de 248 min que reemplaza al registro previo de 179 min del mismo descanso, se conserva el más completo, sin sumar 427 min ni rechazarlo por una superposición que significa actualización. Se rechazan superposiciones ambiguas.
- La actualización automática no marca el sueño como sincronizado si la lectura quedó parcial. El gráfico y la reacción de Feli se recalculan desde la lectura guardada, sin inventar duración.
- Prueba de regresión 179 → 248 → 179 (reintento viejo), confirmando total estable en 248 y marca de recorrido completo. Pendiente de compilar y verificar en el iPhone; esto no identifica las fases internas del firmware.
- Hereda el oxígeno confirmado en dispositivo y los cambios de Feli de 869.

## 0.8.4.29 · build 869 (candidata)

- Feli se saluda suavemente al entrar a una categoría de Salud o cambiar entre «Última lectura» e «Histórico». No rebota: mueve patita, cabeza y cola y sigue sus gestos habituales; conserva las orejas largas corregidas en 868.
- «Última lectura»: Feli muestra valor, fecha y hora de la última muestra recibida de esa métrica. Una lectura antigua se describe por su fecha, nunca como tiempo real.
- «Histórico»: muestra promedio del día/semana/mes seleccionado, con el mismo algoritmo por día registrado de los gráficos inteligentes (cada día tiene el mismo peso, los días sin registros no valen cero). Feli cambia su reacción al promedio y al mover el período o la fecha.
- Sueño incompleto no se promedia ni desencadena animaciones por duración hasta recibir sesiones válidas; el fallo comunicado de sueño multisesión todavía requiere diagnóstico real.
- Usuario confirmó que el oxígeno ya sincroniza correctamente en su iPhone: preservar la recuperación BLE validada. Falta probar los cambios de Feli de esta candidata.

## 0.8.4.28 · build 868 (candidata)

- Orejas de Feli corregidas: ahora se dibujan delante de la cabeza y a los lados, con forma caída larga de beagle, detalle interno y articulación independiente; no deberían quedar ocultas tras el hocico.
- Gestos y disparadores conservados: estrés reciente alto/bajo, sueño o actividad semanales cuando hay datos, estados por métrica; respiración, olfateo, estiramiento, patita, bostezo y caricias. «Mate», «asado» y «celebrar» no tienen activadores automáticos basados en lecturas.
- Pendiente de inspección visual en iPhone; la compilación CI solo valida código, no el aspecto. El oxígeno y sueño multisesión permanecen pendientes de diagnóstico físico.

## 0.8.4.27 · build 867 (candidata, prueba pendiente)

- Feli en Salud: animación viva sin rebote — respiración, parpadeos, orejas, cola, mirada, olfateo, estiramiento, pata levantada y bostezos en un ciclo de gestos suaves; acariciarlo con un toque acelera la cola y mueve la cabeza. Respeta «Reducir movimiento» y pausa la animación en segundo plano.
- Un acompañante compacto queda visible durante el scroll de Salud y dentro de cada categoría mediante Safe Area, sin superponerse a gráficos; botón para minimizar/expandir y conocer por qué Feli está así. No aparece en Inicio ni Ayuno.
- Oxígeno: consulta de hasta 7 días de muestras disponibles (antes 24 horas), accesos al diagnóstico desde su pantalla y mensajes específicos del protocolo 31/0B/0C. **No inicia una lectura física del sensor** y no asigna datos de canales no validados a SpO₂.
- Sueño: informe de diagnóstico con campos del índice/sesión y razones de consulta parcial; **el problema comunicado de 4 h 08 en reloj contra 2 h 59 en iWatch sigue sin resolverse en dispositivo** y necesita la captura de «Copiar diagnóstico de sueño».
- Integra los gráficos inteligentes de 866 de la rama base. **A la espera de CI e instalación física.**

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
