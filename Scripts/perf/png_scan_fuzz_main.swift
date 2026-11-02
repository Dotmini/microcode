// Differential test: incremental PNG end-marker scan (DeviceRuntimeService.consumeAndroidMirrorBytes) vs the previous full-buffer scan.
import Foundation
let pngEndMarker = Data([0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

func oldConsume(_ buffer: inout Data, _ data: Data) -> [Data] {
    var out: [Data] = []
    buffer.append(data)
    while let end = buffer.range(of: pngEndMarker) {
        let endIndex = end.upperBound
        let raw = buffer.prefix(upTo: endIndex)
        buffer.removeSubrange(..<endIndex)
        guard let start = raw.range(of: pngSignature) else { continue }
        out.append(Data(raw[start.lowerBound..<raw.endIndex]))
    }
    return out
}
func newConsume(_ buffer: inout Data, _ data: Data) -> [Data] {
    var out: [Data] = []
    let overlap = pngEndMarker.count - 1
    let searchStart = max(buffer.startIndex, buffer.endIndex - overlap)
    buffer.append(data)
    var from = searchStart
    while from < buffer.endIndex,
          let end = buffer.range(of: pngEndMarker, options: [], in: from..<buffer.endIndex) {
        let endIndex = end.upperBound
        let raw = buffer.prefix(upTo: endIndex)
        buffer.removeSubrange(..<endIndex)
        from = buffer.startIndex
        guard let start = raw.range(of: pngSignature) else { continue }
        out.append(Data(raw[start.lowerBound..<raw.endIndex]))
    }
    return out
}
var rng = SystemRandomNumberGenerator()
var failures = 0, frames = 0
for iter in 0..<4000 {
    // stream = junk + several frames (signature + body that may contain partial marker bytes) + trailing partial frame
    var stream = Data((0..<Int.random(in: 0...20, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })
    for _ in 0..<Int.random(in: 1...5, using: &rng) {
        stream.append(pngSignature)
        var body = Data((0..<Int.random(in: 0...400, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })
        if Bool.random(using: &rng) { body.append(pngEndMarker.prefix(Int.random(in: 1...7, using: &rng))) }   // near-miss marker bytes inside the body
        stream.append(body)
        stream.append(pngEndMarker)
    }
    if Bool.random(using: &rng) { stream.append(pngSignature); stream.append(pngEndMarker.prefix(Int.random(in: 1...7, using: &rng))) }
    var b1 = Data(), b2 = Data(), o1: [Data] = [], o2: [Data] = []
    var off = 0
    while off < stream.count {
        let n = min(Int.random(in: 1...(iter % 3 == 0 ? 3 : 64), using: &rng), stream.count - off)   // tiny chunks split the marker across callbacks
        let chunk = stream.subdata(in: off..<(off + n)); off += n
        o1 += oldConsume(&b1, chunk); o2 += newConsume(&b2, chunk)
    }
    frames += o1.count
    if o1 != o2 || b1 != b2 { failures += 1; if failures <= 3 { print("MISMATCH iter \(iter): old frames \(o1.count) new frames \(o2.count)") } }
}
print("png-scan-fuzz: streams=4000 frames=\(frames) failures=\(failures)")
exit(failures == 0 ? 0 : 1)
