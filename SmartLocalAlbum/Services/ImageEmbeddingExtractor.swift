import CoreML
import UIKit

final class ImageEmbeddingExtractor: ImageEmbeddingExtracting {
    // Expected generated model class name after adding Apple's image encoder to Xcode.
    // If Xcode generates a different class name, change this value and/or the model file name here only.
    static let generatedModelClassName = "MobileCLIPImageEncoder"
    static let bundledModelResourceName = "mobileclip_s2_image"

    let embeddingDimension: Int

    private let model: MLModel
    private let inputName: String
    private let inputWidth: Int
    private let inputHeight: Int

    init(
        modelResourceName: String = ImageEmbeddingExtractor.bundledModelResourceName,
        embeddingDimension: Int = 512,
        fallbackInputWidth: Int = 256,
        fallbackInputHeight: Int = 256
    ) throws {
        guard let modelURL = Bundle.main.url(forResource: modelResourceName, withExtension: "mlmodelc") else {
            throw ImageEmbeddingError.modelNotFound(modelResourceName)
        }

        self.embeddingDimension = embeddingDimension
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        self.model = try MLModel(contentsOf: modelURL, configuration: configuration)

        let imageInput = model.modelDescription.inputDescriptionsByName.first(where: { _, description in
            description.type == .image
        })
        self.inputName = imageInput?.key ?? "image"
        self.inputWidth = imageInput?.value.imageConstraint?.pixelsWide ?? fallbackInputWidth
        self.inputHeight = imageInput?.value.imageConstraint?.pixelsHigh ?? fallbackInputHeight
    }

    func embedding(for image: UIImage) async throws -> [Float] {
        try await Task.detached(priority: .userInitiated) {
            let pixelBuffer = try image.pixelBuffer(width: self.inputWidth, height: self.inputHeight)
            let input = try MLDictionaryFeatureProvider(dictionary: [
                self.inputName: MLFeatureValue(pixelBuffer: pixelBuffer)
            ])
            let output = try self.model.prediction(from: input)

            guard let multiArray = output.featureNames.compactMap({
                output.featureValue(for: $0)?.multiArrayValue
            }).first else {
                throw ImageEmbeddingError.missingOutput
            }

            var values = [Float]()
            values.reserveCapacity(multiArray.count)
            for index in 0..<multiArray.count {
                values.append(Float(truncating: multiArray[index]))
            }

            guard !values.isEmpty else { throw ImageEmbeddingError.invalidOutput }
            return VectorUtils.normalize(values)
        }.value
    }
}

private extension UIImage {
    func pixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

        var optionalPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attributes,
            &optionalPixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer = optionalPixelBuffer else {
            throw ImageEmbeddingError.invalidImage
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )
        else {
            throw ImageEmbeddingError.invalidImage
        }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let imageSize = size
        let scale = max(CGFloat(width) / imageSize.width, CGFloat(height) / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (CGFloat(width) - scaledSize.width) / 2,
            y: (CGFloat(height) - scaledSize.height) / 2
        )

        UIGraphicsPushContext(context)
        draw(in: CGRect(origin: origin, size: scaledSize))
        UIGraphicsPopContext()

        return pixelBuffer
    }
}
