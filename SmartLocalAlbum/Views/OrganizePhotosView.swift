import SwiftUI
import UIKit

struct OrganizePhotosView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    @State private var categories: [SmartCategoryModel] = []
    @State private var requestedCount = 25
    @State private var assetIds: [String] = []
    @State private var currentIndex = 0
    @State private var isLoading = false
    @State private var deleteCandidate: String?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var currentAssetId: String? {
        guard assetIds.indices.contains(currentIndex) else { return nil }
        return assetIds[currentIndex]
    }

    var body: some View {
        Group {
            if assetIds.isEmpty {
                startView
            } else {
                organizerView
            }
        }
        .navigationTitle("整理图片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !assetIds.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await startSession() }
                    } label: {
                        Label("重抽", systemImage: "shuffle")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task {
            loadCategories()
        }
        .alert("移入回收站", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("移入", role: .destructive) {
                guard let deleteCandidate else { return }
                moveToTrash(assetId: deleteCandidate)
            }
        } message: {
            Text("照片会从本次整理中移出并进入回收站，之后仍可恢复。")
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

    private var startView: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("随机抽一组照片来整理")
                    .font(.title3.weight(.semibold))
                Text("适合每天花几分钟处理一小批：加入分类、设为未分类、移入回收站，处理完自动进入下一张。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Stepper(value: $requestedCount, in: 5...200, step: 5) {
                HStack {
                    Label("本次数量", systemImage: "number")
                    Spacer()
                    Text("\(requestedCount) 张")
                        .font(.headline.monospacedDigit())
                }
            }
            .padding(.horizontal)

            HStack {
                quickCountButton(10)
                quickCountButton(25)
                quickCountButton(50)
                quickCountButton(100)
            }

            Button {
                Task { await startSession() }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Label("开始整理", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    private var organizerView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(currentIndex + 1) / \(assetIds.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    skipPhoto()
                } label: {
                    Label("跳过", systemImage: "forward")
                }
                .buttonStyle(.bordered)
                .disabled(assetIds.count < 2)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            TabView(selection: $currentIndex) {
                ForEach(Array(assetIds.enumerated()), id: \.element) { index, assetId in
                    OrganizePhotoPage(assetLocalIdentifier: assetId)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)

            actionBar
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Menu {
                    if categories.isEmpty {
                        Text("还没有分类")
                    } else {
                        ForEach(categories) { category in
                            Button {
                                addCurrentPhoto(to: category)
                            } label: {
                                Label(category.name, systemImage: "folder.badge.plus")
                            }
                        }
                    }
                } label: {
                    Label("加入分类", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(categories.isEmpty || currentAssetId == nil)

                Button {
                    markCurrentPhotoUncategorized()
                } label: {
                    Label("未分类", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(currentAssetId == nil)
            }

            HStack(spacing: 10) {
                Button {
                    deleteCandidate = currentAssetId
                } label: {
                    Label("回收站", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(currentAssetId == nil)

                Button {
                    skipPhoto()
                } label: {
                    Label("下一张", systemImage: "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(assetIds.count < 2)
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private func quickCountButton(_ count: Int) -> some View {
        Button {
            requestedCount = count
        } label: {
            Text("\(count)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(requestedCount == count ? .accentColor : nil)
    }

    private func loadCategories() {
        do {
            categories = try coreDataManager.fetchCategoryModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startSession() async {
        isLoading = true
        defer { isLoading = false }

        let trashedAssetIds = (try? coreDataManager.fetchTrashedAssetIdSet()) ?? []
        let randomIds = await photoLibraryManager.randomImageAssetIdentifiers(
            limit: requestedCount,
            excluding: trashedAssetIds
        )
        assetIds = randomIds
        currentIndex = 0
        statusMessage = randomIds.isEmpty ? "没有拿到可整理的照片。请确认相册权限，或在有限权限里添加更多照片。" : nil
        loadCategories()
    }

    private func addCurrentPhoto(to category: SmartCategoryModel) {
        guard let assetId = currentAssetId else { return }
        do {
            try coreDataManager.moveClassificationResult(
                assetLocalIdentifier: assetId,
                from: nil,
                to: category.id
            )
            statusMessage = "已加入 \(category.name)"
            removePhotoFromSession(assetId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markCurrentPhotoUncategorized() {
        guard let assetId = currentAssetId else { return }
        do {
            try coreDataManager.moveToUncategorized(assetLocalIdentifier: assetId)
            statusMessage = "已设为未分类"
            removePhotoFromSession(assetId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func skipPhoto() {
        guard !assetIds.isEmpty else { return }
        currentIndex = (currentIndex + 1) % assetIds.count
    }

    private func moveToTrash(assetId: String) {
        do {
            try coreDataManager.movePhotoToTrash(assetLocalIdentifier: assetId)
            statusMessage = "已移入回收站"
            removePhotoFromSession(assetId)
        } catch {
            errorMessage = error.localizedDescription
        }
        deleteCandidate = nil
    }

    private func removePhotoFromSession(_ assetId: String) {
        guard let index = assetIds.firstIndex(of: assetId) else { return }
        assetIds.remove(at: index)
        if assetIds.isEmpty {
            currentIndex = 0
            statusMessage = "这组照片整理完了。"
        } else if currentIndex >= assetIds.count {
            currentIndex = assetIds.count - 1
        }
    }
}

private struct OrganizePhotoPage: View {
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    let assetLocalIdentifier: String

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: assetLocalIdentifier) {
            image = nil
            image = await photoLibraryManager.previewImage(for: assetLocalIdentifier, maxPixelSize: 1800)
        }
    }
}
