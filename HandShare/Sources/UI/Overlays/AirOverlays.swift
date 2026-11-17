import SwiftUI

struct EdgeGlowOverlayView: View {
    let isVisible: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isVisible {
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.52, blue: 1.0),
                                Color(red: 0.22, green: 0.74, blue: 0.97),
                                Color(red: 0.69, green: 0.32, blue: 0.87),
                                Color(red: 0.04, green: 0.52, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: pulse ? 10 : 6
                    )
                    .blur(radius: pulse ? 12 : 7)
                    .padding(4)
                    .opacity(pulse ? 0.92 : 0.65)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                    .onDisappear { pulse = false }
            }
        }
    }
}

/// Liquid-glass Aurora sphere matching Android's `AirModeBubbleManager.AirBubbleView`.
struct AirAuroraBubbleView: View {
    let isRadarActive: Bool
    let isHoldingCard: Bool
    let badgeCount: Int
    let onTap: () -> Void

    @State private var auroraPhase: Double = 0
    @State private var radarAngle: Double = 0
    @State private var dragOffsetY: CGFloat = 0
    @State private var committedOffsetY: CGFloat = 0

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: onTap) {
                    ZStack {
                        // Outer soft Aurora ambient halo
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.95, blue: 1.0).opacity(isRadarActive ? 0.48 : 0.28),
                                        Color(red: 0.46, green: 0.29, blue: 1.0).opacity(isRadarActive ? 0.26 : 0.14),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: 32
                                )
                            )
                            .frame(width: 62, height: 62)

                        if isRadarActive {
                            Circle()
                                .stroke(
                                    AngularGradient(
                                        colors: [
                                            Color(red: 0.0, green: 0.95, blue: 1.0),
                                            Color(red: 0.04, green: 0.52, blue: 1.0),
                                            Color(red: 1.0, green: 0.18, blue: 0.52),
                                            Color(red: 0.0, green: 0.96, blue: 0.63),
                                            Color(red: 0.0, green: 0.95, blue: 1.0)
                                        ],
                                        center: .center
                                    ),
                                    lineWidth: 2.8
                                )
                                .frame(width: 52, height: 52)
                                .rotationEffect(.degrees(radarAngle))
                        }

                        // Obsidian crystal sphere + flowing aurora lobes inside
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 0.063, green: 0.082, blue: 0.169),
                                            Color(red: 0.020, green: 0.027, blue: 0.067)
                                        ],
                                        center: UnitPoint(x: 0.35, y: 0.3),
                                        startRadius: 2,
                                        endRadius: 28
                                    )
                                )

                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 0.0, green: 0.95, blue: 1.0).opacity(0.9),
                                            Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.45),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 19
                                    )
                                )
                                .offset(
                                    x: cos(auroraPhase) * 6,
                                    y: sin(auroraPhase * 1.3) * 6
                                )
                                .blendMode(.screen)

                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.18, blue: 0.52).opacity(0.88),
                                            Color(red: 0.72, green: 0.13, blue: 1.0).opacity(0.42),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 18
                                    )
                                )
                                .offset(
                                    x: -sin(auroraPhase * 0.9) * 6.5,
                                    y: cos(auroraPhase * 1.1) * 5.5
                                )
                                .blendMode(.screen)

                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 0.0, green: 0.96, blue: 0.63).opacity(0.85),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 14
                                    )
                                )
                                .offset(
                                    x: cos(auroraPhase * 1.5 + 1.2) * 5,
                                    y: sin(auroraPhase * 0.8 + 0.7) * 6
                                )
                                .blendMode(.screen)

                            // Specular highlight top-left
                            Circle()
                                .fill(Color.white.opacity(0.32))
                                .frame(width: 14, height: 8)
                                .blur(radius: 2)
                                .offset(x: -7, y: -11)

                            Image(systemName: isRadarActive ? "hand.raised.fill" : "hand.raised")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white.opacity(isRadarActive ? 1.0 : 0.92))
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.75), Color.cyan.opacity(0.45), Color.purple.opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color.cyan.opacity(isRadarActive ? 0.55 : 0.25), radius: 10, x: 0, y: 4)

                        if badgeCount > 0 {
                            Text("×\(badgeCount)")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.04, green: 0.52, blue: 1.0), in: Capsule())
                                .overlay(Capsule().stroke(Color(red: 0.04, green: 0.05, blue: 0.09), lineWidth: 1.5))
                                .offset(x: 18, y: -18)
                        }
                    }
                }
                .buttonStyle(.plain)
                .offset(y: committedOffsetY + dragOffsetY)
                .gesture(
                    DragGesture()
                        .onChanged { val in dragOffsetY = val.translation.height }
                        .onEnded { val in
                            committedOffsetY = max(-280, min(60, committedOffsetY + val.translation.height))
                            dragOffsetY = 0
                        }
                )
                .padding(.trailing, 8)
                .padding(.bottom, 95)
                .accessibilityLabel(isRadarActive ? "Detectar gestos activo" : "Activar cámara de gestos")
                .accessibilityHint("Toca para activar o pausar el reconocimiento de palma y puño")
                .accessibilityIdentifier("air_aurora_bubble")
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                auroraPhase = .pi * 2
            }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                radarAngle = 360
            }
        }
    }
}

struct AlreadySelectedPillView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
            Text("Ya seleccionada")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.09, green: 0.11, blue: 0.15).opacity(0.88), in: Capsule())
        .overlay(
            Capsule().stroke(Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.65), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
    }
}

struct FloatingHeldCardView: View {
    let previewImage: UIImage?
    let stackCount: Int
    let isDocked: Bool
    let status: GrabStatus
    let transferState: TransferState
    let targetName: String?
    let onTapCard: () -> Void
    let onCancel: () -> Void

    @State private var floatUp = false
    @State private var sweepAngle: Double = 0

    var body: some View {
        ZStack {
            if isDocked {
                VStack {
                    HStack {
                        Spacer()
                        cardBody(width: 74, height: 96, corner: 14)
                            .onTapGesture(perform: onTapCard)
                            .padding(.trailing, 12)
                            .padding(.top, 110)
                    }
                    Spacer()
                }
                .allowsHitTesting(true)
            } else {
                VStack {
                    Spacer()
                    cardBody(width: 210, height: 274, corner: 22)
                        .onTapGesture(perform: onTapCard)
                        .offset(y: floatUp ? -7 : 5)
                    Spacer()

                    Button(action: onCancel) {
                        Text("Cancelar")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 120, height: 40)
                            .background(Color(red: 0.14, green: 0.14, blue: 0.15).opacity(0.75), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 48)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                floatUp = true
            }
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                sweepAngle = 360
            }
        }
    }

    @ViewBuilder
    private func cardBody(width: CGFloat, height: CGFloat, corner: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if stackCount > 1 {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.23, blue: 0.54).opacity(0.78))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Color.cyan.opacity(0.65), lineWidth: 1.5))
                    .frame(width: width * 0.94, height: height * 0.94)
                    .rotationEffect(.degrees(5.5))
                    .offset(x: 9, y: 6)
            }
            if stackCount > 2 {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.23, blue: 0.54).opacity(0.65))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Color.cyan.opacity(0.5), lineWidth: 1.5))
                    .frame(width: width * 0.90, height: height * 0.90)
                    .rotationEffect(.degrees(-5.0))
                    .offset(x: -9, y: 7)
            }

            ZStack(alignment: .bottom) {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.15, green: 0.16, blue: 0.18), Color(red: 0.06, green: 0.07, blue: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: width, height: height)
                }

                // Subtle top glass sheen
                LinearGradient(
                    colors: [Color.white.opacity(0.15), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .frame(width: width, height: height)

                if !isDocked, case .sending = transferState {
                    ProgressView(value: transferState.progressFraction)
                        .tint(Color.cyan)
                        .padding(12)
                        .background(Color.black.opacity(0.45))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: [.white, Color.cyan, HSColor.blue, HSColor.purple, .white],
                            center: .center,
                            angle: .degrees(sweepAngle)
                        ),
                        lineWidth: isDocked ? 2.2 : 2.8
                    )
            )
            .shadow(color: Color.cyan.opacity(0.35), radius: isDocked ? 10 : 22, x: 0, y: 8)

            if stackCount > 1 {
                Text("×\(stackCount)")
                    .font(.system(size: isDocked ? 11 : 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, isDocked ? 7 : 9)
                    .padding(.vertical, isDocked ? 3 : 4)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.04, green: 0.52, blue: 1.0), Color(red: 0.22, green: 0.74, blue: 0.97)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(Color.white, lineWidth: 1.8))
                    .offset(x: 6, y: -6)
            }
        }
    }
}

struct CatchLandingOverlayView: View {
    let message: String
    let item: StagedIncomingItem?
    let onDismiss: () -> Void

    @State private var ringScale: CGFloat = 0.25
    @State private var ringOpacity: Double = 0.9

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            Circle()
                .stroke(Color.cyan, lineWidth: 5)
                .frame(width: 240, height: 240)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            VStack(spacing: 14) {
                if let item, !item.metadata.isVideo,
                   let img = UIImage(contentsOfFile: item.fileURL.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(HSColor.blue.opacity(0.18))
                            .frame(width: 220, height: 150)
                        Image(systemName: item?.metadata.isVideo == true ? "video.fill" : "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundColor(HSColor.green)
                    }
                }

                Text(message)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Button("Listo", action: onDismiss)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(HSColor.blue, in: Capsule())
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.95)) {
                ringScale = 2.6
                ringOpacity = 0.0
            }
        }
    }
}

struct LiveGestureRadarStatusPillView: View {
    @ObservedObject var detector: CameraHandDetector
    let isHoldingCard: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            Text(statusText)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)

            if !detector.cameraPermissionGranted {
                Button(detector.isDeniedOrRestricted ? "Abrir Ajustes" : "Permitir") {
                    Task { _ = await detector.requestPermissionOrOpenSettings() }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(HSColor.blue, in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.76), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("live_gesture_status_pill")
    }

    private var statusColor: Color {
        if !detector.cameraPermissionGranted || !detector.hasFrontCamera {
            return HSColor.orange
        }
        switch detector.gestureState {
        case .handOpen:
            return Color.cyan
        case .grabbed:
            return HSColor.green
        default:
            return detector.isRunning ? HSColor.blue : HSColor.orange
        }
    }

    private var statusText: String {
        if !detector.cameraPermissionGranted {
            return detector.isDeniedOrRestricted
                ? "Cámara desactivada · Actívala en Ajustes"
                : "Permiso de cámara requerido para gestos"
        }
        if !detector.hasFrontCamera {
            return detector.cameraUnavailableReason ?? "Sin cámara frontal disponible"
        }
        if isHoldingCard {
            return "Foto en la mano ✊ · Cierra o cambia de foto"
        }
        switch detector.gestureState {
        case .handOpen:
            return "Palma detectada ✋ · Cierra el puño ✊ para agarrar"
        case .detecting:
            return "Detectando palma abierta…"
        case .grabbed:
            return "Foto agarrada ✊"
        default:
            return "Muestra tu palma abierta ✋ frente a la cámara"
        }
    }
}
