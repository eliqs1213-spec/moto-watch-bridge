import SceneKit
import Foundation

/// Real 3D animation timeline. Every action changes multiple joint transforms.
/// Never just lifts the same paw for all states.
final class Feli3DAnimator: NSObject, SCNSceneRendererDelegate {
    let rig: Feli3DRig
    private(set) var mood: FeliMood
    var reduceMotion = false
    private var startedAt: TimeInterval?
    private var lastTime: TimeInterval = 0
    private var touchAt: TimeInterval = -.greatestFiniteMagnitude
    private var touchedPart = "head"

    init(rig: Feli3DRig, mood: FeliMood) {
        self.rig = rig
        self.mood = mood
        super.init()
        rig.setAccessories(for: mood)
    }

    func changeMood(_ newMood: FeliMood) {
        guard mood != newMood else { return }
        mood = newMood
        startedAt = nil
        rig.setAccessories(for: newMood)
    }

    func touch(_ part: String) {
        touchedPart = part
        touchAt = lastTime
    }

    private func wave(_ t: Double, _ speed: Double = 1) -> Double {
        sin(t * speed)
    }

    /// Smooth entrance/exit of an action in a larger idle cycle.
    private func gesture(_ t: Double, from: Double, until: Double) -> Double {
        guard until > from else { return 0 }
        let cycle = t.truncatingRemainder(dividingBy: 29)
        guard cycle >= from && cycle < until else { return 0 }
        return sin(.pi * (cycle - from) / (until - from))
    }

    private func pulse(_ t: Double, length: Double) -> Double {
        guard t >= 0, t <= length else { return 0 }
        return sin(.pi * t / length)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if startedAt == nil { startedAt = time }
        lastTime = time
        let t = reduceMotion ? 0 : max(0, time - (startedAt ?? time))
        let greet = reduceMotion ? 0 : pulse(t, length: 1.6)
        let touch = reduceMotion ? 0 : pulse(time - touchAt, length: 1.6)
        let breath = reduceMotion ? 0 : wave(t, mood == .sleepy ? 1.4 : 2.2)
        let blink = !reduceMotion && t.truncatingRemainder(dividingBy: 5.15) < 0.16
        let sniffCycle = gesture(t, from: 2, until: 7)
        let stretchCycle = gesture(t, from: 9, until: 13)
        let yawnCycle = gesture(t, from: 17, until: 22)
        let pawCycle = gesture(t, from: 24, until: 27)
        let earReaction = touchedPart == "ear" ? touch : touch * 0.2
        let faceReaction = touchedPart == "head" ? touch : touch * 0.2
        let bellyReaction = touchedPart == "belly" ? touch : 0

        var bodyY = 0.0
        var bodyPitch = 0.0
        var headY = 1.53
        var headPitch = 0.0
        var headRoll = 0.0
        var headYaw = 0.0
        var leftStep = 0.0
        var rightStep = 0.0
        var hindLeftStep = 0.0
        var hindRightStep = 0.0
        var mouth = 0.03
        var leftEarTilt = 0.0
        var rightEarTilt = 0.0
        var tailSpeed = 3.2
        var tailSwing = 0.12
        var eyeClosing = 0.0

        switch mood {
        case .curious:
            // Sniffing has a visible nose-dip, chest lowering and both ears react.
            let sniff = max(sniffCycle, (wave(t, 1.05) + 1) * 0.15)
            headPitch = -0.19 * sniff
            headY -= 0.10 * sniff
            bodyY -= 0.03 * sniff
            headRoll = wave(t, 0.58) * 0.10
            headYaw = wave(t, 0.44) * 0.07
            leftEarTilt += sniff * 0.16
            rightEarTilt -= sniff * 0.13
            leftStep = -0.22 * stretchCycle
            rightStep = -0.24 * stretchCycle - 0.38 * pawCycle
            bodyPitch = -0.14 * stretchCycle
            bodyY -= 0.14 * stretchCycle
            mouth = 0.95 * yawnCycle
            tailSpeed = 3.6
        case .calm:
            // Genuine sleeping/rest posture, NOT the same standing paw animation.
            bodyY = -0.13
            bodyPitch = -0.11
            headY = 1.30
            headPitch = -0.10
            headRoll = wave(t, 0.55) * 0.025
            leftStep = -0.21
            rightStep = -0.16
            leftEarTilt = -0.08
            rightEarTilt = 0.08
            tailSpeed = 1.7
            tailSwing = 0.06
            eyeClosing = 0.28
        case .sleepy:
            // Entire puppy curls down, rests its head, closes eyes, breathes.
            bodyY = -0.35
            bodyPitch = -0.25
            headY = 1.01 + breath * 0.015
            headPitch = -0.26
            headRoll = -0.12
            leftStep = -0.67
            rightStep = -0.53
            hindLeftStep = 0.36
            hindRightStep = 0.32
            tailSpeed = 0
            tailSwing = 0
            eyeClosing = 1
        case .active:
            // Actual four-legged trot: diagonal paws travel in opposite directions.
            let stride = wave(t, 6.1)
            leftStep = stride * 0.55 - 0.12
            rightStep = -stride * 0.55 - 0.12
            hindLeftStep = -stride * 0.33
            hindRightStep = stride * 0.33
            bodyY = abs(stride) * 0.065
            headY += abs(stride) * 0.025
            headRoll = wave(t, 3.1) * 0.045
            mouth = 0.46
            tailSpeed = 11.0
            tailSwing = 0.42
            leftEarTilt = stride * 0.14
            rightEarTilt = -stride * 0.14
        case .worried:
            headYaw = 0.27 + wave(t, 0.8) * 0.10
            headPitch = -0.05
            headRoll = -0.07
            leftEarTilt = 0.21
            rightEarTilt = -0.21
            tailSpeed = 1.4
            tailSwing = 0.035
            mouth = 0
        case .mate:
            // Sip: head approaches the bombilla, lowers mouth and returns.
            let sip = max(0, wave(t, 1.55))
            headYaw = 0.22
            headRoll = 0.08
            headPitch = -0.20 * sip
            headY -= 0.17 * sip
            rightStep = -0.31
            mouth = 0.30 * sip + 0.19
            leftEarTilt = sip * 0.07
            tailSpeed = 6.4
            tailSwing = 0.29
        case .grill:
            // Sniffs toward the 3D parrilla, with independent smoke/flame animation.
            let smell = 0.5 + 0.5 * wave(t, 1.3)
            headYaw = 0.28
            headPitch = -0.16 * smell
            headY -= smell * 0.06
            mouth = 0.22
            leftEarTilt = smell * 0.10
            rightEarTilt = -smell * 0.10
            tailSpeed = 6.2
            tailSwing = 0.23
        case .celebrate:
            // Excited greeting with both forelegs raised and moving independently.
            let lift = 0.54 + 0.16 * wave(t, 5.3)
            leftStep = -lift
            rightStep = -lift + wave(t, 7.2) * 0.13
            bodyY = 0.06 + abs(wave(t, 3.7)) * 0.04
            headPitch = 0.09
            headRoll = wave(t, 4.3) * 0.08
            mouth = 0.62
            tailSpeed = 13
            tailSwing = 0.50
        }

        // Background actions remain distinct even when simply idle.
        if mood != .sleepy && mood != .active {
            leftStep -= stretchCycle * 0.06
            rightStep -= greet * 0.65 + pawCycle * 0.20
            mouth = max(mouth, yawnCycle * 0.92)
            headPitch -= sniffCycle * 0.05
        }
        rightStep -= bellyReaction * 0.50
        headRoll -= faceReaction * 0.13
        headYaw += earReaction * 0.10
        leftEarTilt -= earReaction * 0.28
        rightEarTilt += earReaction * 0.23

        // Actual articulated joints; all rotations have physical meaning.
        rig.body.position.y = Float(bodyY)
        rig.body.eulerAngles.x = Float(bodyPitch)
        rig.body.scale = SCNVector3(Float(1 + breath * 0.013),
                                     Float(1 + breath * 0.023),
                                     Float(1 + breath * 0.017))
        rig.head.position.y = Float(headY)
        rig.head.eulerAngles = SCNVector3(Float(headPitch), Float(headYaw), Float(headRoll))
        rig.leftEar.eulerAngles = SCNVector3(Float(wave(t, 1.1) * 0.035),
                                             Float(leftEarTilt), Float(-0.09 - leftEarTilt))
        rig.rightEar.eulerAngles = SCNVector3(Float(-wave(t, 1.25) * 0.037),
                                              Float(rightEarTilt), Float(0.09 + rightEarTilt))
        rig.leftLeg.eulerAngles.x = Float(leftStep)
        rig.rightLeg.eulerAngles.x = Float(rightStep)
        rig.leftBackLeg.eulerAngles.x = Float(hindLeftStep)
        rig.rightBackLeg.eulerAngles.x = Float(hindRightStep)
        rig.tail.eulerAngles = SCNVector3(Float(0.3 + wave(t, tailSpeed) * tailSwing),
                                          Float(wave(t, tailSpeed + 0.3) * tailSwing),
                                          Float(-0.16 + wave(t, tailSpeed) * tailSwing * 0.7))
        rig.nose.scale = SCNVector3(Float(1 + sniffCycle * 0.07),
                                   Float(1 + sniffCycle * 0.04), 1)
        rig.jaw.position.y = Float(-0.35 - max(0, mouth) * 0.16)
        rig.jaw.scale = SCNVector3(1, Float(1 + mouth * 0.6), 1)
        rig.tongue.isHidden = mouth < 0.18

        let close = max(eyeClosing, blink ? 0.94 : 0)
        rig.leftEye.scale.y = Float(max(0.08, 1 - close))
        rig.rightEye.scale.y = Float(max(0.08, 1 - close))

        // Smoke rises and disperses; embers flicker independently in 3D.
        for (index, puff) in rig.steam.enumerated() {
            let phase = (t * 0.41 + Double(index) / Double(max(1, rig.steam.count)))
                .truncatingRemainder(dividingBy: 1)
            puff.position.y = Float(0.88 + 0.54 * phase)
            puff.position.x = Float(Double(index) * 0.19 - 0.28 + wave(t + Double(index), 1.5) * 0.065)
            let scale = Float(1 + phase * 1.7)
            puff.scale = SCNVector3(0.065 * scale, 0.085 * scale, 0.05 * scale)
            puff.opacity = CGFloat((1 - phase) * 0.45)
        }
        for (index, flame) in rig.flames.enumerated() {
            let flicker = 0.72 + 0.28 * abs(wave(t + Double(index) * 0.42, 7))
            flame.scale.y = Float(flicker)
            flame.opacity = CGFloat(0.64 + flicker * 0.34)
        }
        rig.sparkle.eulerAngles.z = Float(wave(t, 1.9) * 0.16)
        rig.sparkle.scale = SCNVector3(repeating: Float(0.85 + 0.15 * abs(wave(t, 2.5))))
    }
}
