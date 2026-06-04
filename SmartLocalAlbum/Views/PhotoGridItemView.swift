import SwiftUI

struct PhotoGridItemView: View {
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    let assetLocalIdentifier: String
    let similarity: Float?

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                Color.secondary.opacity(0.12)
                    .overlay {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.width)
                        } else {
                            ProgressView()
                        }
                    }
                    .clipped()

                if let similarity {
                    Text(String(format: "%.2f", similarity))
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(5)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .contentShape(Rectangle())
        .task(id: assetLocalIdentifier) {
            image = await photoLibraryManager.thumbnail(
                for: assetLocalIdentifier,
                targetSize: CGSize(width: 640, height: 640)
            )
        }
    }
}
