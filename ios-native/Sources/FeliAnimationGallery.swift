import SwiftUI

/// Previsualización interactiva de las animaciones NATIVAS de Feli.
/// No necesita horas de ayuno ni datos médicos de prueba.
struct FeliAnimationGallery: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected = FeliMood.mate

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
        Scene(.curious, "Curioso", "Olisquea, inclina la cabeza, pestañea y mira alrededor."),
        Scene(.calm, "Tranquilo", "Respira suave, mueve orejas y observa una mariposa."),
        Scene(.sleepy, "Dormido", "Descansa, respira más lento y mantiene los ojos cerrados."),
        Scene(.active, "Activo", "Levanta una patita, mueve la cola y saluda."),
        Scene(.worried, "Atento", "Observa un reloj y presta atención."),
        Scene(.mate, "Mate feliz", "Al iniciar Ayuno, toma un mate y mueve la cola."),
        Scene(.grill, "Vacío a la parrilla", "Vacío, brasas y humo en movimiento."),
        Scene(.celebrate, "Festejo", "Mueve la cola más rápido y aparecen destellos.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Elegí una escena para verla animada de verdad. Tocá la cabeza, las orejas o la pancita para comprobar las reacciones.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 9) {
                        FeliCompanionView(mood: selected, diameter: 210)
                            .id(selected)
                            .frame(maxWidth: .infinity)
                            .frame(height: 224)
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
                    Text("Estas son las animaciones SwiftUI que se usan dentro de Salud y Ayuno. En producción, las escenas se activan según lecturas válidas o el avance del cronómetro; esta galería no altera esos registros.")
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
