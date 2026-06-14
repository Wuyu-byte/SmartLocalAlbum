import Foundation

/// 主 App 与 Widget Extension 之间的数据共享层。
///
/// **配置步骤**(需在 Xcode 手动操作一次):
/// 1. 主 App 与 Widget 扩展的 Signing & Capabilities → 添加 "App Groups"
/// 2. App Group 标识符: `group.com.loyuk.SmartLocalAlbum`
/// 3. 主 App 的 Info.plist 已通过 build settings 配置 App Group
///
/// 数据共享策略:
/// - 小数据(计数、更新时间)走 `UserDefaults(suiteName:)`(系统序列化)
/// - 缩略图等大对象暂未走 widget(避免 Core Data 跨进程访问复杂度),后续可改为共享 Core Data store
enum WidgetSharedData {
    static let appGroupIdentifier = "group.com.loyuk.SmartLocalAlbum"

    /// 共享 UserDefaults;App Group 未配置时回退到 .standard,保证单元测试可用。
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    private enum Keys {
        static let liveAlbumCount = "widget.liveAlbumCount"
        static let liveAlbumSummary = "widget.liveAlbumSummary"
        static let totalCategories = "widget.totalCategories"
        static let pendingPhotos = "widget.pendingPhotos"
        static let lastUpdated = "widget.lastUpdated"
    }

    struct LiveAlbumSummary: Codable, Hashable {
        let categoryId: UUID
        let name: String
        let matchCount: Int
    }

    static func writeSnapshot(
        liveAlbums: [LiveAlbumSummary],
        totalCategories: Int,
        pendingPhotos: Int
    ) {
        let defaults = sharedDefaults
        defaults.set(liveAlbums.count, forKey: Keys.liveAlbumCount)
        defaults.set(totalCategories, forKey: Keys.totalCategories)
        defaults.set(pendingPhotos, forKey: Keys.pendingPhotos)
        defaults.set(Date(), forKey: Keys.lastUpdated)
        if let data = try? JSONEncoder().encode(liveAlbums) {
            defaults.set(data, forKey: Keys.liveAlbumSummary)
        }
    }

    static func readSnapshot() -> WidgetSnapshot {
        let defaults = sharedDefaults
        let liveAlbumCount = defaults.integer(forKey: Keys.liveAlbumCount)
        let totalCategories = defaults.integer(forKey: Keys.totalCategories)
        let pendingPhotos = defaults.integer(forKey: Keys.pendingPhotos)
        let lastUpdated = defaults.object(forKey: Keys.lastUpdated) as? Date ?? .distantPast
        let summaries: [LiveAlbumSummary] = {
            guard let data = defaults.data(forKey: Keys.liveAlbumSummary) else { return [] }
            return (try? JSONDecoder().decode([LiveAlbumSummary].self, from: data)) ?? []
        }()
        return WidgetSnapshot(
            liveAlbumCount: liveAlbumCount,
            totalCategories: totalCategories,
            pendingPhotos: pendingPhotos,
            lastUpdated: lastUpdated,
            liveAlbumSummaries: summaries
        )
    }
}

struct WidgetSnapshot: Hashable {
    let liveAlbumCount: Int
    let totalCategories: Int
    let pendingPhotos: Int
    let lastUpdated: Date
    let liveAlbumSummaries: [WidgetSharedData.LiveAlbumSummary]
}
