import BackgroundTasks
import SwiftUI

@main
struct SmartLocalAlbumApp: App {
    @StateObject private var coreDataManager: CoreDataManager
    @StateObject private var photoLibraryManager: PhotoLibraryManager
    @StateObject private var categoryManager: SmartCategoryManager
    @StateObject private var scanManager: ScanManager
    @StateObject private var backgroundScanManager: BackgroundScanManager

    init() {
        let coreDataManager = CoreDataManager()
        let photoLibraryManager = PhotoLibraryManager(coreDataManager: coreDataManager)

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
                textEmbeddingExtractor: textExtractor,
                faceEmbeddingExtractor: faceExtractor
            )
        )
        _scanManager = StateObject(
            wrappedValue: ScanManager(
                photoLibraryManager: photoLibraryManager,
                coreDataManager: coreDataManager,
                fastImageEmbeddingExtractor: fastImageExtractor,
                faceEmbeddingExtractor: faceExtractor
            )
        )

        let bgManager = BackgroundScanManager(
            photoLibraryManager: photoLibraryManager,
            coreDataManager: coreDataManager,
            fastImageEmbeddingExtractor: fastImageExtractor,
            faceEmbeddingExtractor: faceExtractor
        )
        _backgroundScanManager = StateObject(wrappedValue: bgManager)
        bgManager.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(coreDataManager)
                .environmentObject(photoLibraryManager)
                .environmentObject(categoryManager)
                .environmentObject(scanManager)
                .environmentObject(backgroundScanManager)
        }
    }
}
