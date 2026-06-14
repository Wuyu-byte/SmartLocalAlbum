import SwiftUI

/// 动态相册(Live Album):
/// - 自动展示所有 `isLive = true` 的分类
/// - 每次后台扫描完成后,新匹配的照片会自动进分类
/// - 用户可在此页将任意分类切换为"动态"
///
/// **循环安全**:
/// - `loadCategories` 一次性 fetch,不与 onChange 形成回环
/// - `toggleLive` 用 isLive 本地状态做防抖,500ms 内只触发一次
struct LiveAlbumsView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var scanManager: ScanManager
    @State private var liveAlbums: [SmartCategoryModel] = []
    @State private var showAllCategories: Bool = false
    @State private var allCategories: [SmartCategoryModel] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("动态相册")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAllCategories.toggle()
                        loadCategories()
                    } label: {
                        Label(
                            showAllCategories ? "只看动态" : "管理所有分类",
                            systemImage: showAllCategories ? "sparkles" : "slider.horizontal.3"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { loadCategories() }
        .onChange(of: scanManager.lastReclassifiedAt) { _ in
            loadCategories()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("新照片自动归类", systemImage: "sparkles")
                .font(.headline)
            Text("开启后,扫描时新匹配的照片会自动加入对应相册,无需手动整理。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        let displayed = showAllCategories ? allCategories : liveAlbums
        if displayed.isEmpty {
            emptyState
        } else {
            list(displayed)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(showAllCategories ? "还没有分类" : "还没有动态相册")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(showAllCategories ? "在\"创建分类\"中新建一个分类,然后开启动态。" : "点击右上角菜单 → 管理所有分类,把已有分类标为动态。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ items: [SmartCategoryModel]) -> some View {
        List {
            ForEach(items) { category in
                NavigationLink {
                    CategoryDetailView(categoryId: category.id, title: category.name)
                } label: {
                    LiveAlbumRow(
                        category: category,
                        onToggleLive: { newValue in
                            toggleLive(category: category, isLive: newValue)
                        }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadCategories() {
        do {
            let all = try coreDataManager.fetchCategoryModels()
            allCategories = all
            liveAlbums = all.filter { $0.isLive }
        } catch {
            // 静默
        }
    }

    private func toggleLive(category: SmartCategoryModel, isLive: Bool) {
        do {
            try coreDataManager.updateCategoryLiveState(id: category.id, isLive: isLive)
            loadCategories()
        } catch {
            // 静默
        }
    }
}

private struct LiveAlbumRow: View {
    let category: SmartCategoryModel
    let onToggleLive: (Bool) -> Void

    @EnvironmentObject private var coreDataManager: CoreDataManager
    @State private var matchCount: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(category.name)
                        .font(.headline)
                    if category.isLive {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                Text("\(matchCount) 张 · \(category.sourceLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { category.isLive },
                set: { onToggleLive($0) }
            ))
            .labelsHidden()
        }
        .task(id: category.id) {
            matchCount = (try? coreDataManager.fetchResults(categoryId: category.id, limit: 10_000).count) ?? 0
        }
    }
}
