import SceneKit
import SwiftUI
import UIKit

/// Original articulated three-dimensional lemon/white beagle.
/// Independent SceneKit nodes are an actual 3D rig, not a flat drawing or video.
final class Feli3DRig {
    let scene = SCNScene()
    let dog = SCNNode()
    let body = SCNNode()
    let head = SCNNode()
    let leftEar = SCNNode()
    let rightEar = SCNNode()
    let leftLeg = SCNNode()
    let rightLeg = SCNNode()
    let leftBackLeg = SCNNode()
    let rightBackLeg = SCNNode()
    let tail = SCNNode()
    let jaw = SCNNode()
    let tongue = SCNNode()
    let leftEye = SCNNode()
    let rightEye = SCNNode()
    let nose = SCNNode()
    let mate = SCNNode()
    let grill = SCNNode()
    let sparkle = SCNNode()
    let butterfly = SCNNode()
    let littleClock = SCNNode()
    let clockHand = SCNNode()
    var steam: [SCNNode] = []
    var flames: [SCNNode] = []

    private let lemon = UIColor(red: 0.90, green: 0.68, blue: 0.39, alpha: 1)
    private let warmLemon = UIColor(red: 0.79, green: 0.55, blue: 0.28, alpha: 1)
    private let earGold = UIColor(red: 0.72, green: 0.45, blue: 0.23, alpha: 1)
    private let cream = UIColor(red: 1.00, green: 0.96, blue: 0.88, alpha: 1)
    private let orange = UIColor(red: 0.96, green: 0.31, blue: 0.06, alpha: 1)
    private let noseBlack = UIColor(red: 0.20, green: 0.16, blue: 0.15, alpha: 1)

    init() {
        scene.background.contents = UIColor.clear
        buildLightsAndCamera()
        buildDog()
        buildMate()
        buildGrill()
        buildSparkle()
        buildButterflyAndClock()
    }

    private func mat(_ color: UIColor, roughness: CGFloat = 0.86) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .physicallyBased
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        // Light responds gradually on rounded surfaces, avoiding a faceted look.
        m.specular.contents = UIColor(white: 0.25, alpha: 1)
        m.isDoubleSided = true
        return m
    }

    @discardableResult
    private func sphere(_ name: String, _ color: UIColor,
                        scale: SCNVector3, at pos: SCNVector3,
                        parent: SCNNode, roughness: CGFloat = 0.88) -> SCNNode {
        let mesh = SCNSphere(radius: 1)
        // SceneKit's default tessellation exposed visible flat facets when
        // the user enlarged Feli. Preserve a round silhouette in every pose.
        mesh.segmentCount = name.contains("eye") || name.contains("nose") ? 56 : 88
        let n = SCNNode(geometry: mesh)
        n.name = name
        n.geometry?.materials = [mat(color, roughness: roughness)]
        n.scale = scale
        n.position = pos
        parent.addChildNode(n)
        return n
    }

    @discardableResult
    private func capsule(_ name: String, _ color: UIColor,
                         radius: CGFloat, height: CGFloat,
                         at pos: SCNVector3, parent: SCNNode) -> SCNNode {
        let mesh = SCNCapsule(capRadius: radius, height: height)
        mesh.radialSegmentCount = 64
        let n = SCNNode(geometry: mesh)
        n.name = name
        n.geometry?.materials = [mat(color)]
        n.position = pos
        parent.addChildNode(n)
        return n
    }

    @discardableResult
    private func bar(_ name: String, color: UIColor, width: CGFloat, height: CGFloat,
                     length: CGFloat, at pos: SCNVector3, parent: SCNNode) -> SCNNode {
        let geometry = SCNBox(width: width, height: height,
                              length: length, chamferRadius: min(width, height, length) * 0.35)
        geometry.chamferSegmentCount = 8
        let n = SCNNode(geometry: geometry)
        n.name = name
        n.geometry?.materials = [mat(color)]
        n.position = pos
        parent.addChildNode(n)
        return n
    }

    private func buildLightsAndCamera() {
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 3.35
        camera.zNear = 0.05
        camera.zFar = 60
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0.13, 1.23, 7.4)
        let target = SCNNode()
        target.position = SCNVector3(0, 1.18, 0)
        scene.rootNode.addChildNode(target)
        cameraNode.constraints = [SCNLookAtConstraint(target: target)]
        scene.rootNode.addChildNode(cameraNode)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.color = UIColor(white: 0.89, alpha: 1)
        scene.rootNode.addChildNode(fill)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = UIColor(white: 0.95, alpha: 1)
        key.eulerAngles = SCNVector3(-0.65, -0.4, -0.2)
        scene.rootNode.addChildNode(key)

        let ground = SCNNode(geometry: SCNPlane(width: 3.45, height: 1.45))
        ground.geometry?.firstMaterial = mat(UIColor(red: 0.49, green: 0.41, blue: 0.32, alpha: 0.085))
        ground.eulerAngles.x = -.pi / 2
        ground.position = SCNVector3(0, 0.015, 0)
        ground.name = "floor-shadow"
        scene.rootNode.addChildNode(ground)
    }

    private func buildDog() {
        dog.name = "feli-dog"
        dog.position = SCNVector3(-0.22, 0, 0)
        scene.rootNode.addChildNode(dog)

        body.position = SCNVector3(0, 0, 0)
        dog.addChildNode(body)
        sphere("lemon-torso", lemon, scale: SCNVector3(0.67, 0.87, 0.58),
               at: SCNVector3(0, 0.96, -0.18), parent: body)
        sphere("white-chest", cream, scale: SCNVector3(0.46, 0.73, 0.24),
               at: SCNVector3(0, 0.91, 0.35), parent: body)
        sphere("belly", cream, scale: SCNVector3(0.38, 0.26, 0.32),
               at: SCNVector3(0, 0.40, 0.03), parent: body)
        bar("orange-harness-horizontal", color: orange,
            width: 0.95, height: 0.11, length: 0.16,
            at: SCNVector3(0, 1.01, 0.50), parent: body)
        bar("orange-harness-vertical", color: orange,
            width: 0.13, height: 0.74, length: 0.14,
            at: SCNVector3(0, 0.79, 0.54), parent: body)
        sphere("harness-buckle", UIColor.white, scale: SCNVector3(0.045, 0.045, 0.025),
               at: SCNVector3(0, 1.01, 0.64), parent: body)

        for (node, left) in [(leftLeg, true), (rightLeg, false)] {
            node.name = left ? "front-left-paw" : "front-right-paw"
            node.position = SCNVector3(left ? -0.39 : 0.39, 0.76, 0.30)
            dog.addChildNode(node)
            capsule("foreleg", cream, radius: 0.18, height: 0.86,
                    at: SCNVector3(0, -0.37, 0), parent: node)
            sphere("white-paw", cream, scale: SCNVector3(0.245, 0.14, 0.28),
                   at: SCNVector3(0, -0.69, 0.14), parent: node)
            for index in -1...1 {
                sphere("paw-toe", UIColor(red: 0.91, green: 0.85, blue: 0.77, alpha: 1),
                       scale: SCNVector3(0.026, 0.016, 0.015),
                       at: SCNVector3(Float(index) * 0.07, -0.76, 0.36), parent: node)
            }
        }
        for (node, left) in [(leftBackLeg, true), (rightBackLeg, false)] {
            node.name = left ? "back-left-paw" : "back-right-paw"
            node.position = SCNVector3(left ? -0.46 : 0.46, 0.54, -0.43)
            dog.addChildNode(node)
            sphere("lemon-thigh", lemon, scale: SCNVector3(0.29, 0.43, 0.31),
                   at: SCNVector3(0, -0.13, 0), parent: node)
            sphere("white-back-paw", cream, scale: SCNVector3(0.24, 0.14, 0.25),
                   at: SCNVector3(0, -0.39, 0.25), parent: node)
        }

        tail.name = "tail-pivot"
        tail.position = SCNVector3(0.42, 1.16, -0.63)
        dog.addChildNode(tail)
        let tailBase = capsule("tail-lemon", lemon, radius: 0.115, height: 0.68,
                               at: SCNVector3(0.18, 0.22, -0.07), parent: tail)
        tailBase.eulerAngles.z = -0.48
        sphere("tail-white-tip", cream, scale: SCNVector3(0.13, 0.18, 0.13),
               at: SCNVector3(0.30, 0.51, -0.07), parent: tail)

        head.name = "head-pivot"
        head.position = SCNVector3(0, 1.53, 0.30)
        dog.addChildNode(head)
        sphere("lemon-head", lemon, scale: SCNVector3(0.72, 0.67, 0.57),
               at: SCNVector3(0, 0.23, 0.06), parent: head)
        // Cream blaze travels from forehead into muzzle, like lemon beagle.
        sphere("forehead-blaze", cream, scale: SCNVector3(0.16, 0.48, 0.09),
               at: SCNVector3(0, 0.32, 0.626), parent: head)
        sphere("between-eyes", cream, scale: SCNVector3(0.22, 0.27, 0.10),
               at: SCNVector3(0, 0.09, 0.63), parent: head)

        makeEar(leftEar, left: true)
        makeEar(rightEar, left: false)

        for (node, left) in [(leftEye, true), (rightEye, false)] {
            node.name = left ? "left-eye" : "right-eye"
            node.position = SCNVector3(left ? -0.28 : 0.28, 0.33, 0.59)
            head.addChildNode(node)
            sphere("dark-eye", noseBlack, scale: SCNVector3(0.095, 0.13, 0.057),
                   at: SCNVector3(0, 0, 0), parent: node, roughness: 0.21)
            sphere("eye-glint", .white, scale: SCNVector3(0.021, 0.028, 0.016),
                   at: SCNVector3(-0.027, 0.042, 0.052), parent: node, roughness: 0.17)
        }

        sphere("left-cream-jowl", cream, scale: SCNVector3(0.34, 0.27, 0.24),
               at: SCNVector3(-0.225, -0.12, 0.54), parent: head)
        sphere("right-cream-jowl", cream, scale: SCNVector3(0.34, 0.27, 0.24),
               at: SCNVector3(0.225, -0.12, 0.54), parent: head)
        sphere("protruding-white-muzzle", cream, scale: SCNVector3(0.36, 0.25, 0.29),
               at: SCNVector3(0, -0.19, 0.72), parent: head)
        nose.name = "nose"
        head.addChildNode(nose)
        nose.position = SCNVector3(0, -0.13, 0.98)
        let noseMesh = SCNSphere(radius: 1)
        noseMesh.segmentCount = 64
        let black = SCNNode(geometry: noseMesh)
        black.scale = SCNVector3(0.145, 0.09, 0.075)
        black.geometry?.firstMaterial = mat(noseBlack, roughness: 0.27)
        black.name = "soft-black-nose"
        nose.addChildNode(black)

        jaw.name = "jaw-mouth"
        jaw.position = SCNVector3(0, -0.35, 0.73)
        head.addChildNode(jaw)
        sphere("inside-mouth", noseBlack,
               scale: SCNVector3(0.21, 0.12, 0.08),
               at: SCNVector3(0, -0.06, 0.05), parent: jaw)
        sphere("cream-lower-jaw", cream,
               scale: SCNVector3(0.29, 0.10, 0.18),
               at: SCNVector3(0, -0.14, 0), parent: jaw)
        tongue.name = "pink-tongue"
        jaw.addChildNode(tongue)
        sphere("tongue-shape", UIColor(red: 0.94, green: 0.39, blue: 0.43, alpha: 1),
               scale: SCNVector3(0.105, 0.17, 0.055),
               at: SCNVector3(0, -0.11, 0.14), parent: tongue)
    }

    private func makeEar(_ pivot: SCNNode, left: Bool) {
        pivot.name = left ? "left-ear" : "right-ear"
        pivot.position = SCNVector3(left ? -0.58 : 0.58, 0.52, 0.25)
        head.addChildNode(pivot)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: -0.29, y: -0.19),
                      controlPoint1: CGPoint(x: -0.12, y: 0.10),
                      controlPoint2: CGPoint(x: -0.27, y: -0.03))
        path.addCurve(to: CGPoint(x: -0.36, y: -0.75),
                      controlPoint1: CGPoint(x: -0.38, y: -0.31),
                      controlPoint2: CGPoint(x: -0.46, y: -0.63))
        path.addCurve(to: CGPoint(x: -0.08, y: -0.99),
                      controlPoint1: CGPoint(x: -0.27, y: -0.95),
                      controlPoint2: CGPoint(x: -0.14, y: -1.02))
        path.addCurve(to: CGPoint(x: 0.12, y: -0.72),
                      controlPoint1: CGPoint(x: 0.12, y: -0.96),
                      controlPoint2: CGPoint(x: 0.14, y: -0.80))
        path.addCurve(to: CGPoint(x: 0, y: 0),
                      controlPoint1: CGPoint(x: 0.21, y: -0.30),
                      controlPoint2: CGPoint(x: 0.13, y: -0.06))
        path.close()
        let earGeometry = SCNShape(path: path, extrusionDepth: 0.14)
        earGeometry.chamferRadius = 0.043
        let outer = SCNNode(geometry: earGeometry)
        outer.name = "floppy-lemon-beagle-ear"
        outer.geometry?.firstMaterial = mat(earGold, roughness: 0.92)
        outer.scale.x = left ? 1 : -1
        pivot.addChildNode(outer)
        sphere("ear-soft-tip", warmLemon, scale: SCNVector3(0.18, 0.12, 0.10),
               at: SCNVector3(left ? -0.19 : 0.19, -0.84, 0.06), parent: pivot)
    }

    private func buildMate() {
        mate.name = "mate-cup-prop"
        mate.position = SCNVector3(0.88, 0, 0.45)
        scene.rootNode.addChildNode(mate)
        let cupGeometry = SCNCylinder(radius: 0.23, height: 0.36)
        cupGeometry.radialSegmentCount = 48
        let cup = SCNNode(geometry: cupGeometry)
        cup.name = "mate-gourd"
        cup.geometry?.firstMaterial = mat(UIColor(red: 0.39, green: 0.22, blue: 0.13, alpha: 1))
        cup.position = SCNVector3(0, 0.20, 0)
        mate.addChildNode(cup)
        let leavesGeometry = SCNCylinder(radius: 0.211, height: 0.02)
        leavesGeometry.radialSegmentCount = 48
        let leaves = SCNNode(geometry: leavesGeometry)
        leaves.geometry?.firstMaterial = mat(UIColor(red: 0.28, green: 0.45, blue: 0.15, alpha: 1))
        leaves.position = SCNVector3(0, 0.385, 0)
        mate.addChildNode(leaves)
        let bombilla = SCNNode(geometry: SCNCylinder(radius: 0.028, height: 0.57))
        bombilla.name = "silver-bombilla"
        bombilla.geometry?.firstMaterial = mat(UIColor(white: 0.80, alpha: 1), roughness: 0.3)
        bombilla.position = SCNVector3(0.10, 0.58, 0)
        bombilla.eulerAngles.z = -0.30
        mate.addChildNode(bombilla)
    }

    private func buildGrill() {
        grill.name = "vacio-parrilla"
        grill.position = SCNVector3(1.05, 0, 0.16)
        scene.rootNode.addChildNode(grill)
        for x in [-0.44, 0.44] as [Float] {
            bar("grill-leg", color: UIColor.darkGray, width: 0.09, height: 0.68, length: 0.09,
                at: SCNVector3(x, 0.35, 0), parent: grill)
        }
        bar("charcoal-pan", color: UIColor(red: 0.23, green: 0.25, blue: 0.25, alpha: 1),
            width: 1.13, height: 0.16, length: 0.65,
            at: SCNVector3(0, 0.45, 0), parent: grill)
        for i in 0..<9 {
            bar("grill-iron-bar", color: UIColor(white: 0.23, alpha: 1),
                width: 0.035, height: 0.035, length: 0.72,
                at: SCNVector3(Float(i) * 0.11 - 0.44, 0.67, 0), parent: grill)
        }
        // An original irregular 3D mesh of a long cut of vacio, not a steak emoji.
        let steakPath = UIBezierPath()
        steakPath.move(to: CGPoint(x: -0.45, y: -0.12))
        steakPath.addCurve(to: CGPoint(x: 0.13, y: -0.16),
                           controlPoint1: CGPoint(x: -0.27, y: -0.22),
                           controlPoint2: CGPoint(x: -0.03, y: -0.24))
        steakPath.addCurve(to: CGPoint(x: 0.48, y: 0.08),
                           controlPoint1: CGPoint(x: 0.42, y: -0.20),
                           controlPoint2: CGPoint(x: 0.52, y: -0.06))
        steakPath.addCurve(to: CGPoint(x: 0.13, y: 0.20),
                           controlPoint1: CGPoint(x: 0.39, y: 0.23),
                           controlPoint2: CGPoint(x: 0.29, y: 0.18))
        steakPath.addCurve(to: CGPoint(x: -0.45, y: -0.12),
                           controlPoint1: CGPoint(x: -0.16, y: 0.11),
                           controlPoint2: CGPoint(x: -0.45, y: 0.09))
        steakPath.close()
        let vacio = SCNNode(geometry: SCNShape(path: steakPath, extrusionDepth: 0.085))
        vacio.geometry?.materials = [mat(UIColor(red: 0.58, green: 0.23, blue: 0.11, alpha: 1)),
                                     mat(UIColor(red: 0.94, green: 0.69, blue: 0.46, alpha: 1))]
        vacio.name = "vacio-original-cut"
        vacio.eulerAngles.x = -.pi / 2
        vacio.eulerAngles.z = 0.16
        vacio.position = SCNVector3(0, 0.735, 0)
        grill.addChildNode(vacio)

        for i in 0..<5 {
            let flame = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.052, height: 0.15))
            flame.name = "animated-ember-flame"
            flame.geometry?.firstMaterial = mat(i.isMultiple(of: 2) ? .orange : .yellow)
            flame.position = SCNVector3(Float(i) * 0.19 - 0.38, 0.36, Float(i % 2) * 0.12)
            grill.addChildNode(flame)
            flames.append(flame)
        }
        for i in 0..<4 {
            let puff = sphere("animated-grill-smoke", UIColor(white: 0.69, alpha: 0.55),
                              scale: SCNVector3(0.065, 0.085, 0.05),
                              at: SCNVector3(Float(i) * 0.19 - 0.28, 0.92, 0),
                              parent: grill)
            steam.append(puff)
        }
    }

    private func buildSparkle() {
        sparkle.name = "feli-celebration-spark"
        sparkle.position = SCNVector3(1.0, 2.27, 0.3)
        scene.rootNode.addChildNode(sparkle)
        for i in 0..<5 {
            let n = SCNNode(geometry: SCNSphere(radius: 0.042))
            n.geometry?.firstMaterial = mat(i.isMultiple(of: 2) ? .systemYellow : .systemOrange)
            n.position = SCNVector3(sin(Float(i) * 1.2) * 0.36,
                                    cos(Float(i) * 1.1) * 0.28, 0)
            sparkle.addChildNode(n)
        }
    }

    private func buildButterflyAndClock() {
        butterfly.name = "calm-3d-butterfly"
        butterfly.position = SCNVector3(0.98, 1.95, 0.38)
        scene.rootNode.addChildNode(butterfly)
        let wingPink = UIColor(red: 1.00, green: 0.63, blue: 0.25, alpha: 1)
        let wingOrange = UIColor(red: 0.95, green: 0.43, blue: 0.11, alpha: 1)
        for side in [Float(-1), Float(1)] {
            let wing = sphere("butterfly-wing", side == -1 ? wingPink : wingOrange,
                              scale: SCNVector3(0.15, 0.21, 0.033),
                              at: SCNVector3(side * 0.13, 0.06, 0), parent: butterfly)
            wing.eulerAngles.z = side * -0.40
        }
        capsule("butterfly-body", UIColor(red: 0.36, green: 0.22, blue: 0.17, alpha: 1),
                radius: 0.035, height: 0.25, at: SCNVector3(0, 0, 0.07), parent: butterfly)

        littleClock.name = "attentive-3d-clock"
        littleClock.position = SCNVector3(1.00, 1.78, 0.2)
        scene.rootNode.addChildNode(littleClock)
        let dial = SCNNode(geometry: SCNCylinder(radius: 0.23, height: 0.060))
        dial.geometry?.firstMaterial = mat(UIColor.white)
        dial.eulerAngles.x = .pi / 2
        dial.name = "clock-face"
        littleClock.addChildNode(dial)
        let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.225, pipeRadius: 0.035))
        rim.geometry?.firstMaterial = mat(UIColor(red: 0.96, green: 0.47, blue: 0.06, alpha: 1))
        rim.eulerAngles.x = .pi / 2
        rim.position.z = 0.045
        littleClock.addChildNode(rim)
        clockHand.name = "animated-clock-hand"
        bar("hand", color: UIColor.darkGray,
            width: 0.023, height: 0.16, length: 0.025,
            at: SCNVector3(0, 0.075, 0.076), parent: clockHand)
        clockHand.position.z = 0.02
        littleClock.addChildNode(clockHand)
    }

    func setAccessories(for mood: FeliMood) {
        mate.isHidden = mood != .mate
        grill.isHidden = mood != .grill && mood != .celebrate
        sparkle.isHidden = mood != .celebrate
        butterfly.isHidden = mood != .calm
        littleClock.isHidden = mood != .worried
    }
}
