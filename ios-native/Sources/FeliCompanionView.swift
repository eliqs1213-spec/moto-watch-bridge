import SwiftUI

/// Feli NO es una foto, un GIF ni un sticker: es un personaje construido
/// con partes SwiftUI animadas de manera independiente a 15 cuadros/seg.
/// Su pelaje limón y blanco y sus orejas caídas se basan en la referencia del usuario.
enum FeliMood: String {
    case curious, calm, worried, sleepy, active, mate, grill, celebrate
}

private enum FeliTouchArea: Equatable {
    case head, ear, tummy
}

struct FeliCompanionView: View {
    let mood: FeliMood
    var diameter: CGFloat = 116

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var touchedAt = Date.distantPast
    @State private var appearedAt = Date()
    @State private var touchArea: FeliTouchArea = .head

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0,
                                paused: reduceMotion || scenePhase != .active)) { context in
            let now = context.date
            let seconds = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
            let touchAge = now.timeIntervalSince(touchedAt)
            let greetAge = now.timeIntervalSince(appearedAt)
            let reaction = reduceMotion ? 0 : pulse(touchAge, length: 1.6)
            let greeting = reduceMotion ? 0 : pulse(greetAge, length: 1.45)
            FeliCharacter(mood: mood, seconds: seconds, touch: reaction,
                          touchArea: touchArea, greeting: greeting,
                          reduceMotion: reduceMotion)
                .frame(width: 174, height: 174)
                .scaleEffect(diameter / 174)
                .frame(width: diameter, height: diameter)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { event in
                    let x = event.location.x / max(diameter, 1)
                    let y = event.location.y / max(diameter, 1)
                    touchArea = y > 0.64 ? .tummy : ((x < 0.27 || x > 0.73) ? .ear : .head)
                    touchedAt = Date()
                })
        }
        .frame(width: diameter, height: diameter)
        .onAppear { appearedAt = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description + ". Tocá para interactuar.")
        .accessibilityAddTraits(.isButton)
    }

    private func pulse(_ elapsed: TimeInterval, length: TimeInterval) -> Double {
        guard elapsed >= 0, elapsed < length else { return 0 }
        return sin(.pi * elapsed / length)
    }

    private var description: String {
        switch mood {
        case .curious: return "Feli, beagle limón curioso"
        case .calm: return "Feli tranquilo mirando una mariposa"
        case .worried: return "Feli atento al reloj"
        case .sleepy: return "Feli durmiendo"
        case .active: return "Feli jugando y moviendo la cola"
        case .mate: return "Feli feliz tomando mate"
        case .grill: return "Feli pensando en un asado con vacío a la parrilla"
        case .celebrate: return "Feli festejando"
        }
    }
}

private struct FeliCharacter: View {
    let mood: FeliMood
    let seconds: Double
    let touch: Double
    let touchArea: FeliTouchArea
    let greeting: Double
    let reduceMotion: Bool

    private let lemon = Color(red: 0.91, green: 0.68, blue: 0.38)
    private let lemonShade = Color(red: 0.72, green: 0.46, blue: 0.23)
    private let earShade = Color(red: 0.69, green: 0.42, blue: 0.21)
    private let whiteFur = Color(red: 1.0, green: 0.98, blue: 0.91)
    private let ink = Color(red: 0.20, green: 0.15, blue: 0.13)
    private let orange = Color(red: 0.97, green: 0.29, blue: 0.09)

    private var cycle: Double { (seconds.truncatingRemainder(dividingBy: 29) + 29).truncatingRemainder(dividingBy: 29) }
    private func gesture(_ start: Double, _ end: Double) -> Double {
        guard !reduceMotion, mood != .sleepy, cycle >= start && cycle < end else { return 0 }
        return sin(.pi * (cycle - start) / (end - start))
    }
    private var sniff: Double { gesture(3, 7) }
    private var stretch: Double { gesture(9, 13) }
    private var pawUp: Double { max(greeting, gesture(16, 20), mood == .active ? max(0, sin(seconds * 2.5)) * 0.32 : 0) }
    private var yawn: Double { gesture(23, 27) }
    private var breathe: Double { sin(seconds * (mood == .sleepy ? 1.18 : 2.05)) }
    private var eyeClosed: Bool {
        mood == .sleepy || (!reduceMotion && seconds.truncatingRemainder(dividingBy: 4.7) < 0.17)
    }
    private var tailWag: Double {
        let amplitude = mood == .celebrate ? 19.0 : mood == .active || mood == .mate ? 14.0 : 6.0
        return sin(seconds * (mood == .celebrate ? 9.0 : 4.4)) * amplitude + touch * 15
    }
    private var headTurn: Double {
        (mood == .curious ? sin(seconds * 0.55) * 5 : sin(seconds * 0.68) * 1.6)
            + sniff * 5 + touch * (touchArea == .head ? -9 : -3) + greeting * 4
    }
    private var animatedEar: Double {
        sin(seconds * 1.18) * (mood == .sleepy ? 0.5 : 2.3)
            + sniff * 4 + touch * (touchArea == .ear ? 11 : 4)
    }

    var body: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.07))
                .frame(width: 103, height: 10).offset(y: 72)
            tail
            backPaws
            torso
            frontPaws
            face
                .rotationEffect(.degrees(headTurn), anchor: .bottom)
                .offset(x: CGFloat(sniff * 2),
                        y: CGFloat(sniff * 3 - stretch * 2 - touch * 1.5))
            accessory
            if touch > 0.05 {
                Image(systemName: touchArea == .tummy ? "heart.fill" :
                      touchArea == .ear ? "sparkle" : "heart.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.pink)
                    .opacity(touch)
                    .offset(x: 54, y: CGFloat(-64 - touch * 8))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 174, height: 174)
    }

    private var tail: some View {
        Capsule()
            .fill(LinearGradient(colors: [whiteFur, lemon, lemonShade],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 14, height: 54)
            .rotationEffect(.degrees(-37 + tailWag), anchor: .bottom)
            .offset(x: 51, y: 8)
    }

    private var backPaws: some View {
        HStack(spacing: 44) {
            Ellipse().fill(lemonShade.opacity(0.8)).frame(width: 24, height: 25)
            Ellipse().fill(lemonShade.opacity(0.8)).frame(width: 24, height: 25)
        }
        .offset(y: 55)
    }

    private var torso: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [lemon, lemon, lemonShade.opacity(0.92)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 88, height: 92)
                .scaleEffect(x: CGFloat(1 + stretch * 0.06 + breathe * 0.01),
                             y: CGFloat(1 + breathe * 0.016))
            Ellipse().fill(whiteFur)
                .frame(width: 51, height: 82).offset(y: 10)
            // Arnés naranja: cruza el pecho, no reemplaza el cuello.
            RoundedRectangle(cornerRadius: 4)
                .fill(orange)
                .frame(width: 11, height: 66)
                .rotationEffect(.degrees(-4))
                .offset(x: 1, y: 8)
            Capsule().fill(orange)
                .frame(width: 71, height: 9)
                .offset(y: 3)
            Circle().fill(.white.opacity(0.8))
                .frame(width: 6, height: 6)
                .offset(x: 1, y: 3)
        }
        .offset(y: 32)
    }

    private var frontPaws: some View {
        ZStack {
            frontPaw(left: true, raise: stretch * 4)
            frontPaw(left: false, raise: max(pawUp, touchArea == .tummy ? touch : 0) * 18)
        }
    }
    private func frontPaw(left: Bool, raise: Double) -> some View {
        let sign: Double = left ? -1 : 1
        return ZStack {
            Capsule().fill(LinearGradient(colors: [whiteFur, Color(red: 0.91, green: 0.89, blue: 0.82)],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(width: 21, height: 50)
                .offset(y: -3)
            Ellipse().fill(whiteFur).frame(width: 26, height: 15)
                .offset(y: 21)
        }
        .rotationEffect(.degrees(left ? -stretch * 5 : -pawUp * 17), anchor: .top)
        .offset(x: CGFloat(sign * (24 + stretch * 4)), y: CGFloat(39 - raise))
    }

    private var face: some View {
        ZStack {
            // Orejas realmente caídas: estrechas arriba, más anchas hacia abajo.
            // Se dibujan sobre las mejillas, pero fuera del hocico blanco.
            Ellipse()
                .fill(LinearGradient(colors: [lemon, lemon, lemonShade],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 96, height: 95)
                .offset(y: -27)
            ear(left: true)
            ear(left: false)
            BeagleBlaze()
                .fill(whiteFur)
                .frame(width: 35, height: 76)
                .offset(y: -34)
            HStack(spacing: 32) {
                eye
                eye
            }
            .offset(y: -38)
            HStack(spacing: -5) {
                Ellipse().fill(whiteFur).frame(width: 36, height: 38)
                Ellipse().fill(whiteFur).frame(width: 36, height: 38)
            }
            .offset(y: 0)
            BeagleNose().fill(ink)
                .frame(width: 24, height: 16)
                .offset(y: -12)
            Path { path in
                path.move(to: CGPoint(x: 69, y: 95))
                path.addQuadCurve(to: CGPoint(x: 87, y: 97), control: CGPoint(x: 78, y: 102))
                path.addQuadCurve(to: CGPoint(x: 105, y: 95), control: CGPoint(x: 96, y: 102))
            }
            .stroke(ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 174, height: 174)
            .offset(y: -8)
            if mood == .celebrate || mood == .mate || mood == .active {
                Capsule().fill(Color(red: 0.91, green: 0.37, blue: 0.44))
                    .frame(width: 12, height: CGFloat(6 + max(0, sin(seconds * 3)) * 7))
                    .offset(y: 10)
            }
            if yawn > 0.04 {
                Ellipse().fill(ink)
                    .frame(width: 17, height: CGFloat(4 + yawn * 13))
                    .offset(y: 10)
            }
            if mood == .sleepy {
                Text("ᶻᶻ").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.indigo)
                    .offset(x: 54, y: -65)
            }
        }
    }

    private func ear(left: Bool) -> some View {
        let side: Double = left ? -1 : 1
        return ZStack {
            BeagleEar()
                .fill(LinearGradient(colors: [lemonShade, earShade, lemon],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 36, height: 75)
            BeagleEar()
                .fill(whiteFur.opacity(0.13))
                .frame(width: 16, height: 51)
                .offset(x: -5, y: 10)
        }
        .scaleEffect(x: left ? 1 : -1)
        .rotationEffect(.degrees(side * (11 + animatedEar) + (mood == .worried ? side * 5 : 0)),
                        anchor: .top)
        .offset(x: CGFloat(side * 48), y: CGFloat(-16 + touch * 2))
    }

    private var eye: some View {
        ZStack {
            Capsule().fill(ink)
                .frame(width: 12, height: eyeClosed ? 2.5 : 15)
            if !eyeClosed {
                Circle().fill(.white.opacity(0.9))
                    .frame(width: 3.1, height: 3.1)
                    .offset(x: -2, y: -3)
            }
        }
    }

    @ViewBuilder private var accessory: some View {
        switch mood {
        case .mate:
            FeliMateAccessory(seconds: seconds)
                .frame(width: 53, height: 58)
                .offset(x: 47, y: 35)
        case .grill:
            FeliAsadoAccessory(seconds: seconds)
                .frame(width: 78, height: 72)
                .offset(x: 44, y: 35)
        case .celebrate:
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.orange)
                .rotationEffect(.degrees(sin(seconds * 2.1) * 6))
                .offset(x: 59, y: -51)
        case .calm:
            Text("🦋")
                .font(.system(size: 24))
                .offset(x: CGFloat(53 + sin(seconds * 1.4) * 4),
                        y: CGFloat(-53 + cos(seconds * 1.8) * 5))
        case .worried:
            Image(systemName: "clock")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.orange)
                .rotationEffect(.degrees(sin(seconds * 1.1) * 3))
                .offset(x: 52, y: -51)
        case .curious:
            Image(systemName: "sparkle")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
                .opacity(sniff)
                .offset(x: 58, y: -55)
        case .active, .sleepy:
            EmptyView()
        }
    }
}

private struct BeagleEar: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.31, y: r.height * 0.03))
        p.addCurve(to: CGPoint(x: r.width * 0.06, y: r.height * 0.54),
                   control1: CGPoint(x: r.width * 0.03, y: r.height * 0.03),
                   control2: CGPoint(x: r.width * 0.01, y: r.height * 0.33))
        p.addCurve(to: CGPoint(x: r.width * 0.47, y: r.height * 0.99),
                   control1: CGPoint(x: r.width * 0.03, y: r.height * 0.79),
                   control2: CGPoint(x: r.width * 0.20, y: r.height * 1.03))
        p.addCurve(to: CGPoint(x: r.width * 0.98, y: r.height * 0.60),
                   control1: CGPoint(x: r.width * 0.80, y: r.height * 0.98),
                   control2: CGPoint(x: r.width * 0.94, y: r.height * 0.85))
        p.addCurve(to: CGPoint(x: r.width * 0.31, y: r.height * 0.03),
                   control1: CGPoint(x: r.width * 0.88, y: r.height * 0.29),
                   control2: CGPoint(x: r.width * 0.56, y: r.height * 0.04))
        p.closeSubpath()
        return p
    }
}

private struct BeagleBlaze: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.48, y: 0))
        p.addCurve(to: CGPoint(x: r.width * 0.84, y: r.height),
                   control1: CGPoint(x: r.width * 0.38, y: r.height * 0.36),
                   control2: CGPoint(x: r.width * 0.82, y: r.height * 0.70))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.15, y: r.height),
                       control: CGPoint(x: r.width * 0.48, y: r.height * 0.89))
        p.addCurve(to: CGPoint(x: r.width * 0.48, y: 0),
                   control1: CGPoint(x: r.width * 0.25, y: r.height * 0.48),
                   control2: CGPoint(x: r.width * 0.58, y: r.height * 0.13))
        p.closeSubpath()
        return p
    }
}

private struct BeagleNose: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.12, y: r.height * 0.05))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.88, y: r.height * 0.05),
                       control: CGPoint(x: r.width * 0.50, y: r.height * -0.08))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.5, y: r.height),
                       control: CGPoint(x: r.width * 0.94, y: r.height * 0.61))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.12, y: r.height * 0.05),
                       control: CGPoint(x: r.width * 0.06, y: r.height * 0.61))
        p.closeSubpath()
        return p
    }
}

private struct FeliMateAccessory: View {
    let seconds: Double
    var body: some View {
        ZStack {
            // Bombilla inclinada y pequeña boca del mate.
            Capsule().fill(Color.gray.opacity(0.86))
                .frame(width: 3.6, height: 44)
                .rotationEffect(.degrees(29 + sin(seconds * 1.6) * 3))
                .offset(x: 7, y: -12)
            Ellipse().fill(Color(red: 0.23, green: 0.45, blue: 0.16))
                .frame(width: 36, height: 12).offset(y: -5)
            Ellipse()
                .fill(LinearGradient(colors: [.brown, Color(red: 0.35, green: 0.15, blue: 0.07)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 37, height: 37).offset(y: 10)
            Ellipse().stroke(.white.opacity(0.85), lineWidth: 2.5)
                .frame(width: 37, height: 12).offset(y: -5)
        }
        .rotationEffect(.degrees(sin(seconds * 1.8) * 2))
    }
}

private struct FeliAsadoAccessory: View {
    let seconds: Double
    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "flame.fill")
                        .foregroundStyle(index == 1 ? .orange : .yellow)
                        .font(.system(size: 13))
                        .opacity(0.7 + 0.3 * abs(sin(seconds * 3 + Double(index))))
                }
            }
            .offset(y: 23)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.16, green: 0.17, blue: 0.16))
                .frame(width: 73, height: 10).offset(y: 13)
            // Vacío, no un bistec: pieza larga e irregular con grasa visible.
            FeliVacio()
                .fill(LinearGradient(colors: [Color(red: 0.50, green: 0.21, blue: 0.12),
                                             Color(red: 0.78, green: 0.37, blue: 0.17),
                                             Color(red: 0.36, green: 0.13, blue: 0.09)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 64, height: 24)
                .rotationEffect(.degrees(-7))
                .offset(y: -3)
            FeliVacio()
                .stroke(Color(red: 0.97, green: 0.79, blue: 0.58).opacity(0.9), lineWidth: 2.4)
                .frame(width: 64, height: 24)
                .rotationEffect(.degrees(-7))
                .offset(y: -3)
            ForEach(0..<5, id: \.self) { index in
                Capsule().fill(.black.opacity(0.53))
                    .frame(width: 3, height: 51)
                    .offset(x: CGFloat(-29 + index * 14), y: -1)
                    .rotationEffect(.degrees(90))
            }
            HStack(spacing: 15) {
                Image(systemName: "smoke.fill")
                    .opacity(0.36 + 0.2 * sin(seconds * 1.7))
                Image(systemName: "smoke.fill")
                    .opacity(0.32 + 0.2 * cos(seconds * 1.4))
            }
            .font(.system(size: 11))
            .foregroundStyle(.gray)
            .offset(y: -28)
        }
    }
}

private struct FeliVacio: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.height * 0.31))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.58, y: r.height * 0.12),
                       control: CGPoint(x: r.width * 0.29, y: r.height * -0.08))
        p.addQuadCurve(to: CGPoint(x: r.width, y: r.height * 0.28),
                       control: CGPoint(x: r.width * 0.81, y: r.height * -0.02))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.71, y: r.height * 0.94),
                       control: CGPoint(x: r.width * 0.96, y: r.height * 0.82))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.09, y: r.height * 0.82),
                       control: CGPoint(x: r.width * 0.39, y: r.height * 1.04))
        p.closeSubpath()
        return p
    }
}
