import UIKit

protocol TextEmbeddingExtracting {
    var embeddingDimension: Int { get }
    func embedding(for text: String) async throws -> [Float]
}

struct MockTextEmbeddingExtractor: TextEmbeddingExtracting {
    let embeddingDimension: Int

    init(embeddingDimension: Int = 512) {
        self.embeddingDimension = embeddingDimension
    }

    func embedding(for text: String) async throws -> [Float] {
        await Task.detached(priority: .userInitiated) {
            var values = Array(repeating: Float(0), count: embeddingDimension)
            let scalars = Array(text.unicodeScalars)
            guard !scalars.isEmpty else { return values }

            for (index, scalar) in scalars.enumerated() {
                let bucket = Int((UInt32(index) &* 31 &+ scalar.value) % UInt32(embeddingDimension))
                values[bucket] += 1
            }

            return VectorUtils.normalize(values)
        }.value
    }
}
