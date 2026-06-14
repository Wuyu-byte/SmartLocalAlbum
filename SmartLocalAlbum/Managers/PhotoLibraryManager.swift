import Photos
import UIKit

@MainActor
final class PhotoLibraryManager: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus

    private let imageManager = PHCachingImageManager()
    private let coreDataManager: CoreDataManager
    private var pendingChangeTask: Task<Void, Never>?

    init(coreDataManager: CoreDataManager) {
        self.coreDataManager = coreDataManager
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    var hasReadAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // 去抖:系统批量变更会连续触发多次回调,合并为单次清理任务。
        let debounceNanos: UInt64 = 1_000_000_000
        Task { @MainActor [weak self] in
            self?.pendingChangeTask?.cancel()
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: debounceNanos)
                guard !Task.isCancelled, let self else { return }
                await self.processPhotoLibraryChange()
            }
            self?.pendingChangeTask = task
        }
    }

    @MainActor
    private func processPhotoLibraryChange() async {
        guard let embeddings = try? coreDataManager.fetchAllPhotoEmbeddingModels() else { return }
        let knownIds = Set(embeddings.map(\.assetLocalIdentifier))
        guard !knownIds.isEmpty else { return }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(knownIds), options: nil)
        var existingIds = Set<String>()
        result.enumerateObjects { asset, _, _ in
            existingIds.insert(asset.localIdentifier)
        }

        let staleIds = knownIds.subtracting(existingIds)
        for assetId in staleIds {
            try? coreDataManager.deletePhotoData(assetLocalIdentifier: assetId)
        }
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
            let lock = NSLock()
            var didResume = false

            func resume(_ status: PHAuthorizationStatus) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: status)
            }

            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                resume(status)
            }
        }
        authorizationStatus = status
        return status
    }

    nonisolated static func enumerateImageAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    func fetchImageAssets() -> [PHAsset] {
        Self.enumerateImageAssets()
    }

    func randomImageAssetIdentifiers(limit: Int, excluding excludedAssetIds: Set<String> = []) async -> [String] {
        guard limit > 0 else { return [] }
        let status = hasReadAccess ? authorizationStatus : await requestAuthorization()
        guard status == .authorized || status == .limited else { return [] }

        return Self.randomLocalImageAssetIdentifiers(limit: limit, excluding: excludedAssetIds)
    }

    nonisolated static func randomLocalImageAssetIdentifiers(
        limit: Int,
        excluding excludedAssetIds: Set<String> = []
    ) -> [String] {
        guard limit > 0 else { return [] }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let result = PHAsset.fetchAssets(with: options)
        guard result.count > 0 else { return [] }

        var selected: [String] = []
        selected.reserveCapacity(min(limit, result.count))
        var sampledIndexes = Set<Int>()

        while selected.count < limit && sampledIndexes.count < result.count {
            let index = Int.random(in: 0..<result.count)
            guard sampledIndexes.insert(index).inserted else { continue }

            let assetId = result.object(at: index).localIdentifier
            if !excludedAssetIds.contains(assetId) {
                selected.append(assetId)
            }
        }

        return selected
    }

    func asset(localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    func thumbnail(
        for localIdentifier: String,
        targetSize: CGSize = CGSize(width: 520, height: 520)
    ) async -> UIImage? {
        guard let asset = asset(localIdentifier: localIdentifier) else { return nil }
        return await requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            deliveryMode: .highQualityFormat,
            resizeMode: .exact,
            waitsForFinalImage: true
        )
    }

    func image(
        for asset: PHAsset,
        targetSize: CGSize = CGSize(width: 224, height: 224)
    ) async -> UIImage? {
        await requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            deliveryMode: .fastFormat,
            resizeMode: .fast,
            waitsForFinalImage: false
        )
    }

    func previewImage(
        for localIdentifier: String,
        maxPixelSize: CGFloat = 2600
    ) async -> UIImage? {
        guard let asset = asset(localIdentifier: localIdentifier) else { return nil }
        let targetSize = previewTargetSize(for: asset, maxPixelSize: maxPixelSize)
        return await requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            deliveryMode: .highQualityFormat,
            resizeMode: .exact,
            waitsForFinalImage: true
        )
    }

    func deletePhoto(localIdentifier: String) async throws -> Bool {
        let status = hasReadAccess ? authorizationStatus : await requestAuthorization()
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.permissionDenied
        }
        guard let asset = asset(localIdentifier: localIdentifier) else {
            throw PhotoLibraryError.assetNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func deletePhotos(localIdentifiers: [String]) async throws -> Set<String> {
        let status = hasReadAccess ? authorizationStatus : await requestAuthorization()
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.permissionDenied
        }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assets: [PHAsset] = []
        var foundIds = Set<String>()
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
            foundIds.insert(asset.localIdentifier)
        }
        guard !assets.isEmpty else { return [] }

        let success: Bool = try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }

        return success ? foundIds : []
    }

    private func previewTargetSize(for asset: PHAsset, maxPixelSize: CGFloat) -> CGSize {
        let width = CGFloat(asset.pixelWidth)
        let height = CGFloat(asset.pixelHeight)
        guard width > 0, height > 0 else {
            return CGSize(width: maxPixelSize, height: maxPixelSize)
        }

        let scale = min(maxPixelSize / max(width, height), 1)
        return CGSize(width: width * scale, height: height * scale)
    }

    private func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        resizeMode: PHImageRequestOptionsResizeMode,
        waitsForFinalImage: Bool
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = deliveryMode
            options.resizeMode = resizeMode
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false

            let lock = NSLock()
            var didResume = false
            var requestId: PHImageRequestID = PHInvalidImageRequestID
            let resume: (UIImage?) -> Void = { image in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }

            requestId = imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if let image, !waitsForFinalImage || !isDegraded {
                    resume(image)
                    return
                }

                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let hasError = info?[PHImageErrorKey] != nil
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                if cancelled || hasError || isInCloud || (image == nil && !isDegraded) {
                    resume(nil)
                }
            }

            // 缩略图 8s,高分辨率预览 30s。避免硬 3s 让 iCloud 大图永远拿不到。
            let pixelArea = targetSize.width * targetSize.height
            let timeout: TimeInterval = pixelArea >= 1_500_000 ? 30 : 8
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak imageManager] in
                imageManager?.cancelImageRequest(requestId)
                resume(nil)
            }
        }
    }
}

enum PhotoLibraryError: LocalizedError {
    case permissionDenied
    case assetNotFound

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要相册读写权限才能删除照片。"
        case .assetNotFound:
            return "这张照片已经不在当前可访问的相册中。"
        }
    }
}
