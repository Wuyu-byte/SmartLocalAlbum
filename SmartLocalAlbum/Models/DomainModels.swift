import Foundation

struct SmartCategoryModel: Identifiable, Hashable {
    let id: UUID
    var name: String
    var centerEmbedding: [Float]
    var sampleEmbeddings: [[Float]]
    var threshold: Float
    var sampleAssetIds: [String]
    var isPortrait: Bool
    var creationMode: CategoryCreationMode
    var matchingEmbeddingKind: EmbeddingKind
    var promptText: String?
    var templateKey: String?
    var referenceMatchingMode: ReferenceMatchingMode
    var isLive: Bool
    var createdAt: Date
    var updatedAt: Date

    var thresholdRange: ClosedRange<Double> {
        switch matchingEmbeddingKind {
        case .image where creationMode == .naturalLanguage:
            return 0.05...0.40
        case .image, .face:
            return 0.10...0.99
        case .mobileclip2Image, .dinov2Image:
            return 0.10...0.99
        }
    }

    var sourceLabel: String {
        switch creationMode {
        case .naturalLanguage:
            return "文字描述"
        case .referenceImages:
            return matchingEmbeddingKind.isLegacy ? "旧参考图片" : "参考图片"
        case .portraitReference:
            return "人脸参考"
        }
    }

    var isRetiredReferenceCategory: Bool {
        matchingEmbeddingKind.isLegacy
    }
}

enum EmbeddingKind: String, CaseIterable {
    case image
    case face
    case mobileclip2Image
    case dinov2Image

    /// 历史模型(已弃用),旧分类仅用于提示用户重建,不再参与扫描。
    var isLegacy: Bool {
        self == .mobileclip2Image || self == .dinov2Image
    }
}

enum CategoryCreationMode: String, CaseIterable {
    case referenceImages
    case naturalLanguage
    case portraitReference
}

enum ReferenceMatchingMode: String, CaseIterable {
    case fast
}

struct ClassificationMatch: Identifiable, Hashable {
    var id: String { "\(categoryId.uuidString)-\(assetLocalIdentifier ?? "")" }
    let categoryId: UUID
    let assetLocalIdentifier: String?
    let similarity: Float
}

struct ClassificationResultModel: Identifiable, Hashable {
    let id: UUID
    let assetLocalIdentifier: String
    let categoryId: UUID
    let similarity: Float
    let isManual: Bool
    let createdAt: Date
}

struct TrashedPhotoModel: Identifiable, Hashable {
    var id: String { assetLocalIdentifier }
    let assetLocalIdentifier: String
    let trashedAt: Date
}

struct DuplicateGroup: Identifiable, Hashable {
    let id: UUID
    let assetLocalIdentifiers: [String]
    /// 累计字节估算(展示给用户,不强保证)。
    let approximateSavingsBytes: Int64
}

struct SearchHit: Identifiable, Hashable {
    var id: String { assetLocalIdentifier }
    let assetLocalIdentifier: String
    let similarity: Float
}

struct ExportDestination: Hashable {
    enum Kind: Hashable {
        case systemAlbum(name: String)
        case shareSheet
        case files
    }
    let kind: Kind
}

struct ScanProgress: Equatable {
    var isScanning: Bool = false
    var processed: Int = 0
    var total: Int = 0
    var message: String = "准备就绪 ✨"

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(processed) / Double(total)
    }
}
