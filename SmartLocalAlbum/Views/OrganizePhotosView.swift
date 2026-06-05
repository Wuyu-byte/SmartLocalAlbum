import CoreLocation
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
        .navigationTitle("整理")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "rectangle.stack.badge.play")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.black)
                        )

                    Text("一次只整理一小组")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("抽出一组照片，逐张决定放入分类、保留为未分类，或移入回收站。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("本次整理")
                            .font(.headline)
                        Spacer()
                        Text("\(requestedCount) 张")
                            .font(.title2.monospacedDigit().weight(.semibold))
                    }

                    Stepper("调整数量", value: $requestedCount, in: 5...200, step: 5)

                    HStack(spacing: 10) {
                        quickCountButton(10)
                        quickCountButton(25)
                        quickCountButton(50)
                        quickCountButton(100)
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

                Button {
                    Task { await startSession() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Label("开始整理", systemImage: "play.fill")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor)
                )
                .disabled(isLoading)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var organizerView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let currentAssetId {
                OrganizePhotoPage(assetLocalIdentifier: currentAssetId)
                    .id(currentAssetId)
            }

            VStack(spacing: 0) {
                sessionHeader
                Spacer(minLength: 0)
                actionBar
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -50 {
                        skipPhoto()
                    } else if value.translation.width > 50 {
                        goBack()
                    }
                }
        )
    }

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            Text("\(currentIndex + 1) / \(assetIds.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.42), in: Capsule())

            ProgressView(value: Double(currentIndex + 1), total: Double(max(assetIds.count, 1)))
                .tint(.white)
                .frame(maxWidth: 110)

            Spacer()

            Button {
                skipPhoto()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.42), in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(assetIds.count < 2)
            .accessibilityLabel("跳过")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var actionBar: some View {
        VStack(spacing: 14) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories.prefix(8)) { category in
                            Button {
                                addCurrentPhoto(to: category)
                            } label: {
                                Label(category.name, systemImage: "folder")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(.white.opacity(0.16), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .disabled(currentAssetId == nil)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            HStack(spacing: 14) {
                organizeActionButton(
                    title: "回收站",
                    systemImage: "trash",
                    tint: .red
                ) {
                    deleteCandidate = currentAssetId
                }
                .disabled(currentAssetId == nil)

                organizeActionButton(
                    title: "未分类",
                    systemImage: "tray.and.arrow.down",
                    tint: .white
                ) {
                    markCurrentPhotoUncategorized()
                }
                .disabled(currentAssetId == nil)

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
                    VStack(spacing: 7) {
                        Image(systemName: "folder.badge.plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 46, height: 46)
                            .background(Color.accentColor, in: Circle())
                        Text("加入分类")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(categories.isEmpty || currentAssetId == nil)

                organizeActionButton(
                    title: "下一张",
                    systemImage: "chevron.right",
                    tint: .white
                ) {
                    skipPhoto()
                }
                .disabled(assetIds.count < 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.72), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func quickCountButton(_ count: Int) -> some View {
        Button {
            requestedCount = count
        } label: {
            Text("\(count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    Capsule()
                        .fill(requestedCount == count ? Color.accentColor.opacity(0.16) : Color(.tertiarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(requestedCount == count ? Color.accentColor : .primary)
    }

    private func organizeActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.16), in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
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

    private func goBack() {
        guard !assetIds.isEmpty else { return }
        currentIndex = currentIndex > 0 ? currentIndex - 1 : assetIds.count - 1
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
    @EnvironmentObject private var coreDataManager: CoreDataManager

    let assetLocalIdentifier: String

    @State private var image: UIImage?
    @State private var creationDate: Date?
    @State private var locationName: String?
    @State private var categoryNames: [String] = []

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

            if creationDate != nil || locationName != nil || !categoryNames.isEmpty {
                metadataOverlay
            }
        }
        .task(id: assetLocalIdentifier) {
            image = nil
            creationDate = nil
            locationName = nil
            categoryNames = []

            async let loadedImage = photoLibraryManager.previewImage(for: assetLocalIdentifier, maxPixelSize: 1800)
            async let metadata = loadMetadata()

            image = await loadedImage
            let (date, location, categories) = await metadata
            creationDate = date
            locationName = location
            categoryNames = categories
        }
    }

    private var metadataOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let creationDate {
                Text(creationDate, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption.monospacedDigit())
            }
            if let locationName {
                Label(locationName, systemImage: "location.fill")
                    .font(.caption)
            }
            if !categoryNames.isEmpty {
                HStack(spacing: 4) {
                    ForEach(categoryNames, id: \.self) { name in
                        Text(name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(16)
    }

    private func loadMetadata() async -> (Date?, String?, [String]) {
        guard let asset = photoLibraryManager.asset(localIdentifier: assetLocalIdentifier) else {
            return (nil, nil, [])
        }

        let date = asset.creationDate
        var locationName: String?

        if let location = asset.location {
            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
               let placemark = placemarks.first {
                locationName = placemark.locality ?? placemark.administrativeArea
            }
        }

        let categories = (try? coreDataManager.fetchCategoryNames(for: assetLocalIdentifier)) ?? []
        return (date, locationName, categories)
    }
}
