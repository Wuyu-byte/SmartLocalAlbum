import SwiftUI

/// 智能搜索入口:输入自然语言 → 复用 MobileCLIP text encoder → 余弦相似度 topK。
///
/// **循环安全**:
/// - `searchManager.updateQuery` 内部 300ms 防抖 + 取消上次任务
/// - View 通过 `onChange(of: searchInput)` 触发,debounce 内部决定是否真搜索
/// - 离开 View 时 `.onDisappear { searchManager.cancel() }` 显式取消
struct SearchView: View {
    @EnvironmentObject private var searchManager: SearchManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    @State private var searchInput: String = ""
    @State private var previewImage: UIImage?
    @State private var lastPreviewedId: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
        }
        .navigationTitle("智能搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { searchManager.cancel() }
        .onChange(of: searchInput) { newValue in
            searchManager.updateQuery(newValue)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("试试 \"海边日落\" \"人物\" \"咖啡杯\"", text: $searchInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit {
                    isSearchFocused = false
                    searchManager.updateQuery(searchInput)
                }
            if searchManager.isSearching {
                ProgressView()
                    .scaleEffect(0.85)
            } else if !searchInput.isEmpty {
                Button {
                    searchInput = ""
                    searchManager.updateQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let error = searchManager.lastError {
            errorState(message: error)
        } else if searchManager.query.isEmpty {
            promptState
        } else if searchManager.isSearching && searchManager.hits.isEmpty {
            searchingState
        } else if searchManager.hits.isEmpty {
            emptyState
        } else {
            resultsGrid
        }
    }

    private var promptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("用一句话描述你想找的照片")
                .font(.headline)
            Text("全部在本地完成,不会上传到任何服务器。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在用 MobileCLIP 检索 🔎")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("没有匹配的照片")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("尝试换一种描述,或先在主页面跑一次扫描。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("搜索出错")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 4)]

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(searchManager.hits) { hit in
                    SearchHitCard(hit: hit)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}

private struct SearchHitCard: View {
    let hit: SearchHit
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.secondary.opacity(0.12)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                .clipped()
            Text(String(format: "%.2f", hit.similarity))
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(5)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: hit.assetLocalIdentifier) {
            image = await photoLibraryManager.thumbnail(
                for: hit.assetLocalIdentifier,
                targetSize: CGSize(width: 320, height: 320)
            )
        }
    }
}
