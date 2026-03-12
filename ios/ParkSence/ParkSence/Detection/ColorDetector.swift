import Foundation
import CoreVideo
import UIKit

/// Color-based parking sign detector — port of Android ColorDetector.kt.
/// Works directly on CVPixelBuffer (BGRA format from AVFoundation) for zero-copy speed.
enum ColorDetector {

    // MARK: HSV thresholds (H: 0–360, S/V: 0–1)

    private static let blueH:   ClosedRange<Float> = 190...270
    private static let blueS:   ClosedRange<Float> = 0.31...1
    private static let blueV:   ClosedRange<Float> = 0.16...1

    private static let redH1:   ClosedRange<Float> = 0...20
    private static let redH2:   ClosedRange<Float> = 330...360
    private static let redS:    ClosedRange<Float> = 0.39...1
    private static let redV:    ClosedRange<Float> = 0.31...1

    // MARK: Public API

    /// Lightweight live-frame trigger.
    /// Returns true if the top-centre of the frame contains a blue blob with white inside (P sign).
    static func hasSignInCenter(_ pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return false }
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        // Search top-centre strip — matches Android: cx 30-70%, cy 5-35%
        let cx1 = Int(Float(w) * 0.30)
        let cx2 = Int(Float(w) * 0.70)
        let cy1 = Int(Float(h) * 0.05)
        let cy2 = Int(Float(h) * 0.35)

        var minBx = cx2; var maxBx = cx1
        var minBy = cy2; var maxBy = cy1
        var blueCount = 0

        for y in cy1..<cy2 {
            let rowBase = y * bytesPerRow
            for x in cx1..<cx2 {
                let offset = rowBase + x * 4  // BGRA
                let b = Float(bytes[offset])
                let g = Float(bytes[offset + 1])
                let r = Float(bytes[offset + 2])
                let (h, s, v) = rgbToHsv(r, g, b)
                if isBlue(h, s, v) {
                    blueCount += 1
                    if x < minBx { minBx = x }
                    if x > maxBx { maxBx = x }
                    if y < minBy { minBy = y }
                    if y > maxBy { maxBy = y }
                }
            }
        }

        if blueCount < 30 { return false }
        let bw = maxBx - minBx + 1
        let bh = maxBy - minBy + 1
        if bw < 6 || bh < 6 { return false }
        if Float(bw) / Float(bh) > 3.5 { return false }
        let boxArea = bw * bh
        if Float(blueCount) / Float(boxArea) < 0.20 { return false }

        // Pass 2: check for white "P" letter inside blue region
        var whiteCount = 0
        for y in minBy...maxBy {
            let rowBase = y * bytesPerRow
            for x in minBx...maxBx {
                let offset = rowBase + x * 4
                let b = Float(bytes[offset])
                let g = Float(bytes[offset + 1])
                let r = Float(bytes[offset + 2])
                let (_, s, v) = rgbToHsv(r, g, b)
                if s < 0.25 && v > 0.65 { whiteCount += 1 }
            }
        }
        return Float(whiteCount) / Float(boxArea) >= 0.04
    }

    // MARK: Colour checks

    private static func isBlue(_ h: Float, _ s: Float, _ v: Float) -> Bool {
        blueH.contains(h) && blueS.contains(s) && blueV.contains(v)
    }
    private static func isRed(_ h: Float, _ s: Float, _ v: Float) -> Bool {
        (redH1.contains(h) || redH2.contains(h)) && redS.contains(s) && redV.contains(v)
    }

    // MARK: RGB → HSV  (inputs 0–255, outputs H: 0–360, S/V: 0–1)

    static func rgbToHsv(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let rf = r / 255; let gf = g / 255; let bf = b / 255
        let cmax = max(rf, gf, bf)
        let cmin = min(rf, gf, bf)
        let delta = cmax - cmin
        let v = cmax
        let s: Float = cmax == 0 ? 0 : delta / cmax
        var h: Float = 0
        if delta > 0 {
            if cmax == rf      { h = 60 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6)) }
            else if cmax == gf { h = 60 * ((bf - rf) / delta + 2) }
            else               { h = 60 * ((rf - gf) / delta + 4) }
        }
        if h < 0 { h += 360 }
        return (h, s, v)
    }
}
