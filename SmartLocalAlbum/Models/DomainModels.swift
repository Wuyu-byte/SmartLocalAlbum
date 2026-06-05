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
    var createdAt: Date
    var updatedAt: Date

    var thresholdRange: ClosedRange<Double> {
        switch matchingEmbeddingKind {
        case .image where creationMode == .naturalLanguage:
            return 0.05...0.40
        case .mobileclip2Image, .dinov2Image:
            return 0.10...0.99
        case .image, .face:
            return 0.10...0.99
        }
    }

    var sourceLabel: String {
        switch creationMode {
        case .naturalLanguage:
            return "文字描述"
        case .referenceImages:
            if matchingEmbeddingKind == .dinov2Image || matchingEmbeddingKind == .mobileclip2Image {
                return "旧参考图片"
            }
            return "参考图片"
        case .portraitReference:
            return "人脸参考"
        }
    }

    var isRetiredReferenceCategory: Bool {
        matchingEmbeddingKind == .dinov2Image || matchingEmbeddingKind == .mobileclip2Image
    }
}

enum EmbeddingKind: String, CaseIterable {
    case image
    case face
    case mobileclip2Image
    case dinov2Image
}

enum CategoryCreationMode: String, CaseIterable {
    case referenceImages
    case naturalLanguage
    case portraitReference
}

enum ReferenceMatchingMode: String, CaseIterable {
    case fast

    var displayName: String {
        "默认"
    }
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
