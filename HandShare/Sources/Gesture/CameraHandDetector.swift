import AVFoundation
import Combine
import Foundation
import Vision

@MainActor
final class CameraHandDetector: NSObject, ObservableObject {
    @Published private(set) var gestureState: GestureState = .idle
    @Published private(set) var handVisible: Bool = false
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var cameraPermissionGranted: Bool = false
    @Published private(set) var cameraUnavailableReason: String?

    let grabEvents = PassthroughSubject<Int64, Never>()

    private nonisolated let stateMachine = GrabStateMachine()
    private nonisolated let session = AVCaptureSession()
    private nonisolated let sessionQueue = DispatchQueue(label: "com.handshare.camera.session")
    private nonisolated let outputQueue = DispatchQueue(label: "com.handshare.camera.vision")
    private nonisolated let handPoseRequest: VNDetectHumanHandPoseRequest = {
        let req = VNDetectHumanHandPoseRequest()
        req.maximumHandCount = 1
        return req
    }()

    private nonisolated(unsafe) var isProcessingFrame = false
    private nonisolated(unsafe) var isConfigured = false
    private nonisolated(unsafe) var strictModeStorage = true
    private nonisolated(unsafe) var sensitivityStorage = 1
    private var simAutoResetTask: Task<Void, Never>?

    var strictIntentMode: Bool = true {
        didSet { strictModeStorage = strictIntentMode }
    }

    var sensitivity: Int = 1 {
        didSet { sensitivityStorage = sensitivity }
    }

    var previewSession: AVCaptureSession { session }

    override init() {
        super.init()
        refreshPermissionStatus()
    }

    func refreshPermissionStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermissionGranted = (status == .authorized)
    }

    func requestPermissionAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            cameraPermissionGranted = true
            start()
            return
        }
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermissionGranted = granted
            if granted {
                start()
            } else {
                cameraUnavailableReason = "Permiso de cámara denegado"
            }
            return
        }
        cameraPermissionGranted = false
        cameraUnavailableReason = "Activa el permiso de Cámara en Ajustes de iOS"
    }

    func start() {
        #if targetEnvironment(simulator)
        isRunning = true
        cameraUnavailableReason = "Simulador iOS: usa los botones de prueba de gestos"
        return
        #else
        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        guard auth == .authorized else {
            cameraPermissionGranted = false
            cameraUnavailableReason = "Permiso de cámara requerido"
            return
        }
        cameraPermissionGranted = true
        cameraUnavailableReason = nil
        isRunning = true

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if self.isConfigured && !self.session.isRunning {
                self.session.startRunning()
            }
        }
        #endif
    }

    func stop() {
        simAutoResetTask?.cancel()
        simAutoResetTask = nil
        isRunning = false
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        #endif
        resetGrabStateMachine(preserveSustainedFistGuard: false)
        handVisible = false
    }

    func resetGrabStateMachine(preserveSustainedFistGuard: Bool = true) {
        let next = stateMachine.reset(preserveSustainedFistGuard: preserveSustainedFistGuard)
        gestureState = next
    }

    func rearmIfStillCompleted(_ seqId: Int64) {
        if let next = stateMachine.rearmIfStillCompleted(grabSequenceId: seqId) {
            gestureState = next
        }
    }

    // MARK: - Simulator / Manual Test Hooks

    func simulateOpenPalm() {
        simAutoResetTask?.cancel()
        handVisible = true
        let now = Self.uptimeMs()
        _ = processGeometry(isOpenPalm: true, isFist: false, isOkSign: false, nowMs: now)
        _ = processGeometry(isOpenPalm: true, isFist: false, isOkSign: false, nowMs: now + 70)
    }

    func simulateFistGrab() {
        simAutoResetTask?.cancel()
        handVisible = true
        let now = Self.uptimeMs()
        if stateMachine.currentStep() == .waitingForOpenPalm {
            _ = processGeometry(isOpenPalm: true, isFist: false, isOkSign: false, nowMs: now)
            _ = processGeometry(isOpenPalm: true, isFist: false, isOkSign: false, nowMs: now + 70)
        }
        _ = processGeometry(isOpenPalm: false, isFist: true, isOkSign: false, nowMs: now + 130)
        _ = processGeometry(isOpenPalm: false, isFist: true, isOkSign: false, nowMs: now + 180)
    }

    func simulateCatchRelease() {
        simAutoResetTask?.cancel()
        handVisible = true
        let now = Self.uptimeMs()
        _ = processGeometry(isOpenPalm: true, isFist: false, isOkSign: false, nowMs: now)
        _ = processGeometry(isOpenPalm: true, isFist: false, isOkSign: false, nowMs: now + 60)
    }

    func simulateOkSign() {
        simAutoResetTask?.cancel()
        handVisible = true
        let now = Self.uptimeMs()
        _ = processGeometry(isOpenPalm: false, isFist: false, isOkSign: true, nowMs: now)
        _ = processGeometry(isOpenPalm: false, isFist: false, isOkSign: true, nowMs: now + 60)
    }

    func simulateTrackingLost() {
        simAutoResetTask?.cancel()
        handVisible = false
        let now = Self.uptimeMs()
        _ = stateMachine.onTrackingLost(strictIntentMode: strictIntentMode, nowMs: now)
        _ = stateMachine.onTrackingLost(strictIntentMode: strictIntentMode, nowMs: now + 40)
        gestureState = stateMachine.onTrackingLost(strictIntentMode: strictIntentMode, nowMs: now + 80)
    }

    // MARK: - Private Camera Setup

    private nonisolated func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            Task { @MainActor [weak self] in
                self?.cameraUnavailableReason = "Cámara frontal no disponible"
            }
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
            if conn.isVideoMirroringSupported {
                conn.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
        isConfigured = true
    }

    private nonisolated func processGeometry(
        isOpenPalm: Bool,
        isFist: Bool,
        isOkSign: Bool,
        nowMs: Int64
    ) -> GrabStateMachine.FrameDecision {
        let decision = stateMachine.onFrame(
            isOpenPalm: isOpenPalm,
            isFist: isFist,
            isOkSign: isOkSign,
            strictIntentMode: strictModeStorage,
            sensitivity: sensitivityStorage,
            nowMs: nowMs
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.gestureState = decision.state
            if let haptic = decision.haptic {
                switch haptic {
                case .handDetected: HapticEngine.shared.handDetected()
                case .grabSuccess: HapticEngine.shared.grabSuccess()
                case .teleportSuccess: HapticEngine.shared.teleportSuccess()
                }
            }
            if decision.grabTriggered {
                self.grabEvents.send(decision.grabSequenceId)
            }
        }
        return decision
    }

    private nonisolated static func uptimeMs() -> Int64 {
        Int64(ProcessInfo.processInfo.systemUptime * 1000.0)
    }

    private nonisolated static func analyzeObservation(_ obs: VNHumanHandPoseObservation) -> (openPalm: Bool, fist: Bool, okSign: Bool)? {
        guard let pts = try? obs.recognizedPoints(.all) else { return nil }
        func p(_ name: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let pt = pts[name], pt.confidence >= 0.30 else { return nil }
            return pt.location
        }
        guard let wrist = p(.wrist),
              let indexMCP = p(.indexMCP), let indexPIP = p(.indexPIP), let indexTip = p(.indexTip),
              let middleMCP = p(.middleMCP), let middlePIP = p(.middlePIP), let middleTip = p(.middleTip),
              let ringMCP = p(.ringMCP), let ringPIP = p(.ringPIP), let ringTip = p(.ringTip),
              let littleMCP = p(.littleMCP), let littlePIP = p(.littlePIP), let littleTip = p(.littleTip) else {
            return nil
        }

        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            hypot(a.x - b.x, a.y - b.y)
        }

        let palmScale = max(dist(wrist, middleMCP), 0.01)
        guard palmScale >= 0.055 && palmScale <= 0.78 else { return nil }

        func isCurled(mcp: CGPoint, pip: CGPoint, tip: CGPoint) -> Bool {
            let tipToWrist = dist(tip, wrist)
            let pipToWrist = dist(pip, wrist)
            let tipToMcp = dist(tip, mcp)
            let mcpToPip = dist(mcp, pip)
            return (tipToWrist < pipToWrist * 1.08) ||
                (tipToMcp < mcpToPip * 1.25) ||
                (tipToWrist < palmScale * 1.15)
        }

        let indexCurled = isCurled(mcp: indexMCP, pip: indexPIP, tip: indexTip)
        let middleCurled = isCurled(mcp: middleMCP, pip: middlePIP, tip: middleTip)
        let ringCurled = isCurled(mcp: ringMCP, pip: ringPIP, tip: ringTip)
        let littleCurled = isCurled(mcp: littleMCP, pip: littlePIP, tip: littleTip)
        let curledCount = [indexCurled, middleCurled, ringCurled, littleCurled].filter { $0 }.count

        let isFist = curledCount >= 3
        let isOpenPalm = (curledCount <= 1 &&
            dist(indexTip, wrist) > palmScale * 1.15 &&
            dist(middleTip, wrist) > palmScale * 1.18) || (curledCount == 0)

        var isOkSign = false
        if let thumbTip = p(.thumbTip) {
            let pinching = dist(thumbTip, indexTip) < palmScale * 0.40
            let middleExt = !middleCurled && dist(middleTip, wrist) > palmScale * 1.15
            let ringExt = !ringCurled && dist(ringTip, wrist) > palmScale * 1.10
            let littleExt = !littleCurled && dist(littleTip, wrist) > palmScale * 1.05
            let otherExt = [middleExt, ringExt, littleExt].filter { $0 }.count
            let middleHigher = dist(middleTip, wrist) > dist(indexTip, wrist) * 1.05
            isOkSign = pinching && otherExt >= 2 && middleHigher && !isFist
        }

        return (isOpenPalm, isFist, isOkSign)
    }
}

extension CameraHandDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if isProcessingFrame { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([handPoseRequest])
            let obs = handPoseRequest.results?.first
            if let obs, let result = Self.analyzeObservation(obs) {
                Task { @MainActor [weak self] in
                    self?.handVisible = true
                }
                _ = processGeometry(
                    isOpenPalm: result.openPalm,
                    isFist: result.fist,
                    isOkSign: result.okSign,
                    nowMs: Self.uptimeMs()
                )
            } else {
                let lostState = stateMachine.onTrackingLost(
                    strictIntentMode: strictModeStorage,
                    nowMs: Self.uptimeMs()
                )
                Task { @MainActor [weak self] in
                    self?.handVisible = false
                    self?.gestureState = lostState
                }
            }
        } catch {
            // Skip malformed frame silently
        }
    }
}
