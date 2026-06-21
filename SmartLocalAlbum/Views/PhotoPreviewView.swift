import CoreLocation
import SwiftUI
import UIKit

struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    let assetLocalIdentifier: String

    @State private var image: UIImage?
    @State private var photoInfo: PhotoPreviewInfo?
    @State private var isShowingShareSheet = false
    @State private var isShowingCopiedAlert = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var zoomScale: CGFloat = 1
    @State private var baseZoomScale: CGFloat = 1
    @State private var imageOffset: CGSize = .zero
    @State private var baseImageOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoomScale)
                    .offset(imageOffset)
                    .ignoresSafeArea()
                    .gesture(SimultaneousGesture(zoomGesture, dragGesture))
                    .onTapGesture(count: 2) {
                        toggleZoom()
                    }
            } else {
                ProgressView()
                    .tint(.white)
            }

            metadataOverlay
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
            resetZoom()
            image = await photoLibraryManager.previewImage(for: assetLocalIdentifier)
            await loadPhotoInfo()
        }
    }

    @ViewBuilder
    private var metadataOverlay: some View {
        if let photoInfo, photoInfo.hasContent {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    if let dateText = photoInfo.dateText {
                        Label(dateText, systemImage: "calendar")
                    }
                    if let city = photoInfo.city {
                        Label(city, systemImage: "location")
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .allowsHitTesting(false)
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = min(max(baseZoomScale * value, 1), 6)
            }
            .onEnded { _ in
                baseZoomScale = zoomScale
                if zoomScale <= 1.01 {
                    resetZoom()
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > 1 else { return }
                imageOffset = CGSize(
                    width: baseImageOffset.width + value.translation.width,
                    height: baseImageOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard zoomScale > 1 else {
                    resetZoom()
                    return
                }
                baseImageOffset = imageOffset
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

    private func toggleZoom() {
        if zoomScale > 1 {
            resetZoom()
        } else {
            zoomScale = 2.5
            baseZoomScale = zoomScale
        }
    }

    private func resetZoom() {
        zoomScale = 1
        baseZoomScale = 1
        imageOffset = .zero
        baseImageOffset = .zero
    }

    private func loadPhotoInfo() async {
        guard let asset = photoLibraryManager.asset(localIdentifier: assetLocalIdentifier) else {
            photoInfo = nil
            return
        }

        let dateText = asset.creationDate.map { Self.captureDateFormatter.string(from: $0) }
        let city = await cityName(for: asset.location)
        photoInfo = PhotoPreviewInfo(dateText: dateText, city: city)
    }

    private func cityName(for location: CLLocation?) async -> String? {
        guard let location else { return nil }

        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return placemark.locality
                ?? placemark.subAdministrativeArea
                ?? placemark.administrativeArea
        } catch {
            return nil
        }
    }

    private static let captureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}

private struct PhotoPreviewInfo {
    let dateText: String?
    let city: String?

    var hasContent: Bool {
        dateText != nil || city != nil
    }
}
