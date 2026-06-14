import Accelerate
import CoreGraphics
import Foundation
import UIKit

/// dHash(difference hash):9×8 灰度图 → 64 位汉明距离可比的指纹。
/// 设计目标:**O(1) 每张图 ~5ms**,纯 CPU,无需任何 ML 模型。
enum PerceptualHashExtractor {
    /// 输入必须 > 0,长宽比任意;返回 64-bit 整数,big-endian 字节序。
    static func dHash(image: UIImage) -> Int64? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 9
        let height = 8
        let bytesPerPixel = 1
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        // 8 行,每行 8 个相邻像素比较 → 共 64 bit
        for row in 0..<height {
            let base = row * width
            for col in 0..<(width - 1) {
                let left = pixels[base + col]
                let right = pixels[base + col + 1]
                if left > right {
                    let bitIndex = UInt64(row * 8 + col)
                    hash |= (1 as UInt64) << bitIndex
                }
            }
        }
        return Int64(bitPattern: hash)
    }

    /// 两个 dHash 的汉明距离(不同位的数量)。
    /// 用于"智能去重":distance ≤ 5 视为同一组,> 20 视为无关。
    @inline(__always)
    static func hammingDistance(_ a: Int64, _ b: Int64) -> Int {
        let x = UInt64(bitPattern: a) ^ UInt64(bitPattern: b)
        return x.nonzeroBitCount
    }
}
