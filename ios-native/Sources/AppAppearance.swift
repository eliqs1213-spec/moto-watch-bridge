import SwiftUI

/// Preferencia visual de iWatch. No participa de BLE, Spotify ni Salud.
enum AppAppearance: String, CaseIterable, Identifiable {
    case automatic = "automatic"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automático"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var explanation: String {
        switch self {
        case .automatic: return "Sigue la apariencia configurada en el iPhone."
        case .light: return "Usa la apariencia clara en toda la aplicación."
        case .dark: return "Usa la apariencia oscura en toda la aplicación."
        }
    }
}
