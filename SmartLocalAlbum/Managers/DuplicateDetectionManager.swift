import Foundation
import Photos
import UIKit
import os

/// 智能去重管理器:
/// 1. 遍历已抽 embedding 的 photo 列表(优先用缓存)
/// 2. 对没哈希的照片用 PerceptualHashExtractor 算 dHash
/// 3. 按 dHash 前 N bit 分桶,桶内两两算汉明距离,≤ threshold 视为同组
/// 4. 用并查集(union-find)合并
///
/// **重要**:每个阶段都有 `Task.isCancelled` 出口,**严格禁止 O(N²) 全量比对**。
@MainActor
final class DuplicateDetectionManager: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var progress = ScanProgress()
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var lastError: String?

    private let photoLibraryManager: PhotoLibraryManager
    private let coreDataManager: CoreDataManager

    /// dHash 汉明距离阈值;推荐 5(精确)、10(近重复)、15(相似)。
    @Published var distanceThreshold: Int = 5

    private var currentTask: Task<Void, Never>?

    init(photoLibraryManager: PhotoLibraryManager, coreDataManager: CoreDataManager) {
        self.photoLibraryManager = photoLibraryManager
        self.coreDataManager = coreDataManager
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// 完整跑一次:补齐 hash → 找组。
    func runDetection() {
        cancel()
        isWorking = true
        lastError = nil
        groups = []
        progress = ScanProgress(isScanning: true, processed: 0, total: 0, message: "正在准备 📦")
        let threshold = distanceThreshold
        let photoLibraryManager = self.photoLibraryManager
        let coreDataManager = self.coreDataManager

        currentTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                let assets = try await self.loadAllAssets()
                if Task.isCancelled { return }
                let existingHashes = try await coreDataManager.fetchAllPhotoHashesAsync()
                let hashedIds = Set(existingHashes.map(\.0))
                let toHash = assets.filter { !hashedIds.contains($0.localIdentifier) }
                progress = ScanProgress(
                    isScanning: true,
                    processed: 0,
                    total: toHash.count,
                    message: "正在计算指纹 🧬"
                )

                let newHashes = try await self.computeHashes(for: toHash)
                if Task.isCancelled { return }
                try await self.persistHashes(newHashes)
                if Task.isCancelled { return }
                let combined = existingHashes + newHashes
                if Task.isCancelled { return }
                let found = self.groupDuplicates(in: combined, threshold: threshold, photoLibraryManager: photoLibraryManager)
                if Task.isCancelled { return }
                self.groups = found
                self.progress = ScanProgress(
                    isScanning: false,
                    processed: combined.count,
                    total: combined.count,
                    message: "发现 \(found.count) 组重复"
                )
            } catch is CancellationError {
                self?.progress = ScanProgress(isScanning: false, message: "已取消")
            } catch {
                self?.lastError = error.localizedDescription
                self?.progress = ScanProgress(isScanning: false, message: error.localizedDescription)
            }
            self?.isWorking = false
            self?.currentTask = nil
        }
    }

    private func loadAllAssets() async throws -> [PHAsset] {
        await Task.detached(priority: .userInitiated) {
            PhotoLibraryManager.enumerateImageAssets()
        }.value
    }

    /// 串行处理避免 CPU 飙升 + 内存爆炸;每张完成后检查取消。
    /// 单次 hash 5ms 量级,1k 张约 5s,用户可接受。
    private func computeHashes(for assets: [PHAsset]) async throws -> [(String, Int64)] {
        var results: [(String, Int64)] = []
        results.reserveCapacity(assets.count)
        for (index, asset) in assets.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            guard let image = await photoLibraryManager.image(
                for: asset,
                targetSize: CGSize(width: 256, height: 256)
            ) else {
                continue
            }
            if let hash = PerceptualHashExtractor.dHash(image: image) {
                results.append((asset.localIdentifier, hash))
            }
            if index % 20 == 0 {
                progress = ScanProgress(
                    isScanning: true,
                    processed: index,
                    total: assets.count,
                    message: "正在计算指纹 🧬 \(index)/\(assets.count)"
                )
            }
        }
        return results
    }

    /// 串行 upsert 写回 Core Data,带取消守卫。
    private func persistHashes(_ hashes: [(String, Int64)]) async throws {
        for (assetId, hash) in hashes {
            if Task.isCancelled { throw CancellationError() }
            try await coreDataManager.savePhotoHashAsync(assetLocalIdentifier: assetId, hash: hash)
        }
    }

    /// 桶分组 + 并查集:把 N 张照片按 dHash 前 8 bit 分到 256 桶,
    /// 桶内两两比对汉明距离,O(256 * (N/256)²) = O(N²/256),比朴素 O(N²) 少两个数量级。
    private func groupDuplicates(
        in entries: [(String, Int64)],
        threshold: Int,
        photoLibraryManager: PhotoLibraryManager
    ) -> [DuplicateGroup] {
        guard entries.count > 1 else { return [] }
        var bucket: [UInt8: [(String, UInt64)]] = [:]
        for (assetId, hash) in entries {
            let u = UInt64(bitPattern: hash)
            let key = UInt8(truncatingIfNeeded: u >> 56)  // 前 8 bit
            bucket[key, default: []].append((assetId, u))
        }

        let unionFind = UnionFind(count: entries.count)
        let idToIndex = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.0, $0.offset) })

        for (_, group) in bucket {
            guard group.count > 1 else { continue }
            for i in 0..<group.count {
                if Task.isCancelled { return [] }
                for j in (i + 1)..<group.count {
                    let dist = (group[i].1 ^ group[j].1).nonzeroBitCount
                    if dist <= threshold,
                       let iIdx = idToIndex[group[i].0],
                       let jIdx = idToIndex[group[j].0] {
                        unionFind.union(iIdx, jIdx)
                    }
                }
            }
        }

        // 收集并查集结果
        var rootToMembers: [Int: [Int]] = [:]
        for i in 0..<entries.count {
            let r = unionFind.find(i)
            rootToMembers[r, default: []].append(i)
        }

        var result: [DuplicateGroup] = []
        for (_, members) in rootToMembers where members.count > 1 {
            let assetIds = members.map { entries[$0].0 }
            result.append(DuplicateGroup(
                id: UUID(),
                assetLocalIdentifiers: assetIds,
                approximateSavingsBytes: 0
            ))
        }
        // 按组内数量降序
        result.sort { $0.assetLocalIdentifiers.count > $1.assetLocalIdentifiers.count }
        return result
    }

    /// 从系统照片库删除所选 asset,并清理本地 Core Data 中的 embedding/hash/分类结果。
    /// iOS 自身会弹出系统级确认对话框;调用方需先在 UI 上做应用层二次确认。
    func removeAssets(_ assetIds: [String]) async {
        do {
            let deletedIds = try await photoLibraryManager.deletePhotos(localIdentifiers: assetIds)
            for id in assetIds {
                if Task.isCancelled { return }
                if deletedIds.contains(id) || photoLibraryManager.asset(localIdentifier: id) == nil {
                    try coreDataManager.deletePhotoData(assetLocalIdentifier: id)
                }
            }
            // 同步本地状态:从 groups 中移除
            let removedSet = Set(assetIds)
            groups = groups.compactMap { group in
                let remaining = group.assetLocalIdentifiers.filter { !removedSet.contains($0) }
                if remaining.count < 2 { return nil }
                return DuplicateGroup(
                    id: group.id,
                    assetLocalIdentifiers: remaining,
                    approximateSavingsBytes: group.approximateSavingsBytes
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// 路径压缩 + 按秩合并的并查集,O(α(n)) ≈ 几乎 O(1)。
private final class UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    func find(_ x: Int) -> Int {
        guard parent[x] != x else { return x }
        parent[x] = find(parent[x])
        return parent[x]
    }

    func union(_ a: Int, _ b: Int) {
        let ra = find(a)
        let rb = find(b)
        guard ra != rb else { return }
        if rank[ra] < rank[rb] {
            parent[ra] = rb
        } else if rank[ra] > rank[rb] {
            parent[rb] = ra
        } else {
            parent[rb] = ra
            rank[ra] += 1
        }
    }
}
