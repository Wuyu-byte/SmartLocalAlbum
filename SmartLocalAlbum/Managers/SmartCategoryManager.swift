import Foundation
import UIKit

@MainActor
final class SmartCategoryManager: ObservableObject {
    nonisolated static let referenceFastDefaultThreshold: Float = 0.72
    nonisolated static let portraitDefaultThreshold: Float = 0.72

    private let coreDataManager: CoreDataManager
    private let fastImageEmbeddingExtractor: any ImageEmbeddingExtracting
    private let faceEmbeddingExtractor: any ImageEmbeddingExtracting

    init(
        coreDataManager: CoreDataManager,
        fastImageEmbeddingExtractor: any ImageEmbeddingExtracting,
        faceEmbeddingExtractor: any ImageEmbeddingExtracting
    ) {
        self.coreDataManager = coreDataManager
        self.fastImageEmbeddingExtractor = fastImageEmbeddingExtractor
        self.faceEmbeddingExtractor = faceEmbeddingExtractor
    }

    func createCategory(
        name: String,
        sampleImages: [UIImage],
        sampleAssetIds: [String],
        threshold: Float = SmartCategoryManager.referenceFastDefaultThreshold,
        isPortrait: Bool = false
    ) async throws -> SmartCategoryModel {
        try await createReferenceImageCategory(
            name: name,
            sampleImages: sampleImages,
            sampleAssetIds: sampleAssetIds,
            threshold: threshold,
            isPortrait: isPortrait
        )
    }

    func createReferenceImageCategory(
        name: String,
        sampleImages: [UIImage],
        sampleAssetIds: [String],
        threshold: Float = SmartCategoryManager.referenceFastDefaultThreshold,
        isPortrait: Bool = false
    ) async throws -> SmartCategoryModel {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw SmartCategoryError.emptyName }
        guard (1...10).contains(sampleImages.count) else { throw SmartCategoryError.invalidSampleCount }

        var embeddings: [[Float]] = []
        embeddings.reserveCapacity(sampleImages.count)
        let extractor: any ImageEmbeddingExtracting = isPortrait ? faceEmbeddingExtractor : fastImageEmbeddingExtractor
        let matchingEmbeddingKind: EmbeddingKind = isPortrait ? .face : .image

        for image in sampleImages {
            let embedding = try await extractor.embedding(for: image)
            embeddings.append(embedding)
        }

        let centerEmbedding = VectorUtils.averageEmbedding(embeddings)
        guard !centerEmbedding.isEmpty else { throw SmartCategoryError.embeddingFailed }

        return try coreDataManager.createCategory(
            name: trimmedName,
            centerEmbedding: centerEmbedding,
            sampleEmbeddings: embeddings,
            threshold: threshold,
            sampleAssetIds: sampleAssetIds,
            isPortrait: isPortrait,
            creationMode: isPortrait ? .portraitReference : .referenceImages,
            matchingEmbeddingKind: matchingEmbeddingKind,
            promptText: nil,
            templateKey: nil,
            referenceMatchingMode: .fast
        )
    }

    func updateThreshold(categoryId: UUID, threshold: Float) throws {
        try coreDataManager.updateCategoryThreshold(id: categoryId, threshold: threshold)
    }

    func deleteCategory(categoryId: UUID) throws {
        try coreDataManager.deleteCategory(id: categoryId)
    }
}

enum SmartCategoryError: LocalizedError {
    case emptyName
    case invalidSampleCount
    case embeddingFailed

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "请输入分类名称。"
        case .invalidSampleCount:
            return "请选择 1 到 10 张参考照片。"
        case .embeddingFailed:
            return "无法根据输入内容生成分类特征。"
        }
    }
}
