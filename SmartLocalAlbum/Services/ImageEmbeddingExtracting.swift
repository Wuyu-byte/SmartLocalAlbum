import UIKit

protocol ImageEmbeddingExtracting {
    var embeddingDimension: Int { get }
    func embedding(for image: UIImage) async throws -> [Float]
}

enum ImageEmbeddingError: LocalizedError {
    case modelNotFound(String)
    case invalidImage
    case missingOutput
    case invalidOutput
    case noFaceDetected

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "未在 App 包内找到 Core ML 模型 \(name).mlmodelc。"
        case .invalidImage:
            return "无法将图片转换为 Core ML 模型输入。"
        case .missingOutput:
            return "Core ML 模型没有返回图片向量输出。"
        case .invalidOutput:
            return "Core ML 模型输出无法转换为 Float 向量。"
        case .noFaceDetected:
            return "没有检测到清晰的人脸。"
        }
    }
}
