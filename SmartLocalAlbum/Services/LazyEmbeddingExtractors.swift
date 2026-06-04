import UIKit

final class LazyImageEmbeddingExtractor: ImageEmbeddingExtracting {
    let embeddingDimension: Int

    private let factory: () throws -> any ImageEmbeddingExtracting
    private let fallbackFactory: (() -> any ImageEmbeddingExtracting)?
    private let lock = NSLock()
    private var cachedExtractor: (any ImageEmbeddingExtracting)?

    init(
        embeddingDimension: Int,
        factory: @escaping () throws -> any ImageEmbeddingExtracting,
        fallbackFactory: (() -> any ImageEmbeddingExtracting)? = nil
    ) {
        self.embeddingDimension = embeddingDimension
        self.factory = factory
        self.fallbackFactory = fallbackFactory
    }

    func embedding(for image: UIImage) async throws -> [Float] {
        let extractor = try await Task.detached(priority: .userInitiated) {
            try self.loadExtractor()
        }.value
        return try await extractor.embedding(for: image)
    }

    private func loadExtractor() throws -> any ImageEmbeddingExtracting {
        lock.lock()
        defer { lock.unlock() }

        if let cachedExtractor {
            return cachedExtractor
        }

        do {
            let extractor = try factory()
            cachedExtractor = extractor
            return extractor
        } catch {
            guard let fallbackFactory else { throw error }
            let extractor = fallbackFactory()
            cachedExtractor = extractor
            return extractor
        }
    }
}

final class LazyTextEmbeddingExtractor: TextEmbeddingExtracting {
    let embeddingDimension: Int

    private let factory: () throws -> any TextEmbeddingExtracting
    private let fallbackFactory: (() -> any TextEmbeddingExtracting)?
    private let lock = NSLock()
    private var cachedExtractor: (any TextEmbeddingExtracting)?

    init(
        embeddingDimension: Int,
        factory: @escaping () throws -> any TextEmbeddingExtracting,
        fallbackFactory: (() -> any TextEmbeddingExtracting)? = nil
    ) {
        self.embeddingDimension = embeddingDimension
        self.factory = factory
        self.fallbackFactory = fallbackFactory
    }

    func embedding(for text: String) async throws -> [Float] {
        let extractor = try await Task.detached(priority: .userInitiated) {
            try self.loadExtractor()
        }.value
        return try await extractor.embedding(for: text)
    }

    private func loadExtractor() throws -> any TextEmbeddingExtracting {
        lock.lock()
        defer { lock.unlock() }

        if let cachedExtractor {
            return cachedExtractor
        }

        do {
            let extractor = try factory()
            cachedExtractor = extractor
            return extractor
        } catch {
            guard let fallbackFactory else { throw error }
            let extractor = fallbackFactory()
            cachedExtractor = extractor
            return extractor
        }
    }
}
