# Diagnóstico público: Moto Watch Fit, iOS y WidgetKit

Actualizado: 16/10/2026. Esta guía sirve a otras personas que quieran usar un Moto Watch Fit desde iPhone sin asumir que es un producto oficial de Motorola.

## Requisitos y arquitectura

- Fuente de la app nativa: \`ios-native/Sources/\`. Configuración de compilación y números de versión: \`ios-native/project.yml\`. Extensión en \`ios-native/BatteryWidgets/\`.
- El puente del reloj utiliza características BLE Motorola (lectura de avisos y botones F8F0, escritura F8F1). No se conoce un Wi-Fi propio utilizable desde esta aplicación. El clima viejo aparece cuando se usó antes la app oficial del Motorola Edge; **su formato BLE aún no se identificó**.
- Spotify Premium: App Remote SDK **en primer plano** como prioridad y Web API como respaldo. Si Spotify está suspendido o no hay reproductor activo, algunas órdenes PLAY pueden recibir 404. No repetir NEXT/PREV si el SDK ya intentó enviarlo, para evitar saltar dos pistas.
- Las notificaciones de otras apps se envían con automatizaciones de Atajos: iOS no permite que cualquier app lea el centro de notificaciones completo. El icono Instagram se observó en dispositivo, pero no se ha identificado el mecanismo exacto.
- Salud consulta el historial disponible del reloj. No inicia sensores manuales por Bluetooth; el usuario debe medir en la interfaz nativa del dispositivo antes de recuperar las muestras.
- El histórico de Salud y Ayuno se guarda localmente, **no hay servidor ni sincronización HealthKit**.

## Error confirmado de extensión de WidgetKit

**Síntomas de dispositivo:** la app principal abre; la extensión \`MotoBatteryWidgets.appex\` está dentro del IPA/paquete instalado y tiene bundle ID coherente, pero el widget no aparece al buscar «iWatch» bajo el reloj de la pantalla bloqueada. Se solicita una Actividad en vivo y ActivityKit puede reportar 1 activa, pero Dynamic Island permanece vacía.

**Prueba real:** incidente de iOS **16/10/2026 a las 02:38:26, -03**, iPhone15,4, iOS 27.2 beta (24B5099f), extensión \`MotoBatteryWidgets\` v0.8.4.22 build 862. Resumen saneado del informe:

\`\`\`text
process: MotoWatchNativeProbe.app/PlugIns/MotoBatteryWidgets.appex/MotoBatteryWidgets
bundle: org.motowatchbridge.nativeprobe.<TEAM_ID>.widgets
termination.namespace: CODESIGNING
termination.indicator: Invalid Page
exception: EXC_BAD_ACCESS / SIGKILL
ktriageinfo: Failed to fault in a page with execute permissions
\`\`\`

Este informe acredita **rechazo de validación de una página ejecutable del binario de la extensión de la build 862**. No demuestra un error de SwiftUI ni que iOS no haya copiado \`.appex\`, ni confirma que todas las builds posteriores fallen por la misma causa. La combinación exacta de reempaquetado, firma final de Sideloadly y la beta de iOS queda por aislar.

**Evidencia posterior:** en build 864 (v0.8.4.24) el diagnóstico de app detecta 1 extensión \`.appex\` con manifiesto \`com.apple.widgetkit-extension\`, identificadores coherentes y una actividad ActivityKit registrada. **Ni el widget fijo ni Dynamic Island se ven**. Esta comprobación no inspecciona firma de páginas ejecutables ni registro de WidgetKit.

### Método de investigación reproducible

1. Conservar IPA original unsigned de la compilación verde del workflow; no confundir código fuente con IPA instalado. Guardar versión/build y hora de prueba.
2. Firmar e instalar con una herramienta cada vez, conservando el mismo dispositivo/cuenta y anotando la versión exacta del firmador. Sideloadly 0.70.1 fue usado en las pruebas fallidas. Una versión anterior puede servir como comparativa, **pero no se ha demostrado una solución**. Evitar instaladores de origen desconocido.
3. Buscar en Ajustes → Privacidad y seguridad → Análisis y mejoras → Datos de análisis: \`MotoBatteryWidgets-*.ips\` después de instalar cada build. Filtrar por \`app_version\`, \`build_version\`, \`procName\` y \`termination\` antes de compararlos.
4. Verificar galería **en pantalla bloqueada**, debajo del reloj, no solo en inicio. Verificar ActivityKit por separado (las Actividades en vivo no son widgets fijos).
5. Si se dispone de macOS/Xcode, probar firma y provisioning nativos del host y **de la extensión**, e inspeccionar \`codesign -dv --verbose=4\` y \`codesign --verify --deep --strict\` en el IPA firmado **antes de instalar**. Estos comandos no sustituyen la ejecución en iOS.
6. No subir informes completos: pueden contener identificadores del dispositivo, correo de Apple, contenidos musicales o tokens. Al publicar una reproducción, redactar esos valores.

Se experimentó con re-firma ad-hoc de \`.appex\` y frameworks y con Info.plist sin comprimir en el IPA en la build 863; **no corrigió la ausencia visual en el iPhone**. El script \`ios-native/scripts/prepare-sideload-ipa.sh\` pertenece a ese experimento. No presentarlo como reparación estable.

## Otras limitaciones conocidas

- **Tema del reloj:** la app muestra una carátula ilustrativa con hora del iPhone; no se ha descifrado la carátula instalada ni cómo transferir imágenes.
- **Clima:** el reloj conserva pronósticos sincronizados desde Android; falta mapear los paquetes BLE y la actualización desde iOS.
- **Segundo plano:** los eventos BLE reales pueden reactivar la app cuando iOS lo permite. Si no hay eventos, no existe un temporizador arbitrario garantizado para actualizar canciones continuamente.
- **SDK Spotify:** si App Remote figura sin conexión, Web API puede conservar algunos controles cuando hay reproductor activo; no garantiza reanudar desde una suspensión prolongada.
- **Feli:** chibi local de SwiftUI únicamente en Salud, con reacciones ilustrativas según valores recientes. Nunca reemplaza una evaluación médica.
- **Ayuno:** datos voluntarios y notificaciones locales optativas. El sueño sugiere un **horario**, no una duración apropiada para la salud; los recordatorios dependen de permisos iOS.

## Contribuir

Antes de publicar cambios: abrir PR contra la rama del último desarrollo, ejecutar tests/protocolo + compilación iOS en Actions, registrar evidencia en reloj físico y documentar la diferencia entre comportamiento verificado y pendiente. No modificar BLE/Spotify para arreglar fallas de firma de WidgetKit; son subsistemas independientes.
