import Combine
import Foundation
import Photos
import UIKit

@MainActor
final class GrabSessionCoordinator: ObservableObject {
    static let shared = GrabSessionCoordinator()

    @Published private(set) var status: GrabStatus = .idle
    @Published private(set) var transferState: TransferState = .idle
    @Published private(set) var grabbedAssets: [PHAsset] = []
    @Published private(set) var stagedIncoming: [StagedIncomingItem] = []
    @Published private(set) var selectedTargetEndpointId: String?
    @Published private(set) var selectedTargetName: String?

    @Published var isRadarActive: Bool = false
    @Published var isEdgeGlowVisible: Bool = false
    @Published var isHoldingCard: Bool = false
    @Published var isHeldCardDocked: Bool = false
    @Published var showAlreadySelectedPill: Bool = false
    @Published var floatingPreviewImage: UIImage?
    @Published var activeCatchPreviewItem: StagedIncomingItem?
    @Published var caughtBannerMessage: String?

    let lan = LanTransportService.shared
    let photos = PhotoLibraryService.shared
    let history = TransferHistoryStore.shared
    let detector = CameraHandDetector()
    let prefs = AppPreferences.shared

    private var cancellables = Set<AnyCancellable>()
    private var lastCatchTime: Date = .distantPast
    private var lastHandledGrabSeq: Int64 = 0
    private var radarTimeoutWorkItem: DispatchWorkItem?
    private var catchTimeoutWorkItem: DispatchWorkItem?
    private var alreadyPillWorkItem: DispatchWorkItem?
    private var activeViewerAsset: PHAsset?
    private var isViewerOpen = false
    private var sendQueueTask: Task<Void, Never>?
    private var pendingOutgoingAssets: [PHAsset] = []
    private var isSendingBatch = false
    private var streamCompletedDelivery = false
    private var dropConfirmedByReceiver = false

    private init() {
        wireLanCallbacks()
        wireGestureCallbacks()
    }

    func setActiveViewerAsset(_ asset: PHAsset?, isOpen: Bool) {
        isViewerOpen = isOpen
        let changed = activeViewerAsset?.localIdentifier != asset?.localIdentifier
        activeViewerAsset = isOpen ? asset : nil
        if changed || !isOpen {
            detector.resetGrabStateMachine(preserveSustainedFistGuard: true)
            isEdgeGlowVisible = false
        }
        if isOpen, let asset, isHoldingCard && isAlreadyGrabbed(asset) {
            triggerAlreadySelectedPill()
        }
    }

    func startNetworking() {
        lan.start()
    }

    func selectPeer(_ peer: HandSharePeer) {
        selectedTargetEndpointId = peer.endpointId
        selectedTargetName = peer.name
        lan.connectToPeer(peer)
    }

    func selectedPeer() -> HandSharePeer? {
        if let sel = selectedTargetEndpointId,
           let found = lan.peers.first(where: { $0.endpointId == sel }) {
            return found
        }
        return lan.peers.first(where: { $0.isConnected }) ?? lan.peers.first
    }

    func isAlreadyGrabbed(_ asset: PHAsset) -> Bool {
        grabbedAssets.contains(where: { $0.localIdentifier == asset.localIdentifier })
    }

    func toggleRadar(for asset: PHAsset?) {
        if isRadarActive && status.isSenderHolding {
            extendRadarTimeout()
            HapticEngine.shared.handDetected()
            return
        }
        setRadarActive(!isRadarActive)
    }

    func setRadarActive(_ active: Bool) {
        guard isRadarActive != active else { return }
        isRadarActive = active
        radarTimeoutWorkItem?.cancel()
        radarTimeoutWorkItem = nil

        if active {
            lastHandledGrabSeq = 0
            HapticEngine.shared.handDetected()
            detector.strictIntentMode = (status != .waitingToCatch)
            detector.sensitivity = prefs.gestureSensitivity
            detector.resetGrabStateMachine(preserveSustainedFistGuard: false)
            Task { await detector.requestPermissionAndStart() }
            extendRadarTimeout()
        } else {
            isEdgeGlowVisible = false
            if !isHoldingCard && status != .waitingToCatch {
                detector.stop()
            }
        }
    }

    func extendRadarTimeout() {
        radarTimeoutWorkItem?.cancel()
        guard isRadarActive else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRadarActive else { return }
            if self.isHoldingCard || self.status.isSenderHolding {
                self.extendRadarTimeout()
                return
            }
            self.setRadarActive(false)
        }
        radarTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0, execute: work)
    }

    func grabAsset(_ asset: PHAsset, fromViewer: Bool = true) {
        if status == .waitingToCatch || isInPostCatchCooldown() { return }
        if isAlreadyGrabbed(asset) {
            triggerAlreadySelectedPill()
            return
        }
        if let topAsset = asset as PHAsset? {
            if !grabbedAssets.contains(where: { $0.localIdentifier == topAsset.localIdentifier }) {
                grabbedAssets.append(topAsset)
            }
        }
        isEdgeGlowVisible = false
        isHoldingCard = true
        isHeldCardDocked = !fromViewer
        status = .photoGrabbed
        dropConfirmedByReceiver = false
        streamCompletedDelivery = false
        HapticEngine.shared.grabSuccess()

        Task {
            let preview = await photos.requestFullImage(for: asset)
                ?? (await requestThumbnailAsync(for: asset))
            if let preview {
                floatingPreviewImage = preview
            }
        }

        queueAndSendAsset(asset)
    }

    func grabMultipleAssets(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        if status == .waitingToCatch || isInPostCatchCooldown() { return }
        for asset in assets where !isAlreadyGrabbed(asset) {
            grabbedAssets.append(asset)
        }
        guard let last = assets.last else { return }
        isHoldingCard = true
        isHeldCardDocked = false
        status = .photoGrabbed
        dropConfirmedByReceiver = false
        streamCompletedDelivery = false
        HapticEngine.shared.grabSuccess()
        Task {
            if let preview = await photos.requestFullImage(for: last) {
                floatingPreviewImage = preview
            }
        }
        for asset in assets {
            queueAndSendAsset(asset)
        }
    }

    func cancelHeldGrab() {
        sendQueueTask?.cancel()
        sendQueueTask = nil
        pendingOutgoingAssets.removeAll()
        isSendingBatch = false
        grabbedAssets.removeAll()
        floatingPreviewImage = nil
        isHoldingCard = false
        isHeldCardDocked = false
        isEdgeGlowVisible = false
        showAlreadySelectedPill = false
        status = .idle
        transferState = .idle
        lastHandledGrabSeq = 0
        detector.resetGrabStateMachine(preserveSustainedFistGuard: true)
        setRadarActive(false)

        if let peer = selectedPeer() {
            lan.sendControlMessage(endpointId: peer.endpointId, command: "CANCEL_ARMED")
        }
    }

    func commitCatchNow() {
        guard !stagedIncoming.isEmpty else { return }
        let items = stagedIncoming
        stagedIncoming.removeAll()
        catchTimeoutWorkItem?.cancel()
        catchTimeoutWorkItem = nil
        isEdgeGlowVisible = false
        lastCatchTime = Date()
        status = .photoCaught
        HapticEngine.shared.teleportSuccess()

        if let peer = selectedPeer() {
            lan.sendControlMessage(endpointId: peer.endpointId, command: "DROP_CONFIRMED")
        }

        if let last = items.last {
            activeCatchPreviewItem = last
            caughtBannerMessage = items.count > 1
                ? "\(items.count) archivos guardados en Fotos"
                : "\(last.metadata.fileName) guardado"
        }

        Task {
            for item in items {
                let assetId = await photos.saveMediaToPhotosLibrary(fileURL: item.fileURL, metadata: item.metadata)
                history.recordTransfer(
                    fileName: item.metadata.fileName,
                    mimeType: item.metadata.mimeType,
                    sizeBytes: item.metadata.sizeBytes,
                    remoteName: item.senderName,
                    isSender: false,
                    success: true,
                    localAssetIdentifier: assetId,
                    cachedRelativePath: nil
                )
                prefs.receivedCount += 1
                try? FileManager.default.removeItem(at: item.fileURL)
            }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if status == .photoCaught {
                status = .idle
                if !isHoldingCard {
                    detector.stop()
                }
            }
        }
    }

    func dismissCatchPreview() {
        activeCatchPreviewItem = nil
        caughtBannerMessage = nil
    }

    func triggerAlreadySelectedPill() {
        alreadyPillWorkItem?.cancel()
        showAlreadySelectedPill = true
        let work = DispatchWorkItem { [weak self] in
            self?.showAlreadySelectedPill = false
        }
        alreadyPillWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: work)
    }

    private func isInPostCatchCooldown() -> Bool {
        Date().timeIntervalSince(lastCatchTime) < 8.0
    }

    private func requestThumbnailAsync(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { cont in
            photos.requestThumbnail(for: asset, targetSize: CGSize(width: 480, height: 480)) { img in
                cont.resume(returning: img)
            }
        }
    }

    private func wireLanCallbacks() {
        lan.onPeerConnected = { [weak self] peer in
            guard let self else { return }
            if self.selectedTargetEndpointId == nil {
                self.selectedTargetEndpointId = peer.endpointId
                self.selectedTargetName = peer.name
            }
            if self.isHoldingCard && !self.pendingOutgoingAssets.isEmpty && !self.isSendingBatch {
                self.processSendQueue()
            }
        }

        lan.onControlMessage = { [weak self] _, cmd in
            guard let self else { return }
            switch cmd {
            case "PHOTO_ARMED_IN_HAND":
                self.enterWaitingToCatchMode()
            case "CANCEL_ARMED":
                if self.status == .waitingToCatch {
                    self.clearStagedIncoming()
                    self.status = .idle
                    self.isEdgeGlowVisible = false
                    if self.isRadarActive && !self.isHoldingCard {
                        self.setRadarActive(false)
                    }
                }
            case "DROP_CONFIRMED":
                self.dropConfirmedByReceiver = true
                HapticEngine.shared.teleportSuccess()
                self.completeHeldDelivery()
            default:
                break
            }
        }

        lan.onIncomingProgress = { [weak self] _, _, transferred, total in
            self?.transferState = .receiving(fileName: "Recibiendo...", bytesTransferred: transferred, totalBytes: total)
        }

        lan.onIncomingFileReady = { [weak self] _, item in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastCatchTime) < 14.0 && self.status != .waitingToCatch {
                // Part of an already-caught batch arriving shortly after catch
                Task {
                    let assetId = await self.photos.saveMediaToPhotosLibrary(fileURL: item.fileURL, metadata: item.metadata)
                    self.history.recordTransfer(
                        fileName: item.metadata.fileName,
                        mimeType: item.metadata.mimeType,
                        sizeBytes: item.metadata.sizeBytes,
                        remoteName: item.senderName,
                        isSender: false,
                        success: true,
                        localAssetIdentifier: assetId,
                        cachedRelativePath: nil
                    )
                    self.prefs.receivedCount += 1
                    try? FileManager.default.removeItem(at: item.fileURL)
                }
                self.transferState = .completed(fileName: item.metadata.fileName, isSender: false)
                return
            }

            self.stagedIncoming.append(item)
            self.transferState = .completed(fileName: item.metadata.fileName, isSender: false)
            self.enterWaitingToCatchMode()
        }
    }

    private func enterWaitingToCatchMode() {
        status = .waitingToCatch
        detector.strictIntentMode = false
        detector.sensitivity = prefs.gestureSensitivity
        detector.resetGrabStateMachine(preserveSustainedFistGuard: false)
        Task { await detector.requestPermissionAndStart() }

        catchTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.status == .waitingToCatch else { return }
            self.clearStagedIncoming()
            self.status = .idle
            self.isEdgeGlowVisible = false
            self.detector.stop()
        }
        catchTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 45.0, execute: timeout)
    }

    private func clearStagedIncoming() {
        for item in stagedIncoming {
            try? FileManager.default.removeItem(at: item.fileURL)
        }
        stagedIncoming.removeAll()
    }

    private func wireGestureCallbacks() {
        detector.grabEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] grabSeq in
                guard let self else { return }
                guard grabSeq > self.lastHandledGrabSeq else { return }
                self.lastHandledGrabSeq = grabSeq
                self.handleFistGrab(seq: grabSeq)
            }
            .store(in: &cancellables)

        detector.$gestureState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if self.status == .waitingToCatch {
                    switch state {
                    case .grabbed:
                        self.isEdgeGlowVisible = self.prefs.edgeGlowEnabled
                    case .handOpen, .released:
                        if !self.stagedIncoming.isEmpty && self.detector.handVisible {
                            self.commitCatchNow()
                        }
                    case .idle:
                        if !self.detector.handVisible {
                            self.isEdgeGlowVisible = false
                        }
                    default:
                        break
                    }
                    return
                }

                guard self.isRadarActive || self.isHoldingCard else { return }
                switch state {
                case .handOpen:
                    self.extendRadarTimeout()
                    if let current = self.activeViewerAsset, self.isAlreadyGrabbed(current) {
                        self.isEdgeGlowVisible = false
                        self.triggerAlreadySelectedPill()
                    } else if self.isViewerOpen, self.activeViewerAsset != nil {
                        self.isEdgeGlowVisible = self.prefs.edgeGlowEnabled
                    }
                case .okSign:
                    if self.isHoldingCard {
                        self.isHeldCardDocked = false
                    }
                case .idle:
                    self.isEdgeGlowVisible = false
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func handleFistGrab(seq: Int64) {
        if status == .waitingToCatch || isInPostCatchCooldown() {
            detector.rearmIfStillCompleted(seq)
            return
        }
        guard isViewerOpen, let asset = activeViewerAsset else {
            detector.rearmIfStillCompleted(seq)
            return
        }
        if isAlreadyGrabbed(asset) {
            triggerAlreadySelectedPill()
            detector.rearmIfStillCompleted(seq)
            return
        }
        grabAsset(asset, fromViewer: true)
    }

    private func queueAndSendAsset(_ asset: PHAsset) {
        pendingOutgoingAssets.append(asset)
        if !isSendingBatch {
            processSendQueue()
        }
    }

    private func processSendQueue() {
        guard !isSendingBatch else { return }
        isSendingBatch = true
        sendQueueTask = Task {
            defer { isSendingBatch = false }
            while !Task.isCancelled && !pendingOutgoingAssets.isEmpty {
                guard let peer = selectedPeer() else {
                    // Wait while held card floats until user connects a PC/Android or taps Cancelar
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                let asset = pendingOutgoingAssets.removeFirst()
                status = .teleporting
                transferState = .preparing("Preparando archivo...")
                guard let exported = await photos.exportAssetToTemporaryFile(asset) else {
                    transferState = .failed("No se pudo exportar desde Fotos")
                    continue
                }
                defer { try? FileManager.default.removeItem(at: exported.fileURL) }

                lan.sendControlMessage(endpointId: peer.endpointId, command: "PHOTO_ARMED_IN_HAND")
                let meta = HandShareFileMetadata(
                    fileName: exported.fileName,
                    mimeType: exported.mimeType,
                    sizeBytes: exported.sizeBytes,
                    payloadId: 0
                )
                let ok = await lan.sendFileBlocking(
                    endpointId: peer.endpointId,
                    fileURL: exported.fileURL,
                    metadata: meta
                ) { [weak self] sent, total in
                    Task { @MainActor in
                        self?.transferState = .sending(
                            fileName: exported.fileName,
                            bytesTransferred: sent,
                            totalBytes: total
                        )
                    }
                }
                if ok {
                    history.recordTransfer(
                        fileName: exported.fileName,
                        mimeType: exported.mimeType,
                        sizeBytes: exported.sizeBytes,
                        remoteName: peer.name,
                        isSender: true,
                        success: true,
                        localAssetIdentifier: asset.localIdentifier,
                        cachedRelativePath: nil
                    )
                    prefs.sentCount += 1
                    transferState = .completed(fileName: exported.fileName, isSender: true)
                } else {
                    transferState = .failed("Error enviando \(exported.fileName)")
                }
            }
            if isHoldingCard {
                status = dropConfirmedByReceiver ? .completed : .photoGrabbed
            }
        }
    }

    private func completeHeldDelivery() {
        streamCompletedDelivery = true
        isHoldingCard = false
        isHeldCardDocked = false
        isEdgeGlowVisible = false
        grabbedAssets.removeAll()
        floatingPreviewImage = nil
        pendingOutgoingAssets.removeAll()
        status = .completed
        setRadarActive(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.status == .completed {
                self?.status = .idle
            }
        }
    }
}
