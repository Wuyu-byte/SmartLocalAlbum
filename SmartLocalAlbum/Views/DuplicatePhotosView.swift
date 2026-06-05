import SwiftUI

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let assetIds: [String]
    let similarity: Float
}

struct DuplicatePhotosView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var photoLibraryManager: PhotoLibraryManager

    @State private var groups: [DuplicateGroup] = []
    @State private var isLoading = false
    @State private var threshold: Double = 0.95
    @State private var selectedIds = Set<String>()
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在分析照片特征...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                EmptyStateView(
                    title: "未检测到重复照片",
                    systemImage: "photo.on.rectangle.angled",
                    message: "点击查找按钮开始检测。扫描过的照片越多，检测结果越完整。"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            sectionHeader(for: group)
                            photoGrid(for: group)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("重复照片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await findDuplicates() }
                } label: {
                    Label("查找", systemImage: "magnifyingglass")
                }
                .disabled(isLoading)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedIds.isEmpty {
                bottomBar
            }
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

    private func sectionHeader(for group: DuplicateGroup) -> some View {
        HStack {
            Text("相似度 \(String(format: "%.1f%%", group.similarity * 100))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(group.assetIds.count) 张")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
    }

    private func photoGrid(for group: DuplicateGroup) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(group.assetIds, id: \.self) { assetId in
                ZStack(alignment: .topTrailing) {
                    PhotoGridItemView(
                        assetLocalIdentifier: assetId,
                        similarity: nil
                    )
                    .opacity(selectedIds.contains(assetId) ? 0.5 : 1)
                    .onTapGesture {
                        toggleSelection(assetId)
                    }

                    if selectedIds.contains(assetId) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var bottomBar: some View {
        HStack {
            Text("已选 \(selectedIds.count) 张")
                .font(.subheadline.weight(.medium))

            Spacer()

            Button {
                Task { await deleteSelected() }
            } label: {
                Label("删除选中", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func toggleSelection(_ assetId: String) {
        if selectedIds.contains(assetId) {
            selectedIds.remove(assetId)
        } else {
            selectedIds.insert(assetId)
        }
    }

    private func findDuplicates() async {
        isLoading = true
        defer { isLoading = false }
        selectedIds.removeAll()

        do {
            let allEmbeddings = try coreDataManager.fetchAllPhotoEmbeddingModels(kind: .image)
            guard allEmbeddings.count >= 2 else {
                groups = []
                return
            }

            let thresholdFloat = Float(threshold)
            let result = await Task.detached(priority: .userInitiated) {
                Self.detectDuplicates(embeddings: allEmbeddings, threshold: thresholdFloat)
            }.value

            groups = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelected() async {
        let idsToDelete = Array(selectedIds)
        do {
            let deletedIds = try await photoLibraryManager.deletePhotos(localIdentifiers: idsToDelete)
            for assetId in deletedIds {
                try? coreDataManager.deletePhotoData(assetLocalIdentifier: assetId)
            }
            selectedIds.removeAll()
            groups = groups.compactMap { group in
                let remaining = group.assetIds.filter { !deletedIds.contains($0) }
                return remaining.count >= 2 ? DuplicateGroup(assetIds: remaining, similarity: group.similarity) : nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    nonisolated static func detectDuplicates(
        embeddings: [(assetLocalIdentifier: String, embedding: [Float])],
        threshold: Float
    ) -> [DuplicateGroup] {
        let n = embeddings.count
        var parent = Array(0..<n)
        var rank = [Int](repeating: 0, count: n)

        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root { root = parent[root] }
            var node = x
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return }
            if rank[ra] < rank[rb] { parent[ra] = rb }
            else if rank[ra] > rank[rb] { parent[rb] = ra }
            else { parent[rb] = ra; rank[ra] += 1 }
        }

        for i in 0..<n {
            let a = embeddings[i].embedding
            for j in (i + 1)..<n {
                let b = embeddings[j].embedding
                guard a.count == b.count else { continue }
                let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
                if dot >= threshold {
                    union(i, j)
                }
            }
        }

        var clusters = [Int: [Int]]()
        for i in 0..<n {
            clusters[find(i), default: []].append(i)
        }

        return clusters.values
            .filter { $0.count >= 2 }
            .map { indices in
                let assetIds = indices.map { embeddings[$0].assetLocalIdentifier }
                var minSim: Float = 1.0
                for i in 0..<indices.count {
                    for j in (i + 1)..<indices.count {
                        let dot = zip(embeddings[indices[i]].embedding, embeddings[indices[j]].embedding)
                            .reduce(Float(0)) { $0 + $1.0 * $1.1 }
                        minSim = min(minSim, dot)
                    }
                }
                return DuplicateGroup(assetIds: assetIds, similarity: minSim)
            }
            .sorted { $0.assetIds.count > $1.assetIds.count }
    }
}
