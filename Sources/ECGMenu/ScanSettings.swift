import AppKit

/// Réglages du scanner, modifiables depuis le clic droit sur l'icône
enum ScanSettings {
    private static let defaults = UserDefaults.standard

    /// Le bouton de scan du compte rendu lance aussitôt un scan sur la vitre
    static var autoFlatbedScan: Bool {
        get { defaults.bool(forKey: "autoFlatbedScan") }
        set { defaults.set(newValue, forKey: "autoFlatbedScan") }
    }

    /// Dossier où les scans sont enregistrés (et où « Dernier scan » cherche) ; vide = dossier temporaire
    static var scanFolder: String {
        get { defaults.string(forKey: "scanFolder") ?? "" }
        set { defaults.set(newValue, forKey: "scanFolder") }
    }

    /// Copie de chaque scan dans un second dossier
    static var backupEnabled: Bool {
        get { defaults.bool(forKey: "backupEnabled") }
        set { defaults.set(newValue, forKey: "backupEnabled") }
    }

    static var backupFolder: String {
        get { defaults.string(forKey: "backupFolder") ?? "" }
        set { defaults.set(newValue, forKey: "backupFolder") }
    }

    /// Dossier de destination des scans, s'il existe encore
    static var scanDirectory: URL {
        var isDir: ObjCBool = false
        if !scanFolder.isEmpty, FileManager.default.fileExists(atPath: scanFolder, isDirectory: &isDir), isDir.boolValue {
            return URL(fileURLWithPath: scanFolder)
        }
        return FileManager.default.temporaryDirectory
    }

    /// Fait choisir un dossier ; nil si annulé
    static func chooseFolder(message: String, current: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = message
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current) }
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// Copie le scan dans le dossier de copie, si activé ; renvoie un message d'erreur éventuel
    static func backup(_ url: URL) -> String? {
        guard backupEnabled, !backupFolder.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: backupFolder)
        guard folder.standardizedFileURL != url.deletingLastPathComponent().standardizedFileURL else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Nom déjà pris : « ECG-… 2.png », « ECG-… 3.png »…
            let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
            var target = folder.appendingPathComponent(url.lastPathComponent)
            var n = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
                n += 1
            }
            try FileManager.default.copyItem(at: url, to: target)
            return nil
        } catch {
            return "Copie dans \(folder.lastPathComponent) impossible : \(error.localizedDescription)"
        }
    }
}
