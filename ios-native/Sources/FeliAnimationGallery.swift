import SwiftUI

/// Previsualización interactiva de las animaciones NATIVAS de Feli.
/// No necesita horas de ayuno ni datos médicos de prueba.
struct FeliAnimationGallery: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected = FeliMood.sniff

    private struct Scene: Identifiable {
        let mood: FeliMood
        let label: String
        let detail: String
        var id: String { mood.rawValue }
        init(_ mood: FeliMood, _ label: String, _ detail: String) {
            self.mood = mood; self.label = label; self.detail = detail
        }
    }
    private let scenes: [Scene] = [
        Scene(.sniff, "Olfatea", "Baja la cabeza y el hocico, mueve las orejas y olfatea en 3D."),
        Scene(.yawn, "Bosteza", "Abre la boca y baja la mandíbula con lengua visible."),
        Scene(.stretch, "Se estira", "Adelanta las dos patitas y baja el pecho."),
        Scene(.active, "Buena actividad", "Corre con las cuatro patas alternadas, mueve orejas y cola."),
        Scene(.greet, "Saluda", "Levanta y mueve una patita, inclina la cabeza y mueve la cola."),
        Scene(.earWiggle, "Mueve las orejas", "Las dos orejas largas se doblan con movimientos separados."),
        Scene(.bellyRub, "Pancita", "Se recuesta de lado, muestra la pancita y mueve las patas."),
        Scene(.curious, "Curioso", "Olisquea, inclina la cabeza, pestañea y mira alrededor."),
        Scene(.calm, "Tranquilo", "Respira suave, mueve orejas y observa una mariposa."),
        Scene(.sleepy, "Dormido", "Descansa, respira más lento y mantiene los ojos cerrados."),
        Scene(.worried, "Estrés elevado", "Mira el reloj, mueve orejas, cambia el apoyo y respira lentamente; si hay una lectura elevada, Salud muestra una recomendación breve."),
        Scene(.mate, "Mate feliz", "Al iniciar Ayuno, toma un mate y mueve la cola."),
        Scene(.grill, "Vacío a la parrilla", "Vacío, brasas y humo en movimiento."),
        Scene(.celebrate, "Festejo", "Mueve la cola más rápido y aparecen destellos.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Modelo 3D de Feli. Elegí cada movimiento: olfateo, bostezo, estiramiento, carrera y orejas son animaciones distintas. También podés tocar el personaje.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 9) {
                        FeliThoughtBubble(thought: FeliThoughtBubble.thought(for: selected))
                            .padding(.bottom, -12)
                        FeliCompanionView(mood: selected, diameter: 235)
                            .id(selected)
                            .frame(maxWidth: .infinity)
                            .frame(height: 245)
                        if let row = scenes.first(where: { $0.mood == selected }) {
                            Text(row.label).font(.title3.bold())
                            Text(row.detail).font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 24))

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(scenes) { row in
                            Button {
                                selected = row.mood
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selected == row.mood ? "checkmark.circle.fill" : "circle")
                                    Text(row.label).lineLimit(2)
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .tint(selected == row.mood ? .orange : .secondary)
                        }
                    }
                    Text("Estas son las animaciones 3D SceneKit que se usan dentro de Salud y Ayuno. En producción, las escenas se activan según lecturas válidas o el avance del cronómetro; esta galería no altera esos registros.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Animaciones de Feli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
