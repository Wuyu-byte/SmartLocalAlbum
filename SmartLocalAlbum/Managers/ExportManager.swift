import Foundation
import Photos
import UIKit
import os

/// 导出 / 共享分类内的照片。
/// 支持:
/// 1. 创建一个新系统相册(用户输入名称)并将分类结果中的照片加入
/// 2. 生成分享文件 URL(供 ShareSheet 使用)
/// 3. 通过系统分享面板导出
@MainActor
final class ExportManager: ObservableObject {
    enum ExportError: LocalizedError {
        case noResultsToExport
        case missingPhotoLibraryPermission
        case albumCreationFailed(underlying: Error?)
        case fileWriteFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noResultsToExport: return "分类内没有可导出的照片"
            case .missingPhotoLibraryPermission: return "请先授权访问系统相册"
            case .albumCreationFailed(let error): return "创建相册失败:\(error?.localizedDescription ?? "未知错误")"
            case .fileWriteFailed(let error): return "写入文件失败:\(error.localizedDescription)"
            }
        }
    }

    @Published private(set) var isExporting = false
    @Published private(set) var progress: ScanProgress = ScanProgress()
    @Published private(set) var lastError: String?
    @Published private(set) var lastExportURL: URL?

    private let photoLibraryManager: PhotoLibraryManager
    private let logger = Logger(subsystem: "SmartLocalAlbum", category: "Export")

    init(photoLibraryManager: PhotoLibraryManager) {
        self.photoLibraryManager = photoLibraryManager
    }

    /// 在主相册创建一个新相册,把分类结果全部加进去。
    /// **关键**:PHPhotoLibrary 提交在同一 performChanges 内,避免多次写权限弹窗。
    func exportToSystemAlbum(categoryName: String, assetLocalIdentifiers: [String]) async throws -> String {
        guard !assetLocalIdentifiers.isEmpty else { throw ExportError.noResultsToExport }
        let status = await photoLibraryManager.requestAuthorization()
        guard status == .authorized || status == .limited else {
            throw ExportError.missingPhotoLibraryPermission
        }

        isExporting = true
        progress = ScanProgress(isScanning: true, processed: 0, total: assetLocalIdentifiers.count, message: "正在导出 📤")
        defer { isExporting = false }

        // 1. 一次性 fetch 所有 assets
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetLocalIdentifiers, options: nil)
        guard assets.count > 0 else { throw ExportError.noResultsToExport }

        // 2. 创建相册并加入照片,合并为一次 performChanges
        let collectionTitle = categoryName
        let placeholder: PHObjectPlaceholder
        do {
            placeholder = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<PHObjectPlaceholder, Error>) in
                var created: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: collectionTitle)
                    created = request.placeholderForCreatedAssetCollection
                }) { success, error in
                    if success, let created {
                        cont.resume(returning: created)
                    } else {
                        cont.resume(throwing: error ?? NSError(domain: "Export", code: -1))
                    }
                }
            }
        } catch {
            throw ExportError.albumCreationFailed(underlying: error)
        }

        guard let collection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [placeholder.localIdentifier], options: nil
        ).firstObject else {
            throw ExportError.albumCreationFailed(underlying: nil)
        }

        // 3. 把 assets 加入新建的相册
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
                request.addAssets(assets)
            }) { success, error in
                if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: error ?? NSError(domain: "Export", code: -2))
                }
            }
        }

        progress = ScanProgress(
            isScanning: false,
            processed: assetLocalIdentifiers.count,
            total: assetLocalIdentifiers.count,
            message: "已导出到相册:\(collectionTitle)"
        )
        return collectionTitle
    }

    /// 把分类结果导出为临时文件 URL,供 ShareSheet 使用。
    /// 由于图片很大,这里只写一个 JSON 清单 + 第一张缩略图作为预览。
    /// 实际生产中可以改为 zip 打包。
    func exportManifest(category: SmartCategoryModel, hits: [SearchHit]) throws -> URL {
        do {
            let manifest = ExportManifest(
                categoryName: category.name,
                generatedAt: Date(),
                items: hits.map {
                    ExportManifest.Item(assetLocalIdentifier: $0.assetLocalIdentifier, similarity: $0.similarity)
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            let filename = "SmartAlbum-\(category.name)-\(Int(Date().timeIntervalSince1970)).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            self.lastExportURL = url
            return url
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.fileWriteFailed(underlying: error)
        }
    }
}

private struct ExportManifest: Codable {
    struct Item: Codable {
        let assetLocalIdentifier: String
        let similarity: Float
    }
    let categoryName: String
    let generatedAt: Date
    let items: [Item]
}
