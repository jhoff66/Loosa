import AppKit
import ScreenCaptureKit
import CoreImage

/// Foto desfocada da tela, usada para pintar as áreas de desfoque sem tinta nem borda.
enum ScreenBackdrop {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Pede a permissão uma única vez por execução (abre o aviso do sistema).
    private static var asked = false
    static func requestPermissionOnce() {
        guard !asked, !hasPermission else { return }
        asked = true
        CGRequestScreenCaptureAccess()
    }

    /// Captura a tela já desfocada. Devolve nil sem permissão ou em caso de erro.
    static func blurredSnapshot(of screen: NSScreen, radius: CGFloat = 22) async -> CGImage? {
        guard hasPermission,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
            // O próprio Loosa (overlay e barra) fica de fora da foto.
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            cfg.width = Int(screen.frame.width * scale)
            cfg.height = Int(screen.frame.height * scale)
            cfg.showsCursor = false
            let shot = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            return blur(shot, radius: radius * scale)
        } catch {
            return nil
        }
    }

    private static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let out = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        return CIContext().createCGImage(out, from: input.extent)
    }
}
