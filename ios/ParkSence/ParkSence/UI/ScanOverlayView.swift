import SwiftUI

enum ScanState { case searching, locked, analysing }

/// Animated scanning reticle — port of Android ScanOverlayView.kt.
struct ScanOverlayView: View {
    let state: ScanState

    @State private var pulse:     CGFloat = 0   // 0→1 breathing
    @State private var lockAlpha: CGFloat = 0   // 0→1 green fill fade
    @State private var spinAngle: Double  = 0   // 0→360 spinning arc

    private let green = Color(hex: "ff4b4b")

    var body: some View {
        GeometryReader { geo in
            let w  = geo.size.width
            let h  = geo.size.height
            let cx = w / 2

            // Reticle rect — portrait strip, upper third (matches Android)
            let rw   = w * 0.38
            let rh   = h * 0.45
            let cy   = h * 0.35
            let rect = CGRect(x: cx - rw / 2, y: cy - rh / 2, width: rw, height: rh)
            let len  = min(rw, rh) * 0.16
            let off  = pulse * 4

            // P-box dimensions
            let pBoxW = rw * 0.55
            let pBoxH = rh * 0.18
            let pBoxX = cx - pBoxW / 2
            let pBoxY = rect.minY + rh * 0.02
            let pBox  = CGRect(x: pBoxX, y: pBoxY, width: pBoxW, height: pBoxH)

            // Corner colour: white → green
            let t = Double(lockAlpha)
            let cornerColor = Color(
                red:   1 + (255/255.0 - 1) * t,
                green: 1 + (75/255.0  - 1) * t,
                blue:  1 + (75/255.0  - 1) * t
            )

            ZStack {
                // Dim edges
                DimOverlay(rect: rect)

                Canvas { ctx, _ in
                    // Green fill
                    if lockAlpha > 0 {
                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: 12),
                            with: .color(green.opacity(lockAlpha * 0.12))
                        )
                    }

                    // 4 corner brackets with pulse offset
                    let expanded = rect.insetBy(dx: -off, dy: -off)
                    drawCorners(ctx, rect: expanded, len: len, color: cornerColor)

                    // P box (searching / locked)
                    if state != .analysing {
                        let pColor: Color = state == .locked ? green : .white
                        let pFill: Color  = state == .locked ? green.opacity(0.13) : Color.white.opacity(0.08)

                        ctx.fill(Path(roundedRect: pBox, cornerRadius: 8), with: .color(pFill))
                        ctx.stroke(
                            Path(roundedRect: pBox, cornerRadius: 8),
                            with: .color(pColor),
                            lineWidth: 2.5
                        )

                        // Dashed divider (searching only)
                        if state == .searching {
                            let divY = rect.minY + rh * 0.30
                            var dash = Path()
                            dash.move(to: CGPoint(x: rect.minX + 12, y: divY))
                            dash.addLine(to: CGPoint(x: rect.maxX - 12, y: divY))
                            ctx.stroke(dash, with: .color(.white.opacity(0.27)),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                        }
                    }

                    // Spinning arc (analysing)
                    if state == .analysing {
                        let arcRect = expanded.insetBy(dx: -14, dy: -14)
                        let arc1 = arcPath(rect: arcRect, start: spinAngle, sweep: 80)
                        let arc2 = arcPath(rect: arcRect, start: spinAngle + 180, sweep: 80)
                        ctx.stroke(arc1, with: .color(green),
                                   style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        ctx.stroke(arc2, with: .color(green),
                                   style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    }
                }

                // P label
                if state != .analysing {
                    Text("P")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(state == .locked ? green : .white)
                        .position(x: pBox.midX, y: pBox.midY)
                }

                // Status label
                VStack(spacing: 6) {
                    switch state {
                    case .searching:
                        Text("Align P sign at the top")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    case .locked:
                        Text("Sign detected")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(green)
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                        Text("Hold steady...")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    case .analysing:
                        Text("Analysing...")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(green)
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    }
                }
                .position(x: cx, y: rect.maxY + 52)
            }
        }
        .onChange(of: state) { _, new in applyState(new) }
        .onAppear { applyState(state) }
    }

    // MARK: State transitions

    private func applyState(_ new: ScanState) {
        switch new {
        case .searching:
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulse = 1 }
            withAnimation(.easeOut(duration: 0.3)) { lockAlpha = 0 }
            spinAngle = 0
        case .locked:
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulse = 1 }
            withAnimation(.easeOut(duration: 0.35)) { lockAlpha = 1 }
        case .analysing:
            pulse = 0
            withAnimation(.easeOut(duration: 0.2)) { lockAlpha = 1 }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { spinAngle = 360 }
        }
    }

    // MARK: Canvas helpers

    private func drawCorners(_ ctx: GraphicsContext, rect: CGRect, len: CGFloat, color: Color) {
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY),  1,  1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1,  1),
            (CGPoint(x: rect.minX, y: rect.maxY),  1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (pt, dx, dy) in corners {
            var path = Path()
            path.move(to: pt)
            path.addLine(to: CGPoint(x: pt.x + dx * len, y: pt.y))
            path.move(to: pt)
            path.addLine(to: CGPoint(x: pt.x, y: pt.y + dy * len))
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }

    private func arcPath(rect: CGRect, start: Double, sweep: Double) -> Path {
        Path { p in
            p.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: rect.width / 2,
                startAngle: .degrees(start),
                endAngle:   .degrees(start + sweep),
                clockwise:  false
            )
        }
    }
}

// MARK: - Dim overlay

private struct DimOverlay: View {
    let rect: CGRect
    private let dim = Color.black.opacity(0.33)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            Path { p in
                p.addRect(CGRect(x: 0, y: 0, width: w, height: rect.minY - 20))
                p.addRect(CGRect(x: 0, y: rect.maxY + 20, width: w, height: h - rect.maxY - 20))
                p.addRect(CGRect(x: 0, y: rect.minY - 20, width: rect.minX - 20, height: rect.height + 40))
                p.addRect(CGRect(x: rect.maxX + 20, y: rect.minY - 20, width: w - rect.maxX - 20, height: rect.height + 40))
            }
            .fill(dim)
        }
    }
}
