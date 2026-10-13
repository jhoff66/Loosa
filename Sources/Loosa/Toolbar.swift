import SwiftUI
import AppKit

// MARK: Liquid Glass (macOS 26+), com material comum como alternativa

extension View {
    @ViewBuilder
    func glassBackground(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }
}

// MARK: Rótulo ao passar o mouse (só o nome)

/// Janelinha flutuante com o nome do controle. O tooltip nativo não aparece em painéis
/// que não ativam o app, por isso este é próprio.
final class Tooltip {
    static let shared = Tooltip()
    private var panel: NSPanel?
    private var pending: DispatchWorkItem?

    func show(_ text: String, above rect: CGRect) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.present(text, rect) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func hide() {
        pending?.cancel()
        panel?.orderOut(nil)
    }

    private func present(_ text: String, _ r: CGRect) {
        guard let owner = ToolbarPanel.current else { return }
        let host = NSHostingView(rootView:
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassBackground(radius: 10)
                .padding(6)
        )
        let size = host.fittingSize
        let p = panel ?? {
            let n = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            n.isOpaque = false
            n.backgroundColor = .clear
            n.hasShadow = false
            n.ignoresMouseEvents = true
            n.sharingType = .none
            n.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
            n.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel = n
            return n
        }()
        p.contentView = host
        p.setContentSize(size)
        // r está em coordenadas da janela da barra (origem no topo à esquerda)
        let f = owner.frame
        let x = f.minX + r.midX - size.width / 2
        let y = Settings.shared.toolbarPosition == .top
            ? f.maxY - r.maxY - size.height          // barra no topo: rótulo abaixo do controle
            : f.maxY - r.minY                        // demais: acima do controle
        p.setFrameOrigin(CGPoint(x: x, y: y))
        p.orderFrontRegardless()
    }
}

// MARK: Seletor (dropdown) próprio

struct DropdownList: View {
    let items: [Tool]
    let current: Tool
    let onPick: (Tool) -> Void
    @State private var hovered: Tool?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items) { t in
                Button { onPick(t) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 20)
                        Text(t.title)
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .opacity(current == t ? 1 : 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .frame(minWidth: 190)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(hovered == t ? 0.12 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? t : (hovered == t ? nil : hovered) }
            }
        }
        .padding(6)
        .glassBackground(radius: 16)
        .padding(8)
    }
}

final class Dropdown {
    static let shared = Dropdown()
    private var panel: NSPanel?
    private var monitor: Any?
    private var lastHide = Date.distantPast

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(items: [Tool], current: Tool, above r: CGRect, onPick: @escaping (Tool) -> Void) {
        // o clique que fecha pelo monitor não deve reabrir pelo próprio botão
        if isVisible || Date().timeIntervalSince(lastHide) < 0.2 { hide(); return }
        guard let owner = ToolbarPanel.current else { return }
        Tooltip.shared.hide()

        let host = NSHostingView(rootView: DropdownList(items: items, current: current) { [weak self] t in
            onPick(t)
            self?.hide()
        })
        let size = host.fittingSize
        let p = panel ?? {
            let n = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            n.isOpaque = false
            n.backgroundColor = .clear
            n.hasShadow = false
            n.sharingType = .none
            n.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
            n.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel = n
            return n
        }()
        p.contentView = host
        p.setContentSize(size)
        let f = owner.frame
        let y = Settings.shared.toolbarPosition == .top
            ? f.maxY - r.maxY - size.height + 4
            : f.maxY - r.minY - 4
        p.setFrameOrigin(CGPoint(x: f.minX + r.midX - size.width / 2, y: y))
        p.orderFrontRegardless()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            if e.window !== self?.panel { self?.hide() }
            return e
        }
    }

    func hide() {
        if panel?.isVisible == true { lastHide = Date() }
        panel?.orderOut(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

struct TipModifier: ViewModifier {
    let text: String
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, new in frame = new }
            })
            .onHover { inside in
                if inside { Tooltip.shared.show(text, above: frame) } else { Tooltip.shared.hide() }
            }
    }
}

extension View {
    func tip(_ text: String) -> some View { modifier(TipModifier(text: text)) }
}

// MARK: Escala da barra (preferência do usuário)

private struct BarScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
    var barScale: CGFloat {
        get { self[BarScaleKey.self] }
        set { self[BarScaleKey.self] = newValue }
    }
}

/// Botão quadrado da barra: destaque ao passar o mouse e preenchimento quando ativo.
struct BarButton: View {
    let symbol: String
    var active = false
    var help = ""
    let action: () -> Void
    @State private var hover = false
    @Environment(\.barScale) private var k

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15 * k, weight: .medium))
                .frame(width: 34 * k, height: 34 * k)
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 11 * k, style: .continuous)
                        .fill(active ? Color.accentColor
                                     : Color.primary.opacity(hover ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .tip(help)
    }
}

/// Fundo da barra que a move ao arrastar. Os controles por cima (slider, botões) ficam livres.
struct DragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct ToolbarView: View {
    @ObservedObject var state: DrawState
    @ObservedObject var settings = Settings.shared
    @State private var eraserFrame: CGRect = .zero

    private var draw: [Tool] { Tool.drawing.filter { settings.isOn($0.rawValue) } }
    private var erase: [Tool] { Tool.erasers.filter { settings.isOn($0.rawValue) } }

    private var hasModes: Bool { ["ghost", "smooth", "fill"].contains { settings.isOn($0) } }

    private var k: CGFloat { CGFloat(settings.toolbarScale) }
    private var vertical: Bool { settings.toolbarPosition.isVertical }

    var body: some View {
        Group {
            if vertical {
                HStack(alignment: .top, spacing: 10 * k) { toolsGroup; groupDivider; colorsGroup }
            } else {
                VStack(spacing: 10 * k) { toolsGroup; groupDivider; colorsGroup }
            }
        }
        .padding(.horizontal, 16 * k)
        .padding(.vertical, 12 * k)
        .frame(minWidth: vertical ? nil : 540 * k)
        .background(DragArea())
        .glassBackground(radius: 24 * k)
        .padding(10)
        .environment(\.barScale, k)
    }

    /// Itens de um grupo: em linha na barra horizontal, em coluna na vertical.
    @ViewBuilder
    private func axisStack<C: View>(spacing: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        if vertical {
            VStack(spacing: spacing, content: content)
        } else {
            HStack(spacing: spacing, content: content)
        }
    }

    // Grupo 1: ferramentas, borrachas, modos e configurações
    private var toolsGroup: some View {
        axisStack(spacing: 4 * k) {
            ForEach(draw) { toolButton($0) }
            if !draw.isEmpty && !erase.isEmpty { itemDivider }
            eraserControl
            if hasModes { itemDivider }
            if settings.isOn("ghost") {
                BarButton(symbol: "timer", active: state.ghost,
                          help: shortcutHelp("Traço fantasma", "ghost")) { state.ghost.toggle() }
            }
            if settings.isOn("smooth") {
                BarButton(symbol: "waveform.path", active: state.smooth,
                          help: shortcutHelp("Suavizar desenho", "smooth")) { state.smooth.toggle() }
            }
            if settings.isOn("fill") {
                BarButton(symbol: "square.inset.filled", active: state.filled,
                          help: shortcutHelp("Preencher formas", "fill")) { state.filled.toggle() }
            }
            Spacer(minLength: 12 * k)
            BarButton(symbol: "gearshape", help: "Configurações") { state.onSettings() }
        }
        .frame(maxWidth: vertical ? nil : .infinity,
               maxHeight: vertical ? .infinity : nil,
               alignment: .topLeading)
    }

    // Grupo 2: cores, espessura e ações
    private var colorsGroup: some View {
        axisStack(spacing: 8 * k) {
            ForEach(DrawState.palette.indices, id: \.self) { i in
                Button { state.colorIndex = i } label: {
                    Circle()
                        .fill(Color(nsColor: DrawState.palette[i]))
                        .frame(width: 20 * k, height: 20 * k)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.28), lineWidth: 1))
                        .padding(3 * k)
                        .overlay(Circle().strokeBorder(Color.accentColor,
                                                       lineWidth: state.colorIndex == i ? 2 : 0))
                }
                .buttonStyle(.plain)
                .tip("Cor \(i + 1)")
            }
            if vertical {
                Slider(value: $state.width, in: 2...14)
                    .frame(width: 90 * k, height: 20 * k)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 24 * k, height: 90 * k)
                    .tip("Espessura")
            } else {
                Slider(value: $state.width, in: 2...14)
                    .frame(minWidth: 70 * k, maxWidth: 140 * k)
                    .padding(.leading, 6 * k)
                    .tip("Espessura")
            }
            Spacer(minLength: 16 * k)
            BarButton(symbol: "arrow.uturn.backward", help: "Desfazer") { state.onUndo() }
            BarButton(symbol: "trash", help: "Limpar tudo") { state.onClear() }
            BarButton(symbol: "xmark", help: "Sair") { state.onClose() }
        }
        .frame(maxHeight: vertical ? .infinity : nil, alignment: .top)
    }

    /// Separador entre itens do mesmo grupo.
    private var itemDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.15))
            .frame(width: vertical ? 22 * k : 1, height: vertical ? 1 : 22 * k)
            .padding(vertical ? .vertical : .horizontal, 4 * k)
    }

    /// Separador entre os dois grupos.
    private var groupDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.1))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }

    /// Só o nome da função; sem atalho nem descrição.
    private func shortcutHelp(_ title: String, _ feature: String) -> String { title }

    /// Uma borracha: botão simples. Mais de uma: botão que abre o seletor do tipo.
    @ViewBuilder
    private var eraserControl: some View {
        if erase.count == 1, let only = erase.first {
            toolButton(only)
        } else if erase.count > 1 {
            let current = erase.contains(state.eraser) ? state.eraser : erase[0]
            let active = Tool.erasers.contains(state.tool)
            Button {
                Dropdown.shared.toggle(items: erase, current: current, above: eraserFrame) { state.tool = $0 }
            } label: {
                HStack(spacing: 2 * k) {
                    Image(systemName: current.symbol)
                        .font(.system(size: 15 * k, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7 * k, weight: .bold))
                        .opacity(0.7)
                }
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 46 * k, height: 34 * k)
                .background(
                    RoundedRectangle(cornerRadius: 11 * k, style: .continuous)
                        .fill(active ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { eraserFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, new in eraserFrame = new }
            })
            .tip("Borracha")
        }
    }

    private func toolButton(_ tool: Tool) -> some View {
        BarButton(symbol: tool.symbol, active: state.tool == tool,
                  help: shortcutHelp(tool.title, tool.rawValue)) { state.tool = tool }
    }
}

final class ToolbarPanel: NSPanel {
    static weak var current: ToolbarPanel?
    override var canBecomeKey: Bool { false }
}
