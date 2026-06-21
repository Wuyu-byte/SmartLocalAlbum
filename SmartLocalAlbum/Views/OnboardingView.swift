import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(icon: String, title: String, detail: String)] = [
        (
            "rectangle.stack.badge.plus",
            "创建分类",
            "选择几张参考照片，告诉 App 你想留下哪类照片。"
        ),
        (
            "photo.stack",
            "扫描相册",
            "App 会在本机提取照片特征，与你创建的分类进行匹配。所有处理都在设备上完成，不会上传。"
        ),
        (
            "square.grid.3x3",
            "查看结果",
            "扫描完成后，点进分类就能看到匹配的照片。可以调整严格度来控制结果数量。"
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.accentColor)
                        )

                    Text("欢迎使用 SmartAlbum")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("一个在本机整理照片的智能工具。以下是一些快速上手提示。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 0) {
                                Image(systemName: step.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 44, height: 44)
                                    .background(Color.accentColor.opacity(0.12), in: Circle())

                                if index < steps.count - 1 {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.24))
                                        .frame(width: 2, height: 28)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title)
                                    .font(.headline)
                                Text(step.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("我知道了")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor)
                )
            }
            .padding(24)
        }
        .interactiveDismissDisabled()
    }
}
