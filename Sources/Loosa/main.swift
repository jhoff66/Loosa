import AppKit
import SwiftUI
import Carbon
import Combine

/// Uma sessão de desenho: um overlay transparente por tela + a barra flutuante.
final class DrawingSession {
    let state = DrawState()
    private var windows: [OverlayWindow] = []
    private var canvases: [CanvasView] = []
    private var panel: ToolbarPanel?
    private var host: NSHostingView<ToolbarView>?
    private var settingsSink: AnyCancellable?
    private weak var lastCanvas: CanvasView?

    var isActive: Bool { !windows.isEmpty }
    var onEnd: () -> Void = {}

    func start() {
        guard !isActive else { return }
        state.onUndo = { [weak self] in self?.target?.undo() }
        state.onRedo = { [weak self] in self?.target?.redo() }
        state.onClear = { [weak self] in self?.canvases.forEach { $0.clear() } }
        state.onClose = { [weak self] in self?.stop() }
        state.onSettings = { [weak self] in
            self?.stop()
            SettingsWindow.show()
        }

        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false, screen: screen)
            w.isReleasedWhenClosed = false
            w.setFrame(screen.frame, display: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let c = CanvasView(frame: NSRect(origin: .zero, size: screen.frame.size), state: state)
            c.onActivity = { [weak self] in self?.lastCanvas = $0 }
            w.contentView = c
            w.orderFrontRegardless()
            if ProcessInfo.processInfo.environment["LOOSA_DEBUG"] != nil {
                FileHandle.standardError.write("tela \(screen.frame) janela \(w.frame) visivel \(w.isVisible)\n".data(using: .utf8)!)
            }
            windows.append(w)
            canvases.append(c)
        }
        showToolbar()
        for (screen, canvas) in zip(NSScreen.screens, canvases) {
            Task { [weak canvas] in
                let img = await ScreenBackdrop.blurredSnapshot(of: screen)
                await MainActor.run { canvas?.blurredBackdrop = img }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let key = windows.first { $0.frame.contains(mouse) } ?? windows.first
        key?.makeKeyAndOrderFront(nil)
        if let c = key?.contentView { key?.makeFirstResponder(c) }
        lastCanvas = key?.contentView as? CanvasView
    }

    func stop() {
        Tooltip.shared.hide()
        Dropdown.shared.hide()
        panel?.orderOut(nil)
        panel = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        canvases.removeAll()
        onEnd()
    }

    private var target: CanvasView? { lastCanvas ?? canvases.first }

    private func showToolbar() {
        let host = NSHostingView(rootView: ToolbarView(state: state))
        self.host = host
        let size = host.fittingSize
        let p = ToolbarPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.contentView = host
        p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.sharingType = .none // fora de prints e gravações de tela
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        place(p, size: size, on: screen)
        p.orderFrontRegardless()
        panel = p
        ToolbarPanel.current = p

        // Quando o usuário liga/desliga funções, a barra encolhe/cresce e a ferramenta ativa se ajusta.
        settingsSink = Settings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refitToolbar() }
    }

    private func refitToolbar() {
        if !Settings.shared.isOn(state.tool.rawValue),
           let first = Tool.allCases.first(where: { Settings.shared.isOn($0.rawValue) }) {
            state.tool = first
        }
        guard let p = panel, let host else { return }
        let size = host.fittingSize
        p.setContentSize(size)
        place(p, size: size, on: p.screen ?? NSScreen.main ?? NSScreen.screens[0])
    }

    /// Posiciona a barra conforme a preferência (embaixo, em cima, esquerda ou direita).
    private func place(_ p: NSPanel, size: NSSize, on screen: NSScreen) {
        let vf = screen.visibleFrame
        let m: CGFloat = 24
        let origin: CGPoint
        switch Settings.shared.toolbarPosition {
        case .bottom: origin = CGPoint(x: vf.midX - size.width / 2, y: vf.minY + m)
        case .top: origin = CGPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - m)
        case .left: origin = CGPoint(x: vf.minX + m, y: vf.midY - size.height / 2)
        case .right: origin = CGPoint(x: vf.maxX - size.width - m, y: vf.midY - size.height / 2)
        }
        p.setFrameOrigin(origin)
    }
}

// Atalho global para ligar/desligar (Carbon: não precisa de permissão de acessibilidade).
enum HotKey {
    static var fire: () -> Void = {}
    private static var ref: EventHotKeyRef?
    private static var handlerInstalled = false

    @discardableResult
    static func register(_ binding: HotkeyBinding) -> Bool {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                HotKey.fire()
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        let status = RegisterEventHotKey(binding.keyCode, binding.carbonMods,
                                         EventHotKeyID(signature: OSType(0x4C4F4F53), id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let session = DrawingSession()

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = item.button {
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()
        session.onEnd = { [weak self] in self?.updateIcon() }
        HotKey.fire = { [weak self] in self?.toggle() }
        HotKey.register(Settings.shared.hotkey)
        if ProcessInfo.processInfo.environment["LOOSA_AUTOSTART"] != nil { toggle() }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let preset = Settings.shared.hotkey
            let t = menu.addItem(withTitle: session.isActive ? "Parar de desenhar" : "Desenhar na tela",
                                 action: #selector(toggle), keyEquivalent: preset.menuKey)
            t.keyEquivalentModifierMask = preset.menuFlags
            t.target = self
            let cfg = menu.addItem(withTitle: "Configurações…", action: #selector(openSettings), keyEquivalent: ",")
            cfg.target = self
            menu.addItem(.separator())
            let q = menu.addItem(withTitle: "Sair do Loosa", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            q.target = NSApp
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            toggle()
        }
    }

    @objc private func openSettings() {
        if session.isActive { session.stop() }
        updateIcon()
        SettingsWindow.show()
    }

    @objc private func toggle() {
        session.isActive ? session.stop() : session.start()
        updateIcon()
    }

    /// Ícone da menubar: um quadrado com um risquinho dentro.
    /// Ativo, o quadrado fica preenchido e o traço vaza.
    private static func menuIcon(active: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 21, height: 18), flipped: false) { _ in
            let box = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 18, height: 13), xRadius: 3.5, yRadius: 3.5)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            if active {
                box.fill()
            } else {
                box.lineWidth = 1.5
                box.stroke()
            }

            let squiggle = NSBezierPath()
            squiggle.move(to: NSPoint(x: 5, y: 8))
            squiggle.curve(to: NSPoint(x: 10.5, y: 9),
                           controlPoint1: NSPoint(x: 6.8, y: 12.4), controlPoint2: NSPoint(x: 9, y: 12.4))
            squiggle.curve(to: NSPoint(x: 16, y: 10),
                           controlPoint1: NSPoint(x: 12, y: 5.6), controlPoint2: NSPoint(x: 14.2, y: 5.6))
            squiggle.lineWidth = 1.7
            squiggle.lineCapStyle = .round
            squiggle.lineJoinStyle = .round
            if active {
                NSGraphicsContext.current?.compositingOperation = .destinationOut
            }
            squiggle.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    private func updateIcon() {
        item.button?.image = Self.menuIcon(active: session.isActive)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
