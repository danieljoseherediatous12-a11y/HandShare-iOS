import SwiftUI

struct OnboardingView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var photos = PhotoLibraryService.shared
    @ObservedObject private var lan = LanTransportService.shared
    @ObservedObject private var detector: CameraHandDetector
    @State private var page = 0

    init(coordinator: GrabSessionCoordinator) {
        self.coordinator = coordinator
        _detector = ObservedObject(wrappedValue: coordinator.detector)
    }

    var body: some View {
        ZStack {
            HSColor.background.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    HandShareHeaderLogo(size: 36)
                    Text("HandShare")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(HSColor.label)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                TabView(selection: $page) {
                    onboardingStep(
                        icon: "hand.raised.fingers.spread.fill",
                        tint: HSColor.blue,
                        title: "Agarra en el aire",
                        subtitle: "Abre una foto en HandShare, activa la burbuja Aurora, muestra la palma abierta (✋) y cierra el puño (✊) para llevártela flotando.",
                        tag: 0
                    )
                    onboardingStep(
                        icon: "wifi",
                        tint: HSColor.indigo,
                        title: "iPhone, Android y Windows",
                        subtitle: "Conéctate en la misma red Wi-Fi usando puertos locales 47831/47832 y transfiere fotos o videos originales sin cables.",
                        tag: 1
                    )
                    permissionsStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        completeOnboarding()
                    }
                } label: {
                    Text(page < 2 ? "Continuar" : "Empezar a usar HandShare")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [HSColor.blue, HSColor.indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private func onboardingStep(icon: String, tint: Color, title: String, subtitle: String, tag: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 118, height: 118)
                Image(systemName: icon)
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundColor(tint)
            }
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(HSColor.label)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 15.5))
                .foregroundColor(HSColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .tag(tag)
    }

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Permisos rápidos")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(HSColor.label)
            Text("Activa Fototeca y Cámara para abrir tu carrete y reconocer gestos.")
                .font(.system(size: 14.5))
                .foregroundColor(HSColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                permissionRow(
                    icon: "photo.on.rectangle.angled",
                    tint: HSColor.blue,
                    title: "Fototeca (Fotos y Videos)",
                    granted: photos.isAuthorized
                ) {
                    Task { _ = await photos.requestAuthorization() }
                }

                permissionRow(
                    icon: "camera.fill",
                    tint: HSColor.green,
                    title: "Cámara Frontal (Gestos)",
                    granted: detector.cameraPermissionGranted
                ) {
                    Task { await detector.requestPermissionAndStart() }
                }

                permissionRow(
                    icon: "bonjour",
                    tint: HSColor.indigo,
                    title: "Red Local Wi-Fi (47831/47832)",
                    granted: lan.isWifiAvailable
                ) {
                    coordinator.startNetworking()
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func permissionRow(
        icon: String,
        tint: Color,
        title: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(HSColor.label)
            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(HSColor.green)
            } else {
                Button("Permitir", action: action)
                    .font(.system(size: 13.5, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
        }
        .padding(14)
        .background(HSColor.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func completeOnboarding() {
        coordinator.startNetworking()
        coordinator.prefs.hasCompletedOnboarding = true
    }
}
