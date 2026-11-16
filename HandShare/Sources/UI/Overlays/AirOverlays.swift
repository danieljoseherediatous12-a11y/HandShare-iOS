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

struct AirAuroraBubbleView: View {
    let isRadarActive: Bool
    let isHoldingCard: Bool
    let badgeCount: Int
    let onTap: () -> Void

    @State private var spinAngle: Double = 0
    @State private var dragOffsetY: CGFloat = 0
    @State private var committedOffsetY: CGFloat = 0

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: onTap) {
                    ZStack {
                        if isRadarActive {
                            Circle()
                                .stroke(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            Color.cyan,
                                            HSColor.blue,
                                            HSColor.purple,
                                            Color.cyan
                                        ]),
                                        center: .center
                                    ),
                                    lineWidth: 3.5
                                )
                                .frame(width: 66, height: 66)
                                .rotationEffect(.degrees(spinAngle))
                        }

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isRadarActive
                                        ? [Color(red: 0.05, green: 0.45, blue: 1.0), Color(red: 0.22, green: 0.74, blue: 0.97)]
                                        : [Color.black.opacity(0.78), Color(red: 0.12, green: 0.16, blue: 0.24).opacity(0.92)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 58, height: 58)
                            .overlay(
                                Circle().stroke(Color.white.opacity(isRadarActive ? 0.85 : 0.35), lineWidth: 1.5)
                            )
                            .shadow(color: (isRadarActive ? Color.cyan : Color.black).opacity(0.35), radius: 12, x: 0, y: 6)

                        Image(systemName: isRadarActive ? "hand.raised.fill" : "hand.raised")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundColor(.white)

                        if badgeCount > 0 {
                            Text("×\(badgeCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(HSColor.blue, in: Capsule())
                                .overlay(Capsule().stroke(Color.white, lineWidth: 1.2))
                                .offset(x: 22, y: -22)
                        }
                    }
                }
                .buttonStyle(.plain)
                .offset(y: committedOffsetY + dragOffsetY)
                .gesture(
                    DragGesture()
                        .onChanged { val in
                            dragOffsetY = val.translation.height
                        }
                        .onEnded { val in
                            committedOffsetY = max(-280, min(60, committedOffsetY + val.translation.height))
                            dragOffsetY = 0
                        }
                )
                .padding(.trailing, 14)
                .padding(.bottom, 100)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                spinAngle = 360
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
                        cardBody(width: 78, height: 102, corner: 14)
                            .onTapGesture(perform: onTapCard)
                            .padding(.trailing, 14)
                            .padding(.top, 96)
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

                    HStack(spacing: 12) {
                        Button(action: onCancel) {
                            Text("Cancelar")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.14, green: 0.14, blue: 0.16).opacity(0.86), in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 42)
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
                    .fill(HSColor.indigo.opacity(0.65))
                    .frame(width: width * 0.94, height: height * 0.94)
                    .rotationEffect(.degrees(5.5))
                    .offset(x: 9, y: 6)
            }
            if stackCount > 2 {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(HSColor.blue.opacity(0.48))
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
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.18), Color(white: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: width, height: height)
                        .overlay(ProgressView().tint(.white))
                }

                if !isDocked {
                    VStack(spacing: 4) {
                        Text(statusLabel)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if case .sending = transferState {
                            ProgressView(value: transferState.progressFraction)
                                .tint(Color.cyan)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(width: width)
                    .background(Color.black.opacity(0.55))
                    .clipShape(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                    )
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
                        lineWidth: isDocked ? 2.2 : 3.0
                    )
            )
            .shadow(color: Color.cyan.opacity(0.35), radius: isDocked ? 10 : 22, x: 0, y: 8)

            if stackCount > 1 {
                Text("×\(stackCount)")
                    .font(.system(size: isDocked ? 11 : 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, isDocked ? 7 : 10)
                    .padding(.vertical, isDocked ? 3 : 5)
                    .background(
                        LinearGradient(
                            colors: [HSColor.blue, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                    .offset(x: 6, y: -6)
            }
        }
    }

    private var statusLabel: String {
        switch transferState {
        case let .sending(fileName, _, _):
            return "Enviando \(fileName)"
        case .completed:
            return targetName != nil ? "Listo en \(targetName!)" : "Esperando palma en receptor"
        case let .failed(msg):
            return msg
        default:
            return targetName != nil ? "Conectado a \(targetName!)" : "Buscando receptor Wi-Fi..."
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

struct SimulatorGestureHudView: View {
    @ObservedObject var coordinator: GrabSessionCoordinator

    var body: some View {
        VStack(spacing: 6) {
            Text("SIMULADOR · TEST DE GESTOS")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
            HStack(spacing: 8) {
                Button("✋ Palma") {
                    coordinator.detector.simulateOpenPalm()
                }
                Button("✊ Puño") {
                    coordinator.detector.simulateFistGrab()
                }
                Button("👌 OK") {
                    coordinator.detector.simulateOkSign()
                }
                if coordinator.status == .waitingToCatch {
                    Button("✋ Atrapar") {
                        coordinator.commitCatchNow()
                    }
                }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .tint(HSColor.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
