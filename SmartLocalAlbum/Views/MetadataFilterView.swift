import SwiftUI
import Photos

/// 元数据筛选:按时间范围、大小筛选照片和视频。
struct MetadataFilterView: View {
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    @State private var allAssets: [PHAsset] = []
    @State private var filteredAssets: [PHAsset] = []
    @State private var isLoading = true

    // 时间筛选
    @State private var isDateFilterEnabled = false
    @State private var startDate: Date = Date().addingTimeInterval(-365 * 24 * 3600)
    @State private var endDate: Date = Date()

    // 大小筛选 (MB)
    @State private var isSizeFilterEnabled = false
    @State private var minSizeMB: Double = 0
    @State private var maxSizeMB: Double = 100
    private let maxSizeLimit: Double = 500

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            filterPanel
            Divider()
            resultsContent
        }
        .navigationTitle("筛选照片")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAssets()
        }
    }

    // MARK: - Filter Panel

    private var filterPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                dateFilterSection
                Divider()
                sizeFilterSection
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 220)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Date Filter

    private var dateFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("按时间范围", isOn: $isDateFilterEnabled.animation())
                .font(.subheadline.weight(.medium))
                .onChange(of: isDateFilterEnabled) { _ in applyFilters() }

            if isDateFilterEnabled {
                DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(.caption)
                    .onChange(of: startDate) { _ in applyFilters() }
                DatePicker("结束", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(.caption)
                    .onChange(of: endDate) { _ in applyFilters() }
            }
        }
    }

    // MARK: - Size Filter

    private var sizeFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("按大小", isOn: $isSizeFilterEnabled.animation())
                .font(.subheadline.weight(.medium))
                .onChange(of: isSizeFilterEnabled) { _ in applyFilters() }

            if isSizeFilterEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最小: \(Int(minSizeMB)) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $minSizeMB, in: 0...maxSizeLimit, step: 1)
                        .onChange(of: minSizeMB) { _ in
                            if minSizeMB > maxSizeMB { maxSizeMB = minSizeMB }
                            applyFilters()
                        }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("最大: \(Int(maxSizeMB)) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $maxSizeMB, in: 0...maxSizeLimit, step: 1)
                        .onChange(of: maxSizeMB) { _ in
                            if maxSizeMB < minSizeMB { minSizeMB = maxSizeMB }
                            applyFilters()
                        }
                }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsContent: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在加载照片信息...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredAssets.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("没有符合条件的照片")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("试试调整筛选条件。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(filteredAssets, id: \.localIdentifier) { asset in
                        NavigationLink {
                            PhotoPreviewView(assetLocalIdentifier: asset.localIdentifier)
                        } label: {
                            FilteredAssetCell(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Data Loading

    private func loadAssets() async {
        isLoading = true
        let assets = await Task.detached(priority: .userInitiated) {
            PhotoLibraryManager.enumerateAllAssets()
        }.value
        allAssets = assets
        applyFilters()
        isLoading = false
    }

    // MARK: - Filtering

    private func applyFilters() {
        var result = allAssets

        if isDateFilterEnabled {
            let start = startDate
            let end = endDate.addingTimeInterval(86400)
            result = result.filter { asset in
                guard let date = asset.creationDate else { return false }
                return date >= start && date <= end
            }
        }

        if isSizeFilterEnabled {
            result = result.filter { asset in
                let sizeMB = assetSizeInMB(asset)
                return sizeMB >= minSizeMB && sizeMB <= maxSizeMB
            }
        }

        filteredAssets = result
    }

    /// 估算 asset 的文件大小 (MB)，通过 PHAssetResource 获取。
    private func assetSizeInMB(_ asset: PHAsset) -> Double {
        if let resource = PHAssetResource.assetResources(for: asset).first,
           let fileSize = resource.value(forKey: "fileSize") as? Int64 {
            return Double(fileSize) / 1_048_576.0
        }
        // 回退估算:基于像素数粗略估算
        let pixels = Double(asset.pixelWidth * asset.pixelHeight)
        return pixels / 1_000_000.0 * 2.0 // 假设每像素约 2 字节压缩后
    }
}

// MARK: - Asset Cell

private struct FilteredAssetCell: View {
    let asset: PHAsset
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.secondary.opacity(0.12)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                .clipped()

            HStack(spacing: 4) {
                if asset.mediaType == .video {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10))
                }
                if let date = asset.creationDate {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.caption2.monospacedDigit())
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(5)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: asset.localIdentifier) {
            image = await photoLibraryManager.thumbnail(
                for: asset.localIdentifier,
                targetSize: CGSize(width: 320, height: 320)
            )
        }
    }
}