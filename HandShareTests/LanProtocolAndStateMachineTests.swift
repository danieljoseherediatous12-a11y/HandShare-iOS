import XCTest
@testable import HandShare

final class LanProtocolAndStateMachineTests: XCTestCase {

    func testFrameRoundTripBigEndian() {
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
        // Feed partial prefix first to verify stream framing resilience
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
}
