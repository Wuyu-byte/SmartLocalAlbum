import Foundation
import Photos
import UIKit

@MainActor
final class ScanManager: ObservableObject {
    @Published private(set) var progress = ScanProgress()
    /// 最近一次重新分类的完成时间,UI 通过 .onChange(of:) 监听来刷新。
    @Published private(set) var lastReclassifiedAt: Date = .distantPast

    static let bgScanProgressKey = "SmartLocalAlbum.bgScan.lastProcessedIndex"
    private let weeklyAutoScanKey = "SmartLocalAlbum.lastWeeklyAutoScanAt"
    private let weeklyAutoScanInterval: TimeInterval = 7 * 24 * 60 * 60
    private let photoLibraryManager: PhotoLibraryManager
    private let coreDataManager: CoreDataManager
    private let fastImageEmbeddingExtractor: any ImageEmbeddingExtracting
    private let faceEmbeddingExtractor: any ImageEmbeddingExtracting
    private let classifier = SimilarityClassifier()
    private var scanTask: Task<Void, Never>?

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

    func scanPhotoLibrary() {
        guard progress.isScanning == false else { return }
        scanTask = Task { await performScan(forceReextract: false) }
    }

    func resetScanData() {
        guard progress.isScanning == false else { return }
        do {
            try coreDataManager.resetScanData()
            progress = ScanProgress(isScanning: false, message: "已重置，可以重新扫描")
        } catch {
            progress = ScanProgress(isScanning: false, message: error.localizedDescription)
        }
    }

    func reclassifySavedEmbeddings() {
        guard progress.isScanning == false else { return }
        scanTask = Task { await performReclassification() }
    }

    func runWeeklyAutoScanIfNeeded(hasCategories: Bool) {
        guard hasCategories, progress.isScanning == false else { return }

        let defaults = UserDefaults.standard
        let now = Date()
        guard let lastScan = defaults.object(forKey: weeklyAutoScanKey) as? Date else {
            defaults.set(now, forKey: weeklyAutoScanKey)
            return
        }

        guard now.timeIntervalSince(lastScan) >= weeklyAutoScanInterval else { return }
        defaults.set(now, forKey: weeklyAutoScanKey)
        scanTask = Task { await performScan(forceReextract: false) }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        progress.isScanning = false
        progress.message = "已取消"
    }

    private func performScan(forceReextract: Bool) async {
        let status = photoLibraryManager.hasReadAccess
            ? photoLibraryManager.authorizationStatus
            : await photoLibraryManager.requestAuthorization()

        guard status == .authorized || status == .limited else {
            progress = ScanProgress(isScanning: false, message: "需要相册权限")
            return
        }

        do {
            let categories = try await coreDataManager.fetchCategoryModelsAsync()
            guard !categories.isEmpty else {
                progress = ScanProgress(isScanning: false, message: "请先创建分类")
                return
            }
            let imageCategories = categories.filter { $0.matchingEmbeddingKind == .image }
            let faceCategories = categories.filter { $0.matchingEmbeddingKind == .face }

            let exclusionMap = try await coreDataManager.fetchCategoryExclusionMapAsync()
            let allAssets = await Task.detached(priority: .userInitiated) {
                PhotoLibraryManager.enumerateImageAssets()
            }.value
            let assets = allAssets
            progress = ScanProgress(
                isScanning: true,
                processed: 0,
                total: assets.count,
                message: "正在扫描照片 🔍"
            )

            for (index, asset) in assets.enumerated() {
                if Task.isCancelled { break }
                let assetId = asset.localIdentifier

                var matches: [ClassificationMatch] = []
                let needsImageEmbedding = !imageCategories.isEmpty
                let needsFaceEmbedding = !faceCategories.isEmpty
                var scanImage: UIImage?

                if needsImageEmbedding {
                    if let embedding = try await embedding(
                        for: asset,
                        assetId: assetId,
                        kind: .image,
                        forceReextract: forceReextract,
                        cachedImage: &scanImage
                    ) {
                        matches += classifier.classify(
                            assetLocalIdentifier: assetId,
                            embedding: embedding,
                            categories: imageCategories
                        )
                    }
                }

                if needsFaceEmbedding,
                   let embedding = try await embedding(
                    for: asset,
                    assetId: assetId,
                    kind: .face,
                    forceReextract: forceReextract,
                    cachedImage: &scanImage
                   ) {
                    matches += classifier.classify(
                        assetLocalIdentifier: assetId,
                        embedding: embedding,
                        categories: faceCategories
                    )
                }

                try await coreDataManager.replaceClassificationResultsAsync(
                    assetLocalIdentifier: assetId,
                    matches: matches,
                    excludedCategoryIds: exclusionMap[assetId] ?? []
                )

                progress = ScanProgress(
                    isScanning: true,
                    processed: index + 1,
                    total: assets.count,
                    message: "扫描中 \(index + 1) / \(assets.count)"
                )
            }

            progress = ScanProgress(isScanning: false, message: "扫描完成 ✅")
        } catch {
            progress = ScanProgress(isScanning: false, message: error.localizedDescription)
        }
    }

    private func performReclassification() async {
        do {
            let categories = try await coreDataManager.fetchCategoryModelsAsync()
            let imageCategories = categories.filter { $0.matchingEmbeddingKind == .image }
            let faceCategories = categories.filter { $0.matchingEmbeddingKind == .face }
            let exclusionMap = try await coreDataManager.fetchCategoryExclusionMapAsync()
            let imageEmbeddings = try coreDataManager.fetchAllPhotoEmbeddingModels(kind: .image)
            let faceEmbeddings = try coreDataManager.fetchAllPhotoEmbeddingModels(kind: .face)
            let total = imageEmbeddings.count + faceEmbeddings.count
            progress = ScanProgress(
                isScanning: true,
                processed: 0,
                total: total,
                message: "正在重新分类 🔁"
            )

            var processed = 0
            var groupedMatches: [String: [ClassificationMatch]] = [:]
            let allReclassifiedAssetIds = Set(
                imageEmbeddings.map(\.assetLocalIdentifier) + faceEmbeddings.map(\.assetLocalIdentifier)
            )

            for item in imageEmbeddings {
                if Task.isCancelled { break }
                let matches = classifier.classify(
                    assetLocalIdentifier: item.assetLocalIdentifier,
                    embedding: item.embedding,
                    categories: imageCategories
                )
                groupedMatches[item.assetLocalIdentifier, default: []] += matches
                processed += 1
                progress = ScanProgress(
                    isScanning: true, processed: processed, total: total,
                    message: "重新分类中 \(processed) / \(total)"
                )
            }

            for item in faceEmbeddings {
                if Task.isCancelled { break }
                let matches = classifier.classify(
                    assetLocalIdentifier: item.assetLocalIdentifier,
                    embedding: item.embedding,
                    categories: faceCategories
                )
                groupedMatches[item.assetLocalIdentifier, default: []] += matches
                processed += 1
                progress = ScanProgress(
                    isScanning: true, processed: processed, total: total,
                    message: "重新分类中 \(processed) / \(total)"
                )
            }

            for assetId in allReclassifiedAssetIds {
                try await coreDataManager.replaceClassificationResultsAsync(
                    assetLocalIdentifier: assetId,
                    matches: groupedMatches[assetId] ?? [],
                    excludedCategoryIds: exclusionMap[assetId] ?? []
                )
            }

            progress = ScanProgress(isScanning: false, message: "重新分类完成 ✅")
            lastReclassifiedAt = Date()
        } catch {
            progress = ScanProgress(isScanning: false, message: error.localizedDescription)
        }
    }

    private func embedding(
        for asset: PHAsset,
        assetId: String,
        kind: EmbeddingKind,
        forceReextract: Bool,
        cachedImage: inout UIImage?
    ) async throws -> [Float]? {
        if !forceReextract,
           let cached = try await coreDataManager.fetchPhotoEmbeddingAsync(
            assetLocalIdentifier: assetId, kind: kind
           ) {
            return cached.embedding
        }

        // 人脸检测需要更高分辨率,与 image 抽图不共用缓存。
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

        do {
            let extractor: any ImageEmbeddingExtracting
            switch kind {
            case .image:
                extractor = fastImageEmbeddingExtractor
            case .face:
                extractor = faceEmbeddingExtractor
            case .mobileclip2Image, .dinov2Image:
                return nil
            }
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
