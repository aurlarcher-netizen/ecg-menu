import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Fenêtre « Scan d'ECG » : acquisition (scanner ou fichier) puis mise en forme
final class ScanWindowController: NSObject, NSWindowDelegate {
    static let shared = ScanWindowController()

    private var window: NSWindow?
    private let scanner = ScannerManager()
    private let doc = ECGImageDocument()
    private var browsing = false

    /// Appelé avec la lecture de Claude, pour pré-remplir le compte rendu
    var onAnalysis: ((ECGAnalysis) -> Void)?

    /// `autoScan` : lance un scan sur la vitre dès que le scanner est prêt
    func show(autoScan: Bool = false) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Scan d'ECG"
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 720, height: 520)
            w.contentView = NSHostingView(rootView: ScanView(scanner: scanner, doc: doc) { [weak self] in
                self?.onAnalysis?($0)
            })
            w.delegate = self
            w.center()
            window = w
            scanner.onScan = { [doc] url in doc.load(url) }
        }
        if !browsing { scanner.start(); browsing = true }
        if autoScan { scanner.scanFlatbedWhenReady() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        scanner.stop()
        browsing = false
    }
}

struct ScanView: View {
    @ObservedObject var scanner: ScannerManager
    @ObservedObject var doc: ECGImageDocument
    var onAnalysis: (ECGAnalysis) -> Void

    @AppStorage("scanFolder") private var scanFolder = ""
    @State private var message = ""
    @State private var copied = false
    @AppStorage("skipAnalysisWarning") private var skipWarning = false
    @State private var analyzing = false
    @State private var showWarning = false
    @State private var showKeySheet = false
    @State private var analyzeAfterKey = false
    @State private var aiComment = ""

    var body: some View {
        VStack(spacing: 0) {
            acquisitionBar
            Divider()
            editorArea
            if !aiComment.isEmpty { commentBar }
            Divider()
            layoutBar
        }
        .alert("Envoyer l'ECG à Claude ?", isPresented: $showWarning) {
            Button("Envoyer") { analyze() }
            Button("Envoyer et ne plus demander") { skipWarning = true; analyze() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("L'image rognée est envoyée à l'API Anthropic (\(ClaudeAnalyzer.model)). Vérifiez qu'elle ne montre ni nom, ni date de naissance, ni autre donnée identifiant le patient.")
        }
        .sheet(isPresented: $showKeySheet) {
            APIKeySheet { saved in
                showKeySheet = false
                if saved && analyzeAfterKey { requestAnalysis() }
                analyzeAfterKey = false
            }
        }
    }

    /// Remarques de Claude, hors formulaire
    private var commentBar: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            Text(aiComment).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button { aiComment = "" } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.purple.opacity(0.08))
    }

    // MARK: Acquisition

    private var acquisitionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if scanner.scanners.isEmpty {
                    Label("Aucun scanner", systemImage: "scanner").foregroundStyle(.secondary)
                } else {
                    Menu(scanner.selected?.name ?? "Choisir un scanner") {
                        ForEach(scanner.scanners, id: \.self) { s in
                            Button(s.name ?? "Scanner") { scanner.select(s) }
                        }
                    }
                    .frame(maxWidth: 220)
                    if scanner.sources.count > 1 {
                        Picker("", selection: $scanner.source) {
                            ForEach(scanner.sources, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    Button {
                        scanner.scan()
                    } label: {
                        Label("Scanner", systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scanner.isScanning || scanner.sources.isEmpty)
                    if scanner.isScanning { ProgressView().controlSize(.small) }
                }
                Button { scanner.reset() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Réinitialiser le scanner : ferme la connexion et relance la recherche")
                Spacer()
                Button { importFile() } label: { Label("Importer…", systemImage: "square.and.arrow.down") }
                Button { openLatestScan() } label: { Label("Dernier scan", systemImage: "clock.arrow.circlepath") }
                    .help(scanFolder.isEmpty ? "Choisir le dossier des scans (aussi réglable par clic droit sur l'icône)"
                                             : "Ouvre le fichier le plus récent de \(scanFolder)")
            }
            Text(message.isEmpty ? scanner.status : message)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(10)
        .onChange(of: scanner.status) { _, _ in message = "" }
    }

    private var editorArea: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if doc.image != nil {
                CropEditor(doc: doc).padding(16)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg.rectangle").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Scannez un ECG, importez un fichier (PDF ou image)\nou glissez-le ici.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { load(url) }
            }
            return true
        }
    }

    // MARK: Mise en forme

    private var layoutBar: some View {
        HStack(spacing: 8) {
            Button { doc.rotate(clockwise: false) } label: { Image(systemName: "rotate.left") }
                .help("Pivoter de 90° vers la gauche")
            Button { doc.rotate(clockwise: true) } label: { Image(systemName: "rotate.right") }
                .help("Pivoter de 90° vers la droite")
            Button("Paysage") { doc.makeLandscape() }
                .disabled(doc.pixelSize.height <= doc.pixelSize.width)
                .help("Passer en paysage si l'ECG est en portrait")
            Divider().frame(height: 20)
            Button { doc.clear(); aiComment = ""; message = "" } label: { Label("Retirer", systemImage: "trash") }
                .help("Retirer cette image pour en scanner ou en importer une autre")
            Divider().frame(height: 20)
            Button { doc.applyCrop() } label: { Label("Rogner", systemImage: "crop") }
                .disabled(!doc.isCropped)
            Button("Cadre complet") { doc.crop = ECGImageDocument.fullFrame }
                .disabled(!doc.isCropped)
            Spacer()
            Button { showKeySheet = true } label: { Image(systemName: "key") }
                .help("Clé API Anthropic")
            Button { requestAnalysis() } label: {
                if analyzing {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Analyse…") }
                } else {
                    Label("Analyser", systemImage: "sparkles")
                }
            }
            .disabled(analyzing)
            .help("Pré-remplir le compte rendu avec la lecture de Claude (\(ClaudeAnalyzer.model))")
            Button { copyImage() } label: {
                Label(copied ? "Copié !" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            Button { saveImage() } label: { Label("Enregistrer…", systemImage: "square.and.arrow.down.on.square") }
                .buttonStyle(.borderedProminent)
        }
        .disabled(doc.image == nil)
        .padding(10)
    }

    // MARK: Actions

    private func requestAnalysis() {
        if APIKeyStore.read()?.isEmpty ?? true {
            analyzeAfterKey = true
            showKeySheet = true
        } else if skipWarning {
            analyze()
        } else {
            showWarning = true
        }
    }

    private func analyze() {
        guard let image = doc.croppedImage else { return }
        analyzing = true
        message = "Analyse par Claude en cours…"
        Task {
            do {
                let analysis = try await ClaudeAnalyzer.analyze(image)
                await MainActor.run {
                    analyzing = false
                    aiComment = analysis.comment
                    message = "Compte rendu pré-rempli : relisez et corrigez chaque élément."
                    onAnalysis(analysis)
                }
            } catch {
                await MainActor.run {
                    analyzing = false
                    message = "Analyse impossible : \(error.localizedDescription)"
                }
            }
        }
    }

    private func load(_ url: URL) {
        message = doc.load(url) ? "Ouvert : \(url.lastPathComponent)" : "Impossible d'ouvrir \(url.lastPathComponent)."
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    /// Ouvre le fichier le plus récent du dossier de scans (choisi une fois, puis mémorisé)
    private func openLatestScan() {
        if scanFolder.isEmpty || !FileManager.default.fileExists(atPath: scanFolder) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.message = "Choisissez le dossier des scans (celui de l'app, ou celui d'iPrint&Scan)"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            scanFolder = url.path
        }
        let folder = URL(fileURLWithPath: scanFolder)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: .skipsHiddenFiles)) ?? []
        let candidates = files.filter {
            guard let type = UTType(filenameExtension: $0.pathExtension) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .pdf)
        }
        let latest = candidates.max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        if let latest { load(latest) } else { message = "Aucun PDF ni image dans \(folder.lastPathComponent)." }
    }

    private func copyImage() {
        guard let cg = doc.croppedImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: cg, size: .zero)])
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func saveImage() {
        guard let data = doc.pngData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "ECG.png"
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url); message = "Enregistré : \(url.lastPathComponent)" }
            catch { message = "Enregistrement impossible : \(error.localizedDescription)" }
        }
    }
}

/// Saisie, remplacement ou suppression de la clé API (rangée dans le Trousseau)
struct APIKeySheet: View {
    var done: (Bool) -> Void
    @State private var key = ""
    private let hasKey = !(APIKeyStore.read()?.isEmpty ?? true)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clé API Anthropic").font(.headline)
            Text(hasKey ? "Une clé est déjà enregistrée dans le Trousseau. Saisissez-en une nouvelle pour la remplacer."
                        : "Créez une clé sur console.anthropic.com, puis collez-la ici. Elle est rangée dans le Trousseau macOS.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField("sk-ant-…", text: $key).textFieldStyle(.roundedBorder)
            HStack {
                if hasKey {
                    Button("Supprimer la clé", role: .destructive) { APIKeyStore.delete(); done(false) }
                }
                Spacer()
                Button("Annuler") { done(false) }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") { done(APIKeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
