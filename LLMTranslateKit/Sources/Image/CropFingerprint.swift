import CoreGraphics
import CryptoKit
import Foundation

/// Отпечаток надписи на скриншоте для кэша переводов фрагментов: одна и та же
/// кнопка на повторном снимке находит свой перевод без запроса к модели.
///
/// Отпечаток — чёрно-белая маска букв (буква / фон с большим порогом), обрезанная
/// по краям надписи и приведённая к 24 клеткам по высоте. Такая маска не
/// чувствительна к шуму фона: индикатор «Команд» в Dynamic Island подсвечивает
/// шапку приложения на ±1–8 единиц яркости, и прежний отпечаток по уровням
/// яркости каждый раз менялся (замер: 20% пикселей шапки, максимум 2 единицы).
/// Маска той же шапки в двух прогонах отличалась на 1 клетку из 5424.
///
/// Совпадение: сначала точный ключ, затем «почти та же маска» — не больше 0,4%
/// клеток (минимум 2). Замена одной цифры даёт ≥ 2,7% («…1234»/«…1284», «8,90»/«8,99»),
/// так что «Счёт …1234» с «…1235» не путается.
public enum CropFingerprint {
    public struct Signature: Sendable, Equatable {
        /// Ширина маски в клетках (высота всегда `height`).
        public let width: Int
        /// Клетки построчно, упакованные по 8 в байт.
        public let mask: Data

        /// Точный ключ — хеш маски.
        public var key: String {
            var payload = Data([UInt8(width >> 8), UInt8(width & 0xFF)])
            payload.append(mask)
            return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        }
    }

    public static let height = 24
    static let workHeight = 96
    static let maxWidth = 512
    /// Насколько пиксель должен отличаться от фона, чтобы считаться буквой.
    static let inkThreshold = 48
    /// Допуск «та же надпись»: доля различающихся клеток и минимум в клетках.
    static let toleranceFraction = 0.004
    static let minimumTolerance = 2

    public static func signature(_ image: CGImage) -> Signature? {
        guard image.width > 0, image.height > 0 else { return nil }
        let scale = min(1, Double(workHeight) / Double(image.height))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let gray = grayscale(image, width: width, height: height) else { return nil }

        // Фон — медиана краевых пикселей; буква — всё, что от него заметно отличается.
        var border: [UInt8] = []
        border.reserveCapacity(2 * (width + height))
        for x in 0..<width { border.append(gray[x]); border.append(gray[(height - 1) * width + x]) }
        for y in 0..<height { border.append(gray[y * width]); border.append(gray[y * width + width - 1]) }
        let background = Int(border.sorted()[border.count / 2])

        var ink = [Bool](repeating: false, count: width * height)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where abs(Int(gray[y * width + x]) - background) > inkThreshold {
                ink[y * width + x] = true
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil } // пусто — нечего запоминать

        // Только надпись → `height` клеток по высоте; клетка «буква», если покрыта наполовину.
        let inkWidth = maxX - minX + 1, inkHeight = maxY - minY + 1
        let cellsWide = max(1, min(maxWidth, Int((Double(inkWidth) * Double(Self.height) / Double(inkHeight)).rounded())))
        var bits = [Bool]()
        bits.reserveCapacity(cellsWide * Self.height)
        for cellY in 0..<Self.height {
            let y0 = minY + cellY * inkHeight / Self.height
            let y1 = max(y0 + 1, minY + (cellY + 1) * inkHeight / Self.height)
            for cellX in 0..<cellsWide {
                let x0 = minX + cellX * inkWidth / cellsWide
                let x1 = max(x0 + 1, minX + (cellX + 1) * inkWidth / cellsWide)
                var total = 0, on = 0
                for y in y0..<y1 { for x in x0..<x1 { total += 1; if ink[y * width + x] { on += 1 } } }
                bits.append(on * 2 >= total)
            }
        }
        return Signature(width: cellsWide, mask: pack(bits))
    }

    /// Число различающихся клеток; `nil`, если ширины отличаются больше чем на 1
    /// (разное число букв — точно не та же надпись).
    public static func distance(_ a: Signature, _ b: Signature) -> Int? {
        guard abs(a.width - b.width) <= 1 else { return nil }
        let common = min(a.width, b.width)
        var difference = abs(a.width - b.width) * height // лишний столбец — как отличие
        for y in 0..<height {
            for x in 0..<common where bit(a, x: x, y: y) != bit(b, x: x, y: y) {
                difference += 1
            }
        }
        return difference
    }

    public static func isSameText(_ a: Signature, _ b: Signature) -> Bool {
        guard let difference = distance(a, b) else { return false }
        let cells = max(a.width, b.width) * height
        return difference <= max(minimumTolerance, Int(Double(cells) * toleranceFraction))
    }

    // MARK: - Внутреннее

    private static func pack(_ bits: [Bool]) -> Data {
        var bytes = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for (index, on) in bits.enumerated() where on { bytes[index / 8] |= 1 << UInt8(index % 8) }
        return Data(bytes)
    }

    private static func bit(_ signature: Signature, x: Int, y: Int) -> Bool {
        let index = y * signature.width + x
        let byteIndex = signature.mask.startIndex + index / 8
        guard byteIndex < signature.mask.endIndex else { return false }
        return signature.mask[byteIndex] & (1 << UInt8(index % 8)) != 0
    }

    private static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
