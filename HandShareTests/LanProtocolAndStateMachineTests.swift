import Network
import XCTest
@testable import HandShare

final class LanProtocolAndStateMachineTests: XCTestCase {

    func testFrameRoundTripBigEndianAndResilience() {
        let meta = HandShareFileMetadata(
            fileName: "IMG_20261116.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 123_456,
            payloadId: 99_887_766
        )
        let encodedMeta = meta.toBytes()
        let decodedMeta = HandShareFileMetadata.fromBytes(encodedMeta)
        XCTAssertEqual(meta, decodedMeta)

        let packet = LanProtocol.encodeFrame(
            type: LanFrameType.fileMeta.rawValue,
            payloadId: 42,
            body: encodedMeta
        )
        XCTAssertNotNil(packet)

        var buffer = packet!
        var partial = Data(buffer.prefix(10))
        XCTAssertEqual(LanProtocol.consumeNextFrame(from: &partial), .incomplete)

        let result = LanProtocol.consumeNextFrame(from: &buffer)
        guard case let .decoded(frame) = result else {
            return XCTFail("Expected decoded frame, got \(result)")
        }
        XCTAssertEqual(frame.type, LanFrameType.fileMeta.rawValue)
        XCTAssertEqual(frame.payloadId, 42)
        XCTAssertEqual(HandShareFileMetadata.fromBytes(frame.body), meta)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testFrameRejectsInvalidMagicAndOversizedLength() {
        var badMagic = Data([0x00, 0x01, 0x02, 0x03]) + Data(repeating: 0, count: 13)
        XCTAssertEqual(LanProtocol.consumeNextFrame(from: &badMagic), .invalidMagic)

        var badLen = Data(LanProtocol.frameMagic)
        badLen.append(LanFrameType.ctrl.rawValue)
        badLen.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 1]) // payloadId = 1
        badLen.append(contentsOf: [0x7F, 0xFF, 0xFF, 0xFF]) // oversized body length
        XCTAssertEqual(LanProtocol.consumeNextFrame(from: &badLen), .invalidLength(Int(Int32.max)))
    }

    func testMetadataMagicByteCorrectionAcrossFormats() {
        let raw = HandShareFileMetadata(fileName: "capture.bin", mimeType: "application/octet-stream", sizeBytes: 2048, payloadId: 7)

        let jpgHeader = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0])
        let jpg = HandShareFileMetadata.corrected(forHeader: jpgHeader, metadata: raw)
        XCTAssertEqual(jpg.mimeType, "image/jpeg")
        XCTAssertEqual(jpg.fileName, "capture.jpg")

        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
        let png = HandShareFileMetadata.corrected(forHeader: pngHeader, metadata: raw)
        XCTAssertEqual(png.mimeType, "image/png")
        XCTAssertEqual(png.fileName, "capture.png")

        let heicHeader = Data([0x00, 0x00, 0x00, 0x18]) + Data("ftypheic".utf8)
        let heic = HandShareFileMetadata.corrected(forHeader: heicHeader, metadata: raw)
        XCTAssertEqual(heic.mimeType, "image/heic")
        XCTAssertEqual(heic.fileName, "capture.heic")

        let movHeader = Data([0x00, 0x00, 0x00, 0x14]) + Data("ftypqt  ".utf8)
        let mov = HandShareFileMetadata.corrected(forHeader: movHeader, metadata: raw)
        XCTAssertEqual(mov.mimeType, "video/quicktime")
        XCTAssertEqual(mov.fileName, "capture.mov")

        let mp4Header = Data([0x00, 0x00, 0x00, 0x18]) + Data("ftypisom".utf8)
        let mp4 = HandShareFileMetadata.corrected(forHeader: mp4Header, metadata: raw)
        XCTAssertEqual(mp4.mimeType, "video/mp4")
        XCTAssertEqual(mp4.fileName, "capture.mp4")
    }

    func testSanitizeFilenameAndControlNormalization() {
        XCTAssertEqual(LanProtocol.sanitizeFilename("..\\..\\secret/mi foto (1).jpg"), "mi_foto__1_.jpg")
        XCTAssertEqual(LanProtocol.normalizeControlCommand("PHOTO_ARMED_IN_HAND"), "HS_CTRL:PHOTO_ARMED_IN_HAND")
        XCTAssertEqual(LanProtocol.normalizeControlCommand("HS_CTRL:DROP_CONFIRMED"), "HS_CTRL:DROP_CONFIRMED")
        XCTAssertEqual(LanProtocol.extractControlCommand("HS_CTRL:CANCEL_ARMED\n"), "CANCEL_ARMED")
    }

    func testBeaconJsonRoundTrip() {
        let beacon = LanPeerBeacon(
            id: "ios_iphone_1234",
            name: "iPhone de Papa",
            isDesktop: false,
            os: "ios",
            tcpPort: 47832,
            timestampMs: 1_794_869_000_000
        )
        let data = LanProtocol.encodeHelloJson(beacon)
        let parsed = LanProtocol.parseBeaconJson(data)
        XCTAssertEqual(parsed?.id, beacon.id)
        XCTAssertEqual(parsed?.name, beacon.name)
        XCTAssertEqual(parsed?.isDesktop, false)
        XCTAssertEqual(parsed?.os, "ios")
        XCTAssertEqual(parsed?.tcpPort, 47832)

        let desktopBeacon = LanPeerBeacon(id: "win_pc_01", name: "PC Sala", isDesktop: true, os: "windows")
        XCTAssertEqual(LanProtocol.parseBeaconJson(LanProtocol.encodeHelloJson(desktopBeacon))?.isDesktop, true)
    }

    func testGrabStateMachineEightSequentialGrabsNeverLocksUp() {
        let sm = GrabStateMachine()
        var now: Int64 = 1_000

        for idx in 1...8 {
            let d1 = sm.onFrame(isOpenPalm: true, isFist: false, isOkSign: false, strictIntentMode: true, sensitivity: 1, nowMs: now)
            now += 35
            let d2 = sm.onFrame(isOpenPalm: true, isFist: false, isOkSign: false, strictIntentMode: true, sensitivity: 1, nowMs: now)
            XCTAssertEqual(d2.state, .handOpen)
            XCTAssertFalse(d1.grabTriggered)

            now += 50
            let grab = sm.onFrame(isOpenPalm: false, isFist: true, isOkSign: false, strictIntentMode: true, sensitivity: 1, nowMs: now)
            XCTAssertTrue(grab.grabTriggered)
            XCTAssertEqual(grab.grabSequenceId, Int64(idx))

            now += 200
            let openAgain = sm.onFrame(isOpenPalm: true, isFist: false, isOkSign: false, strictIntentMode: true, sensitivity: 1, nowMs: now)
            now += 30
            let rearm = sm.onFrame(isOpenPalm: true, isFist: false, isOkSign: false, strictIntentMode: true, sensitivity: 1, nowMs: now)
            XCTAssertEqual(openAgain.state, .grabbed)
            XCTAssertEqual(rearm.state, .handOpen)
            now += 100
        }
    }

    func testGrabStateMachineOkSignTimeoutTrackingLostAndCatchRelease() {
        let sm = GrabStateMachine()
        var now: Int64 = 5_000

        // Receiver catch flow (strictIntentMode = false)
        let catchPalm = sm.onFrame(isOpenPalm: true, isFist: false, isOkSign: false, strictIntentMode: false, sensitivity: 1, nowMs: now)
        XCTAssertEqual(catchPalm.state, .handOpen)

        // Wait past fistWaitTimeoutMs without fist -> timeout back to idle
        now += GrabStateMachine.fistWaitTimeoutMs + 100
        let timedOut = sm.onFrame(isOpenPalm: false, isFist: false, isOkSign: false, strictIntentMode: false, sensitivity: 1, nowMs: now)
        XCTAssertEqual(timedOut.state, .idle)
        XCTAssertEqual(timedOut.logEvent, "FIST_WAIT_TIMEOUT")

        // OK sign requires 2 consecutive frames
        now += 50
        _ = sm.onFrame(isOpenPalm: false, isFist: false, isOkSign: true, strictIntentMode: true, sensitivity: 1, nowMs: now)
        now += 30
        let ok2 = sm.onFrame(isOpenPalm: false, isFist: false, isOkSign: true, strictIntentMode: true, sensitivity: 1, nowMs: now)
        XCTAssertEqual(ok2.detectedGesture, .ok)
        XCTAssertEqual(ok2.state, .okSign)

        // Tracking lost for > 2 frames resets cleanly to idle
        for _ in 0..<3 {
            now += 40
            _ = sm.onTrackingLost(strictIntentMode: true, nowMs: now)
        }
        XCTAssertEqual(sm.reset(preserveSustainedFistGuard: false), .idle)
    }

    @MainActor
    func testPreferencesAndHistoryStorePersistenceAndCoordinatorTransitions() {
        let prefs = AppPreferences.shared
        let originalName = prefs.deviceName
        let originalSensitivity = prefs.gestureSensitivity
        let originalGlow = prefs.edgeGlowEnabled
        defer {
            prefs.deviceName = originalName
            prefs.gestureSensitivity = originalSensitivity
            prefs.edgeGlowEnabled = originalGlow
        }

        prefs.deviceName = "iPhone Pruebas"
        prefs.gestureSensitivity = 2
        prefs.edgeGlowEnabled = false
        XCTAssertEqual(prefs.deviceName, "iPhone Pruebas")
        XCTAssertEqual(prefs.gestureSensitivity, 2)
        XCTAssertFalse(prefs.edgeGlowEnabled)

        let history = TransferHistoryStore.shared
        history.clearHistory()
        XCTAssertTrue(history.records.isEmpty)
        history.recordTransfer(
            fileName: "foto_test.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 4096,
            remoteName: "Android Test",
            isSender: true,
            success: true
        )
        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records.first?.fileName, "foto_test.jpg")
        history.clearHistory()
        XCTAssertTrue(history.records.isEmpty)

        let coord = GrabSessionCoordinator.shared
        let peer = HandSharePeer(
            endpointId: "lan:test_peer",
            peerId: "test_peer",
            name: "Pixel Test",
            ip: "127.0.0.1",
            tcpPort: 47832,
            isDesktop: false,
            osName: "android",
            isConnected: true,
            rttMs: 4,
            lastSeen: Date()
        )
        coord.selectPeer(peer)
        XCTAssertEqual(coord.selectedTargetEndpointId, "lan:test_peer")
        XCTAssertEqual(coord.selectedTargetName, "Pixel Test")

        coord.triggerAlreadySelectedPill()
        XCTAssertTrue(coord.showAlreadySelectedPill)
        coord.cancelHeldGrab()
        XCTAssertFalse(coord.isHoldingCard)
        XCTAssertFalse(coord.showAlreadySelectedPill)
        XCTAssertEqual(coord.status, .idle)
    }

    func testLoopbackNetworkFrameworkHsp2FrameRoundTrip() throws {
        let readyExp = expectation(description: "Listener ready")
        let receivedExp = expectation(description: "Frame decoded over loopback TCP")
        let queue = DispatchQueue(label: "com.handshare.tests.loopback")

        let listener = try NWListener(using: .tcp, on: .any)
        var rxBuffer = Data()
        var decodedFrame: LanFrame?

        listener.stateUpdateHandler = { state in
            if case .ready = state { readyExp.fulfill() }
        }
        listener.newConnectionHandler = { conn in
            conn.start(queue: queue)
            func readLoop() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, err in
                    if let data {
                        rxBuffer.append(data)
                        if case let .decoded(frame) = LanProtocol.consumeNextFrame(from: &rxBuffer) {
                            decodedFrame = frame
                            receivedExp.fulfill()
                            return
                        }
                    }
                    if err == nil { readLoop() }
                }
            }
            readLoop()
        }
        listener.start(queue: queue)
        defer { listener.cancel() }

        wait(for: [readyExp], timeout: 5.0)
        guard let port = listener.port else {
            return XCTFail("Missing listener port")
        }

        let client = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
        defer { client.cancel() }
        let payload = Data(LanProtocol.normalizeControlCommand("DROP_CONFIRMED").utf8)
        let packet = LanProtocol.encodeFrame(type: LanFrameType.ctrl.rawValue, payloadId: 77, body: payload)!
        client.stateUpdateHandler = { state in
            if case .ready = state {
                client.send(content: packet, completion: .contentProcessed { _ in })
            }
        }
        client.start(queue: queue)

        wait(for: [receivedExp], timeout: 5.0)
        XCTAssertEqual(decodedFrame?.type, LanFrameType.ctrl.rawValue)
        XCTAssertEqual(decodedFrame?.payloadId, 77)
        XCTAssertEqual(String(data: decodedFrame?.body ?? Data(), encoding: .utf8), "HS_CTRL:DROP_CONFIRMED")
    }
}
