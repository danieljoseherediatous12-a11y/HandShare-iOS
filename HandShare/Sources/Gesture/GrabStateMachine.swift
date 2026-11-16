import Foundation

public enum DetectedGesture: String, Sendable {
    case grab
    case release
    case ok
}

public enum GrabStep: String, Sendable {
    case waitingForOpenPalm
    case waitingForClosedFist
    case completed
    case released
}

public enum GestureState: Equatable, Sendable {
    case idle
    case detecting(gestureName: String, holdProgress: Float)
    case handOpen
    case grabbed
    case released
    case okSign
    case error(String)
}

public final class GrabStateMachine: @unchecked Sendable {
    public enum HapticKind: Equatable, Sendable {
        case handDetected
        case grabSuccess
        case teleportSuccess
    }

    public struct FrameDecision: Equatable, Sendable {
        public let state: GestureState
        public let detectedGesture: DetectedGesture?
        public let grabSequenceId: Int64
        public let grabTriggered: Bool
        public let haptic: HapticKind?
        public let logEvent: String?
    }

    public static let postGrabCooldownMs: Int64 = 600
    public static let fistWaitTimeoutMs: Int64 = 4500
    public static let strictFistWindowMs: Int64 = 4000
    public static let fistConfirmFrames = 1
    public static let strictFistFrames = 1

    private let lock = NSLock()
    private var grabStep: GrabStep = .waitingForOpenPalm
    private var palmDetectedStartTime: Int64 = 0
    private var openPalmConfirmedTime: Int64 = 0
    private var lastOpenPalmSeenMs: Int64 = 0
    private var missedTrackingFrames = 0
    private var consecutiveFistFrames = 0
    private var consecutiveOpenFrames = 0
    private var consecutiveOkFrames = 0
    private var consecutiveNonFistFrames = 0
    private var lastGrabTime: Int64 = 0
    private var lastGrabSequenceId: Int64 = 0
    private var requireReleaseBeforeDirectFist = false
    private var lastFrameWasFist = false
    private var currentState: GestureState = .idle

    public init() {}

    public func currentStep() -> GrabStep {
        lock.lock(); defer { lock.unlock() }
        return grabStep
    }

    public func currentGrabSequenceId() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return lastGrabSequenceId
    }

    public func onFrame(
        isOpenPalm: Bool,
        isFist: Bool,
        isOkSign: Bool,
        strictIntentMode: Bool,
        sensitivity: Int,
        nowMs: Int64
    ) -> FrameDecision {
        lock.lock(); defer { lock.unlock() }

        missedTrackingFrames = 0
        lastFrameWasFist = isFist

        if !isFist {
            consecutiveNonFistFrames += 1
            if isOpenPalm || consecutiveNonFistFrames >= 2 {
                requireReleaseBeforeDirectFist = false
            }
        } else {
            consecutiveNonFistFrames = 0
        }

        if isOkSign {
            consecutiveOkFrames += 1
            if consecutiveOkFrames >= 2 {
                consecutiveOkFrames = 0
                currentState = .okSign
                return FrameDecision(
                    state: currentState,
                    detectedGesture: .ok,
                    grabSequenceId: lastGrabSequenceId,
                    grabTriggered: false,
                    haptic: .teleportSuccess,
                    logEvent: "OK_SIGN"
                )
            }
        } else {
            consecutiveOkFrames = 0
        }

        let palmHoldMs: Int64 = if strictIntentMode {
            switch sensitivity {
            case 0: 0
            case 2: 60
            default: 25
            }
        } else {
            switch sensitivity {
            case 2: 35
            default: 0
            }
        }

        let fistConfirmFrames: Int = if strictIntentMode {
            sensitivity == 2 ? (Self.strictFistFrames + 1) : Self.strictFistFrames
        } else {
            switch sensitivity {
            case 0: 1
            case 2: 2
            default: Self.fistConfirmFrames
            }
        }

        let directFistFrames: Int = switch sensitivity {
        case 0: 1
        case 2: 3
        default: 2
        }

        let waitWindowMs = strictIntentMode ? Self.strictFistWindowMs : Self.fistWaitTimeoutMs

        switch grabStep {
        case .waitingForOpenPalm:
            if isOpenPalm {
                lastOpenPalmSeenMs = nowMs
                consecutiveFistFrames = 0
                requireReleaseBeforeDirectFist = false

                if palmDetectedStartTime == 0 {
                    palmDetectedStartTime = nowMs
                }
                let held = max(0, nowMs - palmDetectedStartTime)
                if held >= palmHoldMs {
                    grabStep = .waitingForClosedFist
                    openPalmConfirmedTime = nowMs
                    palmDetectedStartTime = 0
                    consecutiveFistFrames = 0
                    currentState = .handOpen
                    return FrameDecision(
                        state: currentState,
                        detectedGesture: nil,
                        grabSequenceId: lastGrabSequenceId,
                        grabTriggered: false,
                        haptic: .handDetected,
                        logEvent: "STEP1_OPEN_PALM_CONFIRMED"
                    )
                } else {
                    let progress = palmHoldMs <= 0 ? 1.0 : min(1.0, max(0.2, Float(held) / Float(palmHoldMs)))
                    currentState = .detecting(gestureName: "Open_Palm", holdProgress: progress)
                    return FrameDecision(
                        state: currentState,
                        detectedGesture: nil,
                        grabSequenceId: lastGrabSequenceId,
                        grabTriggered: false,
                        haptic: nil,
                        logEvent: nil
                    )
                }
            } else if isFist {
                palmDetectedStartTime = 0
                let inCooldown = lastGrabTime > 0 && (nowMs - lastGrabTime) < Self.postGrabCooldownMs
                if requireReleaseBeforeDirectFist || inCooldown {
                    currentState = .idle
                    return FrameDecision(
                        state: currentState,
                        detectedGesture: nil,
                        grabSequenceId: lastGrabSequenceId,
                        grabTriggered: false,
                        haptic: nil,
                        logEvent: nil
                    )
                }
                consecutiveFistFrames += 1
                let neededFrames = (lastOpenPalmSeenMs > 0 && nowMs - lastOpenPalmSeenMs <= 350) ? 1 : directFistFrames
                if consecutiveFistFrames >= neededFrames {
                    grabStep = .completed
                    lastGrabTime = nowMs
                    lastGrabSequenceId += 1
                    requireReleaseBeforeDirectFist = true
                    consecutiveFistFrames = 0
                    consecutiveOpenFrames = 0
                    currentState = .grabbed
                    return FrameDecision(
                        state: currentState,
                        detectedGesture: .grab,
                        grabSequenceId: lastGrabSequenceId,
                        grabTriggered: true,
                        haptic: .grabSuccess,
                        logEvent: "DIRECT_FIST_GRAB"
                    )
                }
                return FrameDecision(
                    state: currentState,
                    detectedGesture: nil,
                    grabSequenceId: lastGrabSequenceId,
                    grabTriggered: false,
                    haptic: nil,
                    logEvent: nil
                )
            } else {
                palmDetectedStartTime = 0
                if consecutiveFistFrames > 0 { consecutiveFistFrames -= 1 }
                if currentState != .grabbed {
                    currentState = .idle
                }
                return FrameDecision(
                    state: currentState,
                    detectedGesture: nil,
                    grabSequenceId: lastGrabSequenceId,
                    grabTriggered: false,
                    haptic: nil,
                    logEvent: nil
                )
            }

        case .waitingForClosedFist:
            if !isFist && (nowMs - openPalmConfirmedTime > waitWindowMs) {
                grabStep = .waitingForOpenPalm
                consecutiveFistFrames = 0
                currentState = .idle
                return FrameDecision(
                    state: currentState,
                    detectedGesture: nil,
                    grabSequenceId: lastGrabSequenceId,
                    grabTriggered: false,
                    haptic: nil,
                    logEvent: "FIST_WAIT_TIMEOUT"
                )
            }
            if isFist {
                consecutiveFistFrames += 1
                if consecutiveFistFrames >= fistConfirmFrames {
                    grabStep = .completed
                    lastGrabTime = nowMs
                    lastGrabSequenceId += 1
                    requireReleaseBeforeDirectFist = true
                    consecutiveFistFrames = 0
                    consecutiveOpenFrames = 0
                    currentState = .grabbed
                    return FrameDecision(
                        state: currentState,
                        detectedGesture: .grab,
                        grabSequenceId: lastGrabSequenceId,
                        grabTriggered: true,
                        haptic: .grabSuccess,
                        logEvent: "STEP2_FIST_GRAB"
                    )
                }
                return FrameDecision(
                    state: currentState,
                    detectedGesture: nil,
                    grabSequenceId: lastGrabSequenceId,
                    grabTriggered: false,
                    haptic: nil,
                    logEvent: "FIST_FRAME:\(consecutiveFistFrames)/\(fistConfirmFrames)"
                )
            } else {
                if isOpenPalm {
                    lastOpenPalmSeenMs = nowMs
                }
                if consecutiveFistFrames > 0 { consecutiveFistFrames -= 1 }
                currentState = .handOpen
                return FrameDecision(
                    state: currentState,
                    detectedGesture: nil,
                    grabSequenceId: lastGrabSequenceId,
                    grabTriggered: false,
                    haptic: nil,
                    logEvent: nil
                )
            }

        case .completed:
            if isOpenPalm {
                consecutiveOpenFrames += 1
                lastOpenPalmSeenMs = nowMs
                requireReleaseBeforeDirectFist = false
                if consecutiveOpenFrames >= 2 {
                    consecutiveOpenFrames = 0
                    if strictIntentMode {
                        grabStep = .waitingForClosedFist
                        openPalmConfirmedTime = nowMs
                        consecutiveFistFrames = 0
                        currentState = .handOpen
                        return FrameDecision(
                            state: currentState,
                            detectedGesture: nil,
                            grabSequenceId: lastGrabSequenceId,
                            grabTriggered: false,
                            haptic: .handDetected,
                            logEvent: "SENDER_PALM_REARMED"
                        )
                    } else {
                        grabStep = .released
                        currentState = .released
                        return FrameDecision(
                            state: currentState,
                            detectedGesture: .release,
                            grabSequenceId: lastGrabSequenceId,
                            grabTriggered: false,
                            haptic: .teleportSuccess,
                            logEvent: "RECEIVER_RELEASE"
                        )
                    }
                }
                return FrameDecision(
                    state: currentState,
                    detectedGesture: nil,
                    grabSequenceId: lastGrabSequenceId,
                    grabTriggered: false,
                    haptic: nil,
                    logEvent: nil
                )
            } else {
                if consecutiveOpenFrames > 0 { consecutiveOpenFrames -= 1 }
                currentState = .grabbed
                return FrameDecision(
                    state: currentState,
                    detectedGesture: nil,
                    grabSequenceId: lastGrabSequenceId,
                    grabTriggered: false,
                    haptic: nil,
                    logEvent: nil
                )
            }

        case .released:
            grabStep = .waitingForOpenPalm
            currentState = .idle
            return FrameDecision(
                state: currentState,
                detectedGesture: nil,
                grabSequenceId: lastGrabSequenceId,
                grabTriggered: false,
                haptic: nil,
                logEvent: nil
            )
        }
    }

    public func onTrackingLost(strictIntentMode: Bool, nowMs: Int64) -> GestureState {
        lock.lock(); defer { lock.unlock() }
        missedTrackingFrames += 1
        if missedTrackingFrames <= 2 {
            return currentState
        }
        palmDetectedStartTime = 0
        consecutiveFistFrames = 0
        consecutiveOpenFrames = 0
        consecutiveOkFrames = 0
        consecutiveNonFistFrames = 0
        requireReleaseBeforeDirectFist = false
        lastFrameWasFist = false

        if grabStep == .completed {
            grabStep = .waitingForOpenPalm
            currentState = .idle
            return currentState
        }

        if grabStep == .waitingForClosedFist {
            let window = strictIntentMode ? Self.strictFistWindowMs : Self.fistWaitTimeoutMs
            if nowMs - openPalmConfirmedTime > window {
                grabStep = .waitingForOpenPalm
                currentState = .idle
            }
            return currentState
        }

        currentState = .idle
        return currentState
    }

    @discardableResult
    public func reset(preserveSustainedFistGuard: Bool = true) -> GestureState {
        lock.lock(); defer { lock.unlock() }
        grabStep = .waitingForOpenPalm
        palmDetectedStartTime = 0
        openPalmConfirmedTime = 0
        lastOpenPalmSeenMs = 0
        missedTrackingFrames = 0
        consecutiveFistFrames = 0
        consecutiveOpenFrames = 0
        consecutiveOkFrames = 0
        consecutiveNonFistFrames = 0
        if !preserveSustainedFistGuard {
            lastGrabTime = 0
            requireReleaseBeforeDirectFist = false
            lastFrameWasFist = false
        } else {
            requireReleaseBeforeDirectFist = requireReleaseBeforeDirectFist || lastFrameWasFist
        }
        currentState = .idle
        return currentState
    }

    @discardableResult
    public func rearmIfStillCompleted(grabSequenceId: Int64) -> GestureState? {
        lock.lock(); defer { lock.unlock() }
        guard lastGrabSequenceId == grabSequenceId, grabStep == .completed else {
            return nil
        }
        grabStep = .waitingForOpenPalm
        palmDetectedStartTime = 0
        openPalmConfirmedTime = 0
        consecutiveFistFrames = 0
        consecutiveOpenFrames = 0
        consecutiveOkFrames = 0
        consecutiveNonFistFrames = 0
        requireReleaseBeforeDirectFist = requireReleaseBeforeDirectFist || lastFrameWasFist
        currentState = .idle
        return currentState
    }
}
