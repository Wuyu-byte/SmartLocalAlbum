import BackgroundTasks
import SwiftUI
import WidgetKit

@main
struct SmartLocalAlbumApp: App {
    @StateObject private var coreDataManager: CoreDataManager
    @StateObject private var photoLibraryManager: PhotoLibraryManager
    @StateObject private var categoryManager: SmartCategoryManager
    @StateObject private var scanManager: ScanManager
    @StateObject private var backgroundScanManager: BackgroundScanManager
    @StateObject private var searchManager: SearchManager
    @StateObject private var duplicateManager: DuplicateDetectionManager
    @StateObject private var exportManager: ExportManager
    @State private var widgetSync: WidgetSyncService

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
        _searchManager = StateObject(
            wrappedValue: SearchManager(
                coreDataManager: coreDataManager,
                textEmbeddingExtractor: textExtractor
            )
        )
        _duplicateManager = StateObject(
            wrappedValue: DuplicateDetectionManager(
                photoLibraryManager: photoLibraryManager,
                coreDataManager: coreDataManager
            )
        )
        _exportManager = StateObject(
            wrappedValue: ExportManager(photoLibraryManager: photoLibraryManager)
        )

        let bgManager = BackgroundScanManager(
            photoLibraryManager: photoLibraryManager,
            coreDataManager: coreDataManager,
            fastImageEmbeddingExtractor: fastImageExtractor,
            faceEmbeddingExtractor: faceExtractor
        )
        _backgroundScanManager = StateObject(wrappedValue: bgManager)
        bgManager.registerBackgroundTask()
        _widgetSync = State(initialValue: WidgetSyncService(coreDataManager: coreDataManager))
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(coreDataManager)
                .environmentObject(photoLibraryManager)
                .environmentObject(categoryManager)
                .environmentObject(scanManager)
                .environmentObject(backgroundScanManager)
                .environmentObject(searchManager)
                .environmentObject(duplicateManager)
                .environmentObject(exportManager)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .task {
                    widgetSync.sync()
                }
                .onChange(of: scenePhase) { _ in
                    widgetSync.sync()
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "smartalbum" else { return }
        // 主 App 的 navigation 逻辑在 HomeView 内通过 .onOpenURL 内部处理
    }
}
