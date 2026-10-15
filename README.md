# iWatch · Moto Watch Bridge

App nativa de iPhone para conectar un **Moto Watch Fit**: controles de Spotify, avisos mediante Atajos, batería, búsqueda del teléfono e histórico de salud del reloj.

**Última versión de la app: 0.8.4.5 (build 845).** Cierre de trabajo: 15 de octubre de 2026, Argentina. El código de este cierre incluye todas las mejoras; `main` todavía no contiene los PR de desarrollo apilados. Ver [estado de ramas y validación](docs/ESTADO_ACTUAL.md).

## Empezar

- [Última compilación verificada](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/38676992260): descargar el artefacto **MotoWatchNativeProbe-unsigned**, descomprimirlo y firmar/instalar el IPA.
- [Compilar e instalar](docs/COMPILAR_E_INSTALAR.md).
- [Estado actual y funciones](docs/ESTADO_ACTUAL.md).
- [Arquitectura y protocolo](docs/ARQUITECTURA.md).
- [Pendientes para la próxima sesión](docs/PENDIENTES.md).
- [Cambios de versión](CHANGELOG.md).

Los artefactos de Actions caducan a los 14 días según el workflow. Si el enlace ya no permite descargar, generar otra compilación desde la rama que contiene los cambios. Un IPA descargado de Actions está sin firmar.

## Qué incluye

| Área | Comportamiento actual |
| --- | --- |
| Salud | Pasos, ritmo cardíaco, oxígeno, estrés, calorías activas y sueño; solo Moto Watch, sin Apple Salud. |
| Histórico | Portada de hoy, último valor con fecha de medición y actualización; detalle por día, semana o mes. Guardado local en el iPhone. |
| Actualización | Botón manual y consultas automáticas mientras Salud esté visible y la app activa. |
| Spotify | SDK prioritario, Web API de respaldo y funcionamiento restaurado al anterior a la optimización de ahorro. |
| Notificaciones | Prioridad de envío; dependen de la automatización de Atajos. La app no lee directamente todas las notificaciones del iPhone. |
| iWatch | Tarjetas para conexión, batería, música y búsqueda; configuración completa en «Ajustes y diagnóstico». |

No se garantiza la ejecución permanente de Atajos ni la entrega con Bluetooth apagado o fuera de alcance. La compilación y las pruebas sintéticas no reemplazan la validación con el iPhone bloqueado y el reloj real. El ahorro de batería aún no fue medido.

## Estructura

```text
ios-native/                  App nativa: única fuente de código iOS
  Sources/                   Swift de la app
  Shared/                    Atributos de la actividad en vivo
  BatteryWidgets/            Extensión WidgetKit
  Resources/                 Sonido de búsqueda
  Tests/                     Comprobaciones con datos sintéticos
  project.yml                Proyecto XcodeGen y versión de app/extensión
.github/workflows/           Compilación y publicación del IPA
docs/                        Documentación vigente
docs/archive/                Notas de etapas anteriores, fuera de vigencia
index.html                   Puente web de Bluefy, conservado por separado
```

No copiar Swift ni `project.yml` a la raíz. Las copias antiguas de esa ubicación no participaban en la compilación y se retiraron para evitar editar o subir una versión equivocada. [Detalle de la limpieza](docs/LIMPIEZA_REPOSITORIO.md).

No subir contraseñas, tokens, sesiones Spotify, bugreports ni capturas de tráfico con datos personales. Las sesiones de Spotify se gestionan localmente; los diagnósticos de avisos no deben incluir remitente ni mensaje.
