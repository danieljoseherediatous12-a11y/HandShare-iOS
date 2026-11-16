import Foundation
import UIKit

@MainActor
final class HapticEngine {
    static let shared = HapticEngine()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notif = UINotificationFeedbackGenerator()

    private init() {
        prepare()
    }

    func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        notif.prepare()
    }

    func handDetected() {
        lightImpact.impactOccurred(intensity: 0.72)
        lightImpact.prepare()
    }

    func grabSuccess() {
        heavyImpact.impactOccurred(intensity: 1.0)
        heavyImpact.prepare()
    }

    func teleportSuccess() {
        notif.notificationOccurred(.success)
        notif.prepare()
    }

    func subtleTap() {
        mediumImpact.impactOccurred(intensity: 0.55)
        mediumImpact.prepare()
    }
}
