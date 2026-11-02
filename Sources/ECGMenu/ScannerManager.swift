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

    private let browser = ICDeviceBrowser()
    private var pendingScan = false
    private let resolution = 300

    func start() {
        scanners = []
        selected = nil
        sources = []
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

    func stop() {
        browser.stop()
        selected?.requestCloseSession()
    }

    func select(_ scanner: ICScannerDevice) {
        if let old = selected, old != scanner { old.requestCloseSession() }
        selected = scanner
        sources = []
        status = "Connexion à \(scanner.name ?? "scanner")…"
        scanner.delegate = self
        scanner.requestOpenSession()
    }

    func scan() {
        guard let scanner = selected, scanner.hasOpenSession else { return }
        isScanning = true
        pendingScan = true
        status = "Scan en cours…"
        scanner.requestSelect(source)
    }

    // MARK: ICDeviceBrowserDelegate

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let scanner = device as? ICScannerDevice else { return }
        scanners.append(scanner)
        if selected == nil { select(scanner) }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        scanners.removeAll { $0 == device }
        if selected == device { selected = nil; sources = []; status = "Scanner déconnecté." }
    }

    // MARK: ICDeviceDelegate

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        guard let scanner = device as? ICScannerDevice else { return }
        if let error { status = "Connexion impossible : \(error.localizedDescription)"; return }
        sources = scanner.availableFunctionalUnitTypes.compactMap { ICScannerFunctionalUnitType(rawValue: $0.uintValue) }
            .filter { $0 == .flatbed || $0 == .documentFeeder }
        source = sources.contains(.flatbed) ? .flatbed : (sources.first ?? .flatbed)
        status = "Prêt : \(scanner.name ?? "scanner")"
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

    func didRemove(_ device: ICDevice) {
        if selected == device { selected = nil; sources = [] }
    }

    // MARK: ICScannerDeviceDelegate

    func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: Error?) {
        guard pendingScan else { return }
        pendingScan = false
        if let error { finish("Sélection de la source impossible : \(error.localizedDescription)"); return }

        functionalUnit.pixelDataType = .RGB
        functionalUnit.bitDepth = .depth8Bits
        let supported = functionalUnit.supportedResolutions
        functionalUnit.resolution = supported.contains(resolution)
            ? resolution
            : supported.min { abs($0 - resolution) < abs($1 - resolution) } ?? functionalUnit.preferredResolutions.first ?? resolution
        if let feeder = functionalUnit as? ICScannerFunctionalUnitDocumentFeeder {
            feeder.documentType = .typeA4
        } else {
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
