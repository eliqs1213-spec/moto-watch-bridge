import SwiftUI

/// Feli se suma a Ayuno sin superponerse al cronómetro. Su estado depende
/// del tiempo real y del objetivo; las escenas de comida son simbólicas.
struct FeliFastingDock: View {
    @ObservedObject var fasting: FastingStore
    @AppStorage("iwatch.fasting.feli.compact") private var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let session = fasting.active
            let elapsed = session.map { max(0, context.date.timeIntervalSince($0.startedAt)) }
            let goal = session.map { $0.targetEndAt.timeIntervalSince($0.startedAt) } ?? 12 * 3600
            let recentFinish = fasting.lastCompleted.map { last in
                guard let ended = last.endedAt else { return false }
                return context.date.timeIntervalSince(ended) >= 0
                    && context.date.timeIntervalSince(ended) <= 1800
                    && ended >= last.targetEndAt
            } ?? false
            let stage = FeliFastingAnimationPolicy.stage(
                activeElapsed: elapsed, targetSeconds: goal,
                recentlyCompleted: session == nil && recentFinish)
            let mood = mood(for: stage)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 10) {
                    FeliCompanionView(mood: mood, diameter: compact ? 55 : 103)
                        .id(stage.rawValue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(compact ? "Feli te acompaña en Ayuno" : stage.headline)
                            .font(.subheadline.bold())
                            .lineLimit(compact ? 1 : 2)
                        if !compact {
                            Text(stage.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let elapsed {
                                Text("\(Int((min(1, elapsed / max(goal, 1)) * 100).rounded()))% del objetivo elegido")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                            Text("Tocá a Feli para saludarlo")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            compact.toggle()
                        }
                    } label: {
                        Image(systemName: compact ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.system(size: 22))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(compact ? "Expandir Feli" : "Reducir Feli")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 4 : 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.orange.opacity(0.15), lineWidth: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground).opacity(0.94))
        }
    }

    private func mood(for stage: FeliFastingStage) -> FeliMood {
        switch stage {
        case .ready: return .curious
        case .mate: return .mate
        case .resting: return .calm
        case .imaginingFood: return .curious
        case .asado: return .grill
        case .countdown: return .worried
        case .goalReached, .completed: return .celebrate
        }
    }
}
