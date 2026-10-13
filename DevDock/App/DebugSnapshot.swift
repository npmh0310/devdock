#if DEBUG
import AppKit
import SwiftUI

/// `DevDock --snapshot <dir>` renders every module, AI account and port detail to PNG, then quits.
/// Layout check only: the glass backdrop is AppKit, so it is faked with a flat fill.
enum DebugSnapshot {
    static func runIfRequested(state: AppState) -> Bool {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-icon"), args.indices.contains(index + 1) {
            renderAppIcon(to: URL(fileURLWithPath: args[index + 1]))
            NSApp.terminate(nil)
            return true
        }
        guard let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) else { return false }
        let directory = URL(fileURLWithPath: args[index + 1])

        Task {
            await state.ports.refresh()
            await state.aiUsage.refresh()
            await state.claudeMem.refresh()
            await state.projects.refresh()

            for module in AppModule.allCases {
                state.module = module
                write(RootView(state: state, onClose: {}), to: directory, name: module.rawValue)
            }
            for account in state.aiUsage.accounts {
                write(AIUsageView(store: state.aiUsage, selectedID: account.id).padding(DS.Space.l),
                      to: directory, name: "ai-\(account.name)")
            }
            for port in state.ports.ports where port.category != .other {
                let detail = PortDetailView(store: state.ports, portID: port.id, onBack: {})
                write(detail.padding(DS.Space.l), to: directory, name: "port-\(port.port)")
            }
            NSApp.terminate(nil)
        }
        return true
    }

    /// `DevDock --render-icon <dir>` writes AppIcon PNGs (16…1024 px) from `BrandMark`.
    private static func renderAppIcon(to directory: URL) {
        for pixels in [16, 32, 64, 128, 256, 512, 1024] {
            let size = CGFloat(pixels)
            guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            BrandMark.drawAppIcon(in: context, size: size)
            guard let image = context.makeImage(),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: directory.appendingPathComponent("icon_\(pixels).png"))
        }
    }

    private static func write(_ content: some View, to directory: URL, name: String) {
        let view = content
            .frame(width: DS.Size.panelWidth)
            .background(Color(white: 0.16))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
#endif
