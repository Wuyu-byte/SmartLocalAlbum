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
    @State private var isDeleting = false
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
                .disabled(image == nil || isDeleting)

                Button {
                    isShowingShareSheet = true
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .disabled(image == nil || isDeleting)

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(isDeleting)
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
        .alert("确认删除这张照片?", isPresented: $isShowingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deletePhoto() }
            }
        } message: {
            Text("删除后会从系统照片库彻底移除（iOS 会再次弹出系统确认），本应用也会一并清理该照片的分类和指纹数据。")
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
        }
    }

    private func copyImage() {
        guard let image else { return }
        UIPasteboard.general.image = image
        isShowingCopiedAlert = true
    }

    private func deletePhoto() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            let deleted = try await photoLibraryManager.deletePhoto(localIdentifier: assetLocalIdentifier)
            if deleted || photoLibraryManager.asset(localIdentifier: assetLocalIdentifier) == nil {
                try coreDataManager.deletePhotoData(assetLocalIdentifier: assetLocalIdentifier)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
