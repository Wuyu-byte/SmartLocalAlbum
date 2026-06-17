import SwiftUI
import Translation

/// 智能搜索入口:输入自然语言 → 复用 MobileCLIP text encoder → 余弦相似度 topK。
///
/// **交互能力**:
/// - 点击缩略图 → NavigationLink 全屏预览 (PhotoPreviewView)
/// - 长按缩略图 → 上下文菜单 (选择/复制)
/// - 选择模式: 工具栏切换, 支持多选 + 全选 + 批量删除
///
/// **搜索与翻译**:
/// - `searchManager.updateQuery` 内部 300ms 防抖 + 取消上次任务
/// - View 通过 `onChange(of: searchInput)` 触发, debounce 内部决定是否真搜索
/// - iOS 18+ 中文输入用系统 Translation 框架转为英文; iOS 18 以下原文搜索
/// - 离开 View 时 `.onDisappear { searchManager.cancel() }` 显式取消
struct SearchView: View {
    @EnvironmentObject private var searchManager: SearchManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager
    @EnvironmentObject private var coreDataManager: CoreDataManager

    @State private var searchInput: String = ""
    @State private var pendingTranslation = ""
    @State private var isTranslating = false
    @State private var translationRequestID = 0

    // MARK: Select mode
    @State private var isSelectMode: Bool = false
    @State private var selectedIds: Set<String> = []

    @FocusState private var isSearchFocused: Bool

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *) {
            mainContent
                .modifier(SystemTranslationModifier(
                    sourceText: pendingTranslation,
                    requestID: translationRequestID,
                    onSuccess: { translatedText in
                        isTranslating = false
                        searchManager.updateQuery(translatedText)
                    },
                    onFailure: {
                        isTranslating = false
                        searchManager.updateQuery(pendingTranslation)
                    }
                ))
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
        }
        .navigationTitle("智能搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { selectionToolbar }
        .onDisappear {
            searchManager.cancel()
            pendingTranslation = ""
            isTranslating = false
        }
        .onChange(of: searchInput) { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                searchManager.updateQuery("")
                pendingTranslation = ""
                isTranslating = false
                return
            }
            updateQuery(trimmed)
        }
    }

    // MARK: - Search Bar

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
                let trimmed = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                updateQuery(trimmed)
            }
            if isTranslating || searchManager.isSearching {
                ProgressView()
                    .scaleEffect(0.85)
            } else if !searchInput.isEmpty {
                Button {
                    searchInput = ""
                    searchManager.updateQuery("")
                    pendingTranslation = ""
                    isTranslating = false
                    exitSelectMode()
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

    // MARK: - Selection Toolbar

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        if !searchManager.hits.isEmpty {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSelectMode {
                    Button("全选") {
                        selectAll()
                    }
                    .disabled(selectedIds.count == searchManager.hits.count)

                    Button("完成") {
                        exitSelectMode()
                    }
                    .fontWeight(.semibold)
                } else {
                    Button {
                        enterSelectMode()
                    } label: {
                        Label("选择", systemImage: "checkmark.circle")
                    }
                }
            }
        }
    }

    // MARK: - Content States

    @ViewBuilder
    private var content: some View {
        if let error = searchManager.lastError {
            errorState(message: error)
        } else if searchManager.query.isEmpty {
            promptState
        } else if (isTranslating || searchManager.isSearching) && searchManager.hits.isEmpty {
            searchingState
        } else if searchManager.hits.isEmpty {
            emptyState
        } else {
            resultsArea
        }
    }

    private var promptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("用一句话描述你想找的照片")
                .font(.headline)
            Text("iOS 18 及以上中文会使用系统翻译为英文搜索;低版本会直接按原文搜索。")
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
            Text(isTranslating ? "正在翻译并搜索..." : "正在用 MobileCLIP 检索...")
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

    // MARK: - Results Grid

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 3)]

    private var resultsArea: some View {
        VStack(spacing: 0) {
            if isSelectMode {
                batchActionBar
            }
            resultsGrid
        }
    }

    private var batchActionBar: some View {
        HStack(spacing: 16) {
            Text("已选 \(selectedIds.count) 张")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                batchDelete()
            } label: {
                Label("删除", systemImage: "trash")
                    .font(.subheadline)
            }
            .disabled(selectedIds.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(searchManager.hits) { hit in
                    if isSelectMode {
                        // 选择模式: 点击切换选中状态
                        SearchHitCard(
                            hit: hit,
                            isSelectMode: true,
                            isSelected: selectedIds.contains(hit.assetLocalIdentifier)
                        )
                        .onTapGesture {
                            toggleSelection(hit.assetLocalIdentifier)
                        }
                        .contextMenu {
                            hitSelectContextMenu(hit)
                        }
                    } else {
                        // 浏览模式: 点击跳转预览
                        NavigationLink {
                            PhotoPreviewView(assetLocalIdentifier: hit.assetLocalIdentifier)
                        } label: {
                            SearchHitCard(
                                hit: hit,
                                isSelectMode: false,
                                isSelected: false
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            hitBrowseContextMenu(hit)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func hitBrowseContextMenu(_ hit: SearchHit) -> some View {
        Button {
            enterSelectMode()
            selectedIds.insert(hit.assetLocalIdentifier)
        } label: {
            Label("选择", systemImage: "checkmark.circle")
        }

        Button {
            Task {
                if let img = await photoLibraryManager.previewImage(for: hit.assetLocalIdentifier) {
                    UIPasteboard.general.image = img
                }
            }
        } label: {
            Label("复制到剪贴板", systemImage: "doc.on.doc")
        }
    }

    @ViewBuilder
    private func hitSelectContextMenu(_ hit: SearchHit) -> some View {
        let isSel = selectedIds.contains(hit.assetLocalIdentifier)
        Button {
            toggleSelection(hit.assetLocalIdentifier)
        } label: {
            Label(isSel ? "取消选择" : "选择", systemImage: isSel ? "circle" : "checkmark.circle")
        }

        Divider()

        Button {
            Task {
                if let img = await photoLibraryManager.previewImage(for: hit.assetLocalIdentifier) {
                    UIPasteboard.general.image = img
                }
            }
        } label: {
            Label("复制到剪贴板", systemImage: "doc.on.doc")
        }
    }

    // MARK: - Selection Logic

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func enterSelectMode() {
        isSelectMode = true
        selectedIds = []
    }

    private func exitSelectMode() {
        isSelectMode = false
        selectedIds = []
    }

    private func selectAll() {
        selectedIds = Set(searchManager.hits.map(\.assetLocalIdentifier))
    }

    private func batchDelete() {
        guard !selectedIds.isEmpty else { return }
        let ids = selectedIds
        exitSelectMode()
        Task {
            for id in ids {
                _ = try? await photoLibraryManager.deletePhoto(localIdentifier: id)
                try? coreDataManager.deletePhotoData(assetLocalIdentifier: id)
            }
        }
    }

    private func updateQuery(_ text: String) {
        guard containsCJKCharacters(text), #available(iOS 18.0, *) else {
            pendingTranslation = ""
            isTranslating = false
            searchManager.updateQuery(text)
            return
        }

        pendingTranslation = text
        isTranslating = true
        translationRequestID += 1
    }

    private func containsCJKCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0x2E80...0x2EFF).contains(scalar.value)
                || (0x3000...0x303F).contains(scalar.value)
        }
    }

}

@available(iOS 18.0, *)
struct SystemTranslationModifier: ViewModifier {
    let sourceText: String
    let requestID: Int
    let onSuccess: @MainActor (String) -> Void
    let onFailure: @MainActor () -> Void

    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onChange(of: requestID) { _ in
                guard !sourceText.isEmpty else {
                    configuration = nil
                    return
                }
                configuration = TranslationSession.Configuration(
                    source: .init(identifier: "zh-Hans"),
                    target: .init(identifier: "en")
                )
            }
            .translationTask(configuration) { session in
                let text = sourceText
                guard !text.isEmpty else { return }

                defer { configuration = nil }

                do {
                    let response = try await session.translate(text)
                    onSuccess(response.targetText)
                } catch {
                    onFailure()
                }
            }
    }
}
// MARK: - SearchHitCard

private struct SearchHitCard: View {
    let hit: SearchHit
    let isSelectMode: Bool
    let isSelected: Bool

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

            // Similarity badge
            Text(String(format: "%.2f", hit.similarity))
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(5)

            // Select mode checkmark overlay
            if isSelectMode {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? .blue : .white.opacity(0.7))
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(isSelected ? 1 : 0.35))
                                    .frame(width: 20, height: 20)
                            )
                            .padding(6)
                    }
                    Spacer()
                }

                // 黑色遮罩提示已选中
                if isSelected {
                    Color.black.opacity(0.15)
                        .allowsHitTesting(false)
                }
            }
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
