import AVKit
import Photos
import PhotosUI
import SwiftUI

struct GalleryTabView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var photos = PhotoLibraryService.shared
    @ObservedObject private var history = TransferHistoryStore.shared
    let onOpenViewer: (PHAsset) -> Void

    @State private var selectedFilterIndex = 0
    @State private var selectionMode = false
    @State private var selectedIds: [String] = []
    @State private var pickerItems: [PhotosPickerItem] = []

    private let filters = ["Todo", "Fotos", "Videos", "Recibidos", "Enviados"]
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var filteredAssets: [PHAsset] {
        let all = photos.assets
        switch selectedFilterIndex {
        case 1:
            return all.filter { $0.mediaType == .image }
        case 2:
            return all.filter { $0.mediaType == .video }
        case 3:
            let ids = Set(history.records.filter { !$0.isSender }.compactMap { $0.localAssetIdentifier })
            return all.filter { ids.contains($0.localIdentifier) }
        case 4:
            let ids = Set(history.records.filter { $0.isSender }.compactMap { $0.localAssetIdentifier })
            return all.filter { ids.contains($0.localIdentifier) }
        default:
            return all
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                LargeTitleBar(title: "Galería") {
                    HStack(spacing: 8) {
                        if selectionMode && !selectedIds.isEmpty {
                            Button {
                                sendSelectedBatch()
                            } label: {
                                Text("Enviar")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(HSColor.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            HapticEngine.shared.subtleTap()
                            withAnimation {
                                selectionMode.toggle()
                                if !selectionMode { selectedIds.removeAll() }
                            }
                        } label: {
                            Text(selectionMode ? "Cancelar" : "Seleccionar")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selectionMode ? HSColor.label : HSColor.blue)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background(
                                    selectionMode ? HSColor.fill : HSColor.blue.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: 20,
                            matching: .any(of: [.images, .videos]),
                            photoLibrary: .shared()
                        ) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(HSColor.blue)
                                .frame(width: 38, height: 38)
                                .background(HSColor.card, in: Circle())
                        }
                    }
                }

                IosSegmentedControlBar(options: filters, selected: $selectedFilterIndex)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)

                if selectionMode {
                    HStack {
                        Text(selectedIds.isEmpty
                             ? "Toca varias fotos o videos para seleccionarlos"
                             : "\(selectedIds.count) seleccionados")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(HSColor.blue)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                } else {
                    Spacer().frame(height: 10)
                }

                if !photos.isAuthorized {
                    Spacer()
                    VStack(spacing: 14) {
                        Circle()
                            .fill(HSColor.fill)
                            .frame(width: 76, height: 76)
                            .overlay(
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 32))
                                    .foregroundColor(HSColor.blue)
                            )
                        Text("Autoriza tu Fototeca")
                            .font(.system(size: 16, weight: .bold))
                        Text("Para ver todas tus fotos y videos aquí igual que en Android.")
                            .font(.system(size: 13.5))
                            .foregroundColor(HSColor.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                        Button(photos.isDeniedOrRestricted ? "Abrir Ajustes" : "Permitir Fototeca") {
                            Task { _ = await photos.requestAuthorizationOrOpenSettings() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HSColor.blue)
                        .accessibilityIdentifier("gallery_allow_photos_btn")
                    }
                    .padding(.bottom, 100)
                    Spacer()
                } else if filteredAssets.isEmpty {
                    Spacer()
                    VStack(spacing: 14) {
                        Circle()
                            .fill(HSColor.fill)
                            .frame(width: 76, height: 76)
                            .overlay(
                                Image(systemName: selectedFilterIndex == 3 ? "square.and.arrow.down" : (selectedFilterIndex == 4 ? "paperplane.fill" : "photo.on.rectangle"))
                                    .font(.system(size: 30))
                                    .foregroundColor(HSColor.secondary)
                            )
                        Text(emptyLabel)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(HSColor.secondary)
                        CircleIconButton(icon: "arrow.clockwise", tint: HSColor.blue, accessibilityTitle: "Recargar galería") {
                            photos.reloadAssets()
                        }
                    }
                    .padding(.bottom, 100)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(filteredAssets, id: \.localIdentifier) { asset in
                                let selIndex = selectedIds.firstIndex(of: asset.localIdentifier)
                                let isSelected = selIndex != nil
                                Button {
                                    if selectionMode {
                                        toggleSelection(asset.localIdentifier)
                                    } else {
                                        onOpenViewer(asset)
                                    }
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        PHAssetThumbnailView(asset: asset, size: CGSize(width: 240, height: 240))
                                            .aspectRatio(1, contentMode: .fill)
                                            .scaleEffect(isSelected ? 0.90 : 1.0)
                                            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isSelected)

                                        if isSelected {
                                            Rectangle()
                                                .fill(HSColor.blue.opacity(0.24))
                                                .overlay(Rectangle().stroke(HSColor.blue, lineWidth: 2.5))
                                        }

                                        if selectionMode {
                                            ZStack {
                                                Circle()
                                                    .fill(isSelected ? HSColor.blue : Color.black.opacity(0.42))
                                                    .frame(width: 24, height: 24)
                                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                                if let selIndex {
                                                    Text("\(selIndex + 1)")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(.white)
                                                }
                                            }
                                            .padding(7)
                                        }
                                    }
                                    .background(HSColor.fill)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                                        HapticEngine.shared.grabSuccess()
                                        if !selectionMode { selectionMode = true }
                                        if !selectedIds.contains(asset.localIdentifier), selectedIds.count < 20 {
                                            selectedIds.append(asset.localIdentifier)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.bottom, !selectedIds.isEmpty ? 185 : 120)
                    }
                }
            }

            if selectionMode && !selectedIds.isEmpty {
                Button {
                    sendSelectedBatch()
                } label: {
                    Text("Enviar")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 11)
                        .background(HSColor.blue, in: Capsule())
                        .shadow(color: HSColor.blue.opacity(0.45), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 108)
            }
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

    private var emptyLabel: String {
        switch selectedFilterIndex {
        case 3: return "Aún no has recibido fotos ni videos"
        case 4: return "Aún no has enviado fotos ni videos"
        default: return "No se encontraron archivos"
        }
    }

    private func toggleSelection(_ id: String) {
        HapticEngine.shared.subtleTap()
        if let idx = selectedIds.firstIndex(of: id) {
            selectedIds.remove(at: idx)
        } else if selectedIds.count < 20 {
            selectedIds.append(id)
        }
    }

    private func sendSelectedBatch() {
        HapticEngine.shared.grabSuccess()
        let assets = selectedIds.compactMap { id in
            filteredAssets.first(where: { $0.localIdentifier == id })
        }
        selectionMode = false
        selectedIds.removeAll()
        coordinator.grabMultipleAssets(assets)
    }
}

struct FullscreenMediaViewerView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    let assets: [PHAsset]
    let initialAsset: PHAsset
    let onClose: () -> Void

    @State private var currentId: String
    @State private var showChrome = true
    @ObservedObject private var detector: CameraHandDetector

    init(
        coordinator: GrabSessionCoordinator,
        assets: [PHAsset],
        initialAsset: PHAsset,
        onClose: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        _detector = ObservedObject(wrappedValue: coordinator.detector)
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
                        .accessibilityLabel("Volver")
                        .accessibilityIdentifier("viewer_back_btn")
                        Spacer()

                        Button {
                            coordinator.grabAsset(currentAsset ?? initialAsset, fromViewer: true)
                        } label: {
                            Label("Agarrar", systemImage: "hand.raised.fill")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(HSColor.blue.opacity(0.9), in: Capsule())
                        }
                        .accessibilityIdentifier("viewer_grab_btn")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer()
                }
            }

            AirAuroraBubbleView(
                isRadarActive: coordinator.isRadarActive,
                isHoldingCard: coordinator.isHoldingCard,
                badgeCount: coordinator.grabbedAssets.count
            ) {
                coordinator.toggleRadar(for: currentAsset)
            }

            if coordinator.isRadarActive {
                VStack {
                    Spacer()
                    LiveGestureRadarStatusPillView(
                        detector: detector,
                        isHoldingCard: coordinator.isHoldingCard
                    )
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
                    player = AVPlayer(playerItem: AVPlayerItem(asset: av))
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
