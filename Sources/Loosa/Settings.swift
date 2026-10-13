import SwiftUI
import AppKit
import Carbon
import ServiceManagement

/// Atalho global escolhido pelo usuário (tecla + modificadores).
struct HotkeyBinding: Equatable {
    var keyCode: UInt32
    var flags: UInt          // NSEvent.ModifierFlags.rawValue, só ⌘⌥⌃⇧
    var keyLabel: String

    static let standard = HotkeyBinding(keyCode: UInt32(kVK_ANSI_1),
                                        flags: NSEvent.ModifierFlags.command.rawValue, keyLabel: "1")

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: flags) }

    var carbonMods: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    var label: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        return out + keyLabel
    }

    /// Equivalente de tecla para o item do menu ("" quando não é um caractere simples).
    var menuKey: String {
        keyLabel == "Espaço" ? " " : (keyLabel.count == 1 ? keyLabel.lowercased() : "")
    }
    var menuFlags: NSEvent.ModifierFlags { modifiers }

    static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case 49: return "Espaço"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

/// Onde a barra de ferramentas aparece na tela.
enum ToolbarPosition: String, CaseIterable, Identifiable {
    case bottom, top, left, right
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottom: return "Embaixo"
        case .top: return "Em cima"
        case .left: return "Esquerda"
        case .right: return "Direita"
        }
    }
    var isVertical: Bool { self == .left || self == .right }
}

/// Preferências do usuário, guardadas em UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    /// Funções que o usuário pode ligar/desligar além das ferramentas.
    static let extraFeatures = ["ghost", "smooth", "fill"]

    @Published var disabled: Set<String> {
        didSet { UserDefaults.standard.set(Array(disabled), forKey: "disabled") }
    }
    static let defaultPaletteHex = ["#FF3B30", "#FFCC00", "#33C759", "#0A85FF", "#FFFFFF", "#000000"]

    /// Funções que aceitam atalho de letra, na ordem em que aparecem nas configurações.
    static let features: [String] = Tool.allCases.map(\.rawValue) + extraFeatures

    static let defaultShortcuts: [String: String] = [
        "pen": "p", "highlighter": "h", "arrow": "a", "rect": "r", "oval": "o", "text": "t",
        "blur": "d", "eraserItem": "e", "eraserFree": "b", "ghost": "g", "smooth": "s", "fill": "f",
    ]

    /// Só o que o usuário mudou; o resto vem de `defaultShortcuts`. "" = sem atalho.
    @Published var shortcutOverrides: [String: String] {
        didSet { UserDefaults.standard.set(shortcutOverrides, forKey: "shortcuts") }
    }

    @Published var paletteHex: [String] {
        didSet { UserDefaults.standard.set(paletteHex, forKey: "paletteHex") }
    }
    @Published var toolbarPosition: ToolbarPosition {
        didSet { UserDefaults.standard.set(toolbarPosition.rawValue, forKey: "toolbarPosition") }
    }
    /// Escala da barra: 0.8 (pequena) a 1.6 (grande).
    @Published var toolbarScale: Double {
        didSet { UserDefaults.standard.set(toolbarScale, forKey: "toolbarScale") }
    }
    @Published var ghostLife: Double {
        didSet { UserDefaults.standard.set(ghostLife, forKey: "ghostLife") }
    }
    @Published var hotkey: HotkeyBinding {
        didSet {
            let d = UserDefaults.standard
            d.set(Int(hotkey.keyCode), forKey: "hotkeyCode")
            d.set(Int(hotkey.flags), forKey: "hotkeyFlags")
            d.set(hotkey.keyLabel, forKey: "hotkeyLabel")
            HotKey.register(hotkey)
        }
    }

    private init() {
        let d = UserDefaults.standard
        disabled = Set(d.stringArray(forKey: "disabled") ?? [])
        let life = d.double(forKey: "ghostLife")
        ghostLife = life > 0 ? life : 2
        if d.object(forKey: "hotkeyCode") != nil, let label = d.string(forKey: "hotkeyLabel") {
            hotkey = HotkeyBinding(keyCode: UInt32(d.integer(forKey: "hotkeyCode")),
                                   flags: UInt(d.integer(forKey: "hotkeyFlags")), keyLabel: label)
        } else {
            // migra a escolha antiga (lista de atalhos prontos)
            let cmd = NSEvent.ModifierFlags.command.rawValue, shift = NSEvent.ModifierFlags.shift.rawValue
            let ctrl = NSEvent.ModifierFlags.control.rawValue, opt = NSEvent.ModifierFlags.option.rawValue
            switch d.string(forKey: "hotkey") ?? "" {
            case "cmdShift1": hotkey = HotkeyBinding(keyCode: UInt32(kVK_ANSI_1), flags: cmd | shift, keyLabel: "1")
            case "ctrl1": hotkey = HotkeyBinding(keyCode: UInt32(kVK_ANSI_1), flags: ctrl, keyLabel: "1")
            case "ctrlOptD": hotkey = HotkeyBinding(keyCode: UInt32(kVK_ANSI_D), flags: ctrl | opt, keyLabel: "D")
            case "optSpace": hotkey = HotkeyBinding(keyCode: UInt32(kVK_Space), flags: opt, keyLabel: "Espaço")
            default: hotkey = .standard
            }
        }
        toolbarPosition = ToolbarPosition(rawValue: d.string(forKey: "toolbarPosition") ?? "") ?? .bottom
        let sc = d.double(forKey: "toolbarScale")
        toolbarScale = sc > 0 ? min(max(sc, 0.8), 1.6) : 1.0
        let n = Self.defaultPaletteHex.count
        if let hex = d.stringArray(forKey: "paletteHex"), hex.count == n { paletteHex = hex }
        else { paletteHex = Self.defaultPaletteHex }
        shortcutOverrides = d.dictionary(forKey: "shortcuts") as? [String: String] ?? [:]
    }

    var palette: [NSColor] {
        paletteHex.enumerated().map { i, h in
            NSColor(hex: h) ?? NSColor(hex: Self.defaultPaletteHex[i]) ?? .red
        }
    }

    func key(for feature: String) -> String {
        shortcutOverrides[feature] ?? Self.defaultShortcuts[feature] ?? ""
    }

    /// Função que usa esta letra, se houver.
    func feature(forKey k: String) -> String? {
        guard !k.isEmpty else { return nil }
        return Self.features.first { key(for: $0) == k }
    }

    /// Normaliza o que foi digitado: uma letra minúscula que nenhuma outra função usa. "" se inválida.
    func sanitizedKey(_ raw: String, for feature: String) -> String {
        guard let c = raw.lowercased().first(where: { $0.isLetter }) else { return "" }
        let k = String(c)
        if let other = self.feature(forKey: k), other != feature { return "" }
        return k
    }

    func isOn(_ feature: String) -> Bool { !disabled.contains(feature) }

    func set(_ feature: String, _ on: Bool) {
        if on { disabled.remove(feature) } else { disabled.insert(feature) }
    }

    func resetDefaults() {
        disabled = []
        ghostLife = 2
        hotkey = .standard
        toolbarPosition = .bottom
        toolbarScale = 1.0
        paletteHex = Self.defaultPaletteHex
        shortcutOverrides = [:]
    }
}

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private func lastEnabledDrawingTool(_ t: Tool) -> Bool {
        let all = Tool.allCases
        return settings.isOn(t.rawValue) && all.filter { settings.isOn($0.rawValue) }.count == 1
    }

    var body: some View {
        Form {
            Section {
                ForEach(Tool.allCases) { tool in
                    FunctionRow(feature: tool.rawValue, title: tool.title, symbol: tool.symbol,
                                locked: lastEnabledDrawingTool(tool))
                }
            } header: {
                Text("Ferramentas e atalhos")
            } footer: {
                Text("A letra ao lado é o atalho de cada função com o desenho aberto. Clique na tecla e aperte a nova letra (Delete remove o atalho).")
            }

            Section {
                ForEach(0..<settings.paletteHex.count, id: \.self) { i in
                    ColorRow(slot: i)
                }
            } header: {
                Text("Cores")
            } footer: {
                Text("Com o desenho aberto, as teclas 1 a 6 escolhem as cores na ordem da barra.")
            }

            Section("Modos") {
                FunctionRow(feature: "ghost", title: "Traço fantasma", symbol: "timer")
                FunctionRow(feature: "smooth", title: "Suavizar desenho", symbol: "waveform.path")
                FunctionRow(feature: "fill", title: "Preencher formas", symbol: "square.inset.filled")
                HStack {
                    Text("Tempo do traço fantasma")
                    Slider(value: $settings.ghostLife, in: 1...10, step: 0.5)
                    Text(String(format: "%.1f s", settings.ghostLife))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .disabled(!settings.isOn("ghost"))
            }

            Section {
                Picker("Posição", selection: $settings.toolbarPosition) {
                    ForEach(ToolbarPosition.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Tamanho")
                    Slider(value: $settings.toolbarScale, in: 0.8...1.6, step: 0.1)
                    Text("\(Int((settings.toolbarScale * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            } header: {
                Text("Barra de ferramentas")
            } footer: {
                Text("Em cima e embaixo a barra fica na horizontal; nas laterais, na vertical.")
            }

            Section {
                ScreenPermissionRow()
            } header: {
                Text("Desfoque")
            } footer: {
                Text("O desfoque real precisa da permissão de Gravação de Tela. Sem ela, usa um vidro fosco acinzentado.")
            }

            Section("Geral") {
                HStack {
                    Text("Atalho para desenhar")
                    Spacer()
                    HotkeyRecorder()
                }
                Toggle("Abrir o Loosa ao iniciar o Mac", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = "Não consegui alterar: \(error.localizedDescription)"
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let e = loginError {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Button("Restaurar padrões") { settings.resetDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 760)
    }
}

/// Gravador de atalho: clique, aperte a combinação (com ⌘, ⌃ ou ⌥) e pronto.
struct HotkeyRecorder: View {
    @ObservedObject var settings = Settings.shared
    @State private var recording = false
    @State private var message: String?

    var body: some View {
        HStack(spacing: 8) {
            if let m = message {
                Text(m).font(.caption).foregroundStyle(.orange)
            }
            Button {
                message = nil
                recording.toggle()
            } label: {
                Text(recording ? "Aperte o atalho…" : settings.hotkey.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(minWidth: 96, minHeight: 26)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(recording ? 0.14 : 0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.18),
                                      lineWidth: recording ? 1.5 : 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(KeyCatcher(recording: $recording,
                                   onRecord: { candidate in
                                       let previous = settings.hotkey
                                       if HotKey.register(candidate) {
                                           message = nil
                                           settings.hotkey = candidate
                                       } else {
                                           message = "Atalho indisponível"
                                           _ = HotKey.register(previous)
                                       }
                                   },
                                   onInvalid: { message = $0 }))
        }
    }
}

/// Recebe a tecla enquanto o gravador está ativo (inclui combinações com ⌘).
struct KeyCatcher: NSViewRepresentable {
    @Binding var recording: Bool
    let onRecord: (HotkeyBinding) -> Void
    let onInvalid: (String) -> Void

    final class CatcherView: NSView {
        var onKey: (NSEvent) -> Bool = { _ in false }
        var onStop: () -> Void = {}
        override var acceptsFirstResponder: Bool { true }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            window?.firstResponder === self ? onKey(event) : false
        }
        override func keyDown(with event: NSEvent) { _ = onKey(event) }
        override func resignFirstResponder() -> Bool {
            onStop()
            return true
        }
    }

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ v: CatcherView, context: Context) {
        v.onStop = { recording = false }
        v.onKey = { event in
            guard recording else { return false }
            if event.keyCode == 53 { recording = false; return true } // esc cancela
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isDisjoint(with: [.command, .option, .control]) else {
                onInvalid("Inclua ⌘, ⌃ ou ⌥")
                return true
            }
            onRecord(HotkeyBinding(keyCode: UInt32(event.keyCode), flags: mods.rawValue,
                                   keyLabel: HotkeyBinding.label(for: event)))
            recording = false
            return true
        }
        if recording, v.window?.firstResponder !== v {
            DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        }
    }
}

/// Mostra se o Loosa pode ler a tela (necessário para o desfoque de verdade).
struct ScreenPermissionRow: View {
    @State private var granted = ScreenBackdrop.hasPermission

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(granted ? "Gravação de Tela liberada" : "Gravação de Tela não liberada")
            Spacer()
            if !granted {
                Button("Liberar…") {
                    ScreenBackdrop.requestPermissionOnce()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = ScreenBackdrop.hasPermission
        }
    }
}

struct ColorRow: View {
    @ObservedObject var settings = Settings.shared
    let slot: Int

    var body: some View {
        HStack {
            Text("\(slot + 1)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 20)
                .foregroundStyle(.secondary)
            ColorPicker("Tecla \(slot + 1)", selection: Binding(
                get: { Color(nsColor: NSColor(hex: settings.paletteHex[slot]) ?? .red) },
                set: { settings.paletteHex[slot] = NSColor($0).hexString }
            ), supportsOpacity: false)
        }
    }
}

/// Uma função: ícone e nome à esquerda; letra do atalho e liga/desliga alinhados à direita.
struct FunctionRow: View {
    @ObservedObject var settings = Settings.shared
    let feature: String
    let title: String
    let symbol: String
    var locked = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer(minLength: 12)
            ShortcutField(feature: feature)
            Toggle("", isOn: Binding(get: { settings.isOn(feature) },
                                     set: { settings.set(feature, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(locked)
        }
        .padding(.vertical, 2)
    }
}

/// Tecla do atalho: clique nela e aperte a letra desejada (Delete limpa, Esc cancela).
struct ShortcutField: View {
    @ObservedObject var settings = Settings.shared
    let feature: String
    @FocusState private var focused: Bool
    @State private var warning = false

    private var label: String {
        if focused { return "…" }
        let k = settings.key(for: feature)
        return k.isEmpty ? "–" : k.uppercased()
    }

    var body: some View {
        HStack(spacing: 8) {
            if warning {
                Text("em uso").font(.caption).foregroundStyle(.orange)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(focused ? 0.14 : 0.08))
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(focused ? Color.accentColor
                                          : (warning ? Color.orange : Color.primary.opacity(0.18)),
                                  lineWidth: focused ? 1.5 : 1)
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(settings.key(for: feature).isEmpty && !focused ? .secondary : .primary)
            }
            .frame(width: 32, height: 26)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handle(press) }
            .help("Clique e aperte a letra do atalho")
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape { focused = false; return .handled }
        if press.key == .delete || press.key == .deleteForward {
            settings.shortcutOverrides[feature] = ""
            warning = false
            focused = false
            return .handled
        }
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        guard let c = press.characters.lowercased().first, c.isLetter else { return .ignored }
        let ok = settings.sanitizedKey(String(c), for: feature)
        if ok.isEmpty {
            warning = true
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                warning = false
            }
        } else {
            settings.shortcutOverrides[feature] = ok
            warning = false
        }
        focused = false
        return .handled
    }
}

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 760),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Configurações do Loosa"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
