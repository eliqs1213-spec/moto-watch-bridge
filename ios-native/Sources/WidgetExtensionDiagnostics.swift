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
        let extInfo = widgetInfo["NSExtension"] as? [String: Any] ?? [:]
        let extensionPoint = extInfo["NSExtensionPointIdentifier"] as? String ??
            "(ausente)"
        let extensionName = widgetInfo["CFBundleDisplayName"] as? String ??
            "(sin nombre)"
        let liveActivitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
        let activeLiveActivities = Activity<MotoBatteryActivityAttributes>.activities.count
        let idRelationOK = widgetURL != nil && widgetID.hasPrefix(appID + ".")
        let extensionNames = appExtensions.map { $0.lastPathComponent }.joined(separator: ", ")

        let conclusion: String
        if !dirExists || widgetURL == nil {
            conclusion = "FALTA EXTENSIÓN: el .appex no está dentro de la app instalada; revisar cómo Sideloadly firma/empaqueta el IPA."
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
            "Punto de extensión: \(extensionPoint)",
            "Relación de IDs app/widget: \(idRelationOK ? "coherente" : "no comprobada / distinta")",
            "Actividad en vivo permitida: \(liveActivitiesAllowed ? "sí" : "no")",
            "Actividades de batería activas en ActivityKit: \(activeLiveActivities)",
            "",
            "Diagnóstico: \(conclusion)",
            "Nota: no se consulta el registro interno de WidgetKit, la firma de los binarios ni la galería de widgets."
        ].joined(separator: "\n")
    }
}
