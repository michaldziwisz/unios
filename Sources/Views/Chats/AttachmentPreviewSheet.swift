import SwiftUI
import AVKit
#if canImport(UIKit)
import UIKit
#endif

enum AttachmentPreviewItem: Identifiable, Hashable {
    case image(url: URL, title: String)
    case video(url: URL, title: String)
    case document(url: URL, title: String)

    var id: String {
        switch self {
        case let .image(url, title), let .video(url, title), let .document(url, title):
            return "\(url.path)::\(title)"
        }
    }

    var title: String {
        switch self {
        case let .image(_, title), let .video(_, title), let .document(_, title):
            return title
        }
    }
}

struct AttachmentPreviewSheet: View {
    let item: AttachmentPreviewItem

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case let .image(url, title):
            imagePreview(url: url, title: title)

        case let .video(url, _):
            VideoPlayer(player: AVPlayer(url: url))
                .background(Color.black.ignoresSafeArea())
                .accessibilityLabel("Video preview")
                .accessibilityHint("Double tap to play or pause the selected video.")

        case let .document(url, _):
            QuickLookPreviewController(url: url)
                .ignoresSafeArea()
        }
    }

    private func imagePreview(url: URL, title: String) -> some View {
        Group {
            #if canImport(UIKit)
            if let image = UIImage(contentsOfFile: url.path) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                }
                .background(Color.black.opacity(0.96).ignoresSafeArea())
                .accessibilityLabel(title)
                .accessibilityHint("Image preview.")
            } else {
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "photo",
                    description: Text("The selected image could not be loaded from local storage.")
                )
            }
            #else
            ContentUnavailableView(
                "Preview Unavailable",
                systemImage: "photo",
                description: Text("Image preview is unavailable on this platform.")
            )
            #endif
        }
    }
}
