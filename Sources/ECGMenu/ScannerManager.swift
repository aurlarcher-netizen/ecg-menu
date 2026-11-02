import AppKit
import ImageCaptureCore
import UniformTypeIdentifiers

/// Détection et pilotage des scanners visibles par macOS (Image Capture)
final class ScannerManager: NSObject, ObservableObject, ICDeviceBrowserDelegate, ICScannerDeviceDelegate {
    @Published var scanners: [ICScannerDevice] = []
    @Published var selected: ICScannerDevice?
    @Published var sources: [ICScannerFunctionalUnitType] = []
    @Published var source: ICScannerFunctionalUnitType = .flatbed
    @Published var status = "Recherche des scanners…"
    @Published var isScanning = false

    /// Appelé avec chaque page scannée
    var onScan: ((URL) -> Void)?

    /// Recherche des scanners, lancée une seule fois : l'arrêter puis la relancer fait échouer
    /// la connexion suivante (« failed to open a connection to the device »)
    private let browser = ICDeviceBrowser()
    private var browsing = false
    private var pendingScan = false
    private var openRetried = false
    /// Une session est en cours de fermeture : en rouvrir une tout de suite échoue aussi
    private var closingSince: Date?
    private let resolution = 300

    /// Dernier scanner choisi, présélectionné à la prochaine ouverture
    private var preferredName: String? {
        get { UserDefaults.standard.string(forKey: "scannerName") }
        set { UserDefaults.standard.set(newValue, forKey: "scannerName") }
    }

    func start() {
        isScanning = false
        pendingScan = false
        guard !browsing else { reconnect(); return }
        browsing = true
        status = "Recherche des scanners…"
        browser.delegate = self
        let mask = ICDeviceTypeMask.scanner.rawValue | ICDeviceLocationTypeMask.local.rawValue
            | ICDeviceLocationTypeMask.shared.rawValue | ICDeviceLocationTypeMask.bonjour.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask)!
        browser.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.scanners.isEmpty else { return }
            self.status = "Aucun scanner détecté : vérifiez qu'il est allumé et ajouté dans Réglages Système > Imprimantes et scanners, ou importez un fichier."
        }
    }

    /// Ferme la connexion au scanner (la recherche reste active)
    func stop() {
        pendingScan = false
        isScanning = false
        if let s = selected, s.hasOpenSession {
            closingSince = Date()
            s.requestCloseSession()
        }
    }

    /// En cas d'erreur : ferme la connexion, puis se reconnecte au scanner habituel
    func reset() {
        stop()
        selected = nil
        sources = []
        status = "Réinitialisation…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.reconnect() }
    }

    private func reconnect() {
        if let since = closingSince, Date().timeIntervalSince(since) < 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reconnect() }
            return
        }
        closingSince = nil
        if let target = scanners.first(where: { $0.name == preferredName }) ?? scanners.first {
            select(target)
        } else {
            status = "Recherche des scanners…"
        }
    }

    func select(_ scanner: ICScannerDevice) {
        if let old = selected, old != scanner, old.hasOpenSession { closingSince = Date(); old.requestCloseSession() }
        selected = scanner
        sources = []
        openRetried = false
        preferredName = scanner.name
        status = "Connexion à \(scanner.name ?? "scanner")…"
        scanner.delegate = self
        if scanner.hasOpenSession { updateSources(scanner) } else { scanner.requestOpenSession() }
    }

    func scan() {
        guard let scanner = selected, scanner.hasOpenSession else { return }
        isScanning = true
        status = "Scan en cours…"
        let unit = scanner.selectedFunctionalUnit
        if unit.type == source && !unit.supportedResolutions.isEmpty {
            startScan(scanner, unit)
        } else {
            pendingScan = true
            scanner.requestSelect(source)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let self, self.pendingScan else { return }
                self.pendingScan = false
                self.finish("Le scanner ne répond pas. Cliquez sur Réinitialiser puis réessayez.")
            }
        }
    }

    private func updateSources(_ scanner: ICScannerDevice) {
        sources = scanner.availableFunctionalUnitTypes.compactMap { ICScannerFunctionalUnitType(rawValue: $0.uintValue) }
            .filter { $0 == .flatbed || $0 == .documentFeeder }
        guard !sources.isEmpty else { return }
        if !sources.contains(source) { source = sources.contains(.flatbed) ? .flatbed : sources[0] }
        status = "Prêt : \(scanner.name ?? "scanner")"
    }

    // MARK: ICDeviceBrowserDelegate

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let scanner = device as? ICScannerDevice else { return }
        scanners.append(scanner)
        if let name = preferredName {
            if scanner.name == name && selected?.name != name { select(scanner) }
            else if selected == nil {
                // Laisse un peu de temps au scanner habituel pour apparaître avant d'en prendre un autre
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    if let self, self.selected == nil, let first = self.scanners.first { self.select(first) }
                }
            }
        } else if selected == nil {
            select(scanner)
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        scanners.removeAll { $0 == device }
        if selected == device { selected = nil; sources = []; status = "Scanner déconnecté." }
    }

    // MARK: ICDeviceDelegate

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        guard let scanner = device as? ICScannerDevice else { return }
        if let error {
            // Souvent passager (scanner en veille, occupé par une autre app) : un second essai suffit
            if !openRetried {
                openRetried = true
                status = "Connexion difficile, nouvel essai…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard self?.selected == scanner else { return }
                    scanner.requestOpenSession()
                }
            } else {
                status = "Connexion impossible à \(scanner.name ?? "scanner") : \(error.localizedDescription). "
                    + "Fermez iPrint&Scan ou Transfert d'images, essayez un autre scanner de la liste, ou Réinitialiser."
            }
            return
        }
        status = "Connecté à \(scanner.name ?? "scanner"), préparation…"
        updateSources(scanner)
    }

    /// Les sources (vitre, chargeur) ne sont connues qu'une fois le scanner prêt
    func deviceDidBecomeReady(_ device: ICDevice) {
        guard let scanner = device as? ICScannerDevice, scanner == selected else { return }
        updateSources(scanner)
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        closingSince = nil
    }

    func didRemove(_ device: ICDevice) {
        if selected == device { selected = nil; sources = [] }
    }

    // MARK: ICScannerDeviceDelegate

    func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: Error?) {
        guard pendingScan else { return }
        if let error { pendingScan = false; finish("Sélection de la source impossible : \(error.localizedDescription)"); return }
        // macOS répond d'abord avec une source vide, puis avec la source demandée et ses réglages
        guard functionalUnit.type == source, !functionalUnit.supportedResolutions.isEmpty else { return }
        pendingScan = false
        startScan(scanner, functionalUnit)
    }

    private func startScan(_ scanner: ICScannerDevice, _ functionalUnit: ICScannerFunctionalUnit) {
        functionalUnit.pixelDataType = .RGB
        functionalUnit.bitDepth = .depth8Bits
        let supported = functionalUnit.supportedResolutions
        functionalUnit.resolution = supported.contains(resolution)
            ? resolution
            : supported.min { abs($0 - resolution) < abs($1 - resolution) } ?? functionalUnit.preferredResolutions.first ?? resolution
        if let feeder = functionalUnit as? ICScannerFunctionalUnitDocumentFeeder {
            feeder.documentType = .typeA4
        } else if functionalUnit.physicalSize != .zero {
            functionalUnit.scanArea = NSRect(origin: .zero, size: functionalUnit.physicalSize)
        }

        scanner.transferMode = .fileBased
        scanner.downloadsDirectory = FileManager.default.temporaryDirectory
        scanner.documentName = "ECG-\(Int(Date().timeIntervalSince1970))"
        scanner.documentUTI = UTType.png.identifier
        scanner.requestScan()
    }

    func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) {
        onScan?(url)
    }

    func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: Error?) {
        finish(error.map { "Échec du scan : \($0.localizedDescription)" } ?? "Scan terminé.")
    }

    private func finish(_ message: String) {
        isScanning = false
        status = message
    }
}

extension ICScannerFunctionalUnitType {
    var label: String {
        switch self {
        case .flatbed: return "Vitre"
        case .documentFeeder: return "Chargeur"
        default: return "Autre"
        }
    }
}
