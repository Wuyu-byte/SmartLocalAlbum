import SwiftUI

struct CategoryDetailView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager

    let categoryId: UUID
    let title: String

    @State private var results: [ClassificationResultModel] = []
    @State private var categories: [SmartCategoryModel] = []
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        Group {
            if results.isEmpty {
                EmptyStateView(
                    title: "暂无匹配",
                    systemImage: "square.grid.3x3",
                    message: "可以先扫描相册，或调低这个分类的匹配严格度。"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(results) { result in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    PhotoPreviewView(assetLocalIdentifier: result.assetLocalIdentifier)
                                } label: {
                                    PhotoGridItemView(
                                        assetLocalIdentifier: result.assetLocalIdentifier,
                                        similarity: result.similarity
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    removeFromCategory(assetId: result.assetLocalIdentifier)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(.black.opacity(0.58), in: Circle())
                                        .overlay(
                                            Circle()
                                                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                                        )
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("从此分类移除")
                            }
                            .contextMenu {
                                Button {
                                    removeFromCategory(assetId: result.assetLocalIdentifier)
                                } label: {
                                    Label("从此分类移除", systemImage: "xmark.circle")
                                }
                                moveButtons(for: result)
                                Button {
                                    moveToUncategorized(assetId: result.assetLocalIdentifier)
                                } label: {
                                    Label("移到未分类", systemImage: "tray.and.arrow.down")
                                }
                                Button(role: .destructive) {
                                    moveToTrash(assetId: result.assetLocalIdentifier)
                                } label: {
                                    Label("移入回收站", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { loadData() }
        .refreshable { loadData() }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func moveButtons(for result: ClassificationResultModel) -> some View {
        if categories.filter({ $0.id != categoryId }).isEmpty {
            Text("没有其他分类")
        } else {
            ForEach(categories.filter { $0.id != categoryId }) { category in
                Button {
                    move(result: result, to: category)
                } label: {
                    Label("移到 \(category.name)", systemImage: "folder")
                }
            }
        }
    }

    private func loadData() {
        do {
            results = try coreDataManager.fetchResults(categoryId: categoryId)
            categories = try coreDataManager.fetchCategoryModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func move(result: ClassificationResultModel, to category: SmartCategoryModel) {
        do {
            try coreDataManager.moveClassificationResult(
                assetLocalIdentifier: result.assetLocalIdentifier,
                from: categoryId,
                to: category.id
            )
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeFromCategory(assetId: String) {
        do {
            try coreDataManager.excludePhotoFromCategory(
                assetLocalIdentifier: assetId,
                categoryId: categoryId
            )
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToUncategorized(assetId: String) {
        do {
            try coreDataManager.moveToUncategorized(assetLocalIdentifier: assetId)
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToTrash(assetId: String) {
        do {
            try coreDataManager.movePhotoToTrash(assetLocalIdentifier: assetId)
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct UncategorizedPhotosView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager

    @State private var assetIds: [String] = []
    @State private var categories: [SmartCategoryModel] = []
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        Group {
            if assetIds.isEmpty {
                EmptyStateView(
                    title: "没有未分类照片",
                    systemImage: "tray",
                    message: "扫描后，不属于任何自定义分类的照片会显示在这里。"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assetIds, id: \.self) { assetId in
                            NavigationLink {
                                PhotoPreviewView(assetLocalIdentifier: assetId)
                            } label: {
                                PhotoGridItemView(
                                    assetLocalIdentifier: assetId,
                                    similarity: nil
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                ForEach(categories) { category in
                                    Button {
                                        add(assetId: assetId, to: category)
                                    } label: {
                                        Label("放入 \(category.name)", systemImage: "folder.badge.plus")
                                    }
                                }
                                Button(role: .destructive) {
                                    moveToTrash(assetId: assetId)
                                } label: {
                                    Label("移入回收站", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .navigationTitle("未分类")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadData() }
        .refreshable { loadData() }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadData() {
        do {
            assetIds = try coreDataManager.fetchUncategorizedAssetIds()
            categories = try coreDataManager.fetchCategoryModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(assetId: String, to category: SmartCategoryModel) {
        do {
            try coreDataManager.moveClassificationResult(
                assetLocalIdentifier: assetId,
                from: nil,
                to: category.id
            )
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToTrash(assetId: String) {
        do {
            try coreDataManager.movePhotoToTrash(assetLocalIdentifier: assetId)
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
