import PhotosUI
import SwiftUI

struct CreateCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var categoryManager: SmartCategoryManager

    @State private var name = ""
    @State private var classificationMode: CreateCategoryMode = .naturalLanguage
    @State private var referenceMatchingMode: ReferenceMatchingMode = .fast
    @State private var promptText = ""
    @State private var threshold = Double(SmartCategoryManager.naturalLanguageDefaultThreshold)
    @State private var isPortrait = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var sampleImages: [UIImage] = []
    @State private var sampleAssetIds: [String] = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var isShowingPreciseModeTip = false

    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isCreating else {
            return false
        }
        switch classificationMode {
        case .naturalLanguage:
            return !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .referenceImages:
            return (1...10).contains(sampleImages.count)
        }
    }

    private var sampleCountText: String {
        "已选择 \(sampleImages.count) 张"
    }

    private var sampleCountColor: Color {
        sampleImages.count >= 1 ? .secondary : .red
    }

    private var thresholdRange: ClosedRange<Double> {
        switch classificationMode {
        case .naturalLanguage:
            return 0.05...0.40
        case .referenceImages:
            return isPortrait || referenceMatchingMode == .fast ? 0.10...0.99 : 0.30...0.95
        }
    }

    private var defaultThreshold: Double {
        switch classificationMode {
        case .naturalLanguage:
            return Double(SmartCategoryManager.naturalLanguageDefaultThreshold)
        case .referenceImages:
            return Double(isPortrait
                ? SmartCategoryManager.portraitDefaultThreshold
                : (referenceMatchingMode == .quality
                    ? SmartCategoryManager.referenceQualityDefaultThreshold
                    : SmartCategoryManager.referenceFastDefaultThreshold))
        }
    }

    var body: some View {
        Form {
            Section("分类 🏷") {
                TextField("分类名称", text: $name)
                    .textInputAutocapitalization(.words)

                Picker("分类方式", selection: $classificationMode) {
                    Text("文字描述").tag(CreateCategoryMode.naturalLanguage)
                    Text("参考图片").tag(CreateCategoryMode.referenceImages)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading) {
                    HStack {
                        Text("匹配严格度")
                        Spacer()
                        Text(String(format: "%.2f", threshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $threshold, in: thresholdRange, step: 0.01)
                    Text("越高越准但照片更少；越低照片更多但可能混入不相关内容。这里的数值是模型判断照片是否属于该分类的最低分数。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if classificationMode == .referenceImages {
                    Toggle(isOn: $isPortrait) {
                        Label("按人脸找照片", systemImage: "person.crop.square")
                    }

                    if !isPortrait {
                        Picker("图片分类模式", selection: $referenceMatchingMode) {
                            Text("快速").tag(ReferenceMatchingMode.fast)
                            Text("精确").tag(ReferenceMatchingMode.quality)
                        }
                        .pickerStyle(.segmented)

                        Text(referenceMatchingMode == .quality
                            ? "精确模式会更认真地比较参考照片，首次创建和扫描可能更慢。"
                            : "快速模式创建和扫描更轻快，适合大多数日常分类。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if classificationMode == .naturalLanguage {
                Section("想找什么照片") {
                    TextEditor(text: $promptText)
                        .frame(minHeight: 96)
                        .overlay(alignment: .topLeading) {
                            if promptText.isEmpty {
                                Text("例如：猫，猫咪，可爱的猫，家里的猫")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            } else {
                Section("参考照片 🧩") {
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
                            isCreating ? "正在创建分类…" : "创建分类 ✨",
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
        .onChange(of: classificationMode) { _ in
            isPortrait = false
            threshold = defaultThreshold
        }
        .onChange(of: isPortrait) { _ in
            threshold = defaultThreshold
        }
        .onChange(of: referenceMatchingMode) { _ in
            threshold = defaultThreshold
            if referenceMatchingMode == .quality {
                isShowingPreciseModeTip = true
            }
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
        .alert("精确模式提醒", isPresented: $isShowingPreciseModeTip) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("精确模式会调用更大的本地 AI 模型，处理时手机可能会短暂发热、耗电也会多一点。建议只在需要更细致分类时使用。")
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
            switch classificationMode {
            case .naturalLanguage:
                _ = try await categoryManager.createNaturalLanguageCategory(
                    name: name,
                    promptText: promptText,
                    threshold: Float(threshold)
                )
            case .referenceImages:
                _ = try await categoryManager.createReferenceImageCategory(
                    name: name,
                    sampleImages: sampleImages,
                    sampleAssetIds: sampleAssetIds,
                    threshold: Float(threshold),
                    isPortrait: isPortrait,
                    referenceMatchingMode: referenceMatchingMode
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum CreateCategoryMode: Hashable {
    case naturalLanguage
    case referenceImages
}
