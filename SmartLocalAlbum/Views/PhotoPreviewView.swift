import SwiftUI
import UIKit

struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    let assetLocalIdentifier: String

    @State private var image: UIImage?
    @State private var isShowingShareSheet = false
    @State private var isShowingCopiedAlert = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isTrashed = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .navigationTitle("预览 🖼")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    copyImage()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .disabled(image == nil)

                Button {
                    isShowingShareSheet = true
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .disabled(image == nil)

                if isTrashed {
                    Button {
                        restorePhoto()
                    } label: {
                        Label("恢复", systemImage: "arrow.uturn.backward.circle")
                    }
                } else {
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("回收站", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let image {
                ShareSheetView(items: [image])
            }
        }
        .alert("已复制 📋", isPresented: $isShowingCopiedAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("照片已复制到剪贴板。")
        }
        .alert("移入回收站", isPresented: $isShowingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("移入", role: .destructive) {
                moveToTrash()
            }
        } message: {
            Text("照片会从分类和整理列表中隐藏，但仍保留在系统照片库。可以在回收站恢复或永久删除。")
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: assetLocalIdentifier) {
            image = await photoLibraryManager.previewImage(for: assetLocalIdentifier)
            loadTrashState()
        }
    }

    private func copyImage() {
        guard let image else { return }
        UIPasteboard.general.image = image
        isShowingCopiedAlert = true
    }

    private func loadTrashState() {
        do {
            isTrashed = try coreDataManager.isPhotoTrashed(assetLocalIdentifier: assetLocalIdentifier)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToTrash() {
        do {
            try coreDataManager.movePhotoToTrash(assetLocalIdentifier: assetLocalIdentifier)
            isTrashed = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restorePhoto() {
        do {
            try coreDataManager.restorePhotoFromTrash(assetLocalIdentifier: assetLocalIdentifier)
            isTrashed = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
