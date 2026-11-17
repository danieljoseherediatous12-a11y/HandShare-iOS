import SwiftUI
import UIKit

// ═════════════════════════════════════════════════════════════════════════════
// TAB 3 · DISPOSITIVOS (Exact Animated Orbital Radar Twin)
// ═════════════════════════════════════════════════════════════════════════════

struct DevicesTabView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var lan = LanTransportService.shared
    @ObservedObject private var prefs = AppPreferences.shared
    let onOpenManualConnect: () -> Void

    @State private var manualIp = ""
    @State private var connectingManual = false
    @State private var manualStatusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LargeTitleBar(title: "Dispositivos") {
                    CircleIconButton(icon: "arrow.clockwise", tint: HSColor.blue) {
                        lan.refreshDiscovery()
                    }
                }

                RadarCardView(
                    peers: lan.peers,
                    deviceName: prefs.deviceName,
                    localIp: lan.localIPAddress
                )
                .padding(.horizontal, 16)

                GroupCaptionText(text: "CERCANOS")
                IosGroupCard {
                    if lan.peers.isEmpty {
                        HStack(spacing: 14) {
                            ProgressView().tint(HSColor.secondary)
                            Text("Buscando…")
                                .font(.system(size: 16))
                                .foregroundColor(HSColor.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    } else {
                        ForEach(Array(lan.peers.enumerated()), id: \.element.endpointId) { index, peer in
                            DeviceListRowView(peer: peer, gradientIndex: index) {
                                coordinator.selectPeer(peer)
                                HapticEngine.shared.subtleTap()
                            }
                            if index < lan.peers.count - 1 {
                                RowDividerLine(startPadding: 72)
                            }
                        }
                    }
                }

                GroupCaptionText(text: "CONEXIÓN DIRECTA POR IP")
                IosGroupCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("Ej. 192.168.101.2", text: $manualIp)
                                .keyboardType(.decimalPad)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(HSColor.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Button {
                                connectingManual = true
                                manualStatusMessage = nil
                                lan.connectManual(ip: manualIp, port: LanProtocol.tcpPort) { peer in
                                    connectingManual = false
                                    if let peer {
                                        coordinator.selectPeer(peer)
                                        manualIp = ""
                                    } else {
                                        manualStatusMessage = "Sin respuesta en \(manualIp):47832"
                                    }
                                }
                            } label: {
                                Text(connectingManual ? "..." : "Conectar")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(HSColor.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(connectingManual || manualIp.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if let msg = manualStatusMessage {
                            Text(msg)
                                .font(.system(size: 12))
                                .foregroundColor(HSColor.red)
                        } else {
                            Text("Wi‑Fi o Hotspot · Puertos UDP \(LanProtocol.udpDiscoveryPort) / TCP \(lan.activeTcpPort)")
                                .font(.system(size: 12))
                                .foregroundColor(HSColor.secondary)
                        }
                    }
                    .padding(14)
                }
            }
            .padding(.bottom, 120)
        }
        .background(HSColor.background)
    }
}

private struct RadarCardView: View {
    let peers: [HandSharePeer]
    let deviceName: String
    let localIp: String?

    @State private var sweep: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach([0.38, 0.66, 0.96], id: \.self) { frac in
                    Circle()
                        .stroke(HSColor.blue.opacity(0.08), lineWidth: 1)
                        .frame(width: 230 * frac, height: 230 * frac)
                }

                ForEach(0..<3, id: \.self) { i in
                    let p = (sweep + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0)
                    Circle()
                        .stroke(HSColor.blue.opacity((1.0 - p) * 0.28), lineWidth: 2)
                        .frame(width: 230 * (0.25 + 0.75 * p), height: 230 * (0.25 + 0.75 * p))
                }

                ForEach(Array(peers.prefix(6).enumerated()), id: \.element.endpointId) { idx, peer in
                    let total = max(1, min(6, peers.count))
                    let angle = (Double(idx) / Double(total)) * 2.0 * .pi - (.pi / 2.0)
                    let radius: CGFloat = peer.isConnected ? 52 : 76
                    let grad = HSColor.avatarGradients[idx % HSColor.avatarGradients.count]
                    Circle()
                        .fill(LinearGradient(colors: grad, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 3)
                        .overlay(
                            Text(String(peer.name.prefix(1)).uppercased())
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.039, green: 0.518, blue: 1.0), Color(red: 0.369, green: 0.361, blue: 0.902)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: HSColor.blue.opacity(0.45), radius: 14, x: 0, y: 5)
                    .overlay(
                        Image(systemName: "iphone")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 230, height: 230)

            Spacer().frame(height: 14)

            Text(deviceName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(HSColor.label)
            Text(localIp != nil ? "Este dispositivo · \(localIp!)" : "Este dispositivo")
                .font(.system(size: 14))
                .foregroundColor(HSColor.secondary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(HSColor.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                sweep = 1.0
            }
        }
    }
}

private struct DeviceListRowView: View {
    let peer: HandSharePeer
    let gradientIndex: Int
    let onTap: () -> Void

    var body: some View {
        let grad = HSColor.avatarGradients[gradientIndex % HSColor.avatarGradients.count]
        let statusBase = peer.isConnected ? "Conectado" : "Disponible"
        let statusColor = peer.isConnected ? HSColor.green : HSColor.blue
        let subtitle = peer.isDesktop ? "\(statusBase) · PC Wi‑Fi" : "\(statusBase) · \(peer.osName.capitalized)"

        Button(action: onTap) {
            HStack(spacing: 14) {
                Circle()
                    .fill(LinearGradient(colors: grad, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: peer.isDesktop ? "desktopcomputer" : "iphone")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.name)
                        .font(.system(size: 16))
                        .foregroundColor(HSColor.label)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(statusColor)
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(1...4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(HSColor.label)
                            .frame(width: 3, height: CGFloat(3 + Double(i) * 2.5))
                    }
                }
                .frame(height: 14)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HSColor.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 4 · AJUSTES (Exact Android Apple-ID Settings Twin)
// ═════════════════════════════════════════════════════════════════════════════

struct SettingsTabView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var photos = PhotoLibraryService.shared
    @ObservedObject private var lan = LanTransportService.shared
    @ObservedObject private var detector: CameraHandDetector

    let onOpenProfile: () -> Void
    let onOpenPreferences: () -> Void
    let onOpenWelcome: () -> Void
    let onOpenGuide: (Bool) -> Void

    init(
        coordinator: GrabSessionCoordinator,
        onOpenProfile: @escaping () -> Void,
        onOpenPreferences: @escaping () -> Void,
        onOpenWelcome: @escaping () -> Void,
        onOpenGuide: @escaping (Bool) -> Void
    ) {
        self.coordinator = coordinator
        _detector = ObservedObject(wrappedValue: coordinator.detector)
        self.onOpenProfile = onOpenProfile
        self.onOpenPreferences = onOpenPreferences
        self.onOpenWelcome = onOpenWelcome
        self.onOpenGuide = onOpenGuide
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LargeTitleBar(title: "Ajustes") {}

                // Top App Profile & AI Engine Card (Apple ID Style)
                IosGroupCard {
                    Button(action: onOpenProfile) {
                        HStack(spacing: 14) {
                            HandShareHeaderLogo(size: 60)
                                .overlay(Circle().stroke(HSColor.separator, lineWidth: 0.5))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prefs.deviceName)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(HSColor.label)
                                Text("Perfil de Dispositivo, Motor IA y Estadísticas")
                                    .font(.system(size: 13))
                                    .foregroundColor(HSColor.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(HSColor.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }

                GroupCaptionText(text: "PERMISOS")
                IosGroupCard {
                    settingsRow("photo.fill", HSColor.green, "Fototeca", enabled: photos.isAuthorized) {
                        if photos.isAuthorized {
                            openIosSettings()
                        } else {
                            Task { _ = await photos.requestAuthorization() }
                        }
                    }
                    RowDividerLine()
                    settingsRow("camera.fill", HSColor.gray, "Cámara", enabled: detector.cameraPermissionGranted) {
                        if detector.cameraPermissionGranted {
                            openIosSettings()
                        } else {
                            Task { await detector.requestPermissionAndStart() }
                        }
                    }
                    RowDividerLine()
                    settingsRow("wifi", HSColor.blue, "Red local Wi‑Fi", enabled: lan.isWifiAvailable) {
                        lan.refreshDiscovery()
                    }
                }

                GroupCaptionText(text: "GENERAL")
                IosGroupCard {
                    settingsRow("slider.horizontal.3", HSColor.blue, "Preferencias", enabled: nil, action: onOpenPreferences)
                    RowDividerLine()
                    settingsRow("sparkles", HSColor.indigo, "Bienvenida y cómo se usa", enabled: nil, action: onOpenWelcome)
                    RowDividerLine()
                    settingsRow("square.and.arrow.up", HSColor.blue, "Guía Enviar", enabled: nil) { onOpenGuide(true) }
                    RowDividerLine()
                    settingsRow("square.and.arrow.down", HSColor.purple, "Guía Recibir", enabled: nil) { onOpenGuide(false) }
                }

                GroupCaptionText(text: "INFORMACIÓN")
                IosGroupCard {
                    infoRow("Dispositivo", prefs.deviceName)
                    RowDividerLine(startPadding: 16)
                    infoRow("iOS", UIDevice.current.systemVersion)
                    RowDividerLine(startPadding: 16)
                    infoRow("Red LAN", "\(lan.localIPAddress ?? "—") : \(lan.activeTcpPort)")
                    RowDividerLine(startPadding: 16)
                    settingsRow("cpu", HSColor.purple, "HandShare System Engine", enabled: true, action: onOpenProfile)
                }
            }
            .padding(.bottom, 120)
        }
        .background(HSColor.background)
    }

    private func settingsRow(
        _ icon: String,
        _ bg: Color,
        _ title: String,
        enabled: Bool?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(bg)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    )
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(HSColor.label)
                Spacer()
                if let enabled {
                    if enabled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(HSColor.green)
                    } else {
                        Circle()
                            .fill(HSColor.orange)
                            .frame(width: 9, height: 9)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HSColor.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(HSColor.label)
            Spacer()
            Text(value)
                .font(.system(size: 16))
                .foregroundColor(HSColor.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func openIosSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// SHEETS (Exact Match to Android SettingsBottomSheet.kt)
// ═════════════════════════════════════════════════════════════════════════════

struct DeviceProfileAndEngineSheetView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var lan = LanTransportService.shared
    let onDismiss: () -> Void
    let onOpenWelcome: () -> Void

    @State private var editedName: String = AppPreferences.shared.deviceName
    @State private var nameSaved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HandShareHeaderLogo(size: 72)
                        .shadow(color: HSColor.blue.opacity(0.35), radius: 12, x: 0, y: 6)
                        .padding(.top, 12)

                    VStack(spacing: 2) {
                        Text("HandShare Air Hop")
                            .font(.system(size: 24, weight: .bold))
                        Text("Versión 1.0 • Motor Apple Vision Gesture IA")
                            .font(.system(size: 13))
                            .foregroundColor(HSColor.secondary)
                    }

                    HStack(spacing: 12) {
                        statCard("arrow.up", HSColor.blue, prefs.sentCount, "Enviados")
                        statCard("arrow.down", HSColor.green, prefs.receivedCount, "Recibidos")
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOMBRE VISIBLE EN EL RADAR")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(HSColor.secondary)
                            .padding(.leading, 8)
                        HStack(spacing: 10) {
                            Image(systemName: "iphone")
                                .foregroundColor(HSColor.blue)
                                .frame(width: 34, height: 34)
                                .background(HSColor.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            TextField("Nombre", text: $editedName)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(HSColor.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button(nameSaved ? "Listo" : "Guardar") {
                                let clean = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !clean.isEmpty {
                                    prefs.deviceName = clean
                                    lan.updateDeviceName(clean)
                                    nameSaved = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(HSColor.blue)
                        }
                        .padding(14)
                        .background(HSColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("HANDSHARE SYSTEM ENGINE (EN VIVO)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(HSColor.secondary)
                            .padding(.leading, 8)
                        VStack(spacing: 0) {
                            engineRow("eye.fill", HSColor.indigo, "Apple Vision 21-Landmark IA",
                                      "Detección geométrica de palma abierta y puño", "Activo", HSColor.green) {}
                            Divider().padding(.leading, 56)
                            engineRow("sparkles.rectangle.stack.fill", HSColor.cyan, "Visor Galería Air Hop",
                                      "Tarjeta flotante, pila múltiple y aura en bordes", "Conectado", HSColor.green) {}
                            Divider().padding(.leading, 56)
                            engineRow("wifi", HSColor.green, "Red LAN P2P + Bonjour",
                                      lan.peers.isEmpty ? "Escuchando en UDP 47831 / TCP \(lan.activeTcpPort)" : "\(lan.peers.count) equipo(s) cercano(s)",
                                      "P2P Listo", HSColor.blue) { lan.refreshDiscovery() }
                        }
                        .background(HSColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 28)
            }
            .background(HSColor.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: onDismiss)
                }
            }
        }
    }

    private func statCard(_ icon: String, _ tint: Color, _ count: Int, _ label: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundColor(tint))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.system(size: 20, weight: .bold))
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(HSColor.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(HSColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func engineRow(
        _ icon: String,
        _ bg: Color,
        _ title: String,
        _ subtitle: String,
        _ badge: String,
        _ badgeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(bg)
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundColor(HSColor.label)
                    Text(subtitle).font(.system(size: 12)).foregroundColor(HSColor.secondary)
                }
                Spacer()
                Text(badge)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeColor.opacity(0.14), in: Capsule())
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }
}

struct UserPreferencesSheetView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var prefs = AppPreferences.shared
    let onDismiss: () -> Void
    let onOpenWelcome: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Personaliza las animaciones Air Hop, la respuesta táctil y la sensibilidad del sensor de manos.")
                        .font(.system(size: 14))
                        .foregroundColor(HSColor.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXPERIENCIA Y ANIMACIONES")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(HSColor.secondary)
                        VStack(spacing: 0) {
                            Toggle(isOn: $prefs.edgeGlowEnabled) {
                                VStack(alignment: .leading) {
                                    Text("Brillo azul al acercar la mano")
                                    Text("Iluminar los bordes curvos al detectar la palma")
                                        .font(.system(size: 12)).foregroundColor(HSColor.secondary)
                                }
                            }
                            .tint(HSColor.green)
                            .padding(14)

                            Divider().padding(.leading, 14)

                            Toggle(isOn: $prefs.autoOpenReceivedMedia) {
                                VStack(alignment: .leading) {
                                    Text("Abrir al recibir archivo")
                                    Text("Mostrar vista previa automáticamente tras atrapar")
                                        .font(.system(size: 12)).foregroundColor(HSColor.secondary)
                                }
                            }
                            .tint(HSColor.green)
                            .padding(14)

                            Divider().padding(.leading, 14)

                            Toggle(isOn: $prefs.showSimulatorDevControls) {
                                VStack(alignment: .leading) {
                                    Text("Controles de prueba de simulador")
                                    Text("Botones para simular gestos sin cámara física")
                                        .font(.system(size: 12)).foregroundColor(HSColor.secondary)
                                }
                            }
                            .tint(HSColor.blue)
                            .padding(14)
                        }
                        .background(HSColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SENSIBILIDAD DE GESTOS IA")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(HSColor.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Sensibilidad", selection: $prefs.gestureSensitivity) {
                                Text("Rápida").tag(0)
                                Text("Estándar").tag(1)
                                Text("Precisa").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: prefs.gestureSensitivity) { val in
                                coordinator.detector.sensitivity = val
                            }
                            Text(sensitivityHint)
                                .font(.system(size: 12))
                                .foregroundColor(HSColor.secondary)
                        }
                        .padding(14)
                        .background(HSColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(spacing: 10) {
                        Button("Ver bienvenida y guía interactiva") {
                            onDismiss()
                            onOpenWelcome()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        .tint(HSColor.indigo)

                        Button("Limpiar historial local") {
                            coordinator.history.clearHistory()
                        }
                        .foregroundColor(HSColor.red)
                    }
                }
                .padding(20)
            }
            .background(HSColor.background)
            .navigationTitle("Preferencias")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: onDismiss)
                }
            }
        }
    }

    private var sensitivityHint: String {
        switch prefs.gestureSensitivity {
        case 0: "Respuesta instantánea: agarra la foto apenas cierras la mano."
        case 2: "Mayor confirmación: evita agarres accidentales frente a la cámara."
        default: "Equilibrio ideal igual a la respuesta de HandShare Android."
        }
    }
}

struct ManualConnectSheetView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    let onDismiss: () -> Void

    @State private var ipAddress = ""
    @State private var portText = "47832"
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Conectar manualmente en Wi‑Fi") {
                    TextField("Ej. 192.168.101.2", text: $ipAddress)
                        .keyboardType(.decimalPad)
                    TextField("Puerto TCP (47832)", text: $portText)
                        .keyboardType(.numberPad)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(HSColor.red)
                            .font(.system(size: 13.5))
                    }
                }

                Section {
                    Button {
                        let port = Int(portText) ?? LanProtocol.tcpPort
                        isConnecting = true
                        errorMessage = nil
                        coordinator.lan.connectManual(ip: ipAddress, port: port) { peer in
                            isConnecting = false
                            if let peer {
                                coordinator.selectPeer(peer)
                                onDismiss()
                            } else {
                                errorMessage = "No respondió ningún HandShare en \(ipAddress):\(port)."
                            }
                        }
                    } label: {
                        HStack {
                            if isConnecting { ProgressView() }
                            Text(isConnecting ? "Conectando..." : "Conectar ahora")
                        }
                    }
                    .disabled(isConnecting || ipAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Conectar por IP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: onDismiss)
                }
            }
        }
    }
}

struct GestureGuideSheetView: View {
    let isSender: Bool
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isSender
                                ? [Color(red: 0.039, green: 0.518, blue: 1.0), Color(red: 0.369, green: 0.361, blue: 0.902)]
                                : [Color(red: 0.749, green: 0.353, blue: 0.949), Color(red: 1.0, green: 0.216, blue: 0.373)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: isSender ? "square.and.arrow.up" : "square.and.arrow.down")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(.white)
                    )
                    .padding(.top, 20)

                Text(isSender ? "Enviar" : "Recibir")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(HSColor.label)

                IosGroupCard {
                    if isSender {
                        stepRow("photo.on.rectangle.angled", HSColor.blue, "Abre una foto", 1)
                        RowDividerLine(startPadding: 64)
                        stepRow("hand.raised.fill", HSColor.blue, "Muestra la palma", 2)
                        RowDividerLine(startPadding: 64)
                        stepRow("hand.thumbsup.fill", HSColor.blue, "Cierra el puño", 3)
                    } else {
                        stepRow("iphone", HSColor.purple, "Acércate al otro equipo", 1)
                        RowDividerLine(startPadding: 64)
                        stepRow("hand.raised.fill", HSColor.purple, "Abre la mano", 2)
                        RowDividerLine(startPadding: 64)
                        stepRow("checkmark.circle.fill", HSColor.purple, "Listo en tu Fototeca", 3)
                    }
                }
                Spacer()
            }
            .background(HSColor.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: onDismiss)
                }
            }
        }
    }

    private func stepRow(_ icon: String, _ tint: Color, _ label: String, _ num: Int) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(tint.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(tint))
            Text(label)
                .font(.system(size: 16))
                .foregroundColor(HSColor.label)
            Spacer()
            Text("\(num)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(HSColor.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
