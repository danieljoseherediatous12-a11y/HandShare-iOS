import SwiftUI

struct DevicesTabView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject private var lan = LanTransportService.shared
    let onOpenManualConnect: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Dispositivos")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(HSColor.label)
                    Spacer()
                    Button(action: onOpenManualConnect) {
                        Label("Conectar IP", systemImage: "plus")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(HSColor.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(HSColor.card, in: Capsule())
                    }
                    Button {
                        coordinator.lan.refreshDiscovery()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(HSColor.blue)
                            .frame(width: 36, height: 36)
                            .background(HSColor.card, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // Local network summary
                HStack(spacing: 12) {
                    Image(systemName: "wifi.router.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(HSColor.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("IP local: \(lan.localIPAddress ?? "No detectada")")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(HSColor.label)
                        Text("UDP \(LanProtocol.udpDiscoveryPort) · TCP \(lan.activeTcpPort) · Bonjour _handshare._tcp")
                            .font(.system(size: 12))
                            .foregroundColor(HSColor.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)

                if lan.peers.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(HSColor.blue)
                        Text("Buscando equipos HandShare en tu Wi‑Fi...")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(HSColor.label)
                        Text("Asegúrate de tener HandShare abierto en tu Android o Windows PC en la misma red Wi‑Fi, o usa 'Conectar IP'.")
                            .font(.system(size: 13))
                            .foregroundColor(HSColor.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(HSColor.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(lan.peers.enumerated()), id: \.element.endpointId) { idx, peer in
                            let selected = coordinator.selectedTargetEndpointId == peer.endpointId
                            let grad = HSColor.avatarGradients[idx % HSColor.avatarGradients.count]
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(LinearGradient(colors: grad, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 46, height: 46)
                                    .overlay(
                                        Image(systemName: peer.isDesktop ? "desktopcomputer" : "iphone")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.name)
                                        .font(.system(size: 15.5, weight: .semibold))
                                        .foregroundColor(HSColor.label)
                                    HStack(spacing: 6) {
                                        Text(peer.osName.capitalized)
                                        Text("· \(peer.ip):\(peer.tcpPort)")
                                        if let rtt = peer.rttMs {
                                            Text("· \(rtt) ms")
                                                .foregroundColor(HSColor.green)
                                        }
                                    }
                                    .font(.system(size: 12))
                                    .foregroundColor(HSColor.secondary)
                                }

                                Spacer()

                                Button {
                                    if peer.isConnected && selected {
                                        coordinator.lan.disconnectPeer(endpointId: peer.endpointId)
                                    } else {
                                        coordinator.selectPeer(peer)
                                    }
                                } label: {
                                    Text(peer.isConnected ? "Conectado" : "Conectar")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(peer.isConnected ? HSColor.green : .white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            peer.isConnected ? HSColor.green.opacity(0.14) : HSColor.blue,
                                            in: Capsule()
                                        )
                                }
                            }
                            .padding(14)
                            .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(selected ? HSColor.blue : Color.clear, lineWidth: 1.5)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 110)
        }
        .background(HSColor.background)
    }
}

struct SettingsTabView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator
    @ObservedObject var prefs = AppPreferences.shared
    let onOpenGuide: (Bool) -> Void

    @State private var editedName: String = AppPreferences.shared.deviceName
    @State private var savedBanner = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Ajustes")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(HSColor.label)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                // Identity card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        HandShareHeaderLogo(size: 48)
                        TextField("Nombre en tu red Wi‑Fi", text: $editedName)
                            .textFieldStyle(.roundedBorder)
                        Button("Guardar") {
                            let clean = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty {
                                prefs.deviceName = clean
                                coordinator.lan.updateDeviceName(clean)
                                savedBanner = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    savedBanner = false
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HSColor.blue)
                    }
                    Text(savedBanner ? "✓ Nombre actualizado en red" : "Nombre visible para Android y Windows PC")
                        .font(.system(size: 12))
                        .foregroundColor(savedBanner ? HSColor.green : HSColor.secondary)
                }
                .padding(16)
                .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)

                // Gestures & Visuals
                VStack(alignment: .leading, spacing: 14) {
                    Text("CÁMARA Y GESTOS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HSColor.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sensibilidad")
                            .font(.system(size: 14.5, weight: .semibold))
                        Picker("Sensibilidad", selection: $prefs.gestureSensitivity) {
                            Text("Rápida").tag(0)
                            Text("Equilibrada").tag(1)
                            Text("Precisa").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: prefs.gestureSensitivity) { newVal in
                            coordinator.detector.sensitivity = newVal
                        }
                    }

                    Toggle("Aura luminosa en bordes", isOn: $prefs.edgeGlowEnabled)
                        .tint(HSColor.green)
                    Toggle("Abrir vista previa al atrapar", isOn: $prefs.autoOpenReceivedMedia)
                        .tint(HSColor.green)
                    Toggle("Controles de prueba de simulador", isOn: $prefs.showSimulatorDevControls)
                        .tint(HSColor.blue)
                }
                .padding(16)
                .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)

                // Stats & Guide
                VStack(spacing: 12) {
                    HStack {
                        Label("Enviados: \(prefs.sentCount)", systemImage: "arrow.up.circle.fill")
                            .foregroundColor(HSColor.blue)
                        Spacer()
                        Label("Recibidos: \(prefs.receivedCount)", systemImage: "arrow.down.circle.fill")
                            .foregroundColor(HSColor.green)
                    }
                    .font(.system(size: 14, weight: .semibold))

                    Divider()

                    HStack(spacing: 10) {
                        Button("Guía Enviar") { onOpenGuide(true) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        Button("Guía Recibir") { onOpenGuide(false) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }

                    Button("Limpiar historial") {
                        coordinator.history.clearHistory()
                    }
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(HSColor.red)
                }
                .padding(16)
                .background(HSColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 110)
        }
        .background(HSColor.background)
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
                    Button("Cerrar", action: onClose)
                }
            }
        }
    }

    private func onClose() { onDismiss() }
}

struct GestureGuideSheetView: View {
    let isSender: Bool
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: isSender ? "hand.raised.fingers.spread.fill" : "hand.raised.fill")
                    .font(.system(size: 54))
                    .foregroundColor(isSender ? HSColor.blue : HSColor.purple)
                    .padding(.top, 20)

                Text(isSender ? "Enviar con gestos (Emisor)" : "Recibir con gestos (Receptor)")
                    .font(.system(size: 22, weight: .bold))

                VStack(alignment: .leading, spacing: 12) {
                    if isSender {
                        stepRow("1", "Abre una foto o video desde la pestaña Galería.")
                        stepRow("2", "Toca la burbuja Aurora flotante para activar el radar.")
                        stepRow("3", "Muestra tu palma abierta (✋) para iluminar los bordes y cierra el puño (✊) para agarrarla.")
                        stepRow("4", "Para acumular más fotos, vuelve atrás o desliza a otra y cierra el puño otra vez.")
                    } else {
                        stepRow("1", "Cuando otro dispositivo agarre una foto, el iPhone se prepara para atraparla.")
                        stepRow("2", "Muestra el puño o mano entrando y abre la palma (✋) frente a la pantalla para soltarla.")
                        stepRow("3", "La foto o video se guarda automáticamente en tu app Fotos.")
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
                Button("Entendido", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(HSColor.blue)
                    .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: onDismiss)
                }
            }
        }
    }

    private func stepRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(num)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(HSColor.blue, in: Circle())
            Text(text)
                .font(.system(size: 14.5))
                .foregroundColor(HSColor.label)
            Spacer()
        }
    }
}
