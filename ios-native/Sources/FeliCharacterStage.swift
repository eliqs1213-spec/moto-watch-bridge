import SwiftUI

/// El globo pertenece a la escena, junto a la cabeza de Feli: no es
/// otra fila encima del SCNView con espacio en blanco entre ambos.
/// Ambos se mueven de tamaño juntos y la burbuja no captura caricias.
struct FeliCharacterStage: View {
    let mood: FeliMood
    let diameter: CGFloat
    let thought: String
    var showsThought = true

    private var bubbleScale: CGFloat {
        diameter < 130 ? 0.66 : diameter < 205 ? 0.83 : 1.0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            FeliCompanionView(mood: mood, diameter: diameter)
                .frame(width: diameter, height: diameter)
            if showsThought {
                FeliThoughtBubble(thought: thought,
                                  color: mood == .worried ? .orange : .indigo)
                    .scaleEffect(bubbleScale, anchor: .center)
                    .fixedSize(horizontal: true, vertical: true)
                    .position(x: diameter * 0.64, y: diameter * 0.185)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Feli animado: " + thought)
    }
}
