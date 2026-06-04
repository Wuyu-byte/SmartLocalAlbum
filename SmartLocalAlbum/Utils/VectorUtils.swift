import Foundation

enum VectorUtils {
    static func normalize(_ vector: [Float]) -> [Float] {
        let squaredSum = vector.reduce(Float(0)) { $0 + $1 * $1 }
        let magnitude = sqrt(squaredSum)
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let dot = zip(lhs, rhs).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let lhsMagnitude = sqrt(lhs.reduce(Float(0)) { $0 + $1 * $1 })
        let rhsMagnitude = sqrt(rhs.reduce(Float(0)) { $0 + $1 * $1 })
        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return 0 }
        return dot / (lhsMagnitude * rhsMagnitude)
    }

    static func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first, !first.isEmpty else { return [] }
        var sum = Array(repeating: Float(0), count: first.count)

        for embedding in embeddings where embedding.count == first.count {
            for index in embedding.indices {
                sum[index] += embedding[index]
            }
        }

        let count = Float(embeddings.count)
        let average = sum.map { $0 / count }
        return normalize(average)
    }

    static func floatArrayToData(_ values: [Float]) -> Data {
        var copy = values
        return Data(bytes: &copy, count: copy.count * MemoryLayout<Float>.size)
    }

    static func dataToFloatArray(_ data: Data) -> [Float] {
        guard data.count >= MemoryLayout<Float>.size else { return [] }
        return data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }
    }
}

