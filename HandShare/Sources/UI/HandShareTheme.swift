import AVFoundation
import Photos
import SwiftUI

enum HSColor {
    static let background = Color(red: 0.949, green: 0.949, blue: 0.969) // #F2F2F7
    static let card = Color.white
    static let label = Color.black
    static let secondary = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93
    static let tertiary = Color(red: 0.780, green: 0.780, blue: 0.800) // #C7C7CC
    static let separator = Color(red: 0.235, green: 0.235, blue: 0.263, opacity: 0.22)
    static let fill = Color(red: 0.898, green: 0.898, blue: 0.918) // #E5E5EA
    static let blue = Color(red: 0.0, green: 0.478, blue: 1.0) // #007AFF
    static let indigo = Color(red: 0.345, green: 0.337, blue: 0.839) // #5856D6
    static let purple = Color(red: 0.686, green: 0.322, blue: 0.871) // #AF52DE
    static let green = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
    static let orange = Color(red: 1.0, green: 0.584, blue: 0.0) // #FF9500
    static let red = Color(red: 1.0, green: 0.231, blue: 0.188) // #FF3B30
    static let teal = Color(red: 0.188, green: 0.690, blue: 0.780) // #30B0C7
    static let cyan = Color(red: 0.196, green: 0.678, blue: 0.902) // #32ADE6
    static let gray = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93

    static let avatarGradients: [[Color]] = [
        [Color(red: 0.039, green: 0.518, blue: 1.0), Color(red: 0.369, green: 0.361, blue: 0.902)],
        [Color(red: 1.0, green: 0.624, blue: 0.039), Color(red: 1.0, green: 0.216, blue: 0.373)],
        [Color(red: 0.188, green: 0.820, blue: 0.345), Color(red: 0.039, green: 0.518, blue: 1.0)],
        [Color(red: 0.749, green: 0.353, blue: 0.949), Color(red: 0.369, green: 0.361, blue: 0.902)],
        [Color(red: 0.392, green: 0.824, blue: 1.0), Color(red: 0.039, green: 0.518, blue: 1.0)]
    ]
}

enum HSTab: Int, CaseIterable, Identifiable {
    case home = 0
    case gallery = 1
    case devices = 2
    case settings = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: "Inicio"
        case .gallery: "Galería"
        case .devices: "Dispositivos"
        case .settings: "Ajustes"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .gallery: "photo.on.rectangle.angled"
        case .devices: "laptopcomputer.and.iphone"
        case .settings: "gearshape"
        }
    }

    var selectedIcon: String {
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
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(HSColor.fill)
            }

            if asset.mediaType == .video {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("VIDEO")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
}

struct HandShareHeaderLogo: View {
    var size: CGFloat = 34

    var body: some View {
        Image("HandShareCircleLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

struct LargeTitleBar<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(HSColor.label)
                .tracking(-0.8)
            Spacer()
            trailing()
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

struct CircleIconButton: View {
    let icon: String
    var tint: Color = HSColor.label
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(HSColor.card, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeaderBar: View {
    let title: String
    var actionIcon: String = "chevron.right"
    let onAction: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(HSColor.label)
                .tracking(-0.4)
            Spacer()
            Button(action: onAction) {
                Image(systemName: actionIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(HSColor.blue)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 22)
        .padding(.bottom, 10)
    }
}

struct GroupCaptionText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(HSColor.secondary)
            .padding(.leading, 32)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }
}

struct IosGroupCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(HSColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}

struct RowDividerLine: View {
    var startPadding: CGFloat = 60

    var body: some View {
        Rectangle()
            .fill(HSColor.separator)
            .frame(height: 0.5)
            .padding(.leading, startPadding)
    }
}

struct IosSegmentedControlBar: View {
    let options: [String]
    @Binding var selected: Int

    var body: some View {
        GeometryReader { geo in
            let segW = geo.size.width / CGFloat(max(1, options.count))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.46, green: 0.46, blue: 0.50, opacity: 0.12))

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .frame(width: max(0, segW - 4), height: 32)
                    .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1)
                    .offset(x: 2 + CGFloat(selected) * segW)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selected)

                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { index in
                        Button {
                            selected = index
                        } label: {
                            Text(options[index])
                                .font(.system(size: 13, weight: index == selected ? .semibold : .medium))
                                .foregroundColor(HSColor.label)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: 36)
    }
}

struct FloatingGlassTabBar: View {
    @Binding var activeTab: HSTab

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let totalW = geo.size.width - 12
                let itemW = totalW / CGFloat(HSTab.allCases.count)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(HSColor.blue.opacity(0.12))
                        .frame(width: max(0, itemW), height: 52)
                        .offset(x: CGFloat(activeTab.rawValue) * itemW)
                        .animation(.spring(response: 0.30, dampingFraction: 0.72), value: activeTab)

                    HStack(spacing: 0) {
                        ForEach(HSTab.allCases) { tab in
                            let selected = activeTab == tab
                            Button {
                                if activeTab != tab {
                                    HapticEngine.shared.subtleTap()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        activeTab = tab
                                    }
                                }
                            } label: {
                                Image(systemName: selected ? tab.selectedIcon : tab.icon)
                                    .font(.system(size: 21, weight: selected ? .semibold : .regular))
                                    .foregroundColor(selected ? HSColor.blue : HSColor.secondary)
                                    .scaleEffect(selected ? 1.12 : 1.0)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selected)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tab.title)
                        }
                    }
                }
                .padding(6)
            }
            .frame(height: 64)
            .background(Color.white.opacity(0.96), in: Capsule())
            .overlay(Capsule().stroke(Color.white, lineWidth: 0.8))
            .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 28)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(
            LinearGradient(
                colors: [Color.clear, HSColor.background.opacity(0.92), HSColor.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}
