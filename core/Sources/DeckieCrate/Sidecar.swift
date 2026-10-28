import Foundation

/// The binary sidecars: `bars/<id>.bin` and `style/<id>.bin`. Each opens with a 16-byte header, four letters (`DKB1`
/// or `DKS1`) and three 32-bit little-endian integers (for bars: the bar count, the series count and 0; for style:
/// the value count, 0 and 0), followed by float16 values, little-endian. The bars file holds its series one after
/// the other, in the order `features_present` lists them.
enum Sidecar {
    static func bars(_ series: BarSeries, nBars: Int) -> Data {
        var out = header(CrateFormat.barsMagic, UInt32(nBars), UInt32(series.names.count), 0)
        for name in series.names { append(series.series[name]!, to: &out) }
        return Data(out)
    }

    static func style(_ values: [Double]) -> Data {
        var out = header(CrateFormat.styleMagic, UInt32(values.count), 0, 0)
        append(values, to: &out)
        return Data(out)
    }

    /// The series of a bars file, named by `names` in file order, or the problems that keep it from being read.
    static func readBars(_ data: Data, names: [String], nBars: Int, file: String, track: String,
                         gridPath: String) -> Result<BarSeries, CrateError> {
        let b = [UInt8](data)
        var problems: [CrateProblem] = []
        func fail(_ m: String) -> Result<BarSeries, CrateError> {
            .failure(CrateError(problems + [CrateProblem(file: file, path: "", track: track, message: m)]))
        }
        guard let (count, seriesCount, reserved) = readHeader(b, CrateFormat.barsMagic) else {
            return fail("not a bars sidecar (it must start with DKB1 and a 16-byte header)")
        }
        if reserved != 0 { problems.append(CrateProblem(file: file, path: "", track: track, message: "the header's fourth number is \(reserved), not 0")) }
        if count != nBars {
            return fail("holds \(count) bars but \(gridPath) is \(nBars)")
        }
        if seriesCount != names.count {
            return fail("holds \(seriesCount) series but features_present lists \(names.count) (\(names.joined(separator: ", ")))")
        }
        let want = CrateFormat.sidecarHeaderBytes + 2 * count * seriesCount
        if b.count != want { return fail("is \(b.count) bytes; \(seriesCount) series of \(count) bars make \(want)") }
        var series: [String: [Double]] = [:]
        for (k, name) in names.enumerated() {
            let values = halves(b, from: CrateFormat.sidecarHeaderBytes + 2 * count * k, count: count)
            if !values.allSatisfy(\.isFinite) {
                problems.append(CrateProblem(file: file, path: "", track: track, message: "series \(name) holds a value that is not a finite number"))
            }
            series[name] = values
        }
        return problems.isEmpty ? .success(BarSeries(series)) : .failure(CrateError(problems))
    }

    /// The values of a style file, or the problems that keep it from being read.
    static func readStyle(_ data: Data, dims: Int, file: String, track: String,
                          dimsPath: String) -> Result<[Double], CrateError> {
        let b = [UInt8](data)
        func fail(_ m: String) -> Result<[Double], CrateError> {
            .failure(CrateError([CrateProblem(file: file, path: "", track: track, message: m)]))
        }
        guard let (count, r1, r2) = readHeader(b, CrateFormat.styleMagic) else {
            return fail("not a style sidecar (it must start with DKS1 and a 16-byte header)")
        }
        if r1 != 0 || r2 != 0 { return fail("the header's third and fourth numbers are \(r1) and \(r2), not 0") }
        if count != dims { return fail("holds \(count) values but \(dimsPath) is \(dims)") }
        let want = CrateFormat.sidecarHeaderBytes + 2 * count
        if b.count != want { return fail("is \(b.count) bytes; \(count) values make \(want)") }
        let values = halves(b, from: CrateFormat.sidecarHeaderBytes, count: count)
        if !values.allSatisfy(\.isFinite) { return fail("holds a value that is not a finite number") }
        return .success(values)
    }

    private static func header(_ magic: [UInt8], _ a: UInt32, _ b: UInt32, _ c: UInt32) -> [UInt8] {
        var out = magic
        for v in [a, b, c] { out += [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24)] }
        return out
    }

    private static func readHeader(_ b: [UInt8], _ magic: [UInt8]) -> (Int, Int, Int)? {
        guard b.count >= CrateFormat.sidecarHeaderBytes, Array(b[0..<4]) == magic else { return nil }
        func u32(_ at: Int) -> Int { Int(b[at]) | Int(b[at + 1]) << 8 | Int(b[at + 2]) << 16 | Int(b[at + 3]) << 24 }
        return (u32(4), u32(8), u32(12))
    }

    private static func append(_ values: [Double], to out: inout [UInt8]) {
        out.reserveCapacity(out.count + 2 * values.count)
        for v in values {
            let h = Half.bits(v)
            out.append(UInt8(h & 0xff))
            out.append(UInt8(h >> 8))
        }
    }

    private static func halves(_ b: [UInt8], from start: Int, count: Int) -> [Double] {
        (0..<count).map { Half.value(UInt16(b[start + 2 * $0]) | UInt16(b[start + 2 * $0 + 1]) << 8) }
    }
}
