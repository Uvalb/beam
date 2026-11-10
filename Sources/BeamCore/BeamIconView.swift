// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Search icon that "beams in" from the left edge as pixel art, then crossfades
/// to a high-fidelity vector icon drawn from the same geometry (so they align).
/// Tuned in mockups/beam-in.html.
final class BeamIconView: NSView {
    static let duration: CFTimeInterval = 0.63
    static let jitter: CGFloat = 50
    static let crossfade: CFTimeInterval = 0.56

    private static let n = 12              // bitmap is n×n
    private static let ps: CGFloat = 2     // points per pixel
    private static var side: CGFloat { CGFloat(n) * ps }
    // Geometry shared by both versions (in icon-local points).
    private static let cx = side * 0.42, cy = side * 0.42, r = side * 0.33
    private static let ringWidth: CGFloat = 2.2, handleWidth: CGFloat = 2.6
    private static let h0 = CGPoint(x: cx + r * 0.72, y: cy + r * 0.72)
    private static let h1 = CGPoint(x: side * 0.94, y: side * 0.94)

    private struct Pixel { let fx: CGFloat; let sx: CGFloat; let y: CGFloat; let delay: CGFloat }

    /// Icon's top-left in view coords.
    var iconOrigin = CGPoint(x: 20, y: 16)
    private var pixels: [Pixel] = []
    private var start: CFTimeInterval = 0
    private var burstStart: CFTimeInterval = -.infinity
    static let burstDuration: CFTimeInterval = 1.4
    private var timer: Timer?

    override var isFlipped: Bool { true }

    func play() {
        let cells = Self.rasterize()
        pixels = cells.map { (x, y) in
            let fx = iconOrigin.x + CGFloat(x) * Self.ps
            // Start just off the left edge with horizontal jitter; y is fixed.
            let sx = -Self.side + CGFloat(x) * Self.ps - CGFloat.random(in: 0...Self.jitter)
            let delay = (1 - CGFloat(x) / CGFloat(Self.n)) * 0.4 * CGFloat.random(in: 0...1)
            return Pixel(fx: fx, sx: sx, y: iconOrigin.y + CGFloat(y) * Self.ps, delay: delay)
        }
        start = CACurrentMediaTime()
        timer?.invalidate(); timer = nil
        startTimer()
        needsDisplay = true
    }

    /// Celebration: rings pulse out from the icon (milestone beams).
    func burst() {
        burstStart = CACurrentMediaTime()
        startTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if now - start > Self.duration + Self.crossfade, now - burstStart > Self.burstDuration {
            timer?.invalidate(); timer = nil
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let el = CACurrentMediaTime() - start
        let color = NSColor.secondaryLabelColor
        if el < Self.duration {
            drawPixels(progress: CGFloat(el / Self.duration), alpha: 1, color: color)
        } else {
            let a = CGFloat(min(1, (el - Self.duration) / max(Self.crossfade, 0.001)))
            drawPixels(progress: 1, alpha: 1 - a, color: color)
            drawHiFi(alpha: a, color: color)
        }
        drawBurst(CACurrentMediaTime() - burstStart)
    }

    /// Two staggered rings expanding from the lens and fading out.
    private func drawBurst(_ el: CFTimeInterval) {
        guard el >= 0, el < Self.burstDuration else { return }
        let c = CGPoint(x: iconOrigin.x + Self.cx, y: iconOrigin.y + Self.cy)
        for k in 0..<2 {
            let t = CGFloat((el - Double(k) * 0.35) / (Self.burstDuration - 0.35))
            guard t > 0, t < 1 else { continue }
            let e = 1 - pow(1 - t, 3)
            let r = Self.r + e * 14
            NSColor.systemYellow.withAlphaComponent(0.9 * (1 - t)).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ring.lineWidth = 2 * (1 - t) + 0.5
            ring.stroke()
        }
    }

    private func drawPixels(progress: CGFloat, alpha: CGFloat, color: NSColor) {
        guard alpha > 0 else { return }
        for p in pixels {
            let t = min(1, max(0, (progress - p.delay) / (1 - p.delay)))
            guard t > 0 else { continue }
            let e = 1 - pow(1 - t, 3)
            let x = p.sx + (p.fx - p.sx) * e
            color.withAlphaComponent(alpha * min(1, t * 3)).setFill()
            // Snap to the pixel grid so it reads as pixelated in motion.
            NSRect(x: (x / Self.ps).rounded() * Self.ps, y: p.y, width: Self.ps, height: Self.ps).fill()
        }
    }

    private func drawHiFi(alpha: CGFloat, color: NSColor) {
        guard alpha > 0 else { return }
        color.withAlphaComponent(alpha).setStroke()
        let o = iconOrigin
        let ring = NSBezierPath(ovalIn: NSRect(x: o.x + Self.cx - Self.r, y: o.y + Self.cy - Self.r,
                                               width: Self.r * 2, height: Self.r * 2))
        ring.lineWidth = Self.ringWidth
        ring.stroke()
        let handle = NSBezierPath()
        handle.move(to: CGPoint(x: o.x + Self.h0.x, y: o.y + Self.h0.y))
        handle.line(to: CGPoint(x: o.x + Self.h1.x, y: o.y + Self.h1.y))
        handle.lineWidth = Self.handleWidth
        handle.lineCapStyle = .round
        handle.stroke()
    }

    /// Bitmap cells covered by the hi-fi geometry.
    private static func rasterize() -> [(Int, Int)] {
        var cells: [(Int, Int)] = []
        let dx = h1.x - h0.x, dy = h1.y - h0.y
        for y in 0..<n {
            for x in 0..<n {
                let px = (CGFloat(x) + 0.5) * ps, py = (CGFloat(y) + 0.5) * ps
                let onRing = abs(hypot(px - cx, py - cy) - r) <= ringWidth / 2 + 0.05
                let t = max(0, min(1, ((px - h0.x) * dx + (py - h0.y) * dy) / (dx * dx + dy * dy)))
                let onHandle = hypot(px - h0.x - t * dx, py - h0.y - t * dy) <= handleWidth / 2 + 0.3
                if onRing || onHandle { cells.append((x, y)) }
            }
        }
        return cells
    }
}
