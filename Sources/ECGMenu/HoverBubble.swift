import SwiftUI
import AppKit

/// Bulle flottante : un panneau séparé, affiché à côté de la fenêtre du menu,
/// pour ne jamais modifier la taille de celle-ci.
@MainActor
final class HoverBubble {
    static let shared = HoverBubble()

    private let panel: NSPanel

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// Affiche `content` à gauche de la fenêtre du menu, aligné sur la vue `anchor`
    func show<V: View>(_ content: V, anchor: NSView?) {
        guard let anchor, let window = anchor.window else { return }
        let host = NSHostingView(rootView: content
            .frame(width: 380, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3))))
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        panel.contentView = host

        let anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        var x = window.frame.minX - size.width - 8
        if x < screen.minX { x = window.frame.maxX + 8 }
        let y = min(max(anchorRect.maxY - size.height, screen.minY), screen.maxY - size.height)
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}

/// Référence vers la NSView sous-jacente d'un élément SwiftUI (pour positionner la bulle)
final class ViewRef {
    weak var view: NSView?
}

/// Vue AppKit transparente aux clics : sinon elle intercepte les clics destinés au bouton SwiftUI
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct AnchorView: NSViewRepresentable {
    let ref: ViewRef
    func makeNSView(context: Context) -> NSView {
        let v = PassthroughView()
        ref.view = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { ref.view = nsView }
}
