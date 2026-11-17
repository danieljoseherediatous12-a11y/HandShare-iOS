import AVFoundation
import Combine
import Foundation
import Vision

@MainActor
final class CameraHandDetector: NSObject, ObservableObject {
    @Published private(set) var gestureState: GestureState = .idle
    @Published private(set) var handVisible: Bool = false
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published private(set) var cameraPermissionGranted: Bool = false
    @Published private(set) var cameraUnavailableReason: String?

    var hasFrontCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    var isDeniedOrRestricted: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

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
        authorizationStatus = status
        cameraPermissionGranted = (status == .authorized)
        if cameraPermissionGranted && hasFrontCamera {
            if cameraUnavailableReason?.contains("Ajustes") == true || cameraUnavailableReason?.contains("denegado") == true {
                cameraUnavailableReason = nil
            }
        }
    }

    @discardableResult
    func requestPermissionAndStart() async -> Bool {
        refreshPermissionStatus()
        if authorizationStatus == .authorized {
            start()
            return hasFrontCamera
        }
        if authorizationStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            refreshPermissionStatus()
            if granted {
                start()
            } else {
                cameraUnavailableReason = "Activa el permiso de Cámara en Ajustes de iOS"
            }
            return granted
        }
        cameraUnavailableReason = "Activa el permiso de Cámara en Ajustes de iOS"
        return false
    }

    @discardableResult
    func requestPermissionOrOpenSettings() async -> Bool {
        refreshPermissionStatus()
        switch authorizationStatus {
        case .authorized:
            start()
            return hasFrontCamera
        case .notDetermined:
            return await requestPermissionAndStart()
        case .denied, .restricted:
            openSystemAppSettings()
            return false
        @unknown default:
            openSystemAppSettings()
            return false
        }
    }

    func start() {
        refreshPermissionStatus()
        guard authorizationStatus == .authorized else {
            isRunning = false
            cameraUnavailableReason = "Permiso de cámara requerido"
            return
        }
        guard hasFrontCamera else {
            isRunning = false
            cameraUnavailableReason = "Este equipo no dispone de cámara frontal física"
            return
        }
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
    }

    func stop() {
        isRunning = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
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
