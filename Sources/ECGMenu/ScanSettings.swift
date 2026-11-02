import AppKit

/// Réglages du scanner, modifiables depuis le clic droit sur l'icône
enum ScanSettings {
    private static let defaults = UserDefaults.standard

    /// Le bouton de scan du compte rendu lance aussitôt un scan sur la vitre
    static var autoFlatbedScan: Bool {
        get { defaults.bool(forKey: "autoFlatbedScan") }
        set { defaults.set(newValue, forKey: "autoFlatbedScan") }
    }

    /// Dossier où une copie de chaque scan est déposée (et où « Dernier scan » cherche) ; vide = aucun
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

    /// Dépose le scan dans le dossier de scan et, si activé, dans le dossier de copie.
    /// Le scanner écrit toujours d'abord dans le dossier temporaire de l'app : un dossier surveillé
    /// par un autre logiciel (intégration Doctolib…) peut déplacer le fichier avant qu'on l'ouvre.
    /// Renvoie un message pour la barre d'état (vide si aucun dossier n'est réglé).
    static func store(_ url: URL) -> String {
        var targets: [String] = []
        if !scanFolder.isEmpty { targets.append(scanFolder) }
        if backupEnabled, !backupFolder.isEmpty, !targets.contains(backupFolder) { targets.append(backupFolder) }

        var saved: [String] = [], errors: [String] = []
        for path in targets {
            let folder = URL(fileURLWithPath: path)
            do {
                try copy(url, into: folder)
                saved.append(folder.lastPathComponent)
            } catch {
                errors.append("Copie dans \(folder.lastPathComponent) impossible : \(error.localizedDescription)")
            }
        }
        var message = saved.isEmpty ? "" : "Enregistré dans " + saved.joined(separator: " et ") + "."
        if !errors.isEmpty { message += (message.isEmpty ? "" : " ") + errors.joined(separator: " ") }
        return message
    }

    private static func copy(_ url: URL, into folder: URL) throws {
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
    }
}
