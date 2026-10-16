# iWatch 0.8.4.19 / build 859 — reconexión Spotify App Remote

## Reporte
La Web API está operativa (NEXT/PREV y metadatos desde Moto Watch); el panel SDK iOS queda en «SDK reconectando con Spotify…» y no llega a «conectado».

## Causa posible abordada
Tanto UIApplicationDelegate.applicationDidBecomeActive como ContentView.onChange(scenePhase) llamaban SpotifyAppRemoteBridge.applicationDidBecomeActive(). Eso podía emitir SPTAppRemote.connect() repetidamente sin limitar intentos. Además, la UI podía quedar en «reconectando» si el SDK no emitía callback.

## Cambios
- SpotifySDKReconnectPolicy: conexión solo con app activa y SDK habilitado, mínimo 8 s entre intentos automáticos.
- SpotifyAppRemoteBridge: registro SPOTIFY-SDK, timeout de 12 s sin callback, ninguna reconexión continua en bucle.
- Renovar sesión App Remote vencida al volver al primer plano, evitando renovaciones duplicadas.
- Botón Reintentar SDK sin desconectar Web API ni cambiar Bluetooth.
- Pruebas sintéticas en CI; build 858 permanece como referencia y fixes 404 conservados.

## Prueba
1. Spotify Premium abierto reproduciendo; iWatch 859 en primer plano.
2. Esperar 12–15 s y leer Spotify SDK, SDK conectado, Eventos SDK y Último dato nativo.
3. Si SDK sin respuesta, abrir Spotify, volver a iWatch y pulsar Reintentar SDK una vez.
4. Enviar líneas SPOTIFY-SDK y estados, nunca credenciales.
5. La conexión SDK en primer plano no garantiza metadatos naturales al bloquear iOS.

No afirmar que la nueva política garantiza conexión. Spotify Dashboard / OAuth y restricciones de iOS pueden seguir impidiendo App Remote.