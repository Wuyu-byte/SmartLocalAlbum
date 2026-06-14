import BackgroundTasks
import Foundation
import Photos
import UIKit

@MainActor
final class BackgroundScanManager: ObservableObject {
    static let taskIdentifier = "com.loyuk.SmartLocalAlbum.backgroundScan"

    private let photoLibraryManager: PhotoLibraryManager
    private let coreDataManager: CoreDataManager
    private let fastImageEmbeddingExtractor: any ImageEmbeddingExtracting
    private let faceEmbeddingExtractor: any ImageEmbeddingExtracting

    init(
        photoLibraryManager: PhotoLibraryManager,
        coreDataManager: CoreDataManager,
        fastImageEmbeddingExtractor: any ImageEmbeddingExtracting,
        faceEmbeddingExtractor: any ImageEmbeddingExtracting
    ) {
        self.photoLibraryManager = photoLibraryManager
        self.coreDataManager = coreDataManager
        self.fastImageEmbeddingExtractor = fastImageEmbeddingExtractor
        self.faceEmbeddingExtractor = faceEmbeddingExtractor
    }

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let task = task as? BGProcessingTask else { return }
            Task { @MainActor in
                self.handleBackgroundScan(task: task)
            }
        }
    }

    func scheduleBackgroundScan() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[BackgroundScanManager] Failed to schedule: \(error)")
            #endif
        }
    }

    private func handleBackgroundScan(task: BGProcessingTask) {
        let classifier = SimilarityClassifier()
        let photoLibraryManager = self.photoLibraryManager
        let coreDataManager = self.coreDataManager
        let fastImageExtractor = self.fastImageEmbeddingExtractor
        let faceExtractor = self.faceEmbeddingExtractor

        let scanTask = Task { @MainActor in
            do {
                let categories = try await coreDataManager.fetchCategoryModelsAsync()
                guard !categories.isEmpty else {
                    task.setTaskCompleted(success: true)
                    return
                }

                let imageCategories = categories.filter { $0.matchingEmbeddingKind == .image }
                let faceCategories = categories.filter { $0.matchingEmbeddingKind == .face }
                let exclusionMap = try await coreDataManager.fetchCategoryExclusionMapAsync()
                let assets = await Task.detached(priority: .userInitiated) {
                    PhotoLibraryManager.enumerateImageAssets()
                }.value

                let startIndex = UserDefaults.standard.integer(forKey: ScanManager.bgScanProgressKey)
                guard startIndex < assets.count else {
                    UserDefaults.standard.removeObject(forKey: ScanManager.bgScanProgressKey)
                    task.setTaskCompleted(success: true)
                    return
                }

                for index in startIndex..<assets.count {
                    if Task.isCancelled { break }
                    let asset = assets[index]
                    let assetId = asset.localIdentifier

                    var matches: [ClassificationMatch] = []
                    var scanImage: UIImage?

                    if !imageCategories.isEmpty {
                        if let embedding = try await Self.embedding(
                            for: asset,
                            assetId: assetId,
                            kind: .image,
                            photoLibraryManager: photoLibraryManager,
                            coreDataManager: coreDataManager,
                            fastImageExtractor: fastImageExtractor,
                            faceExtractor: faceExtractor,
                            cachedImage: &scanImage
                        ) {
                            matches += classifier.classify(
                                assetLocalIdentifier: assetId, embedding: embedding, categories: imageCategories
                            )
                        }
                    }

                    if !faceCategories.isEmpty,
                       let embedding = try await Self.embedding(
                        for: asset,
                        assetId: assetId,
                        kind: .face,
                        photoLibraryManager: photoLibraryManager,
                        coreDataManager: coreDataManager,
                        fastImageExtractor: fastImageExtractor,
                        faceExtractor: faceExtractor,
                        cachedImage: &scanImage
                       ) {
                        matches += classifier.classify(
                            assetLocalIdentifier: assetId, embedding: embedding, categories: faceCategories
                        )
                    }

                    if Task.isCancelled { break }
                    try await coreDataManager.replaceClassificationResultsAsync(
                        assetLocalIdentifier: assetId,
                        matches: matches,
                        excludedCategoryIds: exclusionMap[assetId] ?? []
                    )

                    if index % 10 == 0 {
                        UserDefaults.standard.set(index + 1, forKey: ScanManager.bgScanProgressKey)
                    }
                }

                let cancelled = Task.isCancelled
                UserDefaults.standard.removeObject(forKey: ScanManager.bgScanProgressKey)
                task.setTaskCompleted(success: !cancelled)
            } catch is CancellationError {
                UserDefaults.standard.removeObject(forKey: ScanManager.bgScanProgressKey)
                task.setTaskCompleted(success: false)
            } catch {
                #if DEBUG
                print("[BackgroundScanManager] scan failed: \(error)")
                #endif
                UserDefaults.standard.removeObject(forKey: ScanManager.bgScanProgressKey)
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            // 标记任务取消,真正的 setTaskCompleted 由 catch/finally 路径统一调用,
            // 避免在 expirationHandler 与 catch 之间重复 setTaskCompleted 引发系统断言。
            scanTask.cancel()
        }
    }

    private static func embedding(
        for asset: PHAsset,
        assetId: String,
        kind: EmbeddingKind,
        photoLibraryManager: PhotoLibraryManager,
        coreDataManager: CoreDataManager,
        fastImageExtractor: any ImageEmbeddingExtracting,
        faceExtractor: any ImageEmbeddingExtracting,
        cachedImage: inout UIImage?
    ) async throws -> [Float]? {
        if let cached = try await coreDataManager.fetchPhotoEmbeddingAsync(assetLocalIdentifier: assetId, kind: kind) {
            return cached.embedding
        }

        // 人脸检测需要更高的分辨率,直接走专用目标尺寸,避免与 image 抽图共用低分辨率缓存。
        let targetSize: CGSize = kind == .face
            ? CGSize(width: 1024, height: 1024)
            : CGSize(width: 512, height: 512)

        let image: UIImage
        if let existing = cachedImage, kind != .face {
            image = existing
        } else {
            guard let loaded = await photoLibraryManager.image(for: asset, targetSize: targetSize) else {
                return nil
            }
            if kind != .face {
                cachedImage = loaded
            }
            image = loaded
        }

        let extractor: any ImageEmbeddingExtracting = kind == .face ? faceExtractor : fastImageExtractor
        do {
            let embedding = try await extractor.embedding(for: image)
            try await coreDataManager.savePhotoEmbeddingAsync(
                assetLocalIdentifier: assetId,
                embedding: embedding,
                kind: kind
            )
            return embedding
        } catch ImageEmbeddingError.noFaceDetected where kind == .face {
            return nil
        }
    }
}
