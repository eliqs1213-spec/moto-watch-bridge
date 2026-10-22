# Widget y Actividad en vivo automáticos — iWatch 0.8.4.53 (build 897)

Esta rama parte de la línea base de clima estable 0.8.4.52 (build 892) y no incorpora el editor ni los experimentos de esferas.

## Cambios

- La Actividad en vivo se inicia automáticamente cuando el Moto Watch Fit termina de conectar mientras iWatch está activa.
- Al volver iWatch a primer plano, se actualiza o intenta iniciar la Actividad en vivo si el reloj ya está conectado.
- Cada lectura real de batería actualiza la Actividad en vivo; si no existía una, se intenta crear sin un botón manual.
- La app solicita a WidgetKit renovar el timeline al iniciar la Actividad en vivo y al recibir una lectura de batería.
- El widget de estado solicita además una renovación periódica cada hora. iOS conserva el control sobre el momento efectivo de renderizado.
- Se quitaron de Ajustes los botones de iniciar/reiniciar/detener Actividad en vivo y los controles manuales de diagnóstico de la extensión.

## Límites de iOS y del widget actual

- Una app no puede añadir automáticamente un widget a la pantalla de bloqueo o de inicio. El usuario debe colocarlo una vez desde la galería de widgets de iOS.
- El widget actual muestra la hora de actualización del timeline; todavía no muestra el porcentaje real de batería.
- Compartir el porcentaje con el widget fijo requiere un canal de datos entre la app y la extensión. Esta rama conserva el diseño sin App Groups para no introducir una dependencia de entitlements que pueda romper la instalación mediante Sideloadly.
- La Actividad en vivo puede ser deshabilitada por el usuario y está sujeta a las reglas de iOS. No se promete que permanezca activa indefinidamente ni que se actualice puntualmente en segundo plano.
- La compilación no demuestra que iOS haya registrado/renderizado la extensión en el dispositivo; debe validarse tras instalar la IPA firmada.

## Validación prevista

1. Instalar la IPA de esta rama mediante Sideloadly.
2. Confirmar que Actividades en vivo estén permitidas en Ajustes de iOS.
3. Conectar el reloj con iWatch en primer plano y comprobar que aparece una sola Actividad en vivo.
4. Verificar que el porcentaje cambia cuando el reloj devuelve una lectura real de batería.
5. Añadir el widget «iWatch · Estado» una sola vez desde la galería y verificar su hora de actualización.

La versión estable 0.8.4.52 (build 892) permanece intacta.
