import AVFoundation
import Photos
import SwiftUI

enum HSColor {
    static let background = Color(red: 0.949, green: 0.949, blue: 0.969) // #F2F2F7
    static let card = Color.white
    static let label = Color.black
    static let secondary = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93
    static let fill = Color(red: 0.898, green: 0.898, blue: 0.918) // #E5E5EA
    static let blue = Color(red: 0.0, green: 0.478, blue: 1.0) // #007AFF
    static let indigo = Color(red: 0.345, green: 0.337, blue: 0.839) // #5856D6
    static let purple = Color(red: 0.686, green: 0.322, blue: 0.871) // #AF52DE
    static let green = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
    static let orange = Color(red: 1.0, green: 0.584, blue: 0.0) // #FF9500
    static let red = Color(red: 1.0, green: 0.231, blue: 0.188) // #FF3B30
    static let teal = Color(red: 0.188, green: 0.690, blue: 0.780) // #30B0C7

    static let avatarGradients: [[Color]] = [
        [Color(red: 0.039, green: 0.518, blue: 1.0), Color(red: 0.369, green: 0.361, blue: 0.902)],
        [Color(red: 1.0, green: 0.624, blue: 0.039), Color(red: 1.0, green: 0.216, blue: 0.373)],
        [Color(red: 0.188, green: 0.820, blue: 0.345), Color(red: 0.039, green: 0.518, blue: 1.0)],
        [Color(red: 0.749, green: 0.353, blue: 0.949), Color(red: 0.369, green: 0.361, blue: 0.902)],
        [Color(red: 0.392, green: 0.824, blue: 1.0), Color(red: 0.039, green: 0.518, blue: 1.0)]
    ]
}

enum HSTab: String, CaseIterable, Identifiable {
    case home = "Inicio"
    case gallery = "Galería"
    case devices = "Dispositivos"
    case settings = "Ajustes"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .gallery: "photo.on.rectangle.angled"
        case .devices: "laptopcomputer.and.iphone"
        case .settings: "gearshape.fill"
        }
    }
}

struct PHAssetThumbnailView: View {
    let asset: PHAsset
    var size: CGSize = CGSize(width: 240, height: 240)
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(HSColor.fill)
                    .overlay(
                        ProgressView().tint(HSColor.secondary)
                    )
            }

            if asset.mediaType == .video {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(formatDuration(asset.duration))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.65), in: Capsule())
                .padding(6)
            }
        }
        .clipped()
        .task(id: asset.localIdentifier) {
            PhotoLibraryService.shared.requestThumbnail(for: asset, targetSize: size) { img in
                if let img {
                    self.image = img
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct HandShareHeaderLogo: View {
    var size: CGFloat = 34

    var body: some View {
        Image("HandShareLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct FloatingGlassTabBar: View {
    @Binding var activeTab: HSTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HSTab.allCases) { tab in
                let isSelected = activeTab == tab
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        activeTab = tab
                    }
                    HapticEngine.shared.subtleTap()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(isSelected ? HSColor.blue : HSColor.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        Group {
                            if isSelected {
                                Capsule()
                                    .fill(HSColor.blue.opacity(0.12))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}
