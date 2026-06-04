import CoreML
import Foundation

final class MobileCLIPTextEmbeddingExtractor: TextEmbeddingExtracting {
    static let bundledModelResourceName = "mobileclip_s2_text"

    let embeddingDimension: Int

    private let model: MLModel
    private let inputName: String
    private let inputType: MLFeatureType
    private let tokenizer: MobileCLIPTokenizer

    init(
        modelResourceName: String = MobileCLIPTextEmbeddingExtractor.bundledModelResourceName,
        embeddingDimension: Int = 512,
        tokenizer: MobileCLIPTokenizer = MobileCLIPTokenizer()
    ) throws {
        guard let modelURL = Bundle.main.url(forResource: modelResourceName, withExtension: "mlmodelc") else {
            throw ImageEmbeddingError.modelNotFound(modelResourceName)
        }

        self.embeddingDimension = embeddingDimension
        self.tokenizer = tokenizer

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        self.model = try MLModel(contentsOf: modelURL, configuration: configuration)

        let firstInput = model.modelDescription.inputDescriptionsByName.first
        self.inputName = firstInput?.key ?? "input_ids"
        self.inputType = firstInput?.value.type ?? .multiArray
    }

    func embedding(for text: String) async throws -> [Float] {
        try await Task.detached(priority: .userInitiated) {
            let provider: MLFeatureProvider
            if self.inputType == .string {
                provider = try MLDictionaryFeatureProvider(dictionary: [
                    self.inputName: MLFeatureValue(string: text)
                ])
            } else {
                let ids = self.tokenizer.tokenIds(for: text)
                let array = try MLMultiArray(
                    shape: [NSNumber(value: 1), NSNumber(value: ids.count)],
                    dataType: .int32
                )
                for (index, id) in ids.enumerated() {
                    array[index] = NSNumber(value: id)
                }
                provider = try MLDictionaryFeatureProvider(dictionary: [
                    self.inputName: MLFeatureValue(multiArray: array)
                ])
            }

            let output = try self.model.prediction(from: provider)
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

struct MobileCLIPTokenizer {
    private let maxTokenCount: Int
    private let startToken: Int
    private let endToken: Int
    private let paddingToken: Int
    private let vocabulary: [String: Int32]
    private let bpeRanks: [BytePair: Int]
    private let byteEncoder: [UInt8: String]

    init(
        maxTokenCount: Int = 77,
        vocabularyResourceName: String = "clip-vocab",
        mergesResourceName: String = "clip-merges"
    ) {
        self.maxTokenCount = maxTokenCount
        self.vocabulary = Self.loadVocabulary(resourceName: vocabularyResourceName)
        self.bpeRanks = Self.loadMerges(resourceName: mergesResourceName)
        self.byteEncoder = Self.makeByteEncoder()
        self.startToken = Int(vocabulary["<|startoftext|>"] ?? 49406)
        self.endToken = Int(vocabulary["<|endoftext|>"] ?? 49407)
        self.paddingToken = 0
    }

    func tokenIds(for text: String) -> [Int32] {
        var tokens = [startToken]
        for token in tokenize(text: text) {
            guard let id = vocabulary[token] else { continue }
            tokens.append(Int(id))
            if tokens.count >= maxTokenCount - 1 { break }
        }
        tokens.append(endToken)

        if tokens.count < maxTokenCount {
            tokens.append(contentsOf: Array(repeating: paddingToken, count: maxTokenCount - tokens.count))
        }

        return Array(tokens.prefix(maxTokenCount)).map { Int32($0) }
    }

    private func tokenize(text: String) -> [String] {
        byteEncode(text: text.lowercased()).flatMap { token in
            bpe(token: token).split(separator: " ").map(String.init)
        }
    }

    private func byteEncode(text: String) -> [String] {
        let pattern = "<\\|startoftext\\|>|<\\|endoftext\\|>|'s|'t|'re|'ve|'m|'ll|'d|[\\p{L}]+|[\\p{N}]|[^\\s\\p{L}\\p{N}]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let stringRange = Range(match.range, in: text) else { return nil }
            return String(text[stringRange].utf8.compactMap { byteEncoder[$0] }.joined())
        }
    }

    private func bpe(token: String) -> String {
        if token.count <= 1 {
            return token + "</w>"
        }

        var word = Array(token).map(String.init)
        word[word.count - 1] += "</w>"
        var pairs = getPairs(word: word)
        guard !pairs.isEmpty else {
            return token + "</w>"
        }

        while true {
            guard let bigram = pairs
                .filter({ bpeRanks[$0] != nil })
                .min(by: { bpeRanks[$0, default: Int.max] < bpeRanks[$1, default: Int.max] })
            else {
                break
            }

            var newWord: [String] = []
            var index = 0
            while index < word.count {
                if let next = word[index..<word.count].firstIndex(of: bigram.a) {
                    newWord.append(contentsOf: word[index..<next])
                    index = next
                } else {
                    newWord.append(contentsOf: word[index..<word.count])
                    break
                }

                if index < word.count - 1,
                   word[index] == bigram.a,
                   word[index + 1] == bigram.b {
                    newWord.append(bigram.a + bigram.b)
                    index += 2
                } else {
                    newWord.append(word[index])
                    index += 1
                }
            }

            word = newWord
            if word.count == 1 { break }
            pairs = getPairs(word: word)
        }
        return word.joined(separator: " ")
    }

    private func getPairs(word: [String]) -> Set<BytePair> {
        guard word.count > 1 else { return [] }
        var pairs = Set<BytePair>()
        for index in 0..<(word.count - 1) {
            pairs.insert(BytePair(word[index], word[index + 1]))
        }
        return pairs
    }

    private static func loadVocabulary(resourceName: String) -> [String: Int32] {
        guard
            let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }
        return raw.mapValues { Int32($0) }
    }

    private static func loadMerges(resourceName: String) -> [BytePair: Int] {
        guard
            let url = Bundle.main.url(forResource: resourceName, withExtension: "txt"),
            let text = try? String(contentsOf: url)
        else {
            return [:]
        }

        var ranks: [BytePair: Int] = [:]
        let lines = text.split(separator: "\n").map(String.init)
        for (index, line) in lines.dropFirst().enumerated() {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count == 2 else { continue }
            ranks[BytePair(parts[0], parts[1])] = index
        }
        return ranks
    }

    private static func makeByteEncoder() -> [UInt8: String] {
        var bytes = Array(33...126) + Array(161...172) + Array(174...255)
        var unicodeValues = bytes
        var next = 0
        for value in 0...255 where !bytes.contains(value) {
            bytes.append(value)
            unicodeValues.append(256 + next)
            next += 1
        }

        var mapping: [UInt8: String] = [:]
        for (byte, unicodeValue) in zip(bytes, unicodeValues) {
            guard let scalar = UnicodeScalar(unicodeValue) else { continue }
            mapping[UInt8(byte)] = String(scalar)
        }
        return mapping
    }
}

private struct BytePair: Hashable {
    let a: String
    let b: String

    init(_ a: String, _ b: String) {
        self.a = a
        self.b = b
    }
}
