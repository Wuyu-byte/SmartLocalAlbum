import SwiftUI

struct CategoryDetailView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    let categoryId: UUID
    let title: String

    @State private var results: [ClassificationResultModel] = []
    @State private var categories: [SmartCategoryModel] = []
    @State private var errorMessage: String?
    @State private var isShowingExport = false
    @State private var currentCategory: SmartCategoryModel?
    @State private var deleteCandidate: ClassificationResultModel?
    @State private var isDeleting = false
    @State private var albumLayout: CategoryAlbumLayout = .match

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
                    VStack(spacing: 12) {
                        albumLayoutPicker
                            .padding(.horizontal, 12)
                            .padding(.top, 12)

                        switch albumLayout {
                        case .match:
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(arrangedResults) { result in
                                    resultCell(result)
                                }
                            }
                            .padding(.horizontal, 2)
                        case .timeline:
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(resultTimelineSections) { section in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(section.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 12)

                                        LazyVGrid(columns: columns, spacing: 2) {
                                            ForEach(section.results) { result in
                                                resultCell(result)
                                            }
                                        }
                                        .padding(.horizontal, 2)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        isShowingExport = true
                    } label: {
                        Label("导出 / 共享", systemImage: "square.and.arrow.up")
                    }
                    .disabled(results.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingExport) {
            if let category = currentCategory {
                ExportSheetView(category: category, resultAssetIds: results.map(\.assetLocalIdentifier))
            }
        }
        .task { loadData() }
        .refreshable { loadData() }
        .alert("确认删除这张照片?", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard let deleteCandidate else { return }
                Task { await confirmDelete(result: deleteCandidate) }
            }
        } message: {
            Text("照片会从系统照片库彻底删除，iOS 会再次弹出系统确认。")
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var albumLayoutPicker: some View {
        Picker("排列方式", selection: $albumLayout) {
            ForEach(CategoryAlbumLayout.allCases, id: \.self) { layout in
                Text(layout.title).tag(layout)
            }
        }
        .pickerStyle(.segmented)
    }

    private func resultCell(_ result: ClassificationResultModel) -> some View {
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
            .disabled(isDeleting)
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
                deleteCandidate = result
            } label: {
                Label("删除照片", systemImage: "trash")
            }
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
            currentCategory = categories.first(where: { $0.id == categoryId })
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

    private func confirmDelete(result: ClassificationResultModel) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        let assetId = result.assetLocalIdentifier
        do {
            let deleted = try await photoLibraryManager.deletePhoto(localIdentifier: assetId)
            if deleted || photoLibraryManager.asset(localIdentifier: assetId) == nil {
                try coreDataManager.deletePhotoData(assetLocalIdentifier: assetId)
            }
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
        deleteCandidate = nil
    }

    private var arrangedResults: [ClassificationResultModel] {
        switch albumLayout {
        case .match:
            return results.sorted {
                if $0.similarity == $1.similarity {
                    return captureDate(for: $0) > captureDate(for: $1)
                }
                return $0.similarity > $1.similarity
            }
        case .timeline:
            return results.sorted {
                let lhsDate = captureDate(for: $0)
                let rhsDate = captureDate(for: $1)
                if Calendar.current.isDate(lhsDate, inSameDayAs: rhsDate) {
                    return $0.similarity > $1.similarity
                }
                return lhsDate > rhsDate
            }
        }
    }

    private var resultTimelineSections: [CategoryResultTimelineSection] {
        let grouped = Dictionary(grouping: arrangedResults) { result in
            let date = captureDate(for: result)
            return Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
        }

        return grouped.keys.sorted(by: >).map { monthStart in
            CategoryResultTimelineSection(
                monthStart: monthStart,
                title: Self.monthFormatter.string(from: monthStart),
                results: grouped[monthStart, default: []].sorted { captureDate(for: $0) > captureDate(for: $1) }
            )
        }
    }

    private func captureDate(for result: ClassificationResultModel) -> Date {
        photoLibraryManager.asset(localIdentifier: result.assetLocalIdentifier)?.creationDate ?? result.createdAt
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()
}

private enum CategoryAlbumLayout: String, CaseIterable, Hashable {
    case match
    case timeline

    var title: String {
        switch self {
        case .match: return "匹配度"
        case .timeline: return "时间线"
        }
    }
}

private struct CategoryResultTimelineSection: Identifiable {
    var id: Date { monthStart }
    let monthStart: Date
    let title: String
    let results: [ClassificationResultModel]
}

struct UncategorizedPhotosView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    @State private var assetIds: [String] = []
    @State private var categories: [SmartCategoryModel] = []
    @State private var errorMessage: String?
    @State private var deleteCandidate: String?
    @State private var isDeleting = false

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
                                    deleteCandidate = assetId
                                } label: {
                                    Label("删除照片", systemImage: "trash")
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
        .alert("确认删除这张照片?", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard let deleteCandidate else { return }
                Task { await confirmDelete(assetId: deleteCandidate) }
            }
        } message: {
            Text("照片会从系统照片库彻底删除，iOS 会再次弹出系统确认。")
        }
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

    private func confirmDelete(assetId: String) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            let deleted = try await photoLibraryManager.deletePhoto(localIdentifier: assetId)
            if deleted || photoLibraryManager.asset(localIdentifier: assetId) == nil {
                try coreDataManager.deletePhotoData(assetLocalIdentifier: assetId)
            }
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
        deleteCandidate = nil
    }
}
