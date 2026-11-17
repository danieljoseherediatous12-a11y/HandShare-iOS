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
    @State private var pickerItems: [PhotosPickerItem] = []

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

    private var isReady: Bool {
        lan.isWifiAvailable && photos.isAuthorized
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LargeTitleBar(title: "HandShare") {
                    CircleIconButton(icon: "gearshape.fill", accessibilityTitle: "Ajustes") {
                        withAnimation { activeTab = .settings }
                    }
                }

                // Continuity Hero Card (Exact Android/iOS Twin)
                ContinuityHeroCardView(
                    isReady: isReady,
                    nearbyCount: lan.peers.count
                ) {
                    if !photos.isAuthorized {
                        Task { _ = await photos.requestAuthorizationOrOpenSettings() }
                    } else {
                        withAnimation { activeTab = .gallery }
                    }
                }
                .padding(.horizontal, 16)
                .accessibilityIdentifier("home_hero_card")

                Spacer().frame(height: 14)

                // Control Center toggles
                HStack(spacing: 0) {
                    controlToggle(
                        icon: lan.isWifiAvailable ? "wifi" : "wifi.slash",
                        label: "Wi‑Fi",
                        active: lan.isWifiAvailable,
                        color: HSColor.blue
                    ) {
                        lan.refreshDiscovery()
                        if !lan.isWifiAvailable {
                            openSystemAppSettings()
                        }
                    }
                    controlToggle(
                        icon: "bonjour",
                        label: "Red local",
                        active: lan.isWifiAvailable,
                        color: HSColor.indigo,
                        action: onOpenManualConnect
                    )
                    controlToggle(
                        icon: detector.cameraPermissionGranted ? "camera.fill" : "camera",
                        label: "Cámara",
                        active: detector.cameraPermissionGranted && detector.hasFrontCamera,
                        color: HSColor.green
                    ) {
                        Task { _ = await detector.requestPermissionOrOpenSettings() }
                    }
                    controlToggle(
                        icon: "photo.fill",
                        label: "Fototeca",
                        active: photos.isAuthorized,
                        color: HSColor.green
                    ) {
                        Task { _ = await photos.requestAuthorizationOrOpenSettings() }
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(HSColor.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)

                // Enviar / Recibir Gesture Tiles
                HStack(spacing: 14) {
                    gestureTile(
                        title: "Enviar",
                        icon: "square.and.arrow.up",
                        gradient: [Color(red: 0.039, green: 0.518, blue: 1.0), Color(red: 0.369, green: 0.361, blue: 0.902)]
                    ) { onOpenGuide(true) }

                    gestureTile(
                        title: "Recibir",
                        icon: "square.and.arrow.down",
                        gradient: [Color(red: 0.749, green: 0.353, blue: 0.949), Color(red: 1.0, green: 0.216, blue: 0.373)]
                    ) { onOpenGuide(false) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // Cercanos (AirDrop style)
                SectionHeaderBar(title: "Cercanos") {
                    withAnimation { activeTab = .devices }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        if lan.peers.isEmpty {
                            ScanningAvatarView()
                            RefreshAvatarView { lan.refreshDiscovery() }
                            ManualIpAvatarView(onTap: onOpenManualConnect)
                        } else {
                            ForEach(Array(lan.peers.enumerated()), id: \.element.endpointId) { idx, peer in
                                let isSelected = coordinator.selectedTargetEndpointId == peer.endpointId
                                DeviceAvatarView(
                                    peer: peer,
                                    gradientIndex: idx,
                                    isSelected: isSelected
                                ) {
                                    coordinator.selectPeer(peer)
                                    HapticEngine.shared.subtleTap()
                                }
                            }
                            RefreshAvatarView { lan.refreshDiscovery() }
                            ManualIpAvatarView(onTap: onOpenManualConnect)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Enviados y Recibidos
                SectionHeaderBar(title: "Enviados y Recibidos") {
                    withAnimation { activeTab = .gallery }
                }
                IosSegmentedControlBar(
                    options: [
                        "Recibidos (\(receivedHistory.count))",
                        "Enviados (\(sentHistory.count))"
                    ],
                    selected: $historyDirectionTab
                )
                .padding(.horizontal, 16)

                Spacer().frame(height: 10)

                if activeHistory.isEmpty {
                    HStack(spacing: 12) {
                        Circle()
                            .fill((historyDirectionTab == 0 ? HSColor.green : HSColor.blue).opacity(0.14))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: historyDirectionTab == 0 ? "square.and.arrow.down" : "square.and.arrow.up")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(historyDirectionTab == 0 ? HSColor.green : HSColor.blue)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(historyDirectionTab == 0 ? "Sin archivos recibidos aún" : "Sin archivos enviados aún")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(HSColor.label)
                            Text(historyDirectionTab == 0
                                 ? "Las fotos y videos que atrapes con ✋ aparecerán aquí"
                                 : "Las fotos y videos que envíes con ✋→✊ aparecerán aquí")
                                .font(.system(size: 13))
                                .foregroundColor(HSColor.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 22)
                    .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(activeHistory.prefix(25)) { record in
                                historyCard(record)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Recientes
                SectionHeaderBar(title: "Recientes") {
                    withAnimation { activeTab = .gallery }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos.recentAssets.prefix(16), id: \.localIdentifier) { asset in
                            Button {
                                onOpenViewer(asset)
                            } label: {
                                PHAssetThumbnailView(asset: asset, size: CGSize(width: 240, height: 300))
                                    .frame(width: 116, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: 20,
                            matching: .any(of: [.images, .videos]),
                            photoLibrary: .shared()
                        ) {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(HSColor.card)
                                .frame(width: 116, height: 150)
                                .overlay(
                                    Circle()
                                        .fill(HSColor.blue.opacity(0.12))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Image(systemName: "plus")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(HSColor.blue)
                                        )
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 120)
        }
        .background(HSColor.background)
        .onChange(of: pickerItems) { newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await coordinator.handlePhotosPickerSelection(newItems)
                pickerItems = []
            }
        }
    }

    private func historyCard(_ record: TransferHistoryRecord) -> some View {
        let asset = record.localAssetIdentifier.flatMap { photos.asset(forIdentifier: $0) }
        return Button {
            if let asset {
                onOpenViewer(asset)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let asset {
                    PHAssetThumbnailView(asset: asset, size: CGSize(width: 260, height: 340))
                        .frame(width: 126, height: 164)
                } else {
                    Rectangle()
                        .fill(HSColor.fill)
                        .frame(width: 126, height: 164)
                        .overlay(
                            Image(systemName: record.isVideo ? "video.fill" : "photo.fill")
                                .font(.system(size: 30))
                                .foregroundColor(HSColor.blue)
                        )
                }

                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill((record.isSender ? HSColor.blue : HSColor.green).opacity(0.9))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: record.isSender ? "arrow.up.right" : "arrow.down.left")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .padding(7)
                    }
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 38)
                    .overlay(
                        HStack {
                            Text(record.isSender ? "A \(record.remoteName)" : "De \(record.remoteName)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 9),
                        alignment: .bottomLeading
                    )
                }
            }
            .frame(width: 126, height: 164)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(asset == nil)
        .accessibilityLabel(record.isSender ? "Enviado \(record.fileName) a \(record.remoteName)" : "Recibido \(record.fileName) de \(record.remoteName)")
    }

    private func controlToggle(
        icon: String,
        label: String,
        active: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Circle()
                    .fill(active ? color : HSColor.fill)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(active ? .white : HSColor.secondary)
                    )
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(active ? HSColor.label : HSColor.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(active ? "activo" : "inactivo")")
    }

    private func gestureTile(
        title: String,
        icon: String,
        gradient: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading) {
                    HStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 46, height: 46)
                            .overlay(
                                Image(systemName: icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(HSColor.tertiary)
                    }
                    Spacer()
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(HSColor.label)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 118)
            .background(HSColor.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Guía de \(title)")
    }
}

private struct ContinuityHeroCardView: View {
    let isReady: Bool
    let nearbyCount: Int
    let action: () -> Void

    @State private var ringPhase: Double = 0
    @State private var breathe: CGFloat = 0.94

    var body: some View {
        Button(action: action) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.039, green: 0.518, blue: 1.0),
                        Color(red: 0.247, green: 0.357, blue: 1.0),
                        Color(red: 0.369, green: 0.361, blue: 0.902)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Soft light blobs matching Android Hero
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 130
                        )
                    )
                    .frame(width: 260, height: 260)
                    .offset(x: -110, y: -75)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.392, green: 0.824, blue: 1.0).opacity(0.30), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .offset(x: 115, y: 80)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continuidad")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.78))
                        Text(isReady ? "Listo" : "Activar")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                            .tracking(-1)
                        Spacer().frame(height: 10)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isReady ? Color(red: 0.188, green: 0.820, blue: 0.345) : Color(red: 1.0, green: 0.839, blue: 0.039))
                                .frame(width: 7, height: 7)
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Text("\(nearbyCount)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.20), in: Capsule())
                    }
                    .padding(.leading, 22)

                    Spacer()

                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            let p = (ringPhase + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0)
                            Circle()
                                .stroke(Color.white.opacity((1.0 - p) * 0.45), lineWidth: 1.6)
                                .frame(width: CGFloat(150 * (0.38 + 0.62 * p)), height: CGFloat(150 * (0.38 + 0.62 * p)))
                        }

                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                            .offset(
                                x: cos(ringPhase * .pi * 2) * 54,
                                y: sin(ringPhase * .pi * 2) * 54
                            )

                        Circle()
                            .fill(Color.white)
                            .frame(width: 62, height: 62)
                            .scaleEffect(breathe)
                            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
                            .overlay(
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(Color(red: 0.247, green: 0.357, blue: 1.0))
                            )
                    }
                    .frame(width: 150, height: 150)
                    .padding(.trailing, 14)
                }
            }
            .frame(height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color(red: 0.227, green: 0.357, blue: 1.0).opacity(0.32), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                ringPhase = 1.0
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathe = 1.04
            }
        }
    }
}

private struct DeviceAvatarView: View {
    let peer: HandSharePeer
    let gradientIndex: Int
    let isSelected: Bool
    let onClick: () -> Void

    var body: some View {
        let grad = HSColor.avatarGradients[gradientIndex % HSColor.avatarGradients.count]
        let initials = peer.name
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .prefix(2)
            .compactMap { $0.first?.uppercased() }
            .joined()
        let badgeColor = peer.isConnected ? HSColor.green : HSColor.blue

        Button(action: onClick) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(LinearGradient(colors: grad, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 66, height: 66)
                        .overlay(
                            Group {
                                if peer.isDesktop {
                                    Image(systemName: "desktopcomputer")
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundColor(.white)
                                } else {
                                    Text(initials.isEmpty ? "?" : initials)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        )
                        .overlay(
                            Circle()
                                .stroke(isSelected ? HSColor.blue : .clear, lineWidth: 2.5)
                                .padding(-2.5)
                        )
                        .shadow(color: grad.last?.opacity(0.45) ?? .clear, radius: isSelected ? 10 : 7, x: 0, y: 4)

                    Circle()
                        .fill(HSColor.background)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .fill(isSelected ? HSColor.blue : badgeColor)
                                .padding(3)
                        )
                }

                Text(peer.name)
                    .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? HSColor.blue : HSColor.label)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(peer.name), \(peer.isConnected ? "conectado" : "disponible")")
    }
}

private struct ScanningAvatarView: View {
    @State private var p: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let pp = (p + Double(i) * 0.5).truncatingRemainder(dividingBy: 1.0)
                    Circle()
                        .stroke(HSColor.blue.opacity((1.0 - pp) * 0.5), lineWidth: 1.5)
                        .frame(width: CGFloat(66 * (0.45 + 0.55 * pp)), height: CGFloat(66 * (0.45 + 0.55 * pp)))
                }
                Circle()
                    .fill(HSColor.blue)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 66, height: 66)

            Text("Buscando")
                .font(.system(size: 12))
                .foregroundColor(HSColor.secondary)
        }
        .frame(width: 72)
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                p = 1.0
            }
        }
    }
}

private struct RefreshAvatarView: View {
    let action: () -> Void
    @State private var angle: Double = 0

    var body: some View {
        Button {
            angle += 360
            action()
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(HSColor.card)
                    .frame(width: 66, height: 66)
                    .overlay(
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(HSColor.blue)
                            .rotationEffect(.degrees(angle))
                            .animation(.easeOut(duration: 0.65), value: angle)
                    )
                Text("Actualizar")
                    .font(.system(size: 12))
                    .foregroundColor(HSColor.secondary)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Actualizar dispositivos cercanos")
    }
}

private struct ManualIpAvatarView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Circle()
                    .fill(HSColor.card)
                    .frame(width: 66, height: 66)
                    .overlay(
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(HSColor.indigo)
                    )
                Text("Por IP")
                    .font(.system(size: 12))
                    .foregroundColor(HSColor.secondary)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Conectar por dirección IP")
    }
}
