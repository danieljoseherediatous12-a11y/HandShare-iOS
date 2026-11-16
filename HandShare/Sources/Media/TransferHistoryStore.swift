import Foundation

@MainActor
final class TransferHistoryStore: ObservableObject {
    static let shared = TransferHistoryStore()

    @Published private(set) var records: [TransferHistoryRecord] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("HandShare", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func recordTransfer(
        fileName: String,
        mimeType: String,
        sizeBytes: Int64,
        remoteName: String,
        isSender: Bool,
        success: Bool,
        localAssetIdentifier: String? = nil,
        cachedRelativePath: String? = nil
    ) {
        let entry = TransferHistoryRecord(
            id: UUID(),
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            remoteName: remoteName,
            isSender: isSender,
            success: success,
            timestamp: Date(),
            localAssetIdentifier: localAssetIdentifier,
            cachedRelativePath: cachedRelativePath
        )
        records.insert(entry, at: 0)
        if records.count > 100 {
            records = Array(records.prefix(100))
        }
        save()
    }

    func clearHistory() {
        records = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([TransferHistoryRecord].self, from: data) {
            records = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
