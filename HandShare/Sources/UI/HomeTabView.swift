import Photos
import PhotosUI
import SwiftUI

struct HomeTabView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var lan = LanTransportService.shared
    @ObservedObject private var photos = PhotoLibraryService.shared
    @ObservedObject private var history = TransferHistoryStore.shared
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var detector: CameraHandDetector
    @Binding var activeTab: HSTab
    let onOpenViewer: (PHAsset) -> Void
    let onOpenManualConnect: () -> Void
    let onOpenGuide: (Bool) -> Void

    @State private var historyDirectionTab = 0 // 0 = Recibidos, 1 = Enviados

    init(
        coordinator: GrabSessionCoordinator,
        activeTab: Binding<HSTab>,
        onOpenViewer: @escaping (PHAsset) -> Void,
        onOpenManualConnect: @escaping () -> Void,
        onOpenGuide: @escaping (Bool) -> Void
    ) {
        self.coordinator = coordinator
        _detector = ObservedObject(wrappedValue: coordinator.detector)
        _activeTab = activeTab
        self.onOpenViewer = onOpenViewer
        self.onOpenManualConnect = onOpenManualConnect
        self.onOpenGuide = onOpenGuide
    }

    private var receivedHistory: [TransferHistoryRecord] {
        history.records.filter { !$0.isSender }
    }

    private var sentHistory: [TransferHistoryRecord] {
        history.records.filter { $0.isSender }
    }

    private var activeHistory: [TransferHistoryRecord] {
        historyDirectionTab == 0 ? receivedHistory : sentHistory
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    HandShareHeaderLogo(size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HandShare")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(HSColor.label)
                        Text(subtitleText)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(HSColor.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        withAnimation { activeTab = .settings }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(HSColor.label)
                            .frame(width: 38, height: 38)
                            .background(HSColor.card, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Hero Card
                ContinuityHeroCardView(
                    isReady: lan.isWifiAvailable && photos.isAuthorized,
                    peerCount: lan.peers.count,
                    isHolding: coordinator.isHoldingCard,
                    statusText: heroStatusText
                ) {
                    if !photos.isAuthorized {
                        Task { _ = await photos.requestAuthorization() }
                    } else {
                        withAnimation { activeTab = .gallery }
                    }
                }
                .padding(.horizontal, 16)

                // Control Center toggles
                HStack(spacing: 8) {
                    controlPill(
                        icon: lan.isWifiAvailable ? "wifi" : "wifi.slash",
                        label: "Wi‑Fi",
                        active: lan.isWifiAvailable,
                        color: HSColor.blue
                    ) {
                        lan.refreshDiscovery()
                    }

                    controlPill(
                        icon: "bonjour",
                        label: "Red local",
                        active: true,
                        color: HSColor.indigo,
                        action: onOpenManualConnect
                    )

                    controlPill(
                        icon: detector.cameraPermissionGranted ? "camera.fill" : "camera",
                        label: "Cámara",
                        active: detector.cameraPermissionGranted,
                        color: HSColor.green
                    ) {
                        Task { await detector.requestPermissionAndStart() }
                    }

                    controlPill(
                        icon: "photo.fill",
                        label: "Fotos",
                        active: photos.isAuthorized,
                        color: HSColor.teal
                    ) {
                        Task { _ = await photos.requestAuthorization() }
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
                .background(HSColor.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)

                // Gesture guide cards
                HStack(spacing: 12) {
                    quickActionTile(
                        title: "Enviar",
                        subtitle: "Palma ✋ → Puño ✊",
                        icon: "square.and.arrow.up",
                        colors: [Color(red: 0.04, green: 0.52, blue: 1.0), Color(red: 0.37, green: 0.36, blue: 0.90)]
                    ) { onOpenGuide(true) }

                    quickActionTile(
                        title: "Recibir",
                        subtitle: "Abre palma ✋ para soltar",
                        icon: "square.and.arrow.down",
                        colors: [Color(red: 0.75, green: 0.35, blue: 0.95), Color(red: 1.0, green: 0.22, blue: 0.37)]
                    ) { onOpenGuide(false) }
                }
                .padding(.horizontal, 16)

                // Nearby devices
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Cercanos") {
                        withAnimation { activeTab = .devices }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            if lan.peers.isEmpty {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(HSColor.fill)
                                        .frame(width: 58, height: 58)
                                        .overlay(ProgressView().tint(HSColor.blue))
                                    Text("Buscando...")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(HSColor.secondary)
                                }
                            } else {
                                ForEach(Array(lan.peers.enumerated()), id: \.element.endpointId) { idx, peer in
                                    let isSelected = coordinator.selectedTargetEndpointId == peer.endpointId
                                    let grad = HSColor.avatarGradients[idx % HSColor.avatarGradients.count]
                                    Button {
                                        coordinator.selectPeer(peer)
                                        HapticEngine.shared.subtleTap()
                                    } label: {
                                        VStack(spacing: 6) {
                                            ZStack(alignment: .bottomTrailing) {
                                                Circle()
                                                    .fill(LinearGradient(colors: grad, startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    .frame(width: 58, height: 58)
                                                    .overlay(
                                                        Image(systemName: peer.isDesktop ? "desktopcomputer" : "iphone")
                                                            .font(.system(size: 22, weight: .semibold))
                                                            .foregroundColor(.white)
                                                    )
                                                    .overlay(
                                                        Circle().stroke(isSelected ? HSColor.blue : Color.clear, lineWidth: 3)
                                                            .padding(-4)
                                                    )
                                                if peer.isConnected {
                                                    Circle()
                                                        .fill(HSColor.green)
                                                        .frame(width: 14, height: 14)
                                                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                                }
                                            }
                                            Text(peer.name)
                                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                                .foregroundColor(HSColor.label)
                                                .lineLimit(1)
                                                .frame(maxWidth: 74)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Button {
                                coordinator.lan.refreshDiscovery()
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(HSColor.card)
                                        .frame(width: 58, height: 58)
                                        .overlay(
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(HSColor.blue)
                                        )
                                    Text("Actualizar")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(HSColor.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Button(action: onOpenManualConnect) {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(HSColor.card)
                                        .frame(width: 58, height: 58)
                                        .overlay(
                                            Image(systemName: "link.badge.plus")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(HSColor.indigo)
                                        )
                                    Text("Por IP")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(HSColor.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Recent Gallery Strip
                if !photos.recentAssets.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Recientes en iPhone") {
                            withAnimation { activeTab = .gallery }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos.recentAssets.prefix(12), id: \.localIdentifier) { asset in
                                    Button {
                                        onOpenViewer(asset)
                                    } label: {
                                        PHAssetThumbnailView(asset: asset, size: CGSize(width: 180, height: 220))
                                            .frame(width: 112, height: 148)
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // Enviados y Recibidos
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Enviados y Recibidos") {
                        withAnimation { activeTab = .gallery }
                    }
                    Picker("Historial", selection: $historyDirectionTab) {
                        Text("Recibidos (\(receivedHistory.count))").tag(0)
                        Text("Enviados (\(sentHistory.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if activeHistory.isEmpty {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill((historyDirectionTab == 0 ? HSColor.green : HSColor.blue).opacity(0.15))
                                    .frame(width: 42, height: 42)
                                Image(systemName: historyDirectionTab == 0 ? "square.and.arrow.down" : "square.and.arrow.up")
                                    .foregroundColor(historyDirectionTab == 0 ? HSColor.green : HSColor.blue)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(historyDirectionTab == 0 ? "Sin archivos recibidos aún" : "Sin archivos enviados aún")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(HSColor.label)
                                Text(historyDirectionTab == 0
                                     ? "Las fotos y videos que atrapes con ✋ aparecerán aquí"
                                     : "Las fotos y videos que envíes con ✋→✊ aparecerán aquí")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(HSColor.secondary)
                            }
                            Spacer()
                        }
                        .padding(18)
                        .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 16)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(activeHistory.prefix(20)) { record in
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let id = record.localAssetIdentifier,
                                           let asset = coordinator.photos.asset(forIdentifier: id) {
                                            PHAssetThumbnailView(asset: asset, size: CGSize(width: 180, height: 180))
                                                .frame(width: 120, height: 120)
                                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        } else {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(HSColor.fill)
                                                .frame(width: 120, height: 120)
                                                .overlay(
                                                    Image(systemName: record.isVideo ? "video.fill" : "photo.fill")
                                                        .font(.system(size: 28))
                                                        .foregroundColor(HSColor.blue)
                                                )
                                        }
                                        Text(record.fileName)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(HSColor.label)
                                            .lineLimit(1)
                                        Text(record.remoteName)
                                            .font(.system(size: 10.5))
                                            .foregroundColor(HSColor.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 120)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.bottom, 110)
        }
        .background(HSColor.background)
    }

    private var subtitleText: String {
        let ip = lan.localIPAddress ?? "Sin IP Wi‑Fi"
        return "\(prefs.deviceName) · \(ip)"
    }

    private var heroStatusText: String {
        if coordinator.isHoldingCard {
            return "Sosteniendo \(coordinator.grabbedAssets.count) elemento(s)"
        }
        if coordinator.status == .waitingToCatch {
            return "Archivo entrante listo — abre la palma ✋"
        }
        if lan.peers.isEmpty {
            return "Buscando Android o Windows PC en puertos 47831/47832"
        }
        return "\(lan.peers.count) dispositivo(s) cercano(s) listo(s)"
    }

    private func sectionHeader(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(HSColor.label)
            Spacer()
            Button(action: action) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(HSColor.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func controlPill(
        icon: String,
        label: String,
        active: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(active ? color : HSColor.fill)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(active ? .white : HSColor.secondary)
                    )
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(HSColor.label)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func quickActionTile(
        title: String,
        subtitle: String,
        icon: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(HSColor.label)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(HSColor.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ContinuityHeroCardView: View {
    let isReady: Bool
    let peerCount: Int
    let isHolding: Bool
    let statusText: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Continuidad")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                    Text(isReady ? "Activo" : "Activar")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text(statusText)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(peerCount > 0 ? HSColor.green : HSColor.orange)
                            .frame(width: 8, height: 8)
                        Text("\(peerCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.16), in: Capsule())
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 82, height: 82)
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
                        .frame(width: 62, height: 62)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: isHolding ? "hand.draw.fill" : "hand.raised.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(HSColor.blue)
                        )
                }
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: isReady
                        ? [Color(red: 0.05, green: 0.25, blue: 0.58), Color(red: 0.08, green: 0.45, blue: 0.88)]
                        : [Color(red: 0.19, green: 0.20, blue: 0.23), Color(red: 0.11, green: 0.12, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
