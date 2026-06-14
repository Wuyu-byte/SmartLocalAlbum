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

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            content
        }
        .navigationTitle("智能去重")
        .navigationBarTitleDisplayMode(.inline)
        .alert("删除所选照片?", isPresented: $showDeleteAllConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                let allIds = duplicateManager.groups.flatMap(\.assetLocalIdentifiers)
                Task {
                    await duplicateManager.removeAssets(allIds)
                }
            }
        } message: {
            Text("已选 \(duplicateManager.groups.flatMap(\.assetLocalIdentifiers).count) 张照片,删除后可在\"回收站\"恢复。")
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
                Picker("相似度", selection: $duplicateManager.distanceThreshold) {
                    Text("精确").tag(5)
                    Text("较近").tag(10)
                    Text("相似").tag(15)
                }
                .pickerStyle(.segmented)
                .disabled(duplicateManager.isWorking)

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
                    Label("全部移到回收站", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
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
                DuplicateGroupRow(group: group)
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @EnvironmentObject private var duplicateManager: DuplicateDetectionManager
    @State private var deleting = false

    private let columns = [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 4)]

    var body: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(group.assetLocalIdentifiers, id: \.self) { assetId in
                    NavigationLink {
                        PhotoPreviewView(assetLocalIdentifier: assetId)
                    } label: {
                        ThumbnailView(assetLocalIdentifier: assetId)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text("\(group.assetLocalIdentifiers.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    deleting = true
                    Task {
                        await duplicateManager.removeAssets(group.assetLocalIdentifiers)
                        deleting = false
                    }
                } label: {
                    if deleting {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("移入回收站")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
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
