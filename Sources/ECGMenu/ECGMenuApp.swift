import SwiftUI
import AppKit
import ServiceManagement

/// Démarrage AppKit pur : aucune scène SwiftUI, donc aucune fenêtre parasite au lancement
@main
enum ECGMenuMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Icône de barre des menus : clic gauche = compte rendu, clic droit = options
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let report = ECGReport()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.qrsIcon()
            button.toolTip = "Compte rendu ECG"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.delegate = self
        // Taille fixée avant l'ouverture : sinon le popover se redimensionne après coup et déborde en haut de l'écran
        let host = NSHostingController(rootView: ContentView(report: report))
        host.sizingOptions = []
        popover.contentViewController = host
        popover.contentSize = ContentView.size
        ScanWindowController.shared.onAnalysis = { [weak self] analysis in
            guard let self else { return }
            self.report.apply(analysis)
            if !self.popover.isShown { self.togglePopover() }
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentSize = ContentView.size
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        HoverBubble.shared.hide()
    }

    // MARK: Menu du clic droit

    private func showMenu() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        let menu = NSMenu()
        let login = NSMenuItem(title: "Ouvrir au démarrage de l'ordinateur",
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let scan = NSMenuItem(title: "Scanner un ECG…", action: #selector(openScanWindow), keyEquivalent: "")
        scan.target = self
        menu.addItem(scan)
        let settings = NSMenuItem(title: "Réglages du scanner", action: nil, keyEquivalent: "")
        settings.submenu = scanSettingsMenu()
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openScanWindow() {
        ScanWindowController.shared.show()
    }

    // MARK: Réglages du scanner

    private func scanSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, on: Bool? = nil) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            if let on { i.state = on ? .on : .off }
            menu.addItem(i)
        }
        func folderName(_ path: String) -> String { path.isEmpty ? "non choisi" : URL(fileURLWithPath: path).lastPathComponent }

        item("Scanner sur la vitre dès le clic sur le bouton de scan", #selector(toggleAutoScan), on: ScanSettings.autoFlatbedScan)
        menu.addItem(.separator())
        let quality = NSMenuItem(title: "Qualité du scan", action: nil, keyEquivalent: "")
        quality.submenu = NSMenu()
        for q in ScanSettings.qualities {
            let i = NSMenuItem(title: q.label, action: #selector(setQuality(_:)), keyEquivalent: "")
            i.target = self
            i.tag = q.dpi
            i.state = ScanSettings.resolution == q.dpi ? .on : .off
            quality.submenu?.addItem(i)
        }
        menu.addItem(quality)
        menu.addItem(.separator())
        item("Dossier d'enregistrement : \(folderName(ScanSettings.scanFolder))…", #selector(chooseScanFolder))
        menu.addItem(.separator())
        item("Enregistrer aussi une copie dans un second dossier", #selector(toggleBackup), on: ScanSettings.backupEnabled)
        item("Dossier de copie : \(folderName(ScanSettings.backupFolder))…", #selector(chooseBackupFolder))
        return menu
    }

    @objc private func toggleAutoScan() { ScanSettings.autoFlatbedScan.toggle() }

    @objc private func setQuality(_ sender: NSMenuItem) { ScanSettings.resolution = sender.tag }

    @objc private func chooseScanFolder() {
        if let path = ScanSettings.chooseFolder(message: "Dossier où le bouton « Enregistrer » dépose les ECG", current: ScanSettings.scanFolder) {
            ScanSettings.scanFolder = path
        }
    }

    @objc private func toggleBackup() {
        // Activer sans dossier : le demander tout de suite
        if !ScanSettings.backupEnabled && ScanSettings.backupFolder.isEmpty {
            chooseBackupFolder()
            guard !ScanSettings.backupFolder.isEmpty else { return }
        }
        ScanSettings.backupEnabled.toggle()
    }

    @objc private func chooseBackupFolder() {
        if let path = ScanSettings.chooseFolder(message: "Second dossier où copier chaque ECG enregistré",
                                                current: ScanSettings.backupFolder) {
            ScanSettings.backupFolder = path
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Impossible de modifier l'ouverture au démarrage"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: Icône

    /// Complexe QRS normal dessiné en image « template » (s'adapte au mode clair/sombre)
    static func qrsIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 18), flipped: false) { _ in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 0.75, y: 6.75))
            p.line(to: NSPoint(x: 2.75, y: 6.75))
            p.line(to: NSPoint(x: 3.9, y: 5))     // Q
            p.line(to: NSPoint(x: 6.1, y: 17))    // R
            p.line(to: NSPoint(x: 8.3, y: 1))     // S
            p.line(to: NSPoint(x: 9.4, y: 6.75))
            p.line(to: NSPoint(x: 11.25, y: 6.75))
            p.lineWidth = 1.5
            p.lineJoinStyle = .round
            p.lineCapStyle = .round
            NSColor.black.setStroke()
            p.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
