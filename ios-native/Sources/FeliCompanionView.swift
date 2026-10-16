import SwiftUI

/// Mascota ilustrada en SwiftUI. La apariencia definitiva se podrá ajustar
/// a partir de una foto de Feli; no requiere descargas, SDK ni recursos externos.
enum FeliMood: String {
    case curious, calm, worried, sleepy, active, mate, grill, celebrate
}

struct FeliCompanionView: View {
    let mood: FeliMood
    var diameter: CGFloat = 116
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moving = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.10))
                .overlay(Circle().strokeBorder(Color.orange.opacity(0.12)))
            Ellipse().fill(Color.black.opacity(0.08))
                .frame(width: diameter * 0.61, height: diameter * 0.08)
                .offset(y: diameter * 0.38)

            // Orejas caídas, hocico claro y manchas característicos de un beagle.
            Ellipse().fill(Color(red: 0.40, green: 0.23, blue: 0.16))
                .frame(width: diameter * 0.26, height: diameter * 0.45)
                .rotationEffect(.degrees(-20 + (moving && !reduceMotion ? -4 : 0)))
                .offset(x: -diameter * 0.30, y: -diameter * 0.04)
            Ellipse().fill(Color(red: 0.40, green: 0.23, blue: 0.16))
                .frame(width: diameter * 0.26, height: diameter * 0.45)
                .rotationEffect(.degrees(20 + (moving && !reduceMotion ? 4 : 0)))
                .offset(x: diameter * 0.30, y: -diameter * 0.04)

            Ellipse().fill(Color(red: 0.83, green: 0.55, blue: 0.31))
                .frame(width: diameter * 0.58, height: diameter * 0.62)
                .offset(y: -diameter * 0.02)
            Ellipse().fill(.white)
                .frame(width: diameter * 0.38, height: diameter * 0.34)
                .offset(y: diameter * 0.15)

            HStack(spacing: diameter * 0.18) {
                eye
                eye
            }.offset(y: -diameter * 0.08)

            Ellipse().fill(Color(red: 0.19, green: 0.15, blue: 0.16))
                .frame(width: diameter * 0.19, height: diameter * 0.12)
                .offset(y: diameter * 0.12)

            if mood == .sleepy {
                Text("Zzz").font(.caption.bold()).foregroundStyle(.indigo)
                    .offset(x: diameter * 0.29, y: -diameter * 0.31)
                    .opacity(moving ? 1 : 0.35)
            }
            if mood == .calm {
                Text("🦋").font(.system(size: diameter * 0.20))
                    .offset(x: moving ? diameter * 0.09 : -diameter * 0.04,
                            y: moving ? -diameter * 0.29 : -diameter * 0.22)
            }
            if mood == .mate {
                Text("🧉").font(.system(size: diameter * 0.29))
                    .offset(x: diameter * 0.29, y: diameter * 0.23)
                    .rotationEffect(.degrees(moving ? 6 : -6))
            }
            if mood == .grill {
                Text("🥩").font(.system(size: diameter * 0.25))
                    .offset(x: diameter * 0.29, y: diameter * 0.23)
                Text("♨️").font(.system(size: diameter * 0.17))
                    .offset(x: diameter * 0.33, y: moving ? -diameter * 0.07 : 0)
            }
            if mood == .worried {
                Image(systemName: "watch.analog")
                    .font(.system(size: diameter * 0.22))
                    .foregroundStyle(.orange)
                    .offset(x: diameter * 0.28, y: diameter * 0.25)
                    .rotationEffect(.degrees(moving ? 9 : -9))
            }
            if mood == .active {
                Text("🐾").font(.system(size: diameter * 0.22))
                    .offset(x: diameter * 0.31, y: moving ? diameter * 0.08 : diameter * 0.23)
            }
            if mood == .celebrate {
                Text("✨").font(.system(size: diameter * 0.25))
                    .offset(x: diameter * 0.31, y: moving ? -diameter * 0.30 : -diameter * 0.18)
            }
        }
        .frame(width: diameter, height: diameter)
        .offset(y: moving && !reduceMotion && (mood == .active || mood == .celebrate) ? -3 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.7).repeatForever(autoreverses: true),
                   value: moving)
        .onAppear { moving = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleDescription)
    }

    private var eye: some View {
        Ellipse().fill(Color(red: 0.15, green: 0.12, blue: 0.13))
            .frame(width: diameter * 0.065, height: mood == .sleepy ? diameter * 0.02 : diameter * 0.086)
    }

    private var accessibleDescription: String {
        switch mood {
        case .curious: return "Feli, beagle curioso"
        case .calm: return "Feli sentado, con una mariposa"
        case .worried: return "Feli preocupado, mirando un reloj"
        case .sleepy: return "Feli durmiendo"
        case .active: return "Feli paseando"
        case .mate: return "Feli tomando mate"
        case .grill: return "Feli preparando un asado"
        case .celebrate: return "Feli festejando"
        }
    }
}
