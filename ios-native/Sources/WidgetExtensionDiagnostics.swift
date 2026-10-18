import Foundation
import ActivityKit

// Inspección LOCAL, de solo lectura, del bundle efectivamente instalado.
// Comprobar que existe un .appex NO demuestra que iOS lo haya firmado,
// registrado o ejecutado: WidgetKit no ofrece una API pública para consultar
// si una extensión está registrada en la galería.
enum WidgetExtensionDiagnostics {
    static func report() -> String {
        let bundle = Bundle.main
        let appID = bundle.bundleIdentifier ?? "(sin identificador)"
        let pluginsURL = bundle.builtInPlugInsURL ??
            bundle.bundleURL.appendingPathComponent("PlugIns", isDirectory: true)
        let dirExists = FileManager.default.fileExists(atPath: pluginsURL.path)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: pluginsURL, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        let appExtensions = children
            .filter { $0.pathExtension.lowercased() == "appex" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let widgetURL = appExtensions.first {
            $0.lastPathComponent == "MotoBatteryWidgets.appex"
        }
        let widgetBundle = widgetURL.flatMap { Bundle(url: $0) }
        let widgetID = widgetBundle?.bundleIdentifier ?? "(sin identificador)"
        let widgetInfo = widgetBundle?.infoDictionary ?? [:]
        let executableName = widgetInfo["CFBundleExecutable"] as? String ?? "MotoBatteryWidgets"
        let executableURL = widgetURL?.appendingPathComponent(executableName)
        let executablePresent = executableURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let signatureManifest = widgetURL?.appendingPathComponent("_CodeSignature/CodeResources")
        let signatureManifestPresent = signatureManifest.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let extInfo = widgetInfo["NSExtension"] as? [String: Any] ?? [:]
        let extensionPoint = extInfo["NSExtensionPointIdentifier"] as? String ??
            "(ausente)"
        let extensionName = widgetInfo["CFBundleDisplayName"] as? String ??
            "(sin nombre)"
        let liveActivitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
        let currentActivities = Activity<MotoBatteryActivityAttributes>.activities
        let activeLiveActivities = currentActivities.count
        let activityDetails = currentActivities.map {
            "ID=\(String($0.id.prefix(8))) estado=\(String(describing: $0.activityState))"
        }.joined(separator: ", ")
        let idRelationOK = widgetURL != nil && widgetID.hasPrefix(appID + ".")
        let extensionNames = appExtensions.map { $0.lastPathComponent }.joined(separator: ", ")

        let conclusion: String
        if !dirExists || widgetURL == nil {
            conclusion = "FALTA EXTENSIÓN: el .appex no está dentro de la app instalada; revisar cómo Sideloadly firma/empaqueta el IPA."
        } else if !executablePresent {
            conclusion = "EJECUTABLE AUSENTE: la extensión se empaquetó sin su binario."
        } else if extensionPoint != "com.apple.widgetkit-extension" {
            conclusion = "MANIFIESTO INCORRECTO: falta el punto de extensión de WidgetKit."
        } else if !idRelationOK {
            conclusion = "IDENTIFICADORES DISTINTOS: el identificador del widget no empieza por el de la app instalada; revisar remapeo de Bundle IDs al firmar."
        } else {
            conclusion = "EXTENSIÓN PRESENTE EN EL BUNDLE: los identificadores y el manifiesto parecen coherentes. ESTO NO CONFIRMA que iOS la haya registrado o firmado correctamente; revisar instalación/firma de Sideloadly."
        }

        return [
            "iWatch · diagnóstico local de widget",
            "Fecha: \(ISO8601DateFormatter().string(from: Date()))",
            "App: \(appID)",
            "Versión: \(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (build \(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"))",
            "Directorio PlugIns: \(dirExists ? "presente" : "ausente")",
            "Cantidad de extensiones .appex: \(appExtensions.count)",
            "Extensiones: \(extensionNames.isEmpty ? "(ninguna)" : extensionNames)",
            "MotoBatteryWidgets.appex: \(widgetURL == nil ? "NO" : "SÍ")",
            "ID de extensión: \(widgetID)",
            "Nombre de extensión: \(extensionName)",
            "Ejecutable de extensión: \(executablePresent ? "presente" : "AUSENTE")",
            "Manifiesto _CodeSignature: \(signatureManifestPresent ? "presente" : "ausente / no inspeccionable")",
            "Soporte Live Activities en app: \((bundle.infoDictionary?["NSSupportsLiveActivities"] as? Bool) == true ? "SÍ" : "NO")",
            "Punto de extensión: \(extensionPoint)",
            "Relación de IDs app/widget: \(idRelationOK ? "coherente" : "no comprobada / distinta")",
            "Actividad en vivo permitida: \(liveActivitiesAllowed ? "sí" : "no")",
            "Actividades de batería activas en ActivityKit: \(activeLiveActivities)",
            "IDs/estados ActivityKit: \(activityDetails.isEmpty ? "sin actividades" : activityDetails)",
            "",
            "Diagnóstico: \(conclusion)",
            "Nota: la presencia de un manifiesto NO valida la firma criptográfica ni asegura que WidgetKit ejecutó el widget.",
            "Si la isla es negra sin contenido, buscar en Ajustes > Privacidad y seguridad > Análisis y mejoras > Datos de análisis un reporte MotoBatteryWidgets. 'CODESIGNING / Invalid Page' apunta a re-firma defectuosa tras Sideloadly."
        ].joined(separator: "\n")
    }
}
