import Foundation

struct SimilarityClassifier {
    func classify(
        assetLocalIdentifier: String? = nil,
        embedding: [Float],
        categories: [SmartCategoryModel]
    ) -> [ClassificationMatch] {
        categories.compactMap { category in
            let similarity = VectorUtils.cosineSimilarity(embedding, category.centerEmbedding)
            guard similarity >= category.threshold else { return nil }
            return ClassificationMatch(
                categoryId: category.id,
                assetLocalIdentifier: assetLocalIdentifier,
                similarity: similarity
            )
        }
        .sorted { $0.similarity > $1.similarity }
    }
}
