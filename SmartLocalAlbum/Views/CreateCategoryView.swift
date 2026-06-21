import PhotosUI
import SwiftUI

struct CreateCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var categoryManager: SmartCategoryManager
    @EnvironmentObject private var scanManager: ScanManager

    @State private var name = ""
    @State private var threshold = Double(SmartCategoryManager.referenceFastDefaultThreshold)
    @State private var isPortrait = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var sampleImages: [UIImage] = []
    @State private var sampleAssetIds: [String] = []
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isCreating else {
            return false
        }
        return (1...10).contains(sampleImages.count)
    }

    private var sampleCountText: String {
        "已选择 \(sampleImages.count) 张"
    }

    private var sampleCountColor: Color {
        sampleImages.count >= 1 ? .secondary : .red
    }

    private var thresholdRange: ClosedRange<Double> {
        0.10...0.99
    }

    private var defaultThreshold: Double {
        Double(isPortrait
            ? SmartCategoryManager.portraitDefaultThreshold
            : SmartCategoryManager.referenceFastDefaultThreshold)
    }

    var body: some View {
        Form {
            Section("分类") {
                TextField("分类名称", text: $name)
                    .textInputAutocapitalization(.words)

                VStack(alignment: .leading) {
                    HStack {
                        Text("匹配严格度")
                        Spacer()
                        Text(String(format: "%.2f", threshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $threshold, in: thresholdRange, step: 0.01)
                    Text("数值越高，结果越谨慎；数值越低，照片更多，也可能混入不相关内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $isPortrait) {
                    Label("按人脸找照片", systemImage: "person.crop.square")
                }

                if !isPortrait {
                    Text("参考照片会在本机生成特征，用来寻找主题、风格或场景相近的照片。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("参考照片") {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 10,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("选择 1 到 10 张参考照片", systemImage: "photo.on.rectangle.angled")
                }

                Text(sampleCountText)
                    .foregroundColor(sampleCountColor)

                if !sampleImages.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Array(sampleImages.enumerated()), id: \.offset) { index, image in
                            GeometryReader { proxy in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: proxy.size.width, height: proxy.size.width)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .clipped()

                                    Button {
                                        removeSample(at: index)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 22, height: 22)
                                            .background(.black.opacity(0.62), in: Circle())
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(.white.opacity(0.24), lineWidth: 1)
                                            )
                                            .padding(5)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("移除参考照片")
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button {
                    Task { await createCategory() }
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView()
                        }
                        Label(
                            isCreating ? "正在创建分类..." : "创建分类",
                            systemImage: isCreating ? "hourglass" : "checkmark.circle"
                        )
                    }
                }
                .disabled(!canCreate)
            }
        }
        .navigationTitle("新建分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .onChange(of: isPortrait) { _ in
            threshold = defaultThreshold
        }
        .onChange(of: selectedItems) { newItems in
            Task { await loadSelectedPhotos(newItems) }
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

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        var assetIds: [String] = []

        for item in items.prefix(10) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
                if let itemIdentifier = item.itemIdentifier {
                    assetIds.append(itemIdentifier)
                }
            }
        }

        sampleImages = images
        sampleAssetIds = assetIds
    }

    private func removeSample(at index: Int) {
        guard sampleImages.indices.contains(index) else { return }
        sampleImages.remove(at: index)
        if selectedItems.indices.contains(index) {
            selectedItems.remove(at: index)
        }
        if sampleAssetIds.indices.contains(index) {
            sampleAssetIds.remove(at: index)
        }
    }

    private func createCategory() async {
        isCreating = true
        defer { isCreating = false }

        do {
            _ = try await categoryManager.createReferenceImageCategory(
                name: name,
                sampleImages: sampleImages,
                sampleAssetIds: sampleAssetIds,
                threshold: Float(threshold),
                isPortrait: isPortrait
            )
            scanManager.reclassifySavedEmbeddings()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
