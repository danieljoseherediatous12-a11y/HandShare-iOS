import Foundation

enum GrabStatus: Equatable {
    case idle
    case waitingForHand
    case handOpenDetected
    case photoGrabbed
    case teleporting
    case waitingToCatch
    case photoCaught
    case completed
    case failed(String)

    var isSenderHolding: Bool {
        self == .photoGrabbed || self == .teleporting
    }
}

struct HandSharePeer: Identifiable, Equatable {
    let endpointId: String
    let peerId: String
    let name: String
    let ip: String
    let tcpPort: Int
    let isDesktop: Bool
    let osName: String
    var isConnected: Bool
    var rttMs: Int?
    var lastSeen: Date

    var id: String { endpointId }
}

struct StagedIncomingItem: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
    let metadata: HandShareFileMetadata
    let senderName: String
}

enum TransferState: Equatable {
    case idle
    case preparing(String)
    case sending(fileName: String, bytesTransferred: Int64, totalBytes: Int64)
    case receiving(fileName: String, bytesTransferred: Int64, totalBytes: Int64)
    case completed(fileName: String, isSender: Bool)
    case failed(String)

    var progressFraction: Double {
        switch self {
        case let .sending(_, sent, total), let .receiving(_, sent, total):
            guard total > 0 else { return 0 }
            return min(1.0, max(0.0, Double(sent) / Double(total)))
        default:
            return 0
        }
    }
}

struct TransferHistoryRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let mimeType: String
    let sizeBytes: Int64
    let remoteName: String
    let isSender: Bool
    let success: Bool
    let timestamp: Date
    let localAssetIdentifier: String?
    let cachedRelativePath: String?

    var isVideo: Bool {
        mimeType.lowercased().hasPrefix("video/")
    }
}
