import AppKit
import Combine

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Camada onde os traços são desenhados; fica acima dos desfoques e não recebe cliques.
final class InkView: NSView {
    weak var canvas: CanvasView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { canvas?.drawInk() }
}

final class PassthroughEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class CanvasView: NSView, NSTextViewDelegate {
    let state: DrawState
    var onActivity: ((CanvasView) -> Void)?

    private let ink = InkView()
    private var blurViews: [UUID: NSVisualEffectView] = [:]
    private var ghostTimer: Timer?

    /// Foto desfocada desta tela. Sem ela (sem permissão), cai no vidro fosco do sistema.
    var blurredBackdrop: CGImage? {
        didSet { syncBlur(); redraw() }
    }

    private var shapes: [Shape] = [] { didSet { syncBlur() } }
    private var undoStack: [[Shape]] = []
    private var redoStack: [[Shape]] = []
    private var current: Shape? { didSet { syncBlur() } }
    private var editor: NSTextView?
    private var editorShape: Shape?

    private var pointer: CGPoint?       // posição do mouse, para o anel da borracha
    private var hovered: Int?           // item em foco no modo "apagar item"
    private var erasedInGesture = false
    private var bag = Set<AnyCancellable>()

    init(frame: NSRect, state: DrawState) {
        self.state = state
        super.init(frame: frame)
        ink.frame = bounds
        ink.autoresizingMask = [.width, .height]
        ink.canvas = self
        addSubview(ink)
        state.$tool
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.hovered = nil
                self.window?.invalidateCursorRects(for: self)
                self.redraw()
            }
            .store(in: &bag)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch state.tool {
        case .text: cursor = .iBeam
        case .eraserItem: cursor = .pointingHand
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    private var eraserRadius: CGFloat { 8 + state.width * 1.5 }
    private var itemTolerance: CGFloat { 8 }

    override func draw(_ dirtyRect: NSRect) {
        // Quase transparente, mas não 100%: é o que faz a janela receber os cliques.
        NSColor(white: 0, alpha: 0.01).setFill()
        bounds.fill()
    }

    fileprivate func drawInk() {
        if let h = hovered, shapes.indices.contains(h) { shapes[h].drawHalo() }
        for s in shapes { paint(s) }
        if let c = current { paint(c) }

        if state.tool == .eraserFree, let p = pointer {
            let r = eraserRadius
            let ring = NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            NSColor.white.withAlphaComponent(0.25).setFill()
            ring.fill()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    /// Desenha um item; o desfoque usa a foto desfocada da tela, recortada na área.
    private func paint(_ s: Shape) {
        guard s.kind == .blur, let img = blurredBackdrop else { s.draw(); return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: s.rect, xRadius: 12, yRadius: 12).addClip()
        NSImage(cgImage: img, size: bounds.size)
            .draw(in: bounds, from: .zero, operation: .sourceOver,
                  fraction: s.fade, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    fileprivate func redraw() { ink.needsDisplay = true }

    // MARK: Desfoque

    private func syncBlur() {
        var want: [(UUID, CGRect, CGFloat)] = []
        if blurredBackdrop == nil {
            want = shapes.filter { $0.kind == .blur }.map { ($0.id, $0.rect, $0.fade) }
            if let c = current, c.kind == .blur { want.append((c.id, c.rect, 1)) }
        }
        let ids = Set(want.map { $0.0 })
        for (id, v) in blurViews where !ids.contains(id) {
            v.removeFromSuperview()
            blurViews[id] = nil
        }
        for (id, r, a) in want {
            let v = blurViews[id] ?? makeBlurView(id)
            v.frame = r
            v.alphaValue = a
        }
    }

    private func makeBlurView(_ id: UUID) -> NSVisualEffectView {
        let v = PassthroughEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        v.layer?.masksToBounds = true
        addSubview(v, positioned: .below, relativeTo: ink)
        blurViews[id] = v
        return v
    }

    // MARK: Fantasma

    private func startGhostTimer() {
        guard ghostTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.shapes.contains(where: { $0.isExpired }) {
                self.shapes.removeAll { $0.isExpired }
                self.hovered = nil
            }
            if !self.shapes.contains(where: { $0.expiresAt != nil }) {
                t.invalidate()
                self.ghostTimer = nil
            }
            self.syncBlur()
            self.redraw()
        }
        RunLoop.main.add(t, forMode: .common)
        ghostTimer = t
    }

    /// Adiciona um item pronto ao desenho (com vida curta se o fantasma estiver ativo).
    private func commit(_ shape: Shape) {
        var s = shape
        if state.ghostActive {
            s.expiresAt = Date().addingTimeInterval(Settings.shared.ghostLife)
            startGhostTimer()
        }
        snapshot()
        shapes.append(s)
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pointer = p
        if state.tool == .eraserItem {
            hovered = itemIndex(at: p)
        }
        if state.tool == .eraserItem || state.tool == .eraserFree { redraw() }
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        hovered = nil
        redraw()
    }

    override func mouseDown(with event: NSEvent) {
        onActivity?(self)
        commitText()
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        pointer = p

        switch state.tool {
        case .text:
            beginText(at: p)
        case .eraserItem, .eraserFree:
            erasedInGesture = false
            erase(at: p)
        case .highlighter:
            current = Shape(kind: .highlighter, start: p, end: p, points: [p],
                            color: DrawState.highlighterColor, width: max(16, state.width * 3))
            redraw()
        case .blur:
            ScreenBackdrop.requestPermissionOnce()
            current = Shape(kind: .blur, start: p, end: p, color: .clear, width: 1)
            redraw()
        default:
            var shape = Shape(kind: state.tool, start: p, end: p, points: [p],
                              color: state.color, width: state.width)
            shape.filled = state.fillActive && (state.tool == .rect || state.tool == .oval)
            current = shape
            redraw()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        var p = convert(event.locationInWindow, from: nil)
        pointer = p

        if state.tool == .eraserItem || state.tool == .eraserFree {
            erase(at: p)
            return
        }

        guard var s = current else { return }
        let shift = event.modifierFlags.contains(.shift)
        switch s.kind {
        case .pen, .highlighter:
            if state.smoothActive, let last = s.points.last {
                // estabilizador: o traço persegue o cursor em vez de copiar cada tremida
                let k: CGFloat = 0.5
                let np = CGPoint(x: last.x + (p.x - last.x) * k, y: last.y + (p.y - last.y) * k)
                if hypot(np.x - last.x, np.y - last.y) >= 0.5 { s.points.append(np) }
            } else {
                s.points.append(p)
            }
        case .rect, .oval:
            if shift {
                let dx = p.x - s.start.x, dy = p.y - s.start.y
                let m = max(abs(dx), abs(dy))
                p = CGPoint(x: s.start.x + (dx < 0 ? -m : m), y: s.start.y + (dy < 0 ? -m : m))
            }
        case .arrow:
            if shift {
                let dx = p.x - s.start.x, dy = p.y - s.start.y
                let len = hypot(dx, dy)
                let step = CGFloat.pi / 4
                let a = (atan2(dy, dx) / step).rounded() * step
                p = CGPoint(x: s.start.x + cos(a) * len, y: s.start.y + sin(a) * len)
            }
        default: break
        }
        s.end = p
        current = s
        redraw()
    }

    override func mouseUp(with event: NSEvent) {
        if state.tool == .eraserItem {
            hovered = itemIndex(at: convert(event.locationInWindow, from: nil))
            redraw()
        }
        guard var s = current else { return }
        current = nil
        if s.isFreehand && state.smoothActive {
            s.points.append(convert(event.locationInWindow, from: nil))
            s.points = smoothed(s.points)
        }
        let size = hypot(s.end.x - s.start.x, s.end.y - s.start.y)
        switch s.kind {
        case .pen, .highlighter: commit(s)
        case .blur: if size > 8 { commit(s) }
        default: if size > 2 { commit(s) }
        }
        redraw()
    }

    // MARK: Borracha

    /// Item mais ao topo sob o ponto.
    private func itemIndex(at p: CGPoint) -> Int? {
        shapes.indices.reversed().first { shapes[$0].hit(p, tolerance: itemTolerance) }
    }

    private func erase(at p: CGPoint) {
        switch state.tool {
        case .eraserItem:
            guard let i = itemIndex(at: p) else { return }
            beginErase()
            shapes.remove(at: i)
            hovered = itemIndex(at: p)
        case .eraserFree:
            var result: [Shape] = []
            var changed = false
            let r = eraserRadius
            for s in shapes {
                guard s.hit(p, tolerance: r) else { result.append(s); continue }
                changed = true
                if s.isFreehand {
                    result.append(contentsOf: s.erasingFreehand(at: p, radius: r))
                }
                // formas, texto e desfoque saem inteiros quando a borracha encosta
            }
            if changed {
                beginErase()
                shapes = result
            }
        default: break
        }
        redraw()
    }

    /// Um único ponto de desfazer por gesto de apagar.
    private func beginErase() {
        if !erasedInGesture {
            snapshot()
            erasedInGesture = true
        }
    }

    // MARK: Teclado

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { // esc
            state.onClose()
            return
        }
        if flags.contains(.command), let c = event.charactersIgnoringModifiers?.lowercased() {
            if c == "z" { flags.contains(.shift) ? state.onRedo() : state.onUndo(); return }
            if event.keyCode == 51 { state.onClear(); return } // ⌘⌫
        }
        if flags.contains(.control), event.charactersIgnoringModifiers?.lowercased() == "z" {
            flags.contains(.shift) ? state.onRedo() : state.onUndo() // ⌃Z
            return
        }
        if flags.isDisjoint(with: [.command, .control, .option]),
           let c = event.charactersIgnoringModifiers?.lowercased() {
            if let n = Int(c), (1...DrawState.palette.count).contains(n) {
                state.colorIndex = n - 1
                return
            }
            if let f = Settings.shared.feature(forKey: c), Settings.shared.isOn(f) {
                switch f {
                case "ghost": state.ghost.toggle()
                case "smooth": state.smooth.toggle()
                case "fill": state.filled.toggle()
                default: if let t = Tool(rawValue: f) { state.tool = t }
                }
                return
            }
        }
        super.keyDown(with: event)
    }

    // MARK: Histórico

    private func snapshot() {
        undoStack.append(shapes)
        redoStack.removeAll()
    }

    func undo() {
        commitText()
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(shapes)
        shapes = prev.filter { !$0.isExpired }
        hovered = nil
        redraw()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(shapes)
        shapes = next.filter { !$0.isExpired }
        hovered = nil
        redraw()
    }

    func clear() {
        cancelText()
        guard !shapes.isEmpty else { return }
        snapshot()
        shapes.removeAll()
        hovered = nil
        redraw()
    }

    // MARK: Texto

    private func beginText(at p: CGPoint) {
        let shape = Shape(kind: .text, start: p, end: p, color: state.color, width: state.width)
        let tv = NSTextView(frame: NSRect(x: p.x, y: p.y, width: 500, height: shape.font.pointSize * 1.4))
        tv.isRichText = false
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 2000, height: 10000)
        tv.isHorizontallyResizable = true
        tv.font = shape.font
        tv.textColor = shape.color
        tv.insertionPointColor = shape.color
        tv.typingAttributes = [.font: shape.font, .foregroundColor: shape.color]
        tv.delegate = self
        addSubview(tv)
        window?.makeFirstResponder(tv)
        editor = tv
        editorShape = shape
    }

    private func commitText() {
        guard let tv = editor, var s = editorShape else { return }
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        tv.removeFromSuperview()
        editor = nil
        editorShape = nil
        window?.makeFirstResponder(self)
        guard !text.isEmpty else { return }
        s.text = text
        commit(s)
        redraw()
    }

    private func cancelText() {
        editor?.removeFromSuperview()
        editor = nil
        editorShape = nil
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if NSEvent.modifierFlags.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                commitText()
            }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            commitText()
            return true
        }
        return false
    }
}
