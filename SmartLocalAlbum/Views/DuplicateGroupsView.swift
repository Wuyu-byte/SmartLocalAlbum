import SwiftUI

/// 智能去重 UI:
/// - 顶部:进度 + 距离阈值 Picker + 重新扫描按钮
/// - 主体:重复组列表,每组有"保留最佳"快捷操作 + 全删按钮
///
/// **循环安全**:
/// - "保留最佳" 用 thumbnail 加载是 .task(id:),不会触发重复加载
/// - "全删" 后 groups 自动 compactMap,SwiftUI 列表不会重叠
struct DuplicateGroupsView: View {
    @EnvironmentObject private var duplicateManager: DuplicateDetectionManager
    @State private var showDeleteAllConfirm = false
    @State private var showDeleteSelectedConfirm = false
    @State private var isSelectMode = false
    @State private var isDeletingSelection = false
    @State private var selectedAssetIds: Set<String> = []
    @State private var previewRoute: DuplicatePhotoRoute?

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            if isSelectMode {
                selectionBar
                Divider()
            }
            content
        }
        .navigationDestination(isPresented: isPreviewPresented) {
            if let previewRoute {
                PhotoPreviewView(assetLocalIdentifier: previewRoute.assetLocalIdentifier)
            }
        }
        .navigationTitle("智能去重")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !duplicateManager.groups.isEmpty {
                    Button(isSelectMode ? "完成" : "选择") {
                        toggleSelectMode()
                    }
                    .disabled(duplicateManager.isWorking || isDeletingSelection)
                }
            }
        }
        .alert("删除全部重复照片?", isPresented: $showDeleteAllConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                let allIds = duplicateManager.groups.flatMap(\.assetLocalIdentifiers)
                Task {
                    await duplicateManager.removeAssets(allIds)
                }
            }
        } message: {
            Text("将删除 \(duplicateManager.groups.flatMap(\.assetLocalIdentifiers).count) 张照片。iOS 会再次弹出系统确认。")
        }
        .alert("删除选中的照片?", isPresented: $showDeleteSelectedConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteSelectedAssets()
            }
        } message: {
            Text("将删除选中的 \(selectedAssetIds.count) 张照片。iOS 会再次弹出系统确认。")
        }
        .onChange(of: duplicateManager.groups) { groups in
            let visibleIds = Set(groups.flatMap(\.assetLocalIdentifiers))
            selectedAssetIds.formIntersection(visibleIds)
            if visibleIds.isEmpty || selectedAssetIds.isEmpty {
                isSelectMode = false
            }
        }
    }

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if duplicateManager.isWorking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.on.square")
                        .foregroundStyle(.tint)
                }
                Text(duplicateManager.progress.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                Text("精确匹配")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Button {
                    if duplicateManager.isWorking {
                        duplicateManager.cancel()
                    } else {
                        duplicateManager.runDetection()
                    }
                } label: {
                    Image(systemName: duplicateManager.isWorking ? "stop.fill" : "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            if !duplicateManager.groups.isEmpty {
                Button(role: .destructive) {
                    showDeleteAllConfirm = true
                } label: {
                    Label("全部删除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(selectedAssetIds.count) 张")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                selectAllVisibleAssets()
            } label: {
                Label("全选", systemImage: "checkmark.circle")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("全选")

            Button {
                selectedAssetIds.removeAll()
            } label: {
                Label("清空", systemImage: "xmark.circle")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("清空选择")
            .disabled(selectedAssetIds.isEmpty)

            Button(role: .destructive) {
                showDeleteSelectedConfirm = true
            } label: {
                if isDeletingSelection {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Label("删除", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
            .accessibilityLabel("删除选中照片")
            .disabled(selectedAssetIds.isEmpty || isDeletingSelection)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder
    private var content: some View {
        if duplicateManager.isWorking {
            workingState
        } else if duplicateManager.groups.isEmpty {
            emptyState
        } else {
            groupsList
        }
    }

    private var workingState: some View {
        VStack(spacing: 12) {
            if duplicateManager.progress.total > 0 {
                ProgressView(value: duplicateManager.progress.fractionCompleted)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 48)
            } else {
                ProgressView()
            }
            Text("正在计算指纹与分组")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("没有发现重复")
                .font(.headline)
            Text("点击右上角重新扫描,或先在主页面运行一次扫描。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupsList: some View {
        List {
            ForEach(duplicateManager.groups) { group in
                DuplicateGroupRow(
                    group: group,
                    isSelectMode: isSelectMode,
                    selectedAssetIds: $selectedAssetIds,
                    openPreview: { assetId in
                        previewRoute = DuplicatePhotoRoute(assetLocalIdentifier: assetId)
                    },
                    selectSingleAsset: { assetId in
                        isSelectMode = true
                        selectedAssetIds = [assetId]
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private var isPreviewPresented: Binding<Bool> {
        Binding(
            get: { previewRoute != nil },
            set: { isPresented in
                if !isPresented {
                    previewRoute = nil
                }
            }
        )
    }

    private func toggleSelectMode() {
        isSelectMode.toggle()
        if !isSelectMode {
            selectedAssetIds.removeAll()
        }
    }

    private func selectAllVisibleAssets() {
        selectedAssetIds = Set(duplicateManager.groups.flatMap(\.assetLocalIdentifiers))
    }

    private func deleteSelectedAssets() {
        guard !selectedAssetIds.isEmpty, !isDeletingSelection else { return }
        isDeletingSelection = true
        let ids = Array(selectedAssetIds)
        Task {
            await duplicateManager.removeAssets(ids)
            selectedAssetIds.subtract(ids)
            isDeletingSelection = false
            if selectedAssetIds.isEmpty {
                isSelectMode = false
            }
        }
    }
}

private struct DuplicatePhotoRoute: Hashable {
    let assetLocalIdentifier: String
}

private struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    let isSelectMode: Bool
    @Binding var selectedAssetIds: Set<String>
    let openPreview: (String) -> Void
    let selectSingleAsset: (String) -> Void

    @EnvironmentObject private var duplicateManager: DuplicateDetectionManager
    @State private var showDeleteGroupConfirm = false
    @State private var deleting = false
    @State private var pendingDeletePhotoId: String?

    private let columns = [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 4)]

    var body: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(group.assetLocalIdentifiers, id: \.self) { assetId in
                    Button {
                        if isSelectMode {
                            toggleAssetSelection(assetId)
                        } else {
                            openPreview(assetId)
                        }
                    } label: {
                        SelectableDuplicateThumbnail(
                            assetLocalIdentifier: assetId,
                            isSelected: selectedAssetIds.contains(assetId),
                            showsSelectionState: isSelectMode
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if isSelectMode {
                            Button {
                                toggleAssetSelection(assetId)
                            } label: {
                                Label(
                                    selectedAssetIds.contains(assetId) ? "取消选择" : "选择这张",
                                    systemImage: selectedAssetIds.contains(assetId) ? "xmark.circle" : "checkmark.circle"
                                )
                            }
                        } else {
                            Button {
                                selectSingleAsset(assetId)
                            } label: {
                                Label("选择这张", systemImage: "checkmark.circle")
                            }
                        }

                        Button(role: .destructive) {
                            pendingDeletePhotoId = assetId
                        } label: {
                            Label("删除这张", systemImage: "trash")
                        }
                    }
                }
            }
            HStack {
                Text("\(group.assetLocalIdentifiers.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    showDeleteGroupConfirm = true
                } label: {
                    if deleting {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("全部删除")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(deleting)
            }
        }
        .alert("删除这一组照片?", isPresented: $showDeleteGroupConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard !deleting else { return }
                deleting = true
                Task {
                    await duplicateManager.removeAssets(group.assetLocalIdentifiers)
                    deleting = false
                }
            }
        } message: {
            Text("将删除本组 \(group.assetLocalIdentifiers.count) 张照片。iOS 会再次弹出系统确认。")
        }
        .alert("删除这张照片?", isPresented: Binding(
            get: { pendingDeletePhotoId != nil },
            set: { if !$0 { pendingDeletePhotoId = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard let assetId = pendingDeletePhotoId else { return }
                Task {
                    await duplicateManager.removeAssets([assetId])
                }
                pendingDeletePhotoId = nil
            }
        } message: {
            Text("将从系统照片库彻底删除,iOS 会再次弹出系统确认。")
        }
    }

    private func toggleAssetSelection(_ assetId: String) {
        if selectedAssetIds.contains(assetId) {
            selectedAssetIds.remove(assetId)
        } else {
            selectedAssetIds.insert(assetId)
        }
    }
}

private struct SelectableDuplicateThumbnail: View {
    let assetLocalIdentifier: String
    let isSelected: Bool
    let showsSelectionState: Bool

    var body: some View {
        ThumbnailView(assetLocalIdentifier: assetLocalIdentifier)
            .overlay {
                if showsSelectionState {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.08))
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsSelectionState {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.white, Color.white)
                        .padding(5)
                        .shadow(radius: 1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }
            .contentShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ThumbnailView: View {
    let assetLocalIdentifier: String
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.12)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView().scaleEffect(0.6)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .task(id: assetLocalIdentifier) {
                image = await photoLibraryManager.thumbnail(
                    for: assetLocalIdentifier,
                    targetSize: CGSize(width: 200, height: 200)
                )
            }
    }
}
