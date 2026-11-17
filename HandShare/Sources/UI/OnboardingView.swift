import Combine
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var photos = PhotoLibraryService.shared
    @ObservedObject private var lan = LanTransportService.shared
    @ObservedObject private var detector: CameraHandDetector
    var onFinished: (() -> Void)? = nil

    @State private var page = 0
    @State private var showDeniedSettingsAlert = false
    @State private var deniedAlertMessage = ""

    init(coordinator: GrabSessionCoordinator, onFinished: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self.onFinished = onFinished
        _detector = ObservedObject(wrappedValue: coordinator.detector)
    }

    private var cameraReadyOrNotApplicable: Bool {
        detector.cameraPermissionGranted || !detector.hasFrontCamera
    }

    private var readyCount: Int {
        [photos.isAuthorized, cameraReadyOrNotApplicable, lan.isWifiAvailable].filter { $0 }.count
    }

    private var allReady: Bool {
        photos.isAuthorized && cameraReadyOrNotApplicable && lan.isWifiAvailable
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Progress Pills matching Android WelcomeOnboardingDialog
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(page >= i ? HSColor.blue : HSColor.tertiary)
                        .frame(width: page == i ? 26 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: page)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 12)

            TabView(selection: $page) {
                WelcomeHeroStepView().tag(0)
                InteractiveGestureDemoStepView().tag(1)
                systemActivationStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Bottom Primary Action Row matching Android
            HStack(spacing: 12) {
                if page > 0 {
                    Button {
                        withAnimation { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(HSColor.label)
                            .frame(width: 64, height: 56)
                            .background(HSColor.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                let canFinish = page < 2 || allReady
                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else if canFinish {
                        finish()
                    } else {
                        Task {
                            await requestRemainingPermissions()
                        }
                    }
                } label: {
                    Text(buttonTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(canFinish ? .white : HSColor.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(
                            canFinish ? HSColor.blue : HSColor.fill,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .shadow(color: (canFinish ? HSColor.blue : HSColor.secondary).opacity(0.32), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding_primary_btn")
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            if page == 2 && !allReady {
                Button("Continuar a HandShare") {
                    finish()
                }
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(HSColor.secondary)
                .padding(.top, 8)
                .accessibilityIdentifier("onboarding_continue_btn")
            }
        }
        .padding(.bottom, 22)
        .background(HSColor.background.ignoresSafeArea())
        .alert("Permisos en Ajustes de iOS", isPresented: $showDeniedSettingsAlert) {
            Button("Abrir Ajustes") {
                openSystemAppSettings()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(deniedAlertMessage)
        }
    }

    private var buttonTitle: String {
        switch page {
        case 0: return "Descubrir cómo funciona"
        case 1: return "Configurar mi dispositivo"
        default:
            return allReady ? "Comenzar a usar HandShare" : "Activar permisos (\(readyCount)/3)"
        }
    }

    private func requestRemainingPermissions() async {
        if photos.authorizationStatus == .notDetermined {
            _ = await photos.requestAuthorization()
        }
        if detector.hasFrontCamera && detector.authorizationStatus == .notDetermined {
            _ = await detector.requestPermissionAndStart()
        }
        coordinator.startNetworking()

        photos.refreshAuthorization()
        detector.refreshPermissionStatus()
        lan.refreshDiscovery()

        var deniedNames: [String] = []
        if photos.isDeniedOrRestricted { deniedNames.append("Fototeca") }
        if detector.hasFrontCamera && detector.isDeniedOrRestricted { deniedNames.append("Cámara") }
        if !lan.isWifiAvailable { deniedNames.append("Wi‑Fi / Red local") }

        if !deniedNames.isEmpty {
            deniedAlertMessage = "Activa \(deniedNames.joined(separator: ", ")) en Ajustes de iOS para usar HandShare al 100%."
            showDeniedSettingsAlert = true
        }
    }

    private func finish() {
        coordinator.startNetworking()
        coordinator.prefs.hasCompletedOnboarding = true
        onFinished?()
    }

    private var systemActivationStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Activa tu dispositivo")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundColor(HSColor.label)
                    .padding(.top, 10)
                Text("Solo unos toques para conectar iPhone con tu Android y PC Windows.")
                    .font(.system(size: 14.5))
                    .foregroundColor(HSColor.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                IosGroupCard {
                    activationRow(
                        icon: "photo.on.rectangle.angled",
                        tint: HSColor.blue,
                        title: "Fototeca (Fotos y Videos)",
                        subtitle: photos.isAuthorized
                            ? "Acceso listo"
                            : (photos.isDeniedOrRestricted ? "Denegado · Toca para abrir Ajustes" : "Toca para mostrar tu galería"),
                        actionTitle: photos.isDeniedOrRestricted ? "Ajustes" : "Activar",
                        granted: photos.isAuthorized
                    ) {
                        Task { _ = await photos.requestAuthorizationOrOpenSettings() }
                    }
                    RowDividerLine()
                    activationRow(
                        icon: "camera.fill",
                        tint: HSColor.green,
                        title: "Cámara Frontal IA",
                        subtitle: cameraSubtitle,
                        actionTitle: detector.isDeniedOrRestricted ? "Ajustes" : "Activar",
                        granted: detector.cameraPermissionGranted
                    ) {
                        Task { _ = await detector.requestPermissionOrOpenSettings() }
                    }
                    RowDividerLine()
                    activationRow(
                        icon: "wifi",
                        tint: HSColor.indigo,
                        title: "Red Local Wi‑Fi",
                        subtitle: lan.isWifiAvailable
                            ? "Puertos \(LanProtocol.udpDiscoveryPort) / \(lan.activeTcpPort) activos"
                            : "Conéctate al Wi‑Fi o revisa Red local en Ajustes",
                        actionTitle: "Ajustes",
                        granted: lan.isWifiAvailable
                    ) {
                        coordinator.startNetworking()
                        lan.refreshDiscovery()
                        if !lan.isWifiAvailable {
                            openSystemAppSettings()
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var cameraSubtitle: String {
        if detector.cameraPermissionGranted {
            return detector.hasFrontCamera ? "Reconocimiento listo" : "Permiso OK (sin cámara física en simulador)"
        }
        if !detector.hasFrontCamera {
            return "No disponible en simulador (funcionará en iPhone)"
        }
        return detector.isDeniedOrRestricted ? "Denegado · Toca para abrir Ajustes" : "Para leer palma ✋ y puño ✊"
    }

    private func activationRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        actionTitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(HSColor.label)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundColor(HSColor.secondary)
                }
                Spacer()
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(HSColor.green)
                } else {
                    Text(actionTitle)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(tint, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

private struct WelcomeHeroStepView: View {
    @State private var orbit: Double = 0
    @State private var floatY: CGFloat = -6

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [HSColor.cyan.opacity(0.25), .clear],
                                center: .center,
                                startRadius: 8,
                                endRadius: 72
                            )
                        )
                        .frame(width: 144, height: 144)

                    Circle()
                        .stroke(HSColor.blue.opacity(0.16), lineWidth: 1.5)
                        .frame(width: 128, height: 128)

                    ForEach(0..<3, id: \.self) { i in
                        let a = orbit + Double(i) * (2.0 * .pi / 3.0)
                        Circle()
                            .fill(HSColor.cyan)
                            .frame(width: 9, height: 9)
                            .offset(x: cos(a) * 64, y: sin(a) * 64)
                    }

                    HandShareHeaderLogo(size: 76)
                        .shadow(color: HSColor.blue.opacity(0.45), radius: 14, x: 0, y: 8)
                        .offset(y: floatY)
                }
                .padding(.top, 4)

                Text("Bienvenido a HandShare")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundColor(HSColor.label)
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                Text("Comparte fotos y videos de un celular a otro en el aire usando únicamente el gesto de tu mano.")
                    .font(.system(size: 14.5))
                    .foregroundColor(HSColor.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                VStack(spacing: 13) {
                    featureRow("hand.raised.fill", HSColor.blue,
                               "Galería Air integrada",
                               "Abre cualquier foto o video en iPhone y usa el mismo flujo flotante que Android.")
                    featureRow("sparkles", HSColor.cyan,
                               "Animación Nativa Air Hop",
                               "El archivo se despega de la pantalla, flota mientras esperas y aterriza con onda de luz.")
                    featureRow("bolt.fill", HSColor.green,
                               "Velocidad P2P Wi‑Fi",
                               "Conecta iPhone, Android y Windows PC en tu misma red sin usar Internet.")
                }
                .padding(16)
                .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)
        }
        .onAppear {
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                orbit = .pi * 2
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                floatY = 6
            }
        }
    }

    private func featureRow(_ icon: String, _ tint: Color, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tint)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(HSColor.label)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(HSColor.secondary)
            }
            Spacer()
        }
    }
}

private struct InteractiveGestureDemoStepView: View {
    @State private var stage: Int = 0
    @State private var handBob: CGFloat = -4
    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Cómo se utiliza")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundColor(HSColor.label)
                    .padding(.top, 8)
                Text("Tres gestos naturales en el aire, sin tocar la pantalla")
                    .font(.system(size: 14.5))
                    .foregroundColor(HSColor.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                // Clean Studio Stage matching Android WelcomeOnboardingDialog
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let pW = w * 0.23
                    let pH = h * 0.74
                    let lX = w * 0.13
                    let rX = w * 0.64
                    let pY = (h - pH) / 2

                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(HSColor.card)

                        // Phone A & Phone B
                        demoPhone(glowing: stage == 0 || stage == 1, width: pW, height: pH)
                            .position(x: lX + pW / 2, y: pY + pH / 2)

                        demoPhone(glowing: stage == 2, width: pW, height: pH)
                            .position(x: rX + pW / 2, y: pY + pH / 2)

                        // Traveling Photo Card
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [HSColor.blue, HSColor.indigo, HSColor.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.85), lineWidth: 1.2))
                            .frame(width: pW * 0.68, height: pH * 0.50)
                            .shadow(color: Color.black.opacity(stage == 1 ? 0.22 : 0.08), radius: 8, x: 0, y: 5)
                            .position(
                                x: stage == 0 ? (lX + pW / 2) : (stage == 1 ? w / 2 : (rX + pW / 2)),
                                y: pY + pH / 2 + (stage == 1 ? handBob - 10 : 0)
                            )

                        // Tutorial 3D Hand Image from Android assets
                        Image(stage == 1 ? "HandFist" : "HandOpen")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 78, height: 78)
                            .position(
                                x: stage == 0 ? (lX + pW / 2) : (stage == 1 ? w / 2 : (rX + pW / 2)),
                                y: pY + pH / 2 - 18 + (stage == 1 ? handBob : 0)
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(HSColor.separator, lineWidth: 1.2)
                    )
                    .animation(.spring(response: 0.55, dampingFraction: 0.78), value: stage)
                }
                .frame(height: 215)
                .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    stageChip(0, "1. Palma ✋")
                    stageChip(1, "2. Puño ✊")
                    stageChip(2, "3. Soltar ✋")
                }
                .padding(.horizontal, 20)

                Text(stageDescription)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HSColor.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
        }
        .onReceive(timer) { _ in
            stage = (stage + 1) % 3
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                handBob = 5
            }
        }
    }

    private var stageDescription: String {
        switch stage {
        case 0: "Acerca la palma abierta frente a la cámara hasta iluminar los bordes."
        case 1: "Cierra el puño para levantar la foto flotando y llevarla contigo."
        default: "Abre la palma frente al otro dispositivo para guardarla al instante."
        }
    }

    private func stageChip(_ idx: Int, _ label: String) -> some View {
        let active = stage == idx
        return Button {
            stage = idx
        } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(active ? .white : HSColor.label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(active ? HSColor.blue : HSColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func demoPhone(glowing: Bool, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            if glowing {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HSColor.cyan.opacity(0.28))
                    .frame(width: width + 18, height: height + 18)
                    .blur(radius: 6)
            }
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.118, green: 0.161, blue: 0.231))
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.88, green: 0.91, blue: 1.0), Color(red: 0.87, green: 0.84, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(3.5)
                )
            Capsule()
                .fill(Color(red: 0.06, green: 0.09, blue: 0.16))
                .frame(width: width * 0.34, height: 7)
                .padding(.top, 7)
        }
    }
}
