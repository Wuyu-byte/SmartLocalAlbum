import SwiftUI

@main
struct SmartLocalAlbumApp: App {
    @StateObject private var coreDataManager: CoreDataManager
    @StateObject private var photoLibraryManager: PhotoLibraryManager
    @StateObject private var categoryManager: SmartCategoryManager
    @StateObject private var scanManager: ScanManager

    init() {
        let coreDataManager = CoreDataManager()
        let photoLibraryManager = PhotoLibraryManager()

        let fastImageExtractor: any ImageEmbeddingExtracting = LazyImageEmbeddingExtractor(
            embeddingDimension: 512,
            factory: {
                try ImageEmbeddingExtractor(
                    modelResourceName: "mobileclip_s2_image",
                    embeddingDimension: 512
                )
            },
            fallbackFactory: { MockImageEmbeddingExtractor() }
        )
        let qualityImageExtractor: any ImageEmbeddingExtracting = LazyImageEmbeddingExtractor(
            embeddingDimension: 768,
            factory: {
                try ImageEmbeddingExtractor(
                    modelResourceName: "mobileclip2_l14_image",
                    embeddingDimension: 768,
                    fallbackInputWidth: 224,
                    fallbackInputHeight: 224
                )
            }
        )
        let textExtractor: any TextEmbeddingExtracting = LazyTextEmbeddingExtractor(
            embeddingDimension: 512,
            factory: { try MobileCLIPTextEmbeddingExtractor() },
            fallbackFactory: { MockTextEmbeddingExtractor() }
        )
        let faceExtractor = FaceEmbeddingExtractor(baseExtractor: fastImageExtractor)

        _coreDataManager = StateObject(wrappedValue: coreDataManager)
        _photoLibraryManager = StateObject(wrappedValue: photoLibraryManager)
        _categoryManager = StateObject(
            wrappedValue: SmartCategoryManager(
                coreDataManager: coreDataManager,
                fastImageEmbeddingExtractor: fastImageExtractor,
                qualityImageEmbeddingExtractor: qualityImageExtractor,
                textEmbeddingExtractor: textExtractor,
                faceEmbeddingExtractor: faceExtractor
            )
        )
        _scanManager = StateObject(
            wrappedValue: ScanManager(
                photoLibraryManager: photoLibraryManager,
                coreDataManager: coreDataManager,
                fastImageEmbeddingExtractor: fastImageExtractor,
                qualityImageEmbeddingExtractor: qualityImageExtractor,
                faceEmbeddingExtractor: faceExtractor
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(coreDataManager)
                .environmentObject(photoLibraryManager)
                .environmentObject(categoryManager)
                .environmentObject(scanManager)
        }
    }
}
