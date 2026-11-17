import Foundation
import UIKit

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let hasCompletedOnboarding = "hs_onboarding_done"
        static let deviceName = "hs_device_name"
        static let gestureSensitivity = "hs_gesture_sensitivity"
        static let edgeGlowEnabled = "hs_edge_glow_enabled"
        static let autoOpenReceivedMedia = "hs_auto_open_received"
        static let sentCount = "hs_sent_count"
        static let receivedCount = "hs_received_count"
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    @Published var deviceName: String {
        didSet { defaults.set(deviceName, forKey: Keys.deviceName) }
    }

    /// 0 = Rápida, 1 = Equilibrada, 2 = Precisa
    @Published var gestureSensitivity: Int {
        didSet { defaults.set(gestureSensitivity, forKey: Keys.gestureSensitivity) }
    }

    @Published var edgeGlowEnabled: Bool {
        didSet { defaults.set(edgeGlowEnabled, forKey: Keys.edgeGlowEnabled) }
    }

    @Published var autoOpenReceivedMedia: Bool {
        didSet { defaults.set(autoOpenReceivedMedia, forKey: Keys.autoOpenReceivedMedia) }
    }

    @Published var sentCount: Int {
        didSet { defaults.set(sentCount, forKey: Keys.sentCount) }
    }

    @Published var receivedCount: Int {
        didSet { defaults.set(receivedCount, forKey: Keys.receivedCount) }
    }

    private init() {
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        let storedName = defaults.string(forKey: Keys.deviceName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedName, !storedName.isEmpty {
            self.deviceName = storedName
        } else {
            let modelName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
            self.deviceName = modelName.isEmpty ? "iPhone" : modelName
        }

        if defaults.object(forKey: Keys.gestureSensitivity) != nil {
            self.gestureSensitivity = defaults.integer(forKey: Keys.gestureSensitivity)
        } else {
            self.gestureSensitivity = 1
        }

        if defaults.object(forKey: Keys.edgeGlowEnabled) != nil {
            self.edgeGlowEnabled = defaults.bool(forKey: Keys.edgeGlowEnabled)
        } else {
            self.edgeGlowEnabled = true
        }

        if defaults.object(forKey: Keys.autoOpenReceivedMedia) != nil {
            self.autoOpenReceivedMedia = defaults.bool(forKey: Keys.autoOpenReceivedMedia)
        } else {
            self.autoOpenReceivedMedia = true
        }

        self.sentCount = defaults.integer(forKey: Keys.sentCount)
        self.receivedCount = defaults.integer(forKey: Keys.receivedCount)
    }
}
