# Compilar e instalar

## Elegir la rama correcta

`main` aún no incluye los PR recientes. La última app compilada y compartida es **0.8.4.5 (845)** en `codex/iwatch-design`; la documentación y limpieza de este cierre están en `codex/repo-docs-cleanup`, que incluye ese código.

Desde una copia nueva:

```powershell
git clone https://github.com/eliqs1213-spec/moto-watch-bridge.git
cd moto-watch-bridge
git switch codex/repo-docs-cleanup
```

En una copia existente, revisar antes los cambios locales. No usar comandos de reset o limpieza que descarten trabajo para cambiar de rama.

## GitHub Actions desde Windows

1. Abrir [Actions](https://github.com/eliqs1213-spec/moto-watch-bridge/actions).
2. Elegir **Compilar Moto Watch Bridge iOS**.
3. En **Run workflow**, seleccionar la rama que contiene la versión deseada; no asumir `main`.
4. Esperar la ejecución completa con resultado verde. Un push que solo modifica Markdown puede no iniciar este workflow por sus filtros de rutas.
5. Descargar **MotoWatchNativeProbe-unsigned**. El ZIP del artefacto contiene `MotoWatchNativeProbe-unsigned.ipa`.
6. Firmar e instalar ese IPA con la herramienta local que ya se usa en Windows. Nunca subir credenciales de Apple a GitHub.

[Última ejecución verificada de la interfaz 0.8.4.5](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/38676992260). Los artefactos se retienen 14 días. Si caducan, volver a compilar.

La app instalada debe mostrar la versión esperada al pie de iWatch. Subir fuentes o descargar un ZIP no actualiza por sí solo la instalación del teléfono. Conservar el identificador de la app y el contexto de firma al actualizar; desinstalar puede eliminar el histórico local de salud.

## Compilación en macOS

El workflow utiliza macOS, Xcode y XcodeGen. La configuración vigente es `ios-native/project.yml`; no hay un proyecto de la app en la raíz.

```sh
brew install xcodegen
cd ios-native
xcodegen generate
cd ..
xcodebuild \
  -project ios-native/MotoWatchNativeProbe.xcodeproj \
  -scheme MotoWatchNativeProbe \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  -derivedDataPath /tmp/MotoWatchBuild \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

El destino mínimo declarado es iOS 16.2. Eso no implica que todas las automatizaciones de notificaciones estén disponibles en todas las versiones de iOS. El paquete Spotify se resuelve desde la rama `master` de su repositorio según la configuración existente; la dependencia no está fijada a una revisión en este cierre.

## Comprobaciones sintéticas

Actions concatena las fuentes de protocolo/almacenamiento/política con las comprobaciones y ejecuta Swift en macOS:

```sh
cat ios-native/Sources/WatchHealthProtocol.swift \
  ios-native/Sources/WatchHealthStore.swift \
  ios-native/Sources/HealthHistoryPeriod.swift \
  ios-native/Sources/WatchTrafficPolicy.swift \
  ios-native/Tests/ProtocolChecks.swift \
  ios-native/Tests/HealthStoreChecks.swift \
  ios-native/Tests/PowerChecks.swift > /tmp/motowatch-health-checks.swift
swift /tmp/motowatch-health-checks.swift
```

Cubren tramas/CRC, fragmentación, índices/selectores, decodificación de categorías, persistencia/migración, deduplicación, separación por reloj, calendario y prioridad de tráfico. No prueban ejecución real de Atajos, radio Bluetooth, reproducción de Spotify ni apariencia en iPhone.

## Primer uso y diagnóstico

- Desconectar otros puentes que estén usando el reloj: web/Bluefy, Windows o teléfono Android.
- Conceder Bluetooth, conectar el reloj y esperar que la sesión esté lista.
- Configurar Spotify desde **iWatch → Ajustes y diagnóstico** con el Client ID y la Redirect URI que muestra la app. No usar ni compartir un Client Secret en la app.
- Configurar los avisos desde **Notificaciones** y comprobar qué campos entrega realmente la automatización de Atajos.
- En **Salud**, consultar y verificar las lecturas contra el reloj; el botón no inicia mediciones.
- Si falla algo, copiar el registro y anotar versión, hora, estado del teléfono y acción realizada. Revisar el texto antes de compartirlo.
