import Darwin
import Foundation
import Network

@MainActor
final class LanTransportService: ObservableObject {
    static let shared = LanTransportService()

    @Published private(set) var peers: [HandSharePeer] = []
    @Published private(set) var connectedEndpointId: String?
    @Published private(set) var localIPAddress: String?
    @Published private(set) var isWifiAvailable: Bool = true
    @Published private(set) var activeTcpPort: Int = LanProtocol.tcpPort
    @Published private(set) var lastNetworkError: String?

    var onControlMessage: ((String, String) -> Void)?
    var onIncomingProgress: ((String, Int64, Int64, Int64) -> Void)?
    var onIncomingFileReady: ((String, StagedIncomingItem) -> Void)?
    var onPeerConnected: ((HandSharePeer) -> Void)?

    private let ioQueue = DispatchQueue(label: "com.handshare.lan.io", qos: .userInitiated)
    private let udpRxQueue = DispatchQueue(label: "com.handshare.lan.udprx", qos: .utility)

    private var pathMonitor: NWPathMonitor?
    private var tcpListener: NWListener?
    private var bonjourBrowser: NWBrowser?
    private var beaconTimer: DispatchSourceTimer?

    private nonisolated(unsafe) var isStarted = false
    private nonisolated(unsafe) var udpSocketFd: Int32 = -1
    private nonisolated(unsafe) var udpStopFlag = false

    private let stateLock = NSLock()
    private nonisolated(unsafe) var peerRecords: [String: PeerRecord] = [:]
    private nonisolated(unsafe) var sessions: [String: TcpPeerSession] = [:]
    private nonisolated(unsafe) var pendingOutbound: [TcpPeerSession] = []

    let localPeerId: String

    private final class PeerRecord {
        let endpointId: String
        let peerId: String
        var name: String
        var ip: String
        var tcpPort: Int
        var isDesktop: Bool
        var osName: String
        var rttMs: Int?
        var lastSeen: Date

        init(
            endpointId: String,
            peerId: String,
            name: String,
            ip: String,
            tcpPort: Int,
            isDesktop: Bool,
            osName: String,
            lastSeen: Date
        ) {
            self.endpointId = endpointId
            self.peerId = peerId
            self.name = name
            self.ip = ip
            self.tcpPort = tcpPort
            self.isDesktop = isDesktop
            self.osName = osName
            self.lastSeen = lastSeen
        }
    }

    private final class IncomingFileState {
        let tempURL: URL
        let metadata: HandShareFileMetadata
        let handle: FileHandle
        var receivedBytes: Int64 = 0
        var lastProgressEmitTime: TimeInterval = 0

        init(tempURL: URL, metadata: HandShareFileMetadata, handle: FileHandle) {
            self.tempURL = tempURL
            self.metadata = metadata
            self.handle = handle
        }
    }

    private final class TcpPeerSession {
        let id = UUID()
        let connection: NWConnection
        weak var owner: LanTransportService?
        var endpointId: String?
        var remoteHost: String?
        var rxBuffer = Data()
        var incoming: [Int64: IncomingFileState] = [:]
        var ackWaiters: [Int64: DispatchSemaphore] = [:]
        var isClosed = false
        private let sendLock = NSLock()

        init(connection: NWConnection, owner: LanTransportService) {
            self.connection = connection
            self.owner = owner
        }

        func start() {
            guard let owner else { return }
            connection.stateUpdateHandler = { [weak self, weak owner] state in
                guard let self, let owner else { return }
                switch state {
                case .ready:
                    if case let .hostPort(host, _) = self.connection.endpoint {
                        self.remoteHost = "\(host)"
                    } else if let remote = self.connection.currentPath?.remoteEndpoint,
                              case let .hostPort(host, _) = remote {
                        self.remoteHost = "\(host)"
                    }
                    self.sendHello(owner: owner)
                    self.receiveLoop()
                case .failed, .cancelled:
                    self.close(notify: true)
                default:
                    break
                }
            }
            connection.start(queue: owner.ioQueue)
        }

        func sendFrame(type: UInt8, payloadId: Int64, body: Data = Data()) -> Bool {
            guard let packet = LanProtocol.encodeFrame(type: type, payloadId: payloadId, body: body) else {
                return false
            }
            sendLock.lock()
            let closed = isClosed
            sendLock.unlock()
            if closed { return false }

            let sem = DispatchSemaphore(value: 0)
            var ok = true
            connection.send(content: packet, completion: .contentProcessed { err in
                if err != nil { ok = false }
                sem.signal()
            })
            _ = sem.wait(timeout: .now() + 20)
            return ok
        }

        func sendFrameAsync(type: UInt8, payloadId: Int64, body: Data = Data()) {
            guard let packet = LanProtocol.encodeFrame(type: type, payloadId: payloadId, body: body) else {
                return
            }
            sendLock.lock()
            let closed = isClosed
            sendLock.unlock()
            if closed { return }
            connection.send(content: packet, completion: .contentProcessed { _ in })
        }

        func prepareAck(payloadId: Int64) -> DispatchSemaphore {
            let sem = DispatchSemaphore(value: 0)
            sendLock.lock()
            ackWaiters[payloadId] = sem
            sendLock.unlock()
            return sem
        }

        func popAck(payloadId: Int64) {
            sendLock.lock()
            ackWaiters.removeValue(forKey: payloadId)
            sendLock.unlock()
        }

        func close(notify: Bool) {
            sendLock.lock()
            if isClosed {
                sendLock.unlock()
                return
            }
            isClosed = true
            let waiters = Array(ackWaiters.values)
            ackWaiters.removeAll()
            let openFiles = Array(incoming.values)
            incoming.removeAll()
            sendLock.unlock()

            for sem in waiters { sem.signal() }
            for item in openFiles {
                try? item.handle.close()
                try? FileManager.default.removeItem(at: item.tempURL)
            }
            connection.cancel()

            if let owner {
                owner.handleSessionClosed(self, notify: notify)
            }
        }

        private func sendHello(owner: LanTransportService) {
            let beacon = owner.buildLocalBeaconSync()
            let data = LanProtocol.encodeHelloJson(beacon)
            sendFrameAsync(type: LanFrameType.hello.rawValue, payloadId: 0, body: data)
        }

        private func receiveLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.rxBuffer.append(data)
                    if !self.drainFrames() {
                        self.close(notify: true)
                        return
                    }
                }
                if isComplete || error != nil {
                    self.close(notify: true)
                    return
                }
                self.receiveLoop()
            }
        }

        private func drainFrames() -> Bool {
            while true {
                switch LanProtocol.consumeNextFrame(from: &rxBuffer) {
                case .incomplete:
                    return true
                case .invalidMagic, .invalidLength:
                    return false
                case let .decoded(frame):
                    handleFrame(frame)
                }
            }
        }

        private func handleFrame(_ frame: LanFrame) {
            guard let owner else { return }
            guard let fType = LanFrameType(rawValue: frame.type) else { return }
            switch fType {
            case .hello:
                guard let beacon = LanProtocol.parseBeaconJson(frame.body),
                      beacon.id != owner.localPeerId else {
                    return
                }
                let hostIp = cleanHostIp(remoteHost) ?? owner.lookupPeerIp(peerId: beacon.id) ?? "local"
                owner.registerConnectedSession(self, beacon: beacon, ip: hostIp)

            case .ctrl:
                guard let ep = endpointId,
                      let raw = String(data: frame.body, encoding: .utf8) else { return }
                let cmd = LanProtocol.extractControlCommand(raw)
                owner.handleIncomingControl(endpointId: ep, command: cmd, session: self)

            case .fileMeta:
                guard let meta = HandShareFileMetadata.fromBytes(frame.body) else { return }
                let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let incomingDir = cacheDir.appendingPathComponent("lan_incoming", isDirectory: true)
                try? FileManager.default.createDirectory(at: incomingDir, withIntermediateDirectories: true)
                let safeName = LanProtocol.sanitizeFilename(meta.fileName)
                let tempURL = incomingDir.appendingPathComponent("lan_\(meta.payloadId)_\(safeName)")
                FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                guard let handle = try? FileHandle(forWritingTo: tempURL) else { return }
                incoming[frame.payloadId] = IncomingFileState(tempURL: tempURL, metadata: meta, handle: handle)

            case .fileChunk:
                guard let state = incoming[frame.payloadId] else { return }
                do {
                    try state.handle.write(contentsOf: frame.body)
                    state.receivedBytes += Int64(frame.body.count)
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - state.lastProgressEmitTime >= 0.08 || state.receivedBytes >= state.metadata.sizeBytes {
                        state.lastProgressEmitTime = now
                        let ep = endpointId ?? ""
                        let total = max(state.metadata.sizeBytes, state.receivedBytes)
                        let fileName = state.metadata.fileName
                        let received = state.receivedBytes
                        DispatchQueue.main.async {
                            owner.onIncomingProgress?(ep, frame.payloadId, received, total)
                            _ = fileName
                        }
                    }
                } catch {
                    incoming.removeValue(forKey: frame.payloadId)
                    try? state.handle.close()
                    try? FileManager.default.removeItem(at: state.tempURL)
                }

            case .fileEnd:
                guard let state = incoming.removeValue(forKey: frame.payloadId) else { return }
                try? state.handle.synchronize()
                try? state.handle.close()
                let corrected = HandShareFileMetadata.corrected(forFileAt: state.tempURL, metadata: state.metadata)
                let finalURL = renameWithCorrectedExt(tempURL: state.tempURL, metadata: corrected, payloadId: frame.payloadId)
                sendFrameAsync(type: LanFrameType.fileAck.rawValue, payloadId: frame.payloadId, body: Data([1]))
                if let ep = endpointId {
                    let peerName = owner.peerName(for: ep)
                    let item = StagedIncomingItem(fileURL: finalURL, metadata: corrected, senderName: peerName)
                    let total = max(corrected.sizeBytes, state.receivedBytes)
                    DispatchQueue.main.async {
                        owner.onIncomingProgress?(ep, frame.payloadId, state.receivedBytes, total)
                        owner.onIncomingFileReady?(ep, item)
                    }
                }

            case .fileAck:
                sendLock.lock()
                let sem = ackWaiters.removeValue(forKey: frame.payloadId)
                sendLock.unlock()
                sem?.signal()
            }
        }

        private func renameWithCorrectedExt(tempURL: URL, metadata: HandShareFileMetadata, payloadId: Int64) -> URL {
            let ext = (metadata.fileName as NSString).pathExtension.lowercased()
            guard !ext.isEmpty else { return tempURL }
            let dst = tempURL.deletingLastPathComponent().appendingPathComponent("hs_recv_\(payloadId).\(ext)")
            if dst == tempURL { return tempURL }
            try? FileManager.default.removeItem(at: dst)
            if (try? FileManager.default.moveItem(at: tempURL, to: dst)) != nil {
                return dst
            }
            return tempURL
        }

        private func cleanHostIp(_ raw: String?) -> String? {
            guard var raw, !raw.isEmpty else { return nil }
            if let pct = raw.firstIndex(of: "%") {
                raw = String(raw[..<pct])
            }
            if raw.hasPrefix("::ffff:") {
                raw = String(raw.dropFirst("::ffff:".count))
            }
            return raw
        }
    }

    private nonisolated(unsafe) var cachedDeviceName: String = "iPhone"
    private nonisolated(unsafe) var cachedTcpPort: Int = LanProtocol.tcpPort

    private init() {
        let key = "hs_lan_peer_id"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            self.localPeerId = saved
        } else {
            let rawModel = UIDevice.current.model.filter { $0.isLetter || $0.isNumber }.prefix(6).lowercased()
            let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
            let created = "ios_\(rawModel.isEmpty ? "iphone" : rawModel)_\(suffix)"
            UserDefaults.standard.set(created, forKey: key)
            self.localPeerId = created
        }
        self.cachedDeviceName = AppPreferences.shared.deviceName
        updateLocalIPAddress()
    }

    func updateDeviceName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = trimmed.isEmpty ? "iPhone" : trimmed
        stateLock.lock()
        cachedDeviceName = effective
        stateLock.unlock()
        triggerBeaconNow()
    }

    func start() {
        if isStarted { return }
        isStarted = true
        stateLock.lock()
        cachedDeviceName = AppPreferences.shared.deviceName
        stateLock.unlock()
        updateLocalIPAddress()
        startPathMonitor()
        startTcpServer()
        startBonjourBrowser()
        startUdpDiscovery()
        startBeaconTimer()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        udpStopFlag = true

        beaconTimer?.cancel()
        beaconTimer = nil
        bonjourBrowser?.cancel()
        bonjourBrowser = nil
        tcpListener?.cancel()
        tcpListener = nil
        pathMonitor?.cancel()
        pathMonitor = nil

        if udpSocketFd >= 0 {
            Darwin.close(udpSocketFd)
            udpSocketFd = -1
        }

        stateLock.lock()
        let activeSessions = Array(sessions.values) + pendingOutbound
        sessions.removeAll()
        pendingOutbound.removeAll()
        stateLock.unlock()

        for s in activeSessions { s.close(notify: false) }
        connectedEndpointId = nil
        emitPeers()
    }

    func refreshDiscovery() {
        updateLocalIPAddress()
        if !isStarted {
            start()
            return
        }
        triggerBeaconNow()
        restartBonjourBrowser()
    }

    func triggerBeaconNow() {
        ioQueue.async { [weak self] in
            self?.sendUdpBeaconPacket()
        }
    }

    func connectToPeer(_ peer: HandSharePeer) {
        ioQueue.async { [weak self] in
            _ = self?.ensureSessionSync(endpointId: peer.endpointId)
        }
    }

    func connectManual(ip: String, port: Int = LanProtocol.tcpPort, completion: @escaping @MainActor (HandSharePeer?) -> Void) {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIp.isEmpty else {
            Task { @MainActor in completion(nil) }
            return
        }
        if !isStarted { start() }
        ioQueue.async { [weak self] in
            guard let self else { return }
            let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? NWEndpoint.Port(integerLiteral: UInt16(LanProtocol.tcpPort))
            let params = NWParameters.tcp
            if let tcpOpts = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcpOpts.noDelay = true
            }
            let conn = NWConnection(host: NWEndpoint.Host(cleanIp), port: nwPort, using: params)
            let session = TcpPeerSession(connection: conn, owner: self)
            session.remoteHost = cleanIp
            self.stateLock.lock()
            self.pendingOutbound.append(session)
            self.stateLock.unlock()
            session.start()

            let deadline = Date().addingTimeInterval(3.5)
            while Date() < deadline && !session.isClosed {
                if let ep = session.endpointId {
                    let matched = self.buildPeerSnapshotList().first(where: { $0.endpointId == ep })
                    Task { @MainActor in completion(matched) }
                    return
                }
                Thread.sleep(forTimeInterval: 0.03)
            }
            if session.endpointId == nil {
                session.close(notify: false)
            }
            Task { @MainActor in completion(nil) }
        }
    }

    func disconnectPeer(endpointId: String) {
        stateLock.lock()
        let sess = sessions.removeValue(forKey: endpointId)
        stateLock.unlock()
        sess?.close(notify: true)
        emitPeers()
    }

    func sendControlMessage(endpointId: String, command: String) {
        let normalized = LanProtocol.normalizeControlCommand(command)
        let data = Data(normalized.utf8)
        ioQueue.async { [weak self] in
            guard let self, let sess = self.ensureSessionSync(endpointId: endpointId) else { return }
            sess.sendFrameAsync(type: LanFrameType.ctrl.rawValue, payloadId: 0, body: data)
        }
    }

    func sendFileBlocking(
        endpointId: String,
        fileURL: URL,
        metadata: HandShareFileMetadata,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async -> Bool {
        await withCheckedContinuation { cont in
            ioQueue.async { [weak self] in
                guard let self else {
                    cont.resume(returning: false)
                    return
                }
                guard let sess = self.ensureSessionSync(endpointId: endpointId),
                      let handle = try? FileHandle(forReadingFrom: fileURL) else {
                    cont.resume(returning: false)
                    return
                }
                defer { try? handle.close() }

                let payloadId = Int64(Date().timeIntervalSince1970 * 1_000_000) & 0x7FFF_FFFF_FFFF_FFFF
                let finalMeta = HandShareFileMetadata(
                    fileName: metadata.fileName,
                    mimeType: metadata.mimeType,
                    sizeBytes: metadata.sizeBytes,
                    payloadId: payloadId
                )
                let ackSem = sess.prepareAck(payloadId: payloadId)
                guard sess.sendFrame(type: LanFrameType.fileMeta.rawValue, payloadId: payloadId, body: finalMeta.toBytes()) else {
                    sess.popAck(payloadId: payloadId)
                    cont.resume(returning: false)
                    return
                }

                var sent: Int64 = 0
                let total = max(1, finalMeta.sizeBytes)
                onProgress(0, total)

                while true {
                    let chunk = handle.readData(ofLength: LanProtocol.fileChunkSize)
                    if chunk.isEmpty { break }
                    if !sess.sendFrame(type: LanFrameType.fileChunk.rawValue, payloadId: payloadId, body: chunk) {
                        sess.popAck(payloadId: payloadId)
                        sess.close(notify: true)
                        cont.resume(returning: false)
                        return
                    }
                    sent += Int64(chunk.count)
                    onProgress(sent, max(total, sent))
                }

                guard sess.sendFrame(type: LanFrameType.fileEnd.rawValue, payloadId: payloadId, body: Data()) else {
                    sess.popAck(payloadId: payloadId)
                    sess.close(notify: true)
                    cont.resume(returning: false)
                    return
                }
                _ = ackSem.wait(timeout: .now() + 3.0)
                sess.popAck(payloadId: payloadId)
                onProgress(sent, max(total, sent))
                cont.resume(returning: true)
            }
        }
    }

    // MARK: - Internals

    private nonisolated func buildLocalBeaconSync() -> LanPeerBeacon {
        stateLock.lock()
        let name = cachedDeviceName
        let port = cachedTcpPort
        stateLock.unlock()
        return LanPeerBeacon(id: localPeerId, name: name, isDesktop: false, os: "ios", tcpPort: port)
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let hasWifi = path.status == .satisfied && !path.usesInterfaceType(.cellular)
            Task { @MainActor [weak self] in
                self?.isWifiAvailable = hasWifi || path.status == .satisfied
                self?.updateLocalIPAddress()
            }
        }
        monitor.start(queue: ioQueue)
        pathMonitor = monitor
    }

    private func startTcpServer() {
        let params = NWParameters.tcp
        if let tcpOpts = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOpts.noDelay = true
        }
        let listener: NWListener?
        if let port = NWEndpoint.Port(rawValue: UInt16(LanProtocol.tcpPort)),
           let l = try? NWListener(using: params, on: port) {
            listener = l
        } else {
            listener = try? NWListener(using: params)
        }
        guard let listener else {
            lastNetworkError = "No se pudo abrir el servidor TCP"
            return
        }
        listener.service = NWListener.Service(
            name: "HandShare-\(localPeerId.prefix(10))",
            type: LanProtocol.nsdServiceType
        )
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let p = Int(listener.port?.rawValue ?? UInt16(LanProtocol.tcpPort))
                self.stateLock.lock()
                self.cachedTcpPort = p
                self.stateLock.unlock()
                Task { @MainActor in self.activeTcpPort = p }
            case let .failed(err):
                Task { @MainActor in self.lastNetworkError = err.localizedDescription }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            let session = TcpPeerSession(connection: conn, owner: self)
            self.stateLock.lock()
            self.pendingOutbound.append(session)
            self.stateLock.unlock()
            session.start()
        }
        listener.start(queue: ioQueue)
        tcpListener = listener
    }

    private func startBonjourBrowser() {
        let params = NWParameters.tcp
        let browser = NWBrowser(for: .bonjour(type: LanProtocol.nsdServiceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for res in results {
                if case let .service(name, _, _, _) = res.endpoint,
                   name.contains(self.localPeerId.prefix(10)) {
                    continue
                }
                self.resolveBonjourEndpoint(res.endpoint)
            }
        }
        browser.start(queue: ioQueue)
        bonjourBrowser = browser
    }

    private func restartBonjourBrowser() {
        bonjourBrowser?.cancel()
        bonjourBrowser = nil
        startBonjourBrowser()
    }

    private nonisolated func resolveBonjourEndpoint(_ endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        if let tcpOpts = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOpts.noDelay = true
        }
        let conn = NWConnection(to: endpoint, using: params)
        let session = TcpPeerSession(connection: conn, owner: self)
        stateLock.lock()
        pendingOutbound.append(session)
        stateLock.unlock()
        session.start()
    }

    private func startUdpDiscovery() {
        udpStopFlag = false
        udpRxQueue.async { [weak self] in
            guard let self else { return }
            let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { return }
            var yes: Int32 = 1
            Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
            Darwin.setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(LanProtocol.udpDiscoveryPort).bigEndian
            addr.sin_addr = in_addr(s_addr: UInt32(0).bigEndian)

            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bound != 0 {
                var ephem = sockaddr_in()
                ephem.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                ephem.sin_family = sa_family_t(AF_INET)
                ephem.sin_port = 0
                ephem.sin_addr = in_addr(s_addr: UInt32(0).bigEndian)
                _ = withUnsafePointer(to: &ephem) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            self.udpSocketFd = fd
            var buf = [UInt8](repeating: 0, count: 4096)

            while self.isStarted && !self.udpStopFlag {
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = Darwin.poll(&pfd, 1, 500)
                if ready <= 0 { continue }

                var senderAddr = sockaddr_in()
                var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &senderAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        Darwin.recvfrom(fd, &buf, buf.count, 0, saPtr, &addrLen)
                    }
                }
                guard n > 0 else { continue }
                let packetData = Data(buf[0..<n])
                guard let beacon = LanProtocol.parseBeaconJson(packetData),
                      beacon.id != self.localPeerId else {
                    continue
                }
                var ipChars = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var sinAddr = senderAddr.sin_addr
                if Darwin.inet_ntop(AF_INET, &sinAddr, &ipChars, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = String(cString: ipChars)
                    self.registerDiscoveredPeer(beacon: beacon, ip: ip)
                }
            }
        }
    }

    private func startBeaconTimer() {
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + 0.2, repeating: 1.5)
        var tick = 0
        timer.setEventHandler { [weak self] in
            guard let self, self.isStarted else { return }
            self.sendUdpBeaconPacket()
            self.pruneStalePeers()
            tick += 1
            if tick % 3 == 0 {
                self.sendPings()
            }
        }
        timer.resume()
        beaconTimer = timer
    }

    private nonisolated func sendUdpBeaconPacket() {
        let fd = udpSocketFd
        guard fd >= 0 else { return }
        let payload = LanProtocol.encodeHelloJson(buildLocalBeaconSync())
        var targets = broadcastAddresses()
        if !targets.contains("255.255.255.255") {
            targets.append("255.255.255.255")
        }

        payload.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.baseAddress else { return }
            for ip in targets {
                var dst = sockaddr_in()
                dst.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                dst.sin_family = sa_family_t(AF_INET)
                dst.sin_port = UInt16(LanProtocol.udpDiscoveryPort).bigEndian
                guard Darwin.inet_pton(AF_INET, ip, &dst.sin_addr) == 1 else { continue }
                _ = withUnsafePointer(to: &dst) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.sendto(fd, ptr, payload.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    private nonisolated func sendPings() {
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        let body = Data(LanProtocol.normalizeControlCommand("PING:\(ms)").utf8)
        stateLock.lock()
        let active = Array(sessions.values)
        stateLock.unlock()
        for sess in active {
            sess.sendFrameAsync(type: LanFrameType.ctrl.rawValue, payloadId: 0, body: body)
        }
    }

    private nonisolated func ensureSessionSync(endpointId: String) -> TcpPeerSession? {
        stateLock.lock()
        if let existing = sessions[endpointId], !existing.isClosed {
            stateLock.unlock()
            return existing
        }
        guard let record = peerRecords[endpointId], !record.ip.isEmpty, record.ip != "local" else {
            stateLock.unlock()
            return nil
        }
        let ip = record.ip
        let port = record.tcpPort
        stateLock.unlock()

        let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? NWEndpoint.Port(integerLiteral: UInt16(LanProtocol.tcpPort))
        let params = NWParameters.tcp
        if let tcpOpts = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOpts.noDelay = true
        }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: params)
        let session = TcpPeerSession(connection: conn, owner: self)
        session.remoteHost = ip
        stateLock.lock()
        pendingOutbound.append(session)
        stateLock.unlock()
        session.start()

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline && !session.isClosed {
            if session.endpointId == endpointId {
                return session
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
        return sessions[endpointId]
    }

    private nonisolated func registerDiscoveredPeer(beacon: LanPeerBeacon, ip: String) {
        let ep = LanProtocol.endpointId(forPeerId: beacon.id)
        let now = Date()
        stateLock.lock()
        let changed: Bool
        if let existing = peerRecords[ep] {
            changed = existing.name != beacon.name ||
                existing.ip != ip ||
                existing.tcpPort != beacon.tcpPort ||
                existing.isDesktop != beacon.isDesktop
            existing.name = beacon.name
            existing.ip = ip
            existing.tcpPort = beacon.tcpPort
            existing.isDesktop = beacon.isDesktop
            existing.osName = beacon.os
            existing.lastSeen = now
        } else {
            changed = true
            peerRecords[ep] = PeerRecord(
                endpointId: ep,
                peerId: beacon.id,
                name: beacon.name,
                ip: ip,
                tcpPort: beacon.tcpPort,
                isDesktop: beacon.isDesktop,
                osName: beacon.os,
                lastSeen: now
            )
        }
        stateLock.unlock()
        if changed { emitPeers() }
    }

    private nonisolated func registerConnectedSession(_ session: TcpPeerSession, beacon: LanPeerBeacon, ip: String) {
        let ep = LanProtocol.endpointId(forPeerId: beacon.id)
        let now = Date()
        stateLock.lock()
        pendingOutbound.removeAll { $0 === session }
        session.endpointId = ep
        let prev = sessions[ep]
        sessions[ep] = session
        peerRecords[ep] = PeerRecord(
            endpointId: ep,
            peerId: beacon.id,
            name: beacon.name,
            ip: ip,
            tcpPort: beacon.tcpPort,
            isDesktop: beacon.isDesktop,
            osName: beacon.os,
            lastSeen: now
        )
        stateLock.unlock()

        if let prev, prev !== session {
            prev.close(notify: false)
        }
        emitPeers()
        let snapshot = buildPeerSnapshotList().first(where: { $0.endpointId == ep })
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connectedEndpointId = ep
            if let snapshot {
                self.onPeerConnected?(snapshot)
            }
        }
    }

    private nonisolated func handleSessionClosed(_ session: TcpPeerSession, notify: Bool) {
        stateLock.lock()
        pendingOutbound.removeAll { $0 === session }
        var removedEp: String?
        if let ep = session.endpointId, sessions[ep] === session {
            sessions.removeValue(forKey: ep)
            removedEp = ep
        }
        stateLock.unlock()
        emitPeers()
        if notify, let removedEp {
            Task { @MainActor [weak self] in
                if self?.connectedEndpointId == removedEp {
                    self?.connectedEndpointId = self?.sessions.keys.first
                }
            }
        }
    }

    private nonisolated func handleIncomingControl(endpointId: String, command: String, session: TcpPeerSession) {
        if command.hasPrefix("PING:") {
            let ts = String(command.dropFirst("PING:".count))
            let body = Data(LanProtocol.normalizeControlCommand("PONG:\(ts)").utf8)
            session.sendFrameAsync(type: LanFrameType.ctrl.rawValue, payloadId: 0, body: body)
            return
        }
        if command.hasPrefix("PONG:") {
            if let sent = Int64(command.dropFirst("PONG:".count)) {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let rtt = max(1, Int(now - sent))
                stateLock.lock()
                peerRecords[endpointId]?.rttMs = rtt
                peerRecords[endpointId]?.lastSeen = Date()
                stateLock.unlock()
                emitPeers()
            }
            return
        }
        Task { @MainActor [weak self] in
            self?.onControlMessage?(endpointId, command)
        }
    }

    private nonisolated func lookupPeerIp(peerId: String) -> String? {
        let ep = LanProtocol.endpointId(forPeerId: peerId)
        stateLock.lock()
        let ip = peerRecords[ep]?.ip
        stateLock.unlock()
        return ip
    }

    private nonisolated func peerName(for endpointId: String) -> String {
        stateLock.lock()
        let name = peerRecords[endpointId]?.name ?? "Dispositivo"
        stateLock.unlock()
        return name
    }

    private nonisolated func pruneStalePeers() {
        let now = Date()
        stateLock.lock()
        var removed = false
        for (ep, rec) in peerRecords {
            let connected = sessions[ep]?.isClosed == false
            if !connected && now.timeIntervalSince(rec.lastSeen) > 12.0 {
                peerRecords.removeValue(forKey: ep)
                removed = true
            }
        }
        stateLock.unlock()
        if removed { emitPeers() }
    }

    private nonisolated func buildPeerSnapshotList() -> [HandSharePeer] {
        stateLock.lock()
        let list = peerRecords.values.map { rec -> HandSharePeer in
            let connected = sessions[rec.endpointId]?.isClosed == false
            return HandSharePeer(
                endpointId: rec.endpointId,
                peerId: rec.peerId,
                name: rec.name,
                ip: rec.ip,
                tcpPort: rec.tcpPort,
                isDesktop: rec.isDesktop,
                osName: rec.osName,
                isConnected: connected,
                rttMs: rec.rttMs,
                lastSeen: rec.lastSeen
            )
        }.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected && !rhs.isConnected }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        stateLock.unlock()
        return list
    }

    private nonisolated func emitPeers() {
        let snapshot = buildPeerSnapshotList()
        Task { @MainActor [weak self] in
            self?.peers = snapshot
        }
    }

    private func updateLocalIPAddress() {
        localIPAddress = Self.firstLocalIPv4()
    }

    private nonisolated func broadcastAddresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let isUp = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isLoop = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoop,
               let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
               let dst = cur.pointee.ifa_dstaddr, dst.pointee.sa_family == UInt8(AF_INET) {
                var sin = dst.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if Darwin.inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let bcast = String(cString: buf)
                    if !bcast.isEmpty && !result.contains(bcast) {
                        result.append(bcast)
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return result
    }

    private nonisolated static func firstLocalIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var fallback: String?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let isUp = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isLoop = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoop,
               let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: cur.pointee.ifa_name)
                var sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if Darwin.inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = String(cString: buf)
                    if !ip.hasPrefix("169.254.") && !ip.hasPrefix("127.") {
                        if name == "en0" { return ip }
                        if fallback == nil { fallback = ip }
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return fallback
    }
}
