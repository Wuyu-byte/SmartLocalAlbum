import BackgroundTasks
import Foundation
import Photos
import UIKit

@MainActor
final class BackgroundScanManager: ObservableObject {
    static let taskIdentifier = "com.loyuk.SmartLocalAlbum.backgroundScan"
    private let scheduleAfterScanKey = "SmartLocalAlbum.bgScan.scheduleAfterScan"

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
            print("[BackgroundScanManager] Failed to schedule: \(error)")
        }
    }

    private func handleBackgroundScan(task: BGProcessingTask) {
        let scanTask = Task {
            let classifier = SimilarityClassifier()

            do {
                let categories = try coreDataManager.fetchCategoryModels()
                guard !categories.isEmpty else {
                    task.setTaskCompleted(success: true)
                    return
                }

                let imageCategories = categories.filter { $0.matchingEmbeddingKind == .image }
                let faceCategories = categories.filter { $0.matchingEmbeddingKind == .face }
                let trashedAssetIds = try coreDataManager.fetchTrashedAssetIdSet()
                let exclusionMap = try coreDataManager.fetchCategoryExclusionMap()
                let allAssets = await Task.detached(priority: .userInitiated) {
                    PhotoLibraryManager.enumerateImageAssets()
                }.value
                let assets = allAssets.filter { !trashedAssetIds.contains($0.localIdentifier) }

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
                        if let embedding = try await embedding(
                            for: asset, assetId: assetId, kind: .image, cachedImage: &scanImage
                        ) {
                            matches += classifier.classify(
                                assetLocalIdentifier: assetId, embedding: embedding, categories: imageCategories
                            )
                        }
                    }

                    if !faceCategories.isEmpty,
                       let embedding = try await embedding(
                        for: asset, assetId: assetId, kind: .face, cachedImage: &scanImage
                       ) {
                        matches += classifier.classify(
                            assetLocalIdentifier: assetId, embedding: embedding, categories: faceCategories
                        )
                    }

                    try coreDataManager.replaceClassificationResults(
                        assetLocalIdentifier: assetId,
                        matches: matches,
                        excludedCategoryIds: exclusionMap[assetId] ?? []
                    )

                    if index % 10 == 0 {
                        UserDefaults.standard.set(index + 1, forKey: ScanManager.bgScanProgressKey)
                    }
                }

                UserDefaults.standard.removeObject(forKey: ScanManager.bgScanProgressKey)
                task.setTaskCompleted(success: !Task.isCancelled)
            } catch {
                UserDefaults.standard.removeObject(forKey: ScanManager.bgScanProgressKey)
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            scanTask.cancel()
        }
    }

    private func embedding(
        for asset: PHAsset,
        assetId: String,
        kind: EmbeddingKind,
        cachedImage: inout UIImage?
    ) async throws -> [Float]? {
        if let cached = try coreDataManager.fetchPhotoEmbedding(assetLocalIdentifier: assetId, kind: kind) {
            return VectorUtils.dataToFloatArray(cached.embeddingData)
        }

        let image: UIImage
        if let existing = cachedImage {
            image = existing
        } else {
            guard let loaded = await photoLibraryManager.image(for: asset, targetSize: CGSize(width: 512, height: 512)) else {
                return nil
            }
            cachedImage = loaded
            image = loaded
        }

        let extractor: any ImageEmbeddingExtracting = kind == .face ? faceEmbeddingExtractor : fastImageEmbeddingExtractor
        do {
            let embedding = try await extractor.embedding(for: image)
            try coreDataManager.savePhotoEmbedding(assetLocalIdentifier: assetId, embedding: embedding, kind: kind)
            return embedding
        } catch ImageEmbeddingError.noFaceDetected where kind == .face {
            return nil
        }
    }
}
