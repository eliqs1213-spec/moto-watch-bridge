import Foundation

/// Las escenas de Ayuno expresan avance del cronómetro; no detectan hambre,
/// no evalúan salud y nunca terminan un ayuno automáticamente.
enum FeliFastingStage: String {
    case ready
    case mate
    case resting
    case imaginingFood
    case asado
    case countdown
    case goalReached
    case completed

    var headline: String {
        switch self {
        case .ready: return "Feli está listo para acompañarte"
        case .mate: return "¡Arrancamos! Feli toma un mate feliz"
        case .resting: return "Feli descansa a tu lado"
        case .imaginingFood: return "Feli está pensando en la merienda"
        case .asado: return "Feli sueña con un vacío a la parrilla"
        case .countdown: return "¡Falta poco! Feli mira el reloj"
        case .goalReached: return "¡Alcanzaste tu objetivo de tiempo!"
        case .completed: return "¡Feli festeja con vos!"
        }
    }

    var detail: String {
        switch self {
        case .ready: return "Iniciá el temporizador cuando quieras."
        case .mate: return "Te saluda con un mate y mueve la colita."
        case .resting: return "Respira, parpadea y mueve suavemente las orejas."
        case .imaginingFood: return "Un gesto divertido del tiempo transcurrido, no una señal de hambre."
        case .asado: return "Se imagina una parrilla con vacío y brasas animadas."
        case .countdown: return "Te acompaña sin modificar el tiempo ni el objetivo."
        case .goalReached: return "El objetivo se cumplió, pero tu sesión sigue activa hasta que decidas finalizarla."
        case .completed: return "La hora de corte real quedó guardada."
        }
    }
}

enum FeliFastingAnimationPolicy {
    static func stage(activeElapsed: TimeInterval?, targetSeconds: TimeInterval,
                      recentlyCompleted: Bool = false) -> FeliFastingStage {
        guard let elapsed = activeElapsed else { return recentlyCompleted ? .completed : .ready }
        let safe = max(1, targetSeconds)
        let progress = max(0, elapsed) / safe
        if progress >= 1 { return .goalReached }
        // Mantener un saludo visible durante los primeros diez minutos,
        // sin depender de la duración elegida por el usuario.
        if elapsed < 600 { return .mate }
        if progress < 0.35 { return .resting }
        if progress < 0.65 { return .imaginingFood }
        if progress < 0.85 { return .asado }
        return .countdown
    }
}
