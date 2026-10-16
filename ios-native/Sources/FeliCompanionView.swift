import SwiftUI

/// Feli es un compañero discreto exclusivamente en Salud.
/// Sus partes se mueven independientemente: respirar, pestañear, orejas,
/// cola y pequeños gestos; nunca se desplaza toda la tarjeta ni rebota.
enum FeliMood: String {
    case curious, calm, worried, sleepy, active, mate, grill, celebrate
}

struct FeliCompanionView: View {
    let mood: FeliMood
    var diameter: CGFloat = 116

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pettedAt: Date = .distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 16.0, paused: reduceMotion)) { context in
            let seconds = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let petAge = context.date.timeIntervalSince(pettedAt)
            let petting = !reduceMotion && petAge >= 0 && petAge < 1.4
            FeliIllustration(mood: mood, seconds: seconds, petted: petting,
                             reduceMotion: reduceMotion)
                .frame(width: 160, height: 160)
                .scaleEffect(diameter / 160)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .onTapGesture {
                    pettedAt = Date()
                }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleDescription + ". Tocá para acariciarlo.")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibleDescription: String {
        switch mood {
        case .curious: return "Feli, beagle curioso"
        case .calm: return "Feli tranquilo, mirando una mariposa"
        case .worried: return "Feli inquieto, junto a su reloj"
        case .sleepy: return "Feli descansando"
        case .active: return "Feli moviendo la cola"
        case .mate: return "Feli junto a un mate"
        case .grill: return "Feli junto a un asado"
        case .celebrate: return "Feli contento"
        }
    }
}

private struct FeliIllustration: View {
    let mood: FeliMood
    let seconds: Double
    let petted: Bool
    let reduceMotion: Bool

    private let fur = Color(red: 0.81, green: 0.52, blue: 0.28)
    private let darkFur = Color(red: 0.39, green: 0.23, blue: 0.17)
    private let ink = Color(red: 0.18, green: 0.14, blue: 0.14)
    private let harness = Color(red: 1.0, green: 0.43, blue: 0.07)

    private var breath: Double { sin(seconds * (mood == .sleepy ? 1.5 : 2.2)) }
    private var wag: Double {
        let speed = petted ? 14.0 : mood == .active || mood == .celebrate ? 7.0 : 3.6
        let size = petted ? 25.0 : mood == .active || mood == .celebrate ? 18.0 : 7.0
        return sin(seconds * speed) * size
    }
    private var blink: Bool {
        !reduceMotion && mood != .sleepy && seconds.truncatingRemainder(dividingBy: 5.2) < 0.15
    }
    private var glance: Double {
        reduceMotion || mood == .sleepy ? 0 : sin(seconds * 0.76) * 1.6
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.orange.opacity(0.045))
                .frame(width: 152, height: 152)
            Ellipse().fill(.black.opacity(0.08))
                .frame(width: 93, height: 8).offset(y: 65)
            tail
            torso
            paws
            face
                .rotationEffect(.degrees(petted ? -5.0 : glance), anchor: .bottom)
                .offset(y: petted ? -1 : 0)
            moodAccessory
        }
        .frame(width: 160, height: 160)
    }

    private var tail: some View {
        Capsule().fill(fur)
            .frame(width: 16, height: 48)
            .overlay(alignment: .top) {
                Capsule().fill(.white).frame(width: 16, height: 13)
            }
            .rotationEffect(.degrees(-42 + wag), anchor: .bottom)
            .offset(x: 46, y: 7)
    }

    private var torso: some View {
        ZStack {
            Ellipse().fill(fur)
                .frame(width: 88, height: 77)
                .scaleEffect(x: 1 + breath * 0.014, y: 1 + breath * 0.018)
                .offset(y: 30)
            Ellipse().fill(.white.opacity(0.97))
                .frame(width: 44, height: 55)
                .offset(y: 36)
            RoundedRectangle(cornerRadius: 5)
                .fill(harness)
                .frame(width: 72, height: 12)
                .offset(y: 31)
            RoundedRectangle(cornerRadius: 5)
                .fill(harness)
                .frame(width: 13, height: 51)
                .offset(y: 27)
            Circle().fill(.white.opacity(0.8))
                .frame(width: 6, height: 6).offset(y: 31)
        }
    }

    private var paws: some View {
        ZStack {
            Ellipse().fill(.white)
                .frame(width: 27, height: 18).offset(x: -28, y: 61)
            Ellipse().fill(.white)
                .frame(width: 27, height: 18)
                .offset(x: 28, y: 61 - (mood == .active ? max(0, sin(seconds * 3)) * 1.6 : 0))
        }
    }

    private var face: some View {
        ZStack {
            // Las orejas se mueven desde su unión a la cabeza.
            Ellipse().fill(darkFur)
                .frame(width: 33, height: 62)
                .rotationEffect(.degrees(-20 + sin(seconds * 1.1) * 2), anchor: .top)
                .offset(x: -38, y: -13)
            Ellipse().fill(darkFur)
                .frame(width: 33, height: 62)
                .rotationEffect(.degrees(20 - sin(seconds * 1.2) * 2), anchor: .top)
                .offset(x: 38, y: -13)
            Ellipse().fill(fur)
                .frame(width: 91, height: 92).offset(y: -24)
            // La franja blanca de la frente y el hocico del beagle.
            Ellipse().fill(.white)
                .frame(width: 18, height: 49).offset(y: -42)
            Ellipse().fill(.white)
                .frame(width: 58, height: 42).offset(y: -1)
            HStack(spacing: 28) {
                eye
                eye
            }
            .offset(y: -32)
            Ellipse().fill(ink)
                .frame(width: 22, height: 14).offset(y: -8)
            if mood == .sleepy {
                Text("ᶻ").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.indigo).offset(x: 39, y: -66)
            }
        }
    }

    private var eye: some View {
        Capsule().fill(ink)
            .frame(width: 10, height: mood == .sleepy || blink ? 2.5 : 12)
    }

    @ViewBuilder private var moodAccessory: some View {
        switch mood {
        case .calm:
            Text("🦋").font(.system(size: 27))
                .offset(x: 53 + sin(seconds * 1.3) * 4,
                        y: -53 + cos(seconds * 1.7) * 6)
        case .worried:
            Image(systemName: "watch.analog")
                .font(.system(size: 25))
                .foregroundStyle(.orange)
                .rotationEffect(.degrees(sin(seconds * 1.4) * 5))
                .offset(x: 54, y: 43)
        case .mate:
            Text("🧉").font(.system(size: 30)).offset(x: 52, y: 43)
        case .grill:
            Text("🥩").font(.system(size: 28)).offset(x: 52, y: 43)
        case .celebrate:
            Text("✨").font(.system(size: 29))
                .opacity(0.55 + 0.35 * (1 + sin(seconds * 2.2)) / 2)
                .offset(x: 54, y: -56)
        case .active, .curious, .sleepy:
            EmptyView()
        }
    }
}
