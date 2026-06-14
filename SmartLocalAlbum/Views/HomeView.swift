import Photos
import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var categoryManager: SmartCategoryManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager
    @EnvironmentObject private var scanManager: ScanManager
    @EnvironmentObject private var backgroundScanManager: BackgroundScanManager

    @State private var categories: [SmartCategoryModel] = []
    @State private var isShowingCreateCategory = false
    @State private var isShowingOnboarding = false
    @State private var errorMessage: String?

    private let hasSeenOnboardingKey = "SmartLocalAlbum.hasSeenOnboarding"

    var body: some View {
        TabView {
            homeTab
                .tabItem {
                    Label("首页", systemImage: "house")
                }

            NavigationStack {
                RecycleBinView()
            }
            .tabItem {
                Label("回收站", systemImage: "trash")
            }

            NavigationStack {
                FAQView()
            }
            .tabItem {
                Label("常见问题", systemImage: "questionmark.circle")
            }
        }
    }

    private var homeTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                permissionBanner
                scanPanel

                List {
                    Section {
                        NavigationLink {
                            UncategorizedPhotosView()
                        } label: {
                            Label("未分类", systemImage: "tray")
                        }
                    }

                    if categories.isEmpty {
                        EmptyStateView(
                            title: "还没有分类",
                            systemImage: "rectangle.stack.badge.plus",
                            message: "用一句描述或几张参考照片，先建一个你想留下的集合。"
                        )
                    } else {
                        Section("我的分类") {
                            ForEach(categories) { category in
                                CategoryRowView(
                                    category: category,
                                    onThresholdChanged: { threshold in
                                        updateThreshold(categoryId: category.id, threshold: threshold)
                                    },
                                    onReclassify: {
                                        scanManager.reclassifySavedEmbeddings()
                                    }
                                )
                            }
                            .onDelete(perform: deleteCategories)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("智能整理相册")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingCreateCategory = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.accentColor))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                            .accessibilityLabel("新建分类")
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $isShowingCreateCategory, onDismiss: loadCategories) {
                NavigationStack {
                    CreateCategoryView()
                }
            }
            .alert("提示", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                photoLibraryManager.refreshAuthorizationStatus()
                loadCategories()
                runAutoScanIfReady()

                if !UserDefaults.standard.bool(forKey: hasSeenOnboardingKey) {
                    isShowingOnboarding = true
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    photoLibraryManager.refreshAuthorizationStatus()
                    loadCategories()
                    runAutoScanIfReady()
                }
            }
            .onChange(of: scanManager.lastReclassifiedAt) { _ in
                loadCategories()
            }
            .onChange(of: scanManager.progress.isScanning) { isScanning in
                if !isScanning && scanManager.progress.message.contains("完成") {
                    backgroundScanManager.scheduleBackgroundScan()
                }
            }
            .sheet(isPresented: $isShowingOnboarding) {
                UserDefaults.standard.set(true, forKey: hasSeenOnboardingKey)
            } content: {
                OnboardingView()
            }
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if photoLibraryManager.authorizationStatus == .limited {
            Label("当前只能访问已授权照片；所有整理都在本机完成。", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.16))
        } else if photoLibraryManager.authorizationStatus == .denied || photoLibraryManager.authorizationStatus == .restricted {
            Label("需要相册权限才能整理照片；照片不会上传。", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.12))
        }
    }

    private var scanPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scanManager.progress.message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if scanManager.progress.total > 0 {
                        Text("\(scanManager.progress.processed) / \(scanManager.progress.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                scanControls
            }

            ProgressView(value: scanManager.progress.fractionCompleted)
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var scanControls: some View {
        if scanManager.progress.isScanning {
            Button {
                scanManager.cancelScan()
            } label: {
                Label("取消", systemImage: "xmark.circle")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.bordered)
        } else {
            HStack(spacing: 8) {
                Button {
                    scanManager.resetScanData()
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise.circle")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .disabled(categories.isEmpty)

                Button {
                    scanManager.scanPhotoLibrary()
                } label: {
                    Label("扫描", systemImage: "photo.stack")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(minWidth: 72)
                }
                .buttonStyle(.borderedProminent)
                .disabled(categories.isEmpty)
            }
            .controlSize(.regular)
        }
    }

    private func loadCategories() {
        do {
            categories = try coreDataManager.fetchCategoryModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runAutoScanIfReady() {
        guard photoLibraryManager.hasReadAccess else { return }
        scanManager.runWeeklyAutoScanIfNeeded(hasCategories: !categories.isEmpty)
    }

    private func updateThreshold(categoryId: UUID, threshold: Float) {
        do {
            try categoryManager.updateThreshold(categoryId: categoryId, threshold: threshold)
            loadCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        do {
            for index in offsets {
                try categoryManager.deleteCategory(categoryId: categories[index].id)
            }
            loadCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

private struct FAQView: View {
    private let items: [(question: String, answer: String)] = [
        (
            "为什么扫描前要先创建分类？",
            "扫描会按你创建的分类寻找照片。先建分类，可以让处理更快，也更贴近你的喜好。"
        ),
        (
            "文字描述和参考图片有什么区别？",
            "文字描述适合找明确主题，比如猫、花、食物；参考图片适合找相近人物、场景或风格。"
        ),
        (
            "匹配严格度应该怎么调？",
            "结果太少时调低一点；混入不相关照片时调高一点。调整后会用已有特征重新整理。"
        ),
        (
            "移除错分照片后还会回来吗？",
            "不会。你在分类页移除的照片会记为这个分类的排除项，之后扫描会跳过它。"
        ),
        (
            "扫描会不会上传照片？",
            "不会。照片读取、特征提取和分类都在本机完成。"
        ),
        (
            "回收站会删除系统相册里的照片吗？",
            "移入回收站只会先从 App 里隐藏，不会立刻删除原图；永久删除或清空回收站时，才会从系统照片库删除，并且 iOS 会弹出系统确认。"
        )
    ]

    var body: some View {
        List {
            Section {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    DisclosureGroup {
                        Text(item.answer)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    } label: {
                        Text(item.question)
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("常见问题")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CategoryRowView: View {
    let category: SmartCategoryModel
    let onThresholdChanged: (Float) -> Void
    let onReclassify: () -> Void

    @State private var threshold: Double

    init(
        category: SmartCategoryModel,
        onThresholdChanged: @escaping (Float) -> Void,
        onReclassify: @escaping () -> Void
    ) {
        self.category = category
        self.onThresholdChanged = onThresholdChanged
        self.onReclassify = onReclassify
        _threshold = State(initialValue: Double(category.threshold))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                CategoryDetailView(categoryId: category.id, title: category.name)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                            .font(.headline)
                        Text(categoryDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "严格度 %.2f", threshold))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                Slider(
                    value: $threshold,
                    in: category.thresholdRange,
                    step: 0.01,
                    onEditingChanged: { editing in
                        if !editing {
                            onThresholdChanged(Float(threshold))
                            onReclassify()
                        }
                    }
                )
                .disabled(category.isRetiredReferenceCategory)
            }

            Text(category.isRetiredReferenceCategory
                ? "这个旧参考分类不会再参与扫描，请重新创建。"
                : "数值越高，结果越谨慎；数值越低，照片更多。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var categoryDescription: String {
        if category.isRetiredReferenceCategory {
            return "旧参考分类 · 请重新创建"
        }

        switch category.creationMode {
        case .naturalLanguage:
            return "\(category.sourceLabel) · \(category.promptText ?? category.name)"
        case .referenceImages, .portraitReference:
            return "\(category.sourceLabel) · \(category.sampleAssetIds.count) 张参考"
        }
    }
}
