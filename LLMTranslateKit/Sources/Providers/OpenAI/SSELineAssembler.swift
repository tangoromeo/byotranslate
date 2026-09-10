import Foundation

/// Собирает произвольные куски байтов сети в законченные строки по `\n`.
/// Специально не использует `URLSession.AsyncBytes.lines`, чтобы граница
/// разрыва JSON между сетевыми чанками была под нашим контролем и
/// тестируемой (раздел 14, п. 2 ТЗ: «поток с разорванным на границе чанка
/// JSON»), а не спрятана в поведении Foundation.
public struct SSELineAssembler {
    private var buffer = Data()

    public init() {}

    /// Возвращает все законченные строки, накопленные к этому моменту.
    /// Незавершённый хвост остаётся во внутреннем буфере.
    public mutating func feed(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        var lines: [String] = []
        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            var lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            if lineData.last == 0x0D { lineData.removeLast() } // \r\n
            lines.append(String(decoding: lineData, as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
        }
        return lines
    }

    /// Раздел 14, п. 2 ТЗ: «преждевременный обрыв соединения» — то, что
    /// осталось в буфере без завершающего `\n`, когда поток закрылся.
    public mutating func finish() -> String? {
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll() }
        return String(decoding: buffer, as: UTF8.self)
    }
}
