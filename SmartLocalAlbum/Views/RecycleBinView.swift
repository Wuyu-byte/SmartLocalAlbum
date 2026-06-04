import SwiftUI

struct RecycleBinView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    @State private var trashedPhotos: [TrashedPhotoModel] = []
    @State private var permanentDeleteCandidate: TrashedPhotoModel?
    @State private var isConfirmingEmptyTrash = false
    @State private var isEmptyingTrash = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        Group {
            if trashedPhotos.isEmpty {
                EmptyStateView(
                    title: "回收站是空的",
                    systemImage: "trash",
                    message: "从整理、分类或预览里删除的照片会先放到这里。"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(trashedPhotos) { photo in
                            NavigationLink {
                                PhotoPreviewView(assetLocalIdentifier: photo.assetLocalIdentifier)
                            } label: {
                                PhotoGridItemView(
                                    assetLocalIdentifier: photo.assetLocalIdentifier,
                                    similarity: nil
                                )
                                .overlay(alignment: .topLeading) {
                                    Text(photo.trashedAt, format: .dateTime.month().day())
                                        .font(.caption2.monospacedDigit())
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 3)
                                        .background(.thinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                        .padding(5)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    restore(photo)
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward.circle")
                                }

                                Button(role: .destructive) {
                                    permanentDeleteCandidate = photo
                                } label: {
                                    Label("永久删除", systemImage: "trash.slash")
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .navigationTitle("回收站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !trashedPhotos.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        isConfirmingEmptyTrash = true
                    } label: {
                        if isEmptyingTrash {
                            ProgressView()
                        } else {
                            Label("清空", systemImage: "trash.slash")
                        }
                    }
                    .disabled(isEmptyingTrash)
                }
            }
        }
        .task { loadData() }
        .refreshable { loadData() }
        .alert("清空回收站", isPresented: $isConfirmingEmptyTrash) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task { await emptyTrash() }
            }
        } message: {
            Text("这会从系统照片库删除回收站内的照片。iOS 会继续弹出系统确认。")
        }
        .alert("永久删除照片", isPresented: Binding(
            get: { permanentDeleteCandidate != nil },
            set: { if !$0 { permanentDeleteCandidate = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                guard let permanentDeleteCandidate else { return }
                Task { await permanentlyDelete(permanentDeleteCandidate) }
            }
        } message: {
            Text("这会从系统照片库删除这张照片。iOS 会继续弹出系统确认。")
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
            trashedPhotos = try coreDataManager.fetchTrashedPhotoModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ photo: TrashedPhotoModel) {
        do {
            try coreDataManager.restorePhotoFromTrash(assetLocalIdentifier: photo.assetLocalIdentifier)
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func permanentlyDelete(_ photo: TrashedPhotoModel) async {
        do {
            let deleted = try await photoLibraryManager.deletePhoto(localIdentifier: photo.assetLocalIdentifier)
            if deleted {
                try coreDataManager.deletePhotoData(assetLocalIdentifier: photo.assetLocalIdentifier)
                loadData()
            }
        } catch PhotoLibraryError.assetNotFound {
            do {
                try coreDataManager.deletePhotoData(assetLocalIdentifier: photo.assetLocalIdentifier)
                loadData()
            } catch {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        permanentDeleteCandidate = nil
    }

    private func emptyTrash() async {
        guard !trashedPhotos.isEmpty, !isEmptyingTrash else { return }
        isEmptyingTrash = true
        defer { isEmptyingTrash = false }

        do {
            let trashedIds = trashedPhotos.map(\.assetLocalIdentifier)
            let deletedIds = try await photoLibraryManager.deletePhotos(localIdentifiers: trashedIds)
            for assetId in trashedIds {
                if deletedIds.contains(assetId) || photoLibraryManager.asset(localIdentifier: assetId) == nil {
                    try coreDataManager.deletePhotoData(assetLocalIdentifier: assetId)
                }
            }
            loadData()
        } catch {
            errorMessage = error.localizedDescription
            loadData()
        }
    }
}
