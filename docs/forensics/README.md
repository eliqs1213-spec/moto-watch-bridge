# Archivo forense público — Moto Watch Fit / iWatch

**Corte documental:** 2026-11-20 · **Repositorio:** `eliqs1213-spec/moto-watch-bridge`

Este índice documenta investigación de interoperabilidad iOS–Moto Watch Fit, análisis de protocolos, firmware/OTA, APK, compilaciones y pruebas. **No equivale a un volcado íntegro de todos los chats, trazas privadas o binarios.** La evidencia disponible se separa de hipótesis, inferencias y pruebas pendientes.

## Empezar aquí
1. [Informe forense técnico](INFORME_FORENSE.md): metodología, evidencia, hallazgos positivos y negativos, cronología y pendientes.
2. [Inventario y procedencia](INVENTARIO_EVIDENCIA.md): fuentes, SHA-256, estado de publicación, retención y preservación.
3. [Guía de reproducción y seguridad](REPRODUCIBILIDAD.md): pruebas no destructivas y protección de datos.
4. [Fuentes del proyecto](../../README.md) y [documentación histórica](../archive/README.md).

## Estado de la aplicación
- **897**: clima, notificaciones, widget y Dynamic Island validados; viento pendiente.
- **900**: regresión reportada de Spotify bloqueado, acciones acumuladas.
- **902/904**: cierres al iniciar AccessorySetupKit, `EXC_BREAKPOINT`.
- **920**: migración de AccessorySetupKit y conexión BLE confirmadas.
- **922 / 0.8.4.75**: [CI exitosa](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/42943917880); reconexión automática confirmada en dispositivo. **Pendiente:** error ActivityKit `Target is not foreground` al iniciar Live Activity.

## Criterio de publicación
Los documentos y resultados técnicos no sensibles pueden publicarse. Las capturas HCI, logs, APK/firmware y paquetes de archivo necesitan revisión de privacidad, derechos de redistribución y hashes antes de publicarse. Un enlace a un archivo externo **no prueba** que esté archivado permanentemente.

## Límites
Los archivos originales grandes y el respaldo consolidado de 254 MB no se han cargado en esta rama: las herramientas de escritura disponibles para este repositorio admiten archivos de texto, no carga de binarios grandes ni creación de Releases. El inventario marca explícitamente esta limitación. No presentar este índice como «respaldo completo» hasta que se verifique la carga y recuperación de cada objeto.
