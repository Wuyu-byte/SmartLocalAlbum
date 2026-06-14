import Foundation
import UIKit
import os

/// 智能搜索:对全量 photo embedding 用 MobileCLIP 文本 encoder 计算余弦相似度,
/// 返回 TopK。**关键:输入防抖 + 任务取消,严禁并发搜索 / 串行队列死锁**。
@MainActor
final class SearchManager: ObservableObject {
    @Published private(set) var query: String = ""
    @Published private(set) var hits: [SearchHit] = []
    @Published private(set) var isSearching = false
    @Published private(set) var lastError: String?

    private let coreDataManager: CoreDataManager
    private let textEmbeddingExtractor: any TextEmbeddingExtracting

    private var debounceTask: Task<Void, Never>?
    private var currentSearchTask: Task<Void, Never>?
    private let debounceNanos: UInt64 = 300_000_000  // 300ms

    /// 单次结果上限,避免主线程渲染 10k 条记录。
    @Published var maxResults: Int = 200

    init(coreDataManager: CoreDataManager, textEmbeddingExtractor: any TextEmbeddingExtracting) {
        self.coreDataManager = coreDataManager
        self.textEmbeddingExtractor = textEmbeddingExtractor
    }

    /// 公开:用户修改 query,内部做 300ms 防抖。
    func updateQuery(_ newQuery: String) {
        query = newQuery
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        debounceTask?.cancel()
        guard !trimmed.isEmpty else {
            currentSearchTask?.cancel()
            currentSearchTask = nil
            isSearching = false
            hits = []
            return
        }
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceNanos ?? 0)
            guard !Task.isCancelled, let self else { return }
            self.runSearch(trimmed)
        }
    }

    func cancel() {
        debounceTask?.cancel()
        currentSearchTask?.cancel()
        currentSearchTask = nil
        isSearching = false
    }

    private func runSearch(_ text: String) {
        currentSearchTask?.cancel()
        isSearching = true
        lastError = nil
        let textExtractor = self.textEmbeddingExtractor
        let coreDataManager = self.coreDataManager
        let maxResults = self.maxResults

        currentSearchTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                if Task.isCancelled { return }
                let queryEmbedding: [Float]
                do {
                    queryEmbedding = try await textExtractor.embedding(for: text)
                } catch {
                    self.lastError = "无法编码查询:\(error.localizedDescription)"
                    self.isSearching = false
                    return
                }
                if Task.isCancelled { return }

                let allEmbeddings = try await coreDataManager.fetchAllPhotoEmbeddingModelsAsync(kind: .image)
                if Task.isCancelled { return }
                let computed = await Task.detached(priority: .userInitiated) { [queryEmbedding] in
                    Self.topKSimilar(queryEmbedding: queryEmbedding, candidates: allEmbeddings, topK: maxResults)
                }.value
                if Task.isCancelled { return }
                self.hits = computed
                self.isSearching = false
            } catch is CancellationError {
                self?.isSearching = false
            } catch {
                self?.lastError = error.localizedDescription
                self?.isSearching = false
            }
        }
    }

    /// 在后台 actor 之外执行的纯计算:
    /// - 仅在前 N 个 topK 上做堆
    /// - 用 maxResults 上限,**绝对不返回超过 topK 条**
    nonisolated static func topKSimilar(
        queryEmbedding: [Float],
        candidates: [PhotoEmbeddingSummary],
        topK: Int
    ) -> [SearchHit] {
        guard !candidates.isEmpty, topK > 0 else { return [] }
        var topKHeap: [(similarity: Float, assetId: String)] = []
        topKHeap.reserveCapacity(topK)
        for candidate in candidates {
            let sim = VectorUtils.cosineSimilarity(queryEmbedding, candidate.embedding)
            if topKHeap.count < topK {
                topKHeap.append((sim, candidate.assetLocalIdentifier))
                if topKHeap.count == topK {
                    topKHeap.sort { $0.similarity < $1.similarity }
                }
            } else if sim > topKHeap[0].similarity {
                topKHeap[0] = (sim, candidate.assetLocalIdentifier)
                topKHeap.sort { $0.similarity < $1.similarity }
            }
        }
        topKHeap.sort { $0.similarity > $1.similarity }
        return topKHeap.map { SearchHit(assetLocalIdentifier: $0.assetId, similarity: $0.similarity) }
    }
}

struct PhotoEmbeddingSummary: Sendable {
    let assetLocalIdentifier: String
    let embedding: [Float]
}
