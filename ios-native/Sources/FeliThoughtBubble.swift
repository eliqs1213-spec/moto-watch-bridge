import SwiftUI

/// Readable thought bubble that explains the *animation*, never invents
/// vital readings. Used next to the actual SceneKit 3D Feli in Salud/Ayuno.
struct FeliThoughtBubble: View {
    let thought: String
    var color: Color = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(thought)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: 138)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(color.opacity(0.38), lineWidth: 1)
                }
            HStack(spacing: 3) {
                Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 0.6))
                Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(width: 4, height: 4)
            }
            .padding(.leading, 17)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feli piensa: \(thought)")
    }

    static func thought(for mood: FeliMood) -> String {
        switch mood {
        case .worried: return "🌬️ Una pausa tranquila"
        case .calm: return "🦋 Qué linda mariposa"
        case .sleepy: return "💤 Hora de descansar"
        case .active: return "🐾 ¡A mover las patas!"
        case .curious: return "💭 Voy a investigar"
        case .mate: return "🧉 ¡Unos mates!"
        case .grill: return "🥩 ¡Un vacío a la parrilla!"
        case .celebrate: return "✨ ¡Qué bien!"
        case .sniff: return "👃 ¿Qué olor es ese?"
        case .stretch: return "🐾 A estirarse"
        case .yawn: return "🥱 ¡Qué sueño!"
        case .greet: return "👋 ¡Hola de nuevo!"
        case .earWiggle: return "👂 Escucho algo"
        case .bellyRub: return "❤️ ¿Una caricia?"
        }
    }
}
