# iWatch Spotify — experimento Atajos 0.8.4.40 (880)

Se agregó el App Intent **Resincronizar Spotify con Moto Watch**, independiente de la Dynamic Island.

Cómo probar:
1. Instalar el IPA con AltStore seleccionando Keep App Extensions.
2. Abrir iWatch una vez, autorizar Spotify y conectar Moto Watch Fit.
3. Abrir Atajos → nuevo atajo → buscar iWatch → Resincronizar Spotify con Moto Watch.
4. Ejecutar primero con iWatch abierta y Spotify reproduciendo. Leer resultado y registros ATAJOS-SPOTIFY.
5. Repetir dejando iWatch en segundo plano, luego con el iPhone bloqueado. En ese caso la ejecución puede no empezar o completarse por restricciones de iOS.
6. Comparar canción en el reloj, no sólo resultado del atajo. Probar otra canción después de unos segundos.

Límites: no concede ejecución continua, no detecta cambios naturales por sí misma, no crea automatizaciones, no despierta indefinidamente el proceso y no garantiza que iOS permita la ejecución con pantalla bloqueada. Una confirmación significa metadatos Spotify nuevos aceptados; la pantalla real del reloj requiere verificación humana. Se respeta Spotify Retry-After y el throttle.

Aislamiento: rama experimental respecto de iWatch 0.8.4.39, sin modificar SpotifyAppRemoteBridge.swift, firmware ni controles Dynamic Island.
