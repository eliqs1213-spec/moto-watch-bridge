# iWatch · Moto Watch Bridge

App nativa de iPhone para conectar un **Moto Watch Fit**: controles de Spotify, avisos mediante Atajos, batería, búsqueda del teléfono e histórico de salud del reloj.

**Versión candidata reciente: 0.8.4.25 (build 865)** en `feature/home-dashboard-stable-0865` ([PR #25](https://github.com/eliqs1213-spec/moto-watch-bridge/pull/25)). Todavía no está integrada a `main` ni verificada en un iPhone.

## Empezar

- [Compilaciones de GitHub Actions](https://github.com/eliqs1213-spec/moto-watch-bridge/actions): elegir la ejecución verde de la rama 865, descargar **MotoWatchNativeProbe-unsigned**, descomprimirlo, firmar e instalar el IPA.
- [Compilar e instalar](docs/COMPILAR_E_INSTALAR.md).
- [Estado actual y funciones](docs/ESTADO_ACTUAL.md).
- [Arquitectura y protocolo](docs/ARQUITECTURA.md).
- [Pendientes para la próxima sesión](docs/PENDIENTES.md).
- [Cambios de versión](CHANGELOG.md).
- [Problemas conocidos: WidgetKit, Sideloadly y Spotify](docs/PROBLEMAS_CONOCIDOS.md).

Los artefactos de Actions caducan a los 14 días según el workflow. Si el enlace ya no permite descargar, generar otra compilación desde la rama que contiene los cambios. Un IPA descargado de Actions está sin firmar.

## Qué incluye

| Área | Comportamiento actual |
| --- | --- |
| Inicio | Reloj ilustrativo con hora actual, batería Motorola real, estados BLE/Spotify, acceso al SDK y guía de mediciones. El tema instalado no se lee todavía. |
| Salud | Pasos, pulso, oxígeno A, estrés, calorías activas y sueño del reloj. Feli chibi animado aparece solo aquí. |
| Estadísticas | Observaciones por métrica con cobertura de datos y recomendaciones prudentes, sin diagnósticos. |
| Ayuno | Temporizador editable, sugerencias de horario en función de 3+ noches, recordatorios locales opt-in e inicio/corte real guardados. |
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
