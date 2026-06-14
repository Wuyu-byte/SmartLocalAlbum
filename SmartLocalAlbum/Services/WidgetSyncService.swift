import Foundation
import WidgetKit

/// 把当前 App 状态同步到 App Group 共享 UserDefaults,并触发 WidgetKit 重新加载时间轴。
/// **关键**:只在数据真正变化时写入并 `WidgetCenter.shared.reloadAllTimelines()`,
/// 避免 onChange 触发链式死循环。
@MainActor
final class WidgetSyncService {
    private let coreDataManager: CoreDataManager
    private var lastSignature: String?

    init(coreDataManager: CoreDataManager) {
        self.coreDataManager = coreDataManager
    }

    /// 主 App 进入前台 / Live Album 变更时调用。
    /// 失败仅记录日志,不抛出;不影响主流程。
    func sync() {
        do {
            let categories = try coreDataManager.fetchCategoryModels()
            let liveAlbums = categories.filter { $0.isLive }
            let summaries: [WidgetSharedData.LiveAlbumSummary] = try liveAlbums.map { album in
                let count = try coreDataManager.fetchResults(categoryId: album.id, limit: 10_000).count
                return WidgetSharedData.LiveAlbumSummary(
                    categoryId: album.id,
                    name: album.name,
                    matchCount: count
                )
            }
            // 估算待分类 = 总 photo - 已有 result 的 photo
            let totalEmbeddings = try coreDataManager.fetchAllPhotoEmbeddingModels().count
            let totalResults = try coreDataManager.fetchResults(categoryId: nil, limit: 1_000_000).count
            let pending = max(0, totalEmbeddings - totalResults)

            let signature = "\(summaries.count)|\(summaries.map(\.matchCount).reduce(0, +))|\(totalEmbeddings)|\(pending)"
            guard signature != lastSignature else { return }
            lastSignature = signature

            WidgetSharedData.writeSnapshot(
                liveAlbums: summaries,
                totalCategories: categories.count,
                pendingPhotos: pending
            )
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // 不影响主流程
        }
    }
}
