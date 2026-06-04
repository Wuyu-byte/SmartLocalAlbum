import UIKit
import Vision

final class FaceEmbeddingExtractor: ImageEmbeddingExtracting {
    let embeddingDimension: Int

    private let baseExtractor: any ImageEmbeddingExtracting

    init(baseExtractor: any ImageEmbeddingExtracting) {
        self.baseExtractor = baseExtractor
        self.embeddingDimension = baseExtractor.embeddingDimension
    }

    func embedding(for image: UIImage) async throws -> [Float] {
        let faceImage = try await Self.cropLargestFace(from: image)
        return try await baseExtractor.embedding(for: faceImage)
    }

    private static func cropLargestFace(from image: UIImage) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { throw ImageEmbeddingError.invalidImage }

            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.cgImagePropertyOrientation,
                options: [:]
            )
            try handler.perform([request])

            guard let face = request.results?.max(by: {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            }) else {
                throw ImageEmbeddingError.noFaceDetected
            }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let box = face.boundingBox
            var rect = CGRect(
                x: box.minX * width,
                y: (1 - box.maxY) * height,
                width: box.width * width,
                height: box.height * height
            )

            let padding = max(rect.width, rect.height) * 0.45
            rect = rect.insetBy(dx: -padding, dy: -padding)
            rect = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))

            guard let cropped = cgImage.cropping(to: rect) else {
                throw ImageEmbeddingError.invalidImage
            }

            return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
        }.value
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

