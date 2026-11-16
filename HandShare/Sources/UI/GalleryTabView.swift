import AVKit
import Photos
import SwiftUI

struct GalleryTabView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var photos = PhotoLibraryService.shared
    @ObservedObject private var history = TransferHistoryStore.shared
    let onOpenViewer: (PHAsset) -> Void

    @State private var selectedFilter: GalleryFilter = .all
    @State private var isMultiSelectMode = false
    @State private var selectedIds: [String] = []

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    private var filteredAssets: [PHAsset] {
        let all = photos.assets
        switch selectedFilter {
        case .all:
            return all
        case .photos:
            return all.filter { $0.mediaType == .image }
        case .videos:
            return all.filter { $0.mediaType == .video }
        case .received:
            let ids = Set(history.records.filter { !$0.isSender }.compactMap { $0.localAssetIdentifier })
            return all.filter { ids.contains($0.localIdentifier) }
        case .sent:
            let ids = Set(history.records.filter { $0.isSender }.compactMap { $0.localAssetIdentifier })
            return all.filter { ids.contains($0.localIdentifier) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Galería")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(HSColor.label)
                Spacer()

                Button {
                    withAnimation {
                        isMultiSelectMode.toggle()
                        if !isMultiSelectMode {
                            selectedIds.removeAll()
                        }
                    }
                } label: {
                    Text(isMultiSelectMode ? "Listo" : "Seleccionar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HSColor.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(HSColor.card, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GalleryFilter.allCases) { filter in
                        let active = selectedFilter == filter
                        Button {
                            selectedFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(active ? .white : HSColor.label)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(active ? HSColor.blue : HSColor.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            if !photos.isAuthorized {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 46))
                        .foregroundColor(HSColor.blue)
                    Text("Autoriza acceso a tus Fotos")
                        .font(.system(size: 18, weight: .bold))
                    Text("Para abrir cualquier foto o video y usar el gesto ✋ → ✊ igual que en Android.")
                        .font(.system(size: 14))
                        .foregroundColor(HSColor.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                    Button("Permitir Fototeca") {
                        Task { _ = await photos.requestAuthorization() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HSColor.blue)
                }
                Spacer()
            } else if filteredAssets.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundColor(HSColor.secondary)
                    Text("No hay elementos en este filtro")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(HSColor.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(filteredAssets, id: \.localIdentifier) { asset in
                            let selIdx = selectedIds.firstIndex(of: asset.localIdentifier)
                            Button {
                                if isMultiSelectMode {
                                    toggleSelection(asset.localIdentifier)
                                } else {
                                    onOpenViewer(asset)
                                }
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    PHAssetThumbnailView(asset: asset, size: CGSize(width: 240, height: 240))
                                        .aspectRatio(1, contentMode: .fill)

                                    if isMultiSelectMode {
                                        ZStack {
                                            Circle()
                                                .fill(selIdx != nil ? HSColor.blue : Color.black.opacity(0.35))
                                                .frame(width: 24, height: 24)
                                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                            if let selIdx {
                                                Text("\(selIdx + 1)")
                                                    .font(.system(size: 11.5, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .padding(6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }

            if isMultiSelectMode && !selectedIds.isEmpty {
                HStack {
                    Text("\(selectedIds.count) seleccionada(s)")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(HSColor.label)
                    Spacer()
                    Button {
                        let assets = selectedIds.compactMap { id in
                            filteredAssets.first(where: { $0.localIdentifier == id })
                        }
                        isMultiSelectMode = false
                        selectedIds.removeAll()
                        coordinator.grabMultipleAssets(assets)
                    } label: {
                        Label("Enviar / Agarrar", systemImage: "paperplane.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(HSColor.blue, in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .padding(.bottom, 76)
            }
        }
        .background(HSColor.background)
    }

    private func toggleSelection(_ id: String) {
        if let idx = selectedIds.firstIndex(of: id) {
            selectedIds.remove(at: idx)
        } else if selectedIds.count < 20 {
            selectedIds.append(id)
        }
        HapticEngine.shared.subtleTap()
    }
}

struct FullscreenMediaViewerView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    let assets: [PHAsset]
    let initialAsset: PHAsset
    let onClose: () -> Void

    @State private var currentId: String
    @State private var showChrome = true
    @ObservedObject private var prefs = AppPreferences.shared

    init(
        coordinator: GrabSessionCoordinator,
        assets: [PHAsset],
        initialAsset: PHAsset,
        onClose: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.assets = assets.isEmpty ? [initialAsset] : assets
        self.initialAsset = initialAsset
        self.onClose = onClose
        _currentId = State(initialValue: initialAsset.localIdentifier)
    }

    private var currentAsset: PHAsset? {
        assets.first(where: { $0.localIdentifier == currentId }) ?? initialAsset
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentId) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    FullAssetPageView(asset: asset)
                        .tag(asset.localIdentifier)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showChrome.toggle()
                            }
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if showChrome {
                VStack {
                    HStack {
                        Button {
                            coordinator.setActiveViewerAsset(nil, isOpen: false)
                            if coordinator.isHoldingCard {
                                coordinator.isHeldCardDocked = true
                            } else {
                                coordinator.setRadarActive(false)
                            }
                            onClose()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.55), in: Circle())
                        }
                        Spacer()

                        Button {
                            if let asset = currentAsset {
                                coordinator.grabAsset(asset, fromViewer: true)
                            }
                        } label: {
                            Label("Agarrar", systemImage: "hand.raised.fill")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(HSColor.blue.opacity(0.9), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer()
                }
            }

            // Floating Aurora Bubble inside viewer
            AirAuroraBubbleView(
                isRadarActive: coordinator.isRadarActive,
                isHoldingCard: coordinator.isHoldingCard,
                badgeCount: coordinator.grabbedAssets.count
            ) {
                coordinator.toggleRadar(for: currentAsset)
            }

            // Simulator HUD (when radar is on & simulator controls enabled)
            if coordinator.isRadarActive && prefs.showSimulatorDevControls {
                VStack {
                    Spacer()
                    SimulatorGestureHudView(coordinator: coordinator)
                        .padding(.bottom, 22)
                }
            }
        }
        .onAppear {
            coordinator.setActiveViewerAsset(currentAsset, isOpen: true)
        }
        .onDisappear {
            coordinator.setActiveViewerAsset(nil, isOpen: false)
        }
        .onChange(of: currentId) { _ in
            if coordinator.isHoldingCard {
                coordinator.isHeldCardDocked = true
            }
            coordinator.setActiveViewerAsset(currentAsset, isOpen: true)
        }
    }
}

private struct FullAssetPageView: View {
    let asset: PHAsset
    @State private var fullImage: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if asset.mediaType == .video, let player {
                VideoPlayer(player: player)
            } else if let fullImage {
                Image(uiImage: fullImage)
                    .resizable()
                    .scaledToFit()
            } else {
                PHAssetThumbnailView(asset: asset, size: CGSize(width: 720, height: 1280))
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: asset.localIdentifier) {
            if asset.mediaType == .video {
                if let av = await PhotoLibraryService.shared.requestAVAsset(for: asset) {
                    let item = AVPlayerItem(asset: av)
                    player = AVPlayer(playerItem: item)
                }
            } else {
                fullImage = await PhotoLibraryService.shared.requestFullImage(for: asset)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
