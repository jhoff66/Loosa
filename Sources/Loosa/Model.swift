import AppKit

enum Tool: String, CaseIterable, Identifiable {
    case pen, highlighter, arrow, rect, oval, text, blur, eraserItem, eraserFree
    static let drawing: [Tool] = [.pen, .highlighter, .arrow, .rect, .oval, .text, .blur]
    static let erasers: [Tool] = [.eraserItem, .eraserFree]
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: return "scribble"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rect: return "square"
        case .oval: return "circle"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .eraserItem: return "eraser.line.dashed"
        case .eraserFree: return "eraser"
        }
    }

    var title: String {
        switch self {
        case .pen: return "Desenho livre"
        case .highlighter: return "Marca-texto"
        case .arrow: return "Seta"
        case .rect: return "Quadrado"
        case .oval: return "Círculo"
        case .text: return "Texto"
        case .blur: return "Desfoque de área"
        case .eraserItem: return "Apagar item"
        case .eraserFree: return "Borracha livre"
        }
    }
}

/// Estado compartilhado entre a barra de ferramentas e os canvas.
final class DrawState: ObservableObject {
    /// Paleta atual (editável nas configurações). As teclas 1…6 escolhem cada posição.
    static var palette: [NSColor] { Settings.shared.palette }

    /// Verde do marca-texto: fixo e semitransparente.
    static let highlighterColor = NSColor(srgbRed: 0.20, green: 0.90, blue: 0.30, alpha: 0.40)

    @Published var tool: Tool = .arrow {
        didSet { if Tool.erasers.contains(tool) { eraser = tool } }
    }
    /// Última borracha usada: é a que o botão da barra mostra.
    @Published var eraser: Tool = .eraserItem
    @Published var colorIndex = 0
    @Published var width: CGFloat = 4
    @Published var ghost = false      // traço fantasma: some depois de 2 s
    @Published var smooth = true      // suaviza o desenho livre
    @Published var filled = false     // quadrado e círculo preenchidos

    var color: NSColor { Self.palette[colorIndex] }

    /// Os modos só valem se a função não foi removida nas configurações.
    var ghostActive: Bool { ghost && Settings.shared.isOn("ghost") }
    var smoothActive: Bool { smooth && Settings.shared.isOn("smooth") }
    var fillActive: Bool { filled && Settings.shared.isOn("fill") }

    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var onClear: () -> Void = {}
    var onClose: () -> Void = {}
    var onSettings: () -> Void = {}
}

struct Shape {
    static let ghostFade: TimeInterval = 0.5

    let id = UUID()
    var kind: Tool
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var color: NSColor
    var width: CGFloat
    var text = ""
    var expiresAt: Date?
    var filled = false

    var isFreehand: Bool { kind == .pen || kind == .highlighter }
    var fontSize: CGFloat { 14 + width * 2.5 }
    var font: NSFont { .systemFont(ofSize: fontSize, weight: .semibold) }

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    // MARK: Fantasma

    var isExpired: Bool { expiresAt.map { $0.timeIntervalSinceNow <= 0 } ?? false }

    /// 1 = visível; cai para 0 nos últimos instantes de vida.
    var fade: CGFloat {
        guard let e = expiresAt else { return 1 }
        return CGFloat(max(0, min(1, e.timeIntervalSinceNow / Self.ghostFade)))
    }

    // MARK: Desenho

    func draw() {
        let f = fade
        if f >= 1 {
            drawBody()
        } else {
            var s = self
            s.color = color.withAlphaComponent(color.alphaComponent * f)
            s.drawBody()
        }
    }

    private func drawBody() {
        color.setStroke()
        color.setFill()
        switch kind {
        case .pen, .highlighter: drawFreehand()
        case .rect:
            let p = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            style(p)
            if filled { p.fill() }
            p.stroke()
        case .oval:
            let p = NSBezierPath(ovalIn: rect)
            style(p)
            if filled { p.fill() }
            p.stroke()
        case .arrow: drawArrow()
        case .text:
            (text as NSString).draw(at: start, withAttributes: [.font: font, .foregroundColor: color])
        case .blur:
            break // sem contorno: o desfoque é pintado pelo canvas
        case .eraserItem, .eraserFree: break
        }
    }

    private func style(_ p: NSBezierPath) {
        p.lineWidth = width
        p.lineCapStyle = kind == .highlighter ? .square : .round
        p.lineJoinStyle = .round
    }

    private func drawFreehand() {
        guard let first = points.first else { return }
        let p = NSBezierPath()
        style(p)
        p.move(to: first)
        if points.count == 1 {
            p.line(to: first)
        } else {
            func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
            var cur = mid(points[0], points[1])
            p.line(to: cur)
            if points.count > 2 {
                for i in 1..<(points.count - 1) {
                    let ctrl = points[i]
                    let to = mid(points[i], points[i + 1])
                    // quadrática -> cúbica
                    let c1 = CGPoint(x: cur.x + 2 / 3 * (ctrl.x - cur.x), y: cur.y + 2 / 3 * (ctrl.y - cur.y))
                    let c2 = CGPoint(x: to.x + 2 / 3 * (ctrl.x - to.x), y: to.y + 2 / 3 * (ctrl.y - to.y))
                    p.curve(to: to, controlPoint1: c1, controlPoint2: c2)
                    cur = to
                }
            }
            p.line(to: points[points.count - 1])
        }
        p.stroke()
    }

    private func drawArrow() {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }
        let angle = atan2(dy, dx)
        let head = min(max(14, width * 4.5), len)
        let spread = CGFloat.pi / 7

        let base = CGPoint(x: end.x - cos(angle) * head * 0.8, y: end.y - sin(angle) * head * 0.8)
        let line = NSBezierPath()
        style(line)
        line.move(to: start)
        line.line(to: base)
        line.stroke()

        let tri = NSBezierPath()
        tri.move(to: end)
        tri.line(to: CGPoint(x: end.x - cos(angle - spread) * head, y: end.y - sin(angle - spread) * head))
        tri.line(to: CGPoint(x: end.x - cos(angle + spread) * head, y: end.y - sin(angle + spread) * head))
        tri.close()
        tri.lineJoinStyle = .round
        tri.lineWidth = 1
        tri.fill()
        tri.stroke()
    }

    // MARK: Seleção

    var textRect: CGRect {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGRect(origin: start, size: size)
    }

    /// Distância do ponto até o item (0 = em cima).
    func distance(to p: CGPoint) -> CGFloat {
        switch kind {
        case .pen, .highlighter:
            guard points.count > 1 else {
                return points.first.map { hypot(p.x - $0.x, p.y - $0.y) } ?? .infinity
            }
            return zip(points, points.dropFirst()).map { segmentDistance(p, $0, $1) }.min() ?? .infinity
        case .arrow:
            return segmentDistance(p, start, end)
        case .rect:
            if filled && rect.contains(p) { return 0 }
            return outlineDistance(p, rect)
        case .blur:
            let r = rect
            return r.contains(p) ? 0 : outlineDistance(p, r)
        case .oval:
            let r = rect
            let a = r.width / 2, b = r.height / 2
            guard a > 0.5, b > 0.5 else { return segmentDistance(p, start, end) }
            let d = hypot((p.x - r.midX) / a, (p.y - r.midY) / b)
            if filled && d <= 1 { return 0 }
            return abs(d - 1) * min(a, b)
        case .text:
            let r = textRect
            let dx = max(r.minX - p.x, 0, p.x - r.maxX)
            let dy = max(r.minY - p.y, 0, p.y - r.maxY)
            return hypot(dx, dy)
        case .eraserItem, .eraserFree:
            return .infinity
        }
    }

    private func outlineDistance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let a = CGPoint(x: r.minX, y: r.minY), b = CGPoint(x: r.maxX, y: r.minY)
        let c = CGPoint(x: r.maxX, y: r.maxY), d = CGPoint(x: r.minX, y: r.maxY)
        return min(segmentDistance(p, a, b), segmentDistance(p, b, c),
                   segmentDistance(p, c, d), segmentDistance(p, d, a))
    }

    func hit(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        distance(to: p) <= tolerance + (kind == .text || kind == .blur ? 0 : width / 2)
    }

    /// Faixa translucente desenhada por baixo do item quando ele está em foco.
    func drawHalo() {
        let halo = NSColor.systemBlue.withAlphaComponent(0.35)
        if kind == .text || kind == .blur {
            halo.setFill()
            let r = kind == .text ? textRect.insetBy(dx: -4, dy: -3) : rect.insetBy(dx: -4, dy: -4)
            NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        } else {
            var h = self
            h.color = halo
            h.width = width + 10
            h.expiresAt = nil
            h.draw()
        }
    }

    /// Apaga o trecho do traço dentro do raio; devolve os pedaços que sobraram.
    func erasingFreehand(at p: CGPoint, radius: CGFloat) -> [Shape] {
        var dense: [CGPoint] = []
        for (i, pt) in points.enumerated() {
            if i > 0 {
                let prev = points[i - 1]
                let n = Int(hypot(pt.x - prev.x, pt.y - prev.y) / 3)
                if n > 1 {
                    for k in 1..<n {
                        let t = CGFloat(k) / CGFloat(n)
                        dense.append(CGPoint(x: prev.x + (pt.x - prev.x) * t, y: prev.y + (pt.y - prev.y) * t))
                    }
                }
            }
            dense.append(pt)
        }
        var pieces: [Shape] = []
        var run: [CGPoint] = []
        func flush() {
            if run.count > 1 {
                var s = self
                s.points = run
                s.start = run[0]
                s.end = run[run.count - 1]
                pieces.append(s)
            }
            run = []
        }
        for pt in dense {
            if hypot(pt.x - p.x, pt.y - p.y) <= radius + width / 2 { flush() } else { run.append(pt) }
        }
        flush()
        return pieces
    }
}

func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let len2 = dx * dx + dy * dy
    guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

/// Média móvel de 3 pontos, mantendo as pontas fixas.
func smoothed(_ pts: [CGPoint], passes: Int = 2) -> [CGPoint] {
    var out = pts
    guard out.count > 2 else { return out }
    for _ in 0..<passes {
        var next = out
        for i in 1..<(out.count - 1) {
            next[i] = CGPoint(x: (out[i - 1].x + out[i].x + out[i + 1].x) / 3,
                              y: (out[i - 1].y + out[i].y + out[i + 1].y) / 3)
        }
        out = next
    }
    return out
}
