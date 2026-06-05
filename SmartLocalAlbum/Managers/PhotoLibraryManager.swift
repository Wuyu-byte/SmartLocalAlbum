import Photos
import UIKit

@MainActor
final class PhotoLibraryManager: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus

    private let imageManager = PHCachingImageManager()
    private let coreDataManager: CoreDataManager

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

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
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
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
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

        let excluded = excludedAssetIds
        return await Task.detached(priority: .userInitiated) {
            Self.sampleImageAssetIdentifiers(limit: limit, excluding: excluded)
        }.value
    }

    nonisolated private static func sampleImageAssetIdentifiers(
        limit: Int,
        excluding excludedAssetIds: Set<String>
    ) -> [String] {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let result = PHAsset.fetchAssets(with: options)
        guard result.count > 0 else { return [] }

        var selected: [String] = []
        selected.reserveCapacity(min(limit, result.count))
        var sampledIndexes = Set<Int>()

        let randomAttemptLimit = min(result.count, max(limit * 20, 200))
        while selected.count < limit && sampledIndexes.count < randomAttemptLimit {
            let index = Int.random(in: 0..<result.count)
            guard sampledIndexes.insert(index).inserted else { continue }

            let assetId = result.object(at: index).localIdentifier
            if !excludedAssetIds.contains(assetId) {
                selected.append(assetId)
            }
        }

        guard selected.count < limit, sampledIndexes.count < result.count else {
            return selected
        }

        let startIndex = Int.random(in: 0..<result.count)
        for offset in 0..<result.count {
            if selected.count >= limit { break }
            let index = (startIndex + offset) % result.count
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

            var didResume = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                guard !didResume else { return }

                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if let image, !waitsForFinalImage || !isDegraded {
                    didResume = true
                    continuation.resume(returning: image)
                    return
                }

                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let hasError = info?[PHImageErrorKey] != nil
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                if cancelled || hasError || isInCloud || (image == nil && !isDegraded) {
                    didResume = true
                    continuation.resume(returning: nil)
                }
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
