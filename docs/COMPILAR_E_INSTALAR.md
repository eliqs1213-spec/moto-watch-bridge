# Compilar e instalar

## Elegir la rama correcta

`main` aún no incluye las funciones recientes. Para Inicio + Feli en Salud + Ayuno, usar **`feature/home-dashboard-stable-0865`**, build **865**, PR #25. Comprobar que el workflow termine en verde; un código publicado no significa un IPA instalado.

Desde una copia nueva:

```powershell
git clone https://github.com/eliqs1213-spec/moto-watch-bridge.git
cd moto-watch-bridge
git switch feature/home-dashboard-stable-0865
```

En una copia existente, revisar antes los cambios locales. No usar comandos de reset o limpieza que descarten trabajo para cambiar de rama.

## GitHub Actions desde Windows

1. Abrir [Actions](https://github.com/eliqs1213-spec/moto-watch-bridge/actions).
2. Elegir **Compilar Moto Watch Bridge iOS**.
3. En **Run workflow**, seleccionar la rama que contiene la versión deseada; no asumir `main`.
4. Esperar la ejecución completa con resultado verde. Un push que solo modifica Markdown puede no iniciar este workflow por sus filtros de rutas.
5. Descargar **MotoWatchNativeProbe-unsigned**. El ZIP del artefacto contiene `MotoWatchNativeProbe-unsigned.ipa`.
6. Firmar e instalar ese IPA con la herramienta local que ya se usa en Windows. Nunca subir credenciales de Apple a GitHub.

[Compilaciones de la rama 865](https://github.com/eliqs1213-spec/moto-watch-bridge/actions). Los artefactos se retienen 14 días. Si caducan, volver a compilar.

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
- En **Inicio**, ver batería y conexiones reales; la esfera es ilustrativa y la hora la da el iPhone.
- En **Salud**, verificar lecturas contra reloj; la consulta no inicia sensores manuales. Feli es un chibi informativo solamente en Salud.
- En **Ayuno**, fijar objetivo/horario, activar avisos locales solo si se desean y probar registro de inicio/corte real tras cerrar la app.
- Si falta WidgetKit o la Dynamic Island queda negra, consultar [problemas conocidos](PROBLEMAS_CONOCIDOS.md) antes de reinstalar.
- Si falla algo, copiar el registro y anotar versión, hora, estado del teléfono y acción realizada. Revisar el texto antes de compartirlo.
