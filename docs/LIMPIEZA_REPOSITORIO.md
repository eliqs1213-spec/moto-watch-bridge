# Limpieza del cierre · 15/10/2026

Se revisó el árbol del commit `8246e4aa45674e4ffcbb235dc8a687d58105f86c`, las fuentes, el workflow y las referencias del proyecto. La app compila desde `ios-native/`; las copias de raíz no se utilizaban.

| Acción | Motivo y conservación |
| --- | --- |
| Retirar 13 archivos Swift de raíz | Eran copias idénticas o versiones antiguas. Las fuentes vigentes siguen en `ios-native/Sources/` y `ios-native/BatteryWidgets/`. Las copias retiradas siguen recuperables en el historial Git. |
| Retirar `FindPhoneAlert.wav` de raíz | Mismo blob que `ios-native/Resources/FindPhoneAlert.wav`, que se conserva. |
| Retirar `project.yml` de raíz | Configuración antigua 0.8.2.5 y rutas que no correspondían a la raíz. Se conserva `ios-native/project.yml`, 0.8.4.5. |
| Retirar `download` | Era el contenido de un `.gitignore`, subido con nombre incorrecto. Las reglas pasan a `ios-native/.gitignore`; se añade `.gitignore` general. |
| Archivar `IMPORTAR_DESDE_WINDOWS.ps1` | Copiaba solo una parte de la app inicial e incluía una ruta inexistente. Queda como texto histórico, sin presentarlo como herramienta vigente. |
| Retirar `ios-native/Shared/BatteryWidgetStore.swift` | Helper antiguo de App Groups sin referencias en código y no incluido por XcodeGen. La actividad en vivo y widget actual no lo usan. |
| Mover los 13 `LEEME_*` al archivo histórico | Conservan decisiones previas, pero sus versiones y afirmaciones no describen la app actual. |
| Conservar README inicial como archivo | Permite consultar la primera etapa sin confundirla con la guía vigente. |

No se eliminan ramas, PR, artefactos, datos del iPhone ni archivos locales del usuario. `index.html` conserva su ruta y contenido. Los protocolos, fuentes activas y recursos usados permanecen iguales; la única fuente Swift retirada dentro de `ios-native/` no formaba parte del target.

Después de la limpieza se revisan enlaces Markdown locales, rutas de XcodeGen, archivo del workflow y comparación de blobs activos; se ejecuta también la compilación completa para comprobar que no se retiraron dependencias necesarias.
