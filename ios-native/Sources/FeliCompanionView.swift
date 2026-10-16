import SwiftUI
import SceneKit
import UIKit

enum FeliMood: String {
    case curious, calm, worried, sleepy, active, mate, grill, celebrate
    // Explicit previewable performances, not hidden variations of paw-waving.
    case sniff, stretch, yawn, greet, earWiggle, bellyRub
}

/// Real, interactive 3D model. Every animation is articulated by SceneKit,
/// not a flat illustration, still photograph, animated emoji or GIF.
struct FeliCompanionView: View {
    let mood: FeliMood
    var diameter: CGFloat = 116

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Feli3DScene(mood: mood, reduceMotion: reduceMotion,
                    isActive: scenePhase == .active)
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Feli, beagle limón en 3D: \(description). Tocá las orejas, la cabeza o las patitas.")
            .accessibilityAddTraits(.isButton)
    }

    private var description: String {
        switch mood {
        case .curious: return "curioso, olfatea y mira a su alrededor"
        case .calm: return "descansa y respira tranquilamente"
        case .worried: return "está atento, mira el reloj"
        case .sleepy: return "acostado y con los ojos cerrados"
        case .active: return "corre moviendo sus cuatro patas"
        case .mate: return "inclina la cabeza para tomar mate feliz"
        case .grill: return "olfatea un vacío en la parrilla con humo"
        case .celebrate: return "festeja moviendo la cola y ambas patas"
        case .sniff: return "baja el hocico, olfatea y mueve las orejas"
        case .stretch: return "se estira y adelanta las dos patas"
        case .yawn: return "abre la boca de verdad, baja la mandíbula y bosteza"
        case .greet: return "saluda levantando y moviendo una pata"
        case .earWiggle: return "mueve ambas orejas largas por separado"
        case .bellyRub: return "se tumba panza arriba y mueve las patitas"
        }
    }
}

private struct Feli3DScene: UIViewRepresentable {
    let mood: FeliMood
    let reduceMotion: Bool
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let rig = Feli3DRig()
        let animator = Feli3DAnimator(rig: rig, mood: mood)
        context.coordinator.animator = animator
        view.scene = rig.scene
        view.delegate = animator
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = reduceMotion ? 2 : 30
        view.rendersContinuously = true
        view.isPlaying = isActive
        view.accessibilityTraits = .button
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.didTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.animator?.changeMood(mood)
        context.coordinator.animator?.reduceMotion = reduceMotion
        view.preferredFramesPerSecond = reduceMotion ? 2 : 30
        view.isPlaying = isActive
        if isActive && !context.coordinator.wasActive {
            context.coordinator.animator?.restartGreeting()
        }
        context.coordinator.wasActive = isActive
    }

    final class Coordinator: NSObject {
        var animator: Feli3DAnimator?
        var wasActive = false

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? SCNView else { return }
            let point = recognizer.location(in: view)
            // Touch-test REAL 3D geometry. An ear and the body do different things.
            let hit = view.hitTest(point, options: [SCNHitTestOption.firstFoundOnly: true])
            var node = hit.first?.node
            var part = "head"
            while let current = node {
                let name = current.name ?? ""
                if name.contains("ear") {
                    part = "ear"
                    break
                }
                if name.contains("paw") || name.contains("belly") ||
                    name.contains("torso") || name.contains("chest") {
                    part = "belly"
                    break
                }
                if name.contains("head") || name.contains("eye") ||
                    name.contains("muzzle") || name.contains("nose") {
                    part = "head"
                    break
                }
                node = current.parent
            }
            animator?.touch(part)
        }
    }
}
