import SwiftUI
import UIKit

/// 分类详情页"导出"按钮弹出的 sheet,提供三种导出路径。
struct ExportSheetView: View {
    @EnvironmentObject private var exportManager: ExportManager
    @Environment(\.dismiss) private var dismiss
    let category: SmartCategoryModel
    let resultAssetIds: [String]

    @State private var albumName: String
    @State private var showShareSheet: Bool = false
    @State private var shareURL: URL?

    init(category: SmartCategoryModel, resultAssetIds: [String]) {
        self.category = category
        self.resultAssetIds = resultAssetIds
        _albumName = State(initialValue: "Smart Album - \(category.name)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("照片数量", value: "\(resultAssetIds.count) 张")
                    LabeledContent("分类", value: category.name)
                } header: {
                    Text("导出概览")
                } footer: {
                    Text("所有操作都在本地完成,无需上传。")
                }

                Section {
                    Button {
                        Task { await exportToSystemAlbum() }
                    } label: {
                        Label("保存为新相册", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(resultAssetIds.isEmpty || exportManager.isExporting)
                } header: {
                    Text("保存到系统相册")
                } footer: {
                    Text("在系统\"照片\"App 中创建一个新相册,把这些照片加进去。")
                }

                Section {
                    Button {
                        exportToFiles()
                    } label: {
                        Label("生成清单 (JSON)", systemImage: "doc.text")
                    }
                    .disabled(resultAssetIds.isEmpty)

                    Button {
                        Task { await prepareShare() }
                    } label: {
                        Label("通过分享面板", systemImage: "square.and.arrow.up")
                    }
                    .disabled(resultAssetIds.isEmpty)
                } header: {
                    Text("分享清单")
                } footer: {
                    Text("生成包含照片标识符与相似度的 JSON 清单,可分享或导出。")
                }

                if exportManager.isExporting {
                    Section {
                        HStack {
                            ProgressView()
                            Text(exportManager.progress.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = exportManager.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("导出 / 共享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    TextField("相册名", text: $albumName)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 200)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheetView(items: [url])
                }
            }
        }
    }

    private func exportToSystemAlbum() async {
        let name = albumName.isEmpty ? category.name : albumName
        do {
            let created = try await exportManager.exportToSystemAlbum(
                categoryName: name,
                assetLocalIdentifiers: resultAssetIds
            )
            albumName = created
        } catch {
            // exportManager 已经写入 lastError
        }
    }

    private func exportToFiles() {
        do {
            let url = try exportManager.exportManifest(
                category: category,
                hits: resultAssetIds.map { SearchHit(assetLocalIdentifier: $0, similarity: 1.0) }
            )
            shareURL = url
            showShareSheet = true
        } catch {
            // exportManager 已经写入 lastError
        }
    }

    private func prepareShare() async {
        exportToFiles()
    }
}
