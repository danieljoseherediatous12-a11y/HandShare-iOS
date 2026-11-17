import Photos
import SwiftUI

@main
struct HandShareApp: App {
    @StateObject private var coordinator = GrabSessionCoordinator.shared
    @StateObject private var prefs = AppPreferences.shared

    var body: some Scene {
        WindowGroup {
            RootContainerView(coordinator: coordinator, prefs: prefs)
                .preferredColorScheme(.light)
        }
    }
}

private struct IdentifiableGuideMode: Identifiable {
    let isSender: Bool
    var id: Bool { isSender }
}

private struct ViewerAssetBox: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

struct RootContainerView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject var prefs: AppPreferences
    @ObservedObject private var photos = PhotoLibraryService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeTab: HSTab = .home
    @State private var viewerAssetBox: ViewerAssetBox?
    @State private var showManualConnect = false
    @State private var showProfileSheet = false
    @State private var showPreferencesSheet = false
    @State private var showWelcomeSheet = false
    @State private var activeGuide: IdentifiableGuideMode?

    var body: some View {
        ZStack {
            if !prefs.hasCompletedOnboarding {
                OnboardingView(coordinator: coordinator)
            } else {
                mainWorkspace
            }

            EdgeGlowOverlayView(isVisible: coordinator.isEdgeGlowVisible)

            if coordinator.showAlreadySelectedPill {
                VStack {
                    AlreadySelectedPillView()
                        .padding(.top, 56)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }

            if coordinator.isHoldingCard {
                FloatingHeldCardView(
                    previewImage: coordinator.floatingPreviewImage,
                    stackCount: max(1, coordinator.grabbedAssets.count),
                    isDocked: coordinator.isHeldCardDocked,
                    status: coordinator.status,
                    transferState: coordinator.transferState,
                    targetName: coordinator.selectedTargetName,
                    onTapCard: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            coordinator.isHeldCardDocked.toggle()
                        }
                    },
                    onCancel: {
                        coordinator.cancelHeldGrab()
                    }
                )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            if coordinator.status == .waitingToCatch {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(Color.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Archivo listo en el aire")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(.white)
                            Text("Abre la palma ✋ frente a la cámara o toca Atrapar")
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Button("Atrapar") {
                            coordinator.commitCatchNow()
                        }
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(HSColor.blue, in: Capsule())
                    }
                    .padding(12)
                    .background(Color(red: 0.08, green: 0.11, blue: 0.16).opacity(0.92),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.cyan.opacity(0.55), lineWidth: 1.2)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 54)
                    Spacer()
                }
            }

            if let message = coordinator.caughtBannerMessage {
                CatchLandingOverlayView(
                    message: message,
                    item: coordinator.activeCatchPreviewItem
                ) {
                    coordinator.dismissCatchPreview()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: coordinator.showAlreadySelectedPill)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: coordinator.isHoldingCard)
        .sheet(isPresented: $showManualConnect) {
            ManualConnectSheetView(coordinator: coordinator) {
                showManualConnect = false
            }
        }
        .sheet(isPresented: $showProfileSheet) {
            DeviceProfileAndEngineSheetView(
                coordinator: coordinator,
                onDismiss: { showProfileSheet = false },
                onOpenWelcome: {
                    showProfileSheet = false
                    showWelcomeSheet = true
                }
            )
        }
        .sheet(isPresented: $showPreferencesSheet) {
            UserPreferencesSheetView(
                coordinator: coordinator,
                onDismiss: { showPreferencesSheet = false },
                onOpenWelcome: {
                    showPreferencesSheet = false
                    showWelcomeSheet = true
                }
            )
        }
        .fullScreenCover(isPresented: $showWelcomeSheet) {
            OnboardingView(coordinator: coordinator) {
                showWelcomeSheet = false
            }
        }
        .sheet(item: $activeGuide) { guide in
            GestureGuideSheetView(isSender: guide.isSender) {
                activeGuide = nil
            }
        }
        .fullScreenCover(item: $viewerAssetBox) { box in
            ZStack {
                FullscreenMediaViewerView(
                    coordinator: coordinator,
                    assets: photos.assets,
                    initialAsset: box.asset
                ) {
                    viewerAssetBox = nil
                }

                EdgeGlowOverlayView(isVisible: coordinator.isEdgeGlowVisible)

                if coordinator.showAlreadySelectedPill {
                    VStack {
                        AlreadySelectedPillView()
                            .padding(.top, 56)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                if coordinator.isHoldingCard {
                    FloatingHeldCardView(
                        previewImage: coordinator.floatingPreviewImage,
                        stackCount: max(1, coordinator.grabbedAssets.count),
                        isDocked: coordinator.isHeldCardDocked,
                        status: coordinator.status,
                        transferState: coordinator.transferState,
                        targetName: coordinator.selectedTargetName,
                        onTapCard: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                coordinator.isHeldCardDocked.toggle()
                            }
                        },
                        onCancel: {
                            coordinator.cancelHeldGrab()
                        }
                    )
                }
            }
        }
        .onAppear {
            coordinator.startNetworking()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                photos.refreshAuthorization()
                coordinator.detector.refreshPermissionStatus()
                coordinator.lan.refreshDiscovery()
            }
        }
    }

    private var mainWorkspace: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch activeTab {
                case .home:
                    HomeTabView(
                        coordinator: coordinator,
                        activeTab: $activeTab,
                        onOpenViewer: { asset in
                            viewerAssetBox = ViewerAssetBox(asset: asset)
                        },
                        onOpenManualConnect: {
                            showManualConnect = true
                        },
                        onOpenGuide: { isSender in
                            activeGuide = IdentifiableGuideMode(isSender: isSender)
                        }
                    )
                case .gallery:
                    GalleryTabView(coordinator: coordinator) { asset in
                        viewerAssetBox = ViewerAssetBox(asset: asset)
                    }
                case .devices:
                    DevicesTabView(coordinator: coordinator) {
                        showManualConnect = true
                    }
                case .settings:
                    SettingsTabView(
                        coordinator: coordinator,
                        onOpenProfile: { showProfileSheet = true },
                        onOpenPreferences: { showPreferencesSheet = true },
                        onOpenWelcome: { showWelcomeSheet = true },
                        onOpenGuide: { isSender in
                            activeGuide = IdentifiableGuideMode(isSender: isSender)
                        }
                    )
                }
            }

            FloatingGlassTabBar(activeTab: $activeTab)
        }
        .background(HSColor.background.ignoresSafeArea())
    }
}
