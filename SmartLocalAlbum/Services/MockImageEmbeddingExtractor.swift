import UIKit

final class MockImageEmbeddingExtractor: ImageEmbeddingExtracting {
    let embeddingDimension: Int

    init(embeddingDimension: Int = 512) {
        self.embeddingDimension = embeddingDimension
    }

    func embedding(for image: UIImage) async throws -> [Float] {
        await Task.detached(priority: .userInitiated) {
            Self.visualEmbedding(for: image, dimension: self.embeddingDimension)
        }.value
    }

    private static func visualEmbedding(for image: UIImage, dimension: Int) -> [Float] {
        let sampleWidth = 16
        let sampleHeight = 16
        let pixelCount = sampleWidth * sampleHeight
        guard let cgImage = image.cgImage else {
            return VectorUtils.normalize(Array(repeating: 0, count: dimension))
        }

        var pixels = Array(repeating: UInt8(0), count: pixelCount * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return VectorUtils.normalize(Array(repeating: 0, count: dimension))
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        let colorHistogramCount = 48
        let luminanceOffset = colorHistogramCount
        let chromaOffset = luminanceOffset + pixelCount
        let summaryOffset = chromaOffset + pixelCount
        let requiredFeatureCount = summaryOffset + 4
        var features = Array(repeating: Float(0), count: max(dimension, requiredFeatureCount))
        var redSum: Float = 0
        var greenSum: Float = 0
        var blueSum: Float = 0
        var luminanceSum: Float = 0

        for index in 0..<pixelCount {
            let offset = index * 4
            let red = Float(pixels[offset]) / 255.0
            let green = Float(pixels[offset + 1]) / 255.0
            let blue = Float(pixels[offset + 2]) / 255.0
            let luminance = red * 0.299 + green * 0.587 + blue * 0.114

            redSum += red
            greenSum += green
            blueSum += blue
            luminanceSum += luminance

            features[Int(red * 15.0)] += 1
            features[16 + Int(green * 15.0)] += 1
            features[32 + Int(blue * 15.0)] += 1
            features[luminanceOffset + index] = luminance
            features[chromaOffset + index] = (red - green) * 0.5 + (blue - luminance) * 0.5
        }

        let count = Float(pixelCount)
        for index in 0..<colorHistogramCount {
            features[index] /= count
        }
        features[summaryOffset] = redSum / count
        features[summaryOffset + 1] = greenSum / count
        features[summaryOffset + 2] = blueSum / count
        features[summaryOffset + 3] = luminanceSum / count

        return VectorUtils.normalize(Array(features.prefix(dimension)))
    }
}
