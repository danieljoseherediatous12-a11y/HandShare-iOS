import Foundation

public enum LanFrameType: UInt8, Sendable {
    case hello = 0x01
    case ctrl = 0x02
    case fileMeta = 0x03
    case fileChunk = 0x04
    case fileEnd = 0x05
    case fileAck = 0x06
}

public struct LanFrame: Equatable, Sendable {
    public let type: UInt8
    public let payloadId: Int64
    public let body: Data

    public init(type: UInt8, payloadId: Int64, body: Data = Data()) {
        self.type = type
        self.payloadId = payloadId
        self.body = body
    }
}

public struct LanPeerBeacon: Codable, Equatable, Sendable {
    public let v: Int
    public let magic: String
    public let id: String
    public let name: String
    public let type: String
    public let os: String
    public let tcpPort: Int
    public let ts: Int64

    public var isDesktop: Bool {
        let lowType = type.lowercased()
        let lowOs = os.lowercased()
        return lowType == "desktop" || lowOs == "windows" || lowOs == "macos" || lowOs == "linux"
    }

    public init(
        id: String,
        name: String,
        isDesktop: Bool = false,
        os: String = "ios",
        tcpPort: Int = LanProtocol.tcpPort,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.v = LanProtocol.protocolVersion
        self.magic = LanProtocol.beaconMagic
        self.id = id
        self.name = name
        self.type = isDesktop ? "desktop" : "phone"
        self.os = os
        self.tcpPort = tcpPort
        self.ts = timestampMs
    }
}

public struct HandShareFileMetadata: Equatable, Sendable {
    public let fileName: String
    public let mimeType: String
    public let sizeBytes: Int64
    public let payloadId: Int64

    public var isVideo: Bool {
        mimeType.lowercased().hasPrefix("video/")
    }

    public init(fileName: String, mimeType: String, sizeBytes: Int64, payloadId: Int64 = 0) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.payloadId = payloadId
    }

    public func toBytes() -> Data {
        let nameData = Data(fileName.utf8)
        let mimeData = Data(mimeType.utf8)
        var out = Data(capacity: 4 + nameData.count + 4 + mimeData.count + 16)
        out.appendBigEndian(Int32(nameData.count))
        out.append(nameData)
        out.appendBigEndian(Int32(mimeData.count))
        out.append(mimeData)
        out.appendBigEndian(sizeBytes)
        out.appendBigEndian(payloadId)
        return out
    }

    public static func fromBytes(_ data: Data) -> HandShareFileMetadata? {
        var offset = 0
        guard let nameLen = data.readBigEndianInt32(at: offset), nameLen >= 0 else { return nil }
        offset += 4
        let nLen = Int(nameLen)
        guard offset + nLen <= data.count else { return nil }
        let nameSlice = data.subdata(in: offset..<(offset + nLen))
        guard let fileName = String(data: nameSlice, encoding: .utf8) else { return nil }
        offset += nLen

        guard let mimeLen = data.readBigEndianInt32(at: offset), mimeLen >= 0 else { return nil }
        offset += 4
        let mLen = Int(mimeLen)
        guard offset + mLen <= data.count else { return nil }
        let mimeSlice = data.subdata(in: offset..<(offset + mLen))
        guard let mimeType = String(data: mimeSlice, encoding: .utf8) else { return nil }
        offset += mLen

        guard let sizeBytes = data.readBigEndianInt64(at: offset) else { return nil }
        offset += 8
        let payloadId = data.readBigEndianInt64(at: offset) ?? 0

        return HandShareFileMetadata(
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            payloadId: payloadId
        )
    }

    public static func corrected(forFileAt url: URL, metadata: HandShareFileMetadata) -> HandShareFileMetadata {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return metadata }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 16)
        return corrected(forHeader: header, metadata: metadata)
    }

    public static func corrected(forHeader header: Data, metadata: HandShareFileMetadata) -> HandShareFileMetadata {
        guard header.count >= 12 else { return metadata }
        let bytes = [UInt8](header)

        func ascii(_ from: Int, _ len: Int) -> String {
            guard from + len <= bytes.count else { return "" }
            return String(bytes: bytes[from..<(from + len)], encoding: .ascii) ?? ""
        }

        let detected: (mime: String, ext: String)?
        if ascii(4, 4) == "ftyp" {
            switch ascii(8, 4).lowercased() {
            case "heic", "heix", "heim", "heis", "mif1", "msf1":
                detected = ("image/heic", "heic")
            case "avif", "avis":
                detected = ("image/avif", "avif")
            case "qt  ":
                detected = ("video/quicktime", "mov")
            case "3gp4", "3gp5", "3gp6", "3gg6", "3gs6":
                detected = ("video/3gpp", "3gp")
            default:
                detected = ("video/mp4", "mp4")
            }
        } else if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            detected = ("image/jpeg", "jpg")
        } else if bytes[0] == 0x89 && ascii(1, 3) == "PNG" {
            detected = ("image/png", "png")
        } else if ascii(0, 4) == "RIFF" && ascii(8, 4) == "WEBP" {
            detected = ("image/webp", "webp")
        } else if ascii(0, 4) == "GIF8" {
            detected = ("image/gif", "gif")
        } else if bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3 {
            if metadata.fileName.lowercased().hasSuffix(".webm") || metadata.mimeType == "video/webm" {
                detected = ("video/webm", "webm")
            } else {
                detected = ("video/x-matroska", "mkv")
            }
        } else {
            detected = nil
        }

        guard let found = detected else { return metadata }
        let realFamily = found.mime.split(separator: "/").first
        let claimedFamily = metadata.mimeType.split(separator: "/").first
        if realFamily == claimedFamily && metadata.mimeType != "application/octet-stream" {
            let ext = (metadata.fileName as NSString).pathExtension.lowercased()
            if ext.isEmpty {
                return HandShareFileMetadata(
                    fileName: "\(metadata.fileName).\(found.ext)",
                    mimeType: metadata.mimeType,
                    sizeBytes: metadata.sizeBytes,
                    payloadId: metadata.payloadId
                )
            }
            return metadata
        }

        let base = ((metadata.fileName as NSString).deletingPathExtension)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBase = base.isEmpty ? "handshare_\(Int(Date().timeIntervalSince1970))" : base
        return HandShareFileMetadata(
            fileName: "\(safeBase).\(found.ext)",
            mimeType: found.mime,
            sizeBytes: metadata.sizeBytes,
            payloadId: metadata.payloadId
        )
    }
}

public enum LanProtocol {
    public static let protocolVersion = 2
    public static let udpDiscoveryPort: Int = 47831
    public static let tcpPort: Int = 47832
    public static let lanEndpointPrefix = "lan:"
    public static let beaconMagic = "HANDSHARE_BEACON"
    public static let nsdServiceType = "_handshare._tcp"
    public static let fileChunkSize = 131_072
    public static let maxFrameBytes = 16 * 1024 * 1024
    public static let frameHeaderSize = 17
    public static let frameMagic: [UInt8] = [0x48, 0x53, 0x50, 0x32] // "HSP2"

    public static func endpointId(forPeerId peerId: String) -> String {
        "\(lanEndpointPrefix)\(peerId)"
    }

    public static func peerId(fromEndpointId endpointId: String) -> String {
        if endpointId.hasPrefix(lanEndpointPrefix) {
            return String(endpointId.dropFirst(lanEndpointPrefix.count))
        }
        return endpointId
    }

    public static func encodeFrame(type: UInt8, payloadId: Int64, body: Data = Data()) -> Data? {
        guard body.count <= maxFrameBytes else { return nil }
        var data = Data(capacity: frameHeaderSize + body.count)
        data.append(contentsOf: frameMagic)
        data.append(type)
        data.appendBigEndian(payloadId)
        data.appendBigEndian(Int32(body.count))
        if !body.isEmpty {
            data.append(body)
        }
        return data
    }

    public enum FrameDecodeResult: Equatable {
        case incomplete
        case invalidMagic
        case invalidLength(Int)
        case decoded(LanFrame)
    }

    public static func consumeNextFrame(from buffer: inout Data) -> FrameDecodeResult {
        guard buffer.count >= frameHeaderSize else { return .incomplete }
        let magicBytes = [UInt8](buffer.prefix(4))
        guard magicBytes == frameMagic else {
            return .invalidMagic
        }
        let type = buffer[buffer.startIndex + 4]
        guard let payloadId = buffer.readBigEndianInt64(at: 5),
              let rawLen = buffer.readBigEndianInt32(at: 13) else {
            return .incomplete
        }
        let bodyLen = Int(rawLen)
        guard bodyLen >= 0 && bodyLen <= maxFrameBytes else {
            return .invalidLength(bodyLen)
        }
        let total = frameHeaderSize + bodyLen
        guard buffer.count >= total else {
            return .incomplete
        }
        let bodyStart = buffer.startIndex + frameHeaderSize
        let bodyEnd = bodyStart + bodyLen
        let body = bodyLen == 0 ? Data() : Data(buffer[bodyStart..<bodyEnd])
        buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + total))
        return .decoded(LanFrame(type: type, payloadId: payloadId, body: body))
    }

    public static func encodeHelloJson(_ beacon: LanPeerBeacon) -> Data {
        let encoder = JSONEncoder()
        return (try? encoder.encode(beacon)) ?? Data()
    }

    public static func parseBeaconJson(_ data: Data) -> LanPeerBeacon? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let magic = dict["magic"] as? String, magic != beaconMagic {
            return nil
        }
        guard let id = (dict["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else {
            return nil
        }
        let nameRaw = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (nameRaw?.isEmpty == false) ? nameRaw! : "HandShare"
        let typeStr = (dict["type"] as? String)?.lowercased() ?? "phone"
        let osStr = (dict["os"] as? String)?.lowercased() ?? (typeStr == "desktop" ? "windows" : "android")
        let parsedPort = (dict["tcpPort"] as? Int) ?? Int((dict["tcpPort"] as? String) ?? "") ?? tcpPort
        let port = (1...65535).contains(parsedPort) ? parsedPort : tcpPort
        let ts = (dict["ts"] as? Int64) ?? Int64((dict["ts"] as? Double) ?? 0)
        let isDesktop = typeStr == "desktop" || osStr == "windows" || osStr == "macos" || osStr == "linux"
        return LanPeerBeacon(
            id: id,
            name: name,
            isDesktop: isDesktop,
            os: osStr,
            tcpPort: port,
            timestampMs: ts > 0 ? ts : Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    public static func normalizeControlCommand(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("HS_CTRL:") ? trimmed : "HS_CTRL:\(trimmed)"
    }

    public static func extractControlCommand(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("HS_CTRL:") {
            return String(trimmed.dropFirst("HS_CTRL:".count))
        }
        return trimmed
    }

    public static func sanitizeFilename(_ raw: String) -> String {
        let slashNormalized = raw.replacingOccurrences(of: "\\", with: "/")
        let lastComp = slashNormalized.split(separator: "/").last.map(String.init) ?? slashNormalized
        let clean = lastComp
            .replacingOccurrences(of: "..", with: "_")
            .map { ch -> Character in
                if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-") {
                    return ch
                }
                return "_"
            }
        let result = String(clean.prefix(96)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return result.isEmpty ? "handshare_\(Int(Date().timeIntervalSince1970)).bin" : result
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: Int32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: Int64) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    func readBigEndianInt32(at offset: Int) -> Int32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let idx = startIndex + offset
        let b0 = UInt32(self[idx])
        let b1 = UInt32(self[idx + 1])
        let b2 = UInt32(self[idx + 2])
        let b3 = UInt32(self[idx + 3])
        return Int32(bitPattern: (b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
    }

    func readBigEndianInt64(at offset: Int) -> Int64? {
        guard offset >= 0, offset + 8 <= count else { return nil }
        let idx = startIndex + offset
        var raw: UInt64 = 0
        for i in 0..<8 {
            raw = (raw << 8) | UInt64(self[idx + i])
        }
        return Int64(bitPattern: raw)
    }
}
