import AppKit

/// Réglages du scanner, modifiables depuis le clic droit sur l'icône
enum ScanSettings {
    private static let defaults = UserDefaults.standard

    /// Qualités proposées (résolutions acceptées par les Brother du cabinet)
    static let qualities: [(dpi: Int, label: String)] = [
        (100, "Brouillon – 100 dpi"),
        (200, "Standard – 200 dpi"),
        (300, "Haute – 300 dpi (recommandé)"),
        (600, "Maximale – 600 dpi (lent, fichiers lourds)"),
    ]

    /// Résolution du scan, en dpi
    static var resolution: Int {
        get { defaults.object(forKey: "scanResolution") as? Int ?? 300 }
        set { defaults.set(newValue, forKey: "scanResolution") }
    }

    /// Le bouton de scan du compte rendu lance aussitôt un scan sur la vitre
    static var autoFlatbedScan: Bool {
        get { defaults.bool(forKey: "autoFlatbedScan") }
        set { defaults.set(newValue, forKey: "autoFlatbedScan") }
    }

    /// Dossier où « Enregistrer » dépose l'ECG (et où « Dernier scan » cherche) ; vide = demandé au premier enregistrement
    static var scanFolder: String {
        get { defaults.string(forKey: "scanFolder") ?? "" }
        set { defaults.set(newValue, forKey: "scanFolder") }
    }

    /// À l'enregistrement, copie aussi dans un second dossier
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

    /// Enregistre l'ECG mis en forme dans le dossier de scan et, si activé, dans le dossier de copie.
    /// Renvoie un message pour la barre d'état.
    static func save(_ png: Data, name: String) -> String {
        var targets = [scanFolder]
        if backupEnabled, !backupFolder.isEmpty, backupFolder != scanFolder { targets.append(backupFolder) }

        var saved: [String] = [], errors: [String] = []
        for path in targets {
            let folder = URL(fileURLWithPath: path)
            do {
                try write(png, name: name, into: folder)
                saved.append(folder.lastPathComponent)
            } catch {
                errors.append("Enregistrement dans \(folder.lastPathComponent) impossible : \(error.localizedDescription)")
            }
        }
        var message = saved.isEmpty ? "" : "Enregistré dans " + saved.joined(separator: " et ") + "."
        if !errors.isEmpty { message += (message.isEmpty ? "" : " ") + errors.joined(separator: " ") }
        return message
    }

    /// Nom de fichier daté : « ECG 2026-11-02 19-30-12.png »
    static func fileName(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "ECG \(f.string(from: date)).png"
    }

    private static func write(_ data: Data, name: String, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Nom déjà pris : « ECG … 2.png », « ECG … 3.png »…
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var target = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        try data.write(to: target, options: .withoutOverwriting)
    }
}
