import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var report: ECGReport
    @State private var copied = false
    /// Texte du compte rendu, modifiable à la main ; régénéré dès qu'un choix change
    @State private var draft = ""

    /// Taille du compte rendu : 680 pt de haut, réduite si l'écran est trop petit (la liste défile)
    static var size: NSSize {
        let available = (NSScreen.main?.visibleFrame.height ?? 800) - 40
        return NSSize(width: 400, height: min(680, available))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hrRow
                    axisRow
                    rhythmRow
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ondes :").font(.headline)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                HoverPreview {
                                    Chip(title: report.qWave ? "Onde Q en" : "Pas d'onde Q significative", selected: true,
                                         tint: report.qWave ? .orange : .accentColor) { report.qWave.toggle() }
                                } preview: {
                                    PreviewCard(title: "Onde Q significative (pathologique)",
                                                text: """
                                                • Durée ≥ 40 ms (1 mm) et/ou profondeur ≥ 25 % du R qui suit
                                                • Dans au moins 2 dérivations contiguës d'un même territoire
                                                • En V2–V3 : toute onde Q ≥ 20 ms, ou aspect QS
                                                Normales : q fine < 40 ms en DI, aVL, V5-V6 ; Q isolée en DIII ou aVR.
                                                """,
                                                traces: Strips.qWave(), pxPerMm: 5)
                                }
                                HoverPreview { optionChip("S1Q3", isOn: $report.s1q3) } preview: {
                                    PreviewCard(title: "Aspect S1Q3 (McGinn-White)",
                                                text: """
                                                • Onde S profonde en DI
                                                • Onde Q (souvent avec T négative) en DIII
                                                Évoque une surcharge ventriculaire droite aiguë (embolie pulmonaire) ; peu sensible et peu spécifique.
                                                """,
                                                traces: Strips.s1q3(), pxPerMm: 5)
                                }
                            }
                            if report.qWave { LeadPicker(selection: $report.qLeads) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HoverPreview { optionChip("Onde delta", isOn: $report.delta) } preview: {
                            PreviewCard(title: "Onde delta (pré-excitation)",
                                        text: """
                                        • Empâtement initial du QRS (montée lente)
                                        • PR court < 120 ms, QRS souvent élargi
                                        • Troubles secondaires de la repolarisation
                                        Évoque un Wolff-Parkinson-White : avis cardiologique, risque en cas de FA.
                                        """,
                                        traces: Strips.delta(), pxPerMm: 5)
                        }
                        if report.delta { LeadPicker(selection: $report.deltaLeads) }
                    }
                    qrsRow
                    VStack(alignment: .leading, spacing: 6) {
                        HoverPreview {
                            Chip(title: report.noST ? "Pas de décalage ST" : "Décalage ST", selected: true,
                                 tint: report.noST ? .accentColor : .orange) { report.noST.toggle() }
                        } preview: {
                            PreviewCard(title: "Décalage ST significatif",
                                        text: """
                                        Mesuré au point J, dans au moins 2 dérivations contiguës :
                                        • Sus-décalage ≥ 1 mm (sauf V2–V3)
                                        • En V2–V3 : ≥ 2 mm chez l'homme ≥ 40 ans, ≥ 2,5 mm < 40 ans, ≥ 1,5 mm chez la femme
                                        • Sous-décalage ≥ 0,5 mm, horizontal ou descendant
                                        Penser au miroir et à la repolarisation précoce.
                                        """,
                                        traces: Strips.st(), pxPerMm: 5)
                        }
                        if !report.noST {
                            HStack(spacing: 6) {
                                optionChip("Sus-décalage", isOn: $report.stUp)
                                optionChip("Sous-décalage", isOn: $report.stDown)
                            }
                            if report.stUp {
                                Text("Sus-décalage en :").font(.caption).foregroundStyle(.secondary)
                                LeadPicker(selection: $report.stUpLeads)
                            }
                            if report.stDown {
                                Text("Sous-décalage en :").font(.caption).foregroundStyle(.secondary)
                                LeadPicker(selection: $report.stDownLeads)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HoverPreview {
                            Chip(title: report.tNormal ? "Ondes T normales" : "Ondes T anormales", selected: true,
                                 tint: report.tNormal ? .accentColor : .orange) { report.tNormal.toggle() }
                        } preview: { tCard(.normales) }
                        if !report.tNormal {
                            HStack(spacing: 6) {
                                HoverPreview { optionChip(TWave.negatives.rawValue, isOn: $report.tNeg) } preview: { tCard(.negatives) }
                                HoverPreview { optionChip(TWave.biphasiques.rawValue, isOn: $report.tBiph) } preview: { tCard(.biphasiques) }
                                HoverPreview { optionChip(TWave.amples.rawValue, isOn: $report.tPeaked) } preview: { tCard(.amples) }
                            }
                            if report.tNeg {
                                Text("T négatives en :").font(.caption).foregroundStyle(.secondary)
                                LeadPicker(selection: $report.tNegLeads)
                            }
                            if report.tBiph {
                                Text("T biphasiques en :").font(.caption).foregroundStyle(.secondary)
                                LeadPicker(selection: $report.tBiphLeads)
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        HoverPreview { optionChip("Onde U", isOn: $report.uWave, tint: .accentColor) }
                            preview: {
                                PreviewCard(title: "Onde U", text: "Petite onde positive après T, mieux vue en V2-V3 : hypokaliémie, bradycardie, médicaments.",
                                            traces: Strips.uWave(), pxPerMm: 5)
                            }
                        ExtrasystoleChip(value: $report.extrasystole)
                    }
                    measures
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onDisappear { HoverBubble.shared.hide() }
    }

    // MARK: Blocs

    private var header: some View {
        HStack {
            Image(systemName: "waveform.path.ecg").foregroundStyle(.red)
            Text("Compte rendu ECG").font(.headline)
            Spacer()
            Picker("", selection: Binding(get: { report.paperSpeed }, set: { report.paperSpeed = $0 })) {
                ForEach(PaperSpeed.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 130)
            Button { ScanWindowController.shared.show() } label: { Image(systemName: "doc.viewfinder") }
                .help("Scanner un ECG")
                .padding(.leading, 6)
        }
        .buttonStyle(.borderless)
        .padding(10)
    }

    private var axisRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                rowLabel("Axe")
                HoverPreview {
                    Chip(title: "Normal", selected: report.axis == .normal) {
                        report.axis = report.axis == .normal ? nil : .normal
                    }
                } preview: { axisCard(.normal) }
                if report.axis != .normal {
                    HoverPreview {
                        Chip(title: Axis.indetermine.rawValue, selected: report.axis == .indetermine, tint: .orange) {
                            report.axis = report.axis == .indetermine ? nil : .indetermine
                        }
                        .opacity(report.axis == .indetermine ? 1 : 0.5)
                    } preview: { axisCard(.indetermine) }
                }
                Spacer()
            }
            if report.axis != .normal && report.axis != .indetermine {
                ChoiceRow(options: [.gauche, .hyperGauche, .droit, .hyperDroit],
                          selection: Binding(get: { report.axis ?? .normal }, set: { report.axis = $0 }),
                          label: \.rawValue) { axisCard($0) }
            }
        }
    }

    private func axisCard(_ a: Axis) -> some View {
        PreviewCard(title: "Axe " + a.rawValue.lowercased(), text: a.info, traces: Strips.axis(a), axisAngle: a.angle)
    }

    private var rhythmRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                rowLabel("Rythme")
                HoverPreview {
                    Chip(title: report.rhythm.rawValue, selected: true,
                         tint: report.rhythm == .rsr ? .accentColor : .orange) {
                        report.rhythm = report.rhythm == .rsr ? .fa : .rsr
                    }
                    .help("Cliquer pour basculer RSR / FA")
                } preview: {
                    PreviewCard(title: report.rhythm.rawValue, text: report.rhythm.info,
                                traces: [Strips.rhythm(report.rhythm)])
                }
                Chip(title: "BAV", selected: report.bavOn) { report.bavOn.toggle() }
                    .disabled(report.rhythm == .fa)
                    .opacity(report.rhythm == .fa ? 0.4 : 1)
                    .help(report.rhythm == .fa ? "BAV non applicable en FA" : "")
                Spacer()
            }
            if report.bavOn {
                ChoiceRow(options: BAVType.allCases, selection: $report.bav, label: \.rawValue) { b in
                    PreviewCard(title: b.phrase, text: b.info, traces: [Strips.bav(b)])
                }
            }
        }
    }

    private var qrsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HoverPreview {
                Chip(title: report.qrs == .fins ? "QRS fins normaux" : "QRS anormaux", selected: true,
                     tint: report.qrs == .fins ? .accentColor : .orange) {
                    report.qrs = report.qrs == .fins ? nil : .fins
                }
            } preview: { qrsCard(.fins) }
            if report.qrs != .fins {
                ChoiceRow(options: QRSType.allCases.filter { $0 != .fins },
                          selection: Binding(get: { report.qrs ?? .fins }, set: { report.qrs = $0 }),
                          label: \.rawValue) { qrsCard($0) }
            }
        }
    }

    private func qrsCard(_ q: QRSType) -> some View {
        PreviewCard(title: q.phrase.capitalizedFirst, text: q.info, traces: Strips.qrs(q), pxPerMm: 5)
    }

    private let labelWidth: CGFloat = 58

    private func rowLabel(_ text: String) -> some View {
        Text(text + " :").font(.headline).frame(width: labelWidth, alignment: .leading)
    }

    private var hrRow: some View {
        HStack(spacing: 6) {
            rowLabel("FC")
            TextField("bpm", text: $report.manualHR)
                .frame(width: 60).textFieldStyle(.roundedBorder)
            Text("bpm")
            Spacer()
            if report.manualHRValue == nil {
                Text(report.heartRate.map { "≈ \(fmt($0)) bpm d'après le RR" } ?? "ou via le RR plus bas")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var measures: some View {
        section("Calcul QTc, FC et Sokolow") {
            HStack(spacing: 14) {
                mmField("QT", $report.qtMm, report.qtMs.map { "\(fmt($0)) ms" } ?? "")
                mmField("RR", $report.rrMm,
                        report.rrAllowed ? (report.measuredRR.map { "\(fmt($0)) ms" } ?? "") : "RSR seul")
                    .disabled(!report.rrAllowed)
            }
            HStack {
                if let v = report.framingham {
                    HoverPreview {
                        (Text("QTc Framingham ").foregroundStyle(.secondary)
                         + Text("\(fmt(v)) ms").bold().foregroundStyle(qtcColor(v))
                         + Text(" · \(report.qtcInterpretation(v))").font(.caption).foregroundStyle(qtcColor(v)))
                            .font(.callout)
                    } preview: { qtcNorms }
                } else if report.qtMs != nil {
                    Text("QTc : saisir la FC ou le RR.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 14) {
                mmField("SV1", $report.sv1Mm, "")
                mmField("RV5/V6", $report.rv5Mm, "")
            }
            if let s = report.sokolow {
                HoverPreview {
                    (Text("Sokolow-Lyon ").foregroundStyle(.secondary)
                     + Text("\(fmt(s)) mm").bold().foregroundStyle(s > 35 ? Color.orange : Color.green)
                     + Text(s > 35 ? " · HVG électrique" : " · pas d'HVG").font(.caption)
                        .foregroundStyle(s > 35 ? Color.orange : Color.green))
                        .font(.callout)
                } preview: { sokolowInfo }
            }
        }
    }

    /// Rappel affiché au survol de l'indice de Sokolow-Lyon
    private var sokolowInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Indice de Sokolow-Lyon").font(.subheadline.bold())
            Text("""
                 SV1 + RV5 (ou RV6, la plus grande) > 35 mm : HVG électrique.
                 Amplitudes en mm à l'étalonnage standard (10 mm = 1 mV).
                 Peu sensible ; souvent faussement positif chez le sujet jeune et mince.
                 """)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func mmField(_ name: String, _ text: Binding<String>, _ hint: String) -> some View {
        HStack(spacing: 4) {
            Text(name).bold()
            TextField("mm", text: text).frame(width: 50).textFieldStyle(.roundedBorder)
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize()
        }
    }

    /// Normes affichées au survol du QTc
    private var qtcNorms: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Valeurs usuelles du QTc").font(.subheadline.bold())
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow { Text("Homme"); Text("≤ 440 ms").bold() }
                GridRow { Text("Femme"); Text("≤ 450 ms").bold() }
                GridRow { Text("Risque majeur (torsades)"); Text("≥ 500 ms").bold().foregroundStyle(.red) }
                GridRow { Text("QT court"); Text("< 340 ms").bold().foregroundStyle(.orange) }
            }
            .font(.caption)
            Text("Framingham : QTc = QT + 154 × (1 − RR en s)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func qtcColor(_ v: Double) -> Color {
        if v >= 500 { return .red }
        if v > 440 || v < 340 { return .orange }
        return .green
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Compte rendu, modifiable avant de copier").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !report.extraFindings.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(.purple)
                    Text("Ajouté par Claude : \(report.extraFindings)")
                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    Button { report.extraFindings = "" } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("Retirer ces constatations du compte rendu")
                }
                .padding(6)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            TextEditor(text: $draft)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(height: 96)
                .padding(4)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .onAppear { draft = report.reportText }
                .onChange(of: report.reportText) { _, new in draft = new }
            HStack {
                Button(role: .destructive) { report.reset() } label: {
                    Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("r", modifiers: .command)
                .help("Tout remettre par défaut (⌘R)")
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copié !" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
    }

    // MARK: Briques

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func tCard(_ w: TWave) -> some View {
        PreviewCard(title: "Ondes T " + w.rawValue.lowercased(), text: w.info, traces: Strips.tWave(w), pxPerMm: 5)
    }

    /// Option facultative : grisée par défaut, colorée (orange par défaut) une fois sélectionnée
    private func optionChip(_ title: String, isOn: Binding<Bool>, tint: Color = .orange) -> some View {
        Chip(title: title, selected: isOn.wrappedValue, tint: tint) { isOn.wrappedValue.toggle() }
            .opacity(isOn.wrappedValue ? 1 : 0.5)
    }

}

// MARK: - Choix exclusif avec aperçu au survol (bulle flottante)

struct ChoiceRow<T: Hashable & Identifiable, Preview: View>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    @ViewBuilder let preview: (T) -> Preview

    @State private var hovered: T?
    @State private var pending: DispatchWorkItem?
    @State private var anchor = ViewRef()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { o in
                let selected = o == selection
                Button { selection = o } label: {
                    Text(label(o))
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(selected ? Color.accentColor : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover(o, inside: $0) }
            }
        }
        .background(AnchorView(ref: anchor))
        .onDisappear { if hovered != nil { HoverBubble.shared.hide() } }
    }

    /// Affiche la bulle après un court survol ; passe directement d'un bouton à l'autre ensuite
    private func hover(_ o: T, inside: Bool) {
        pending?.cancel()
        if inside, hovered != nil { setHovered(o); return }
        let item = DispatchWorkItem { setHovered(inside ? o : nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.4 : 0.15), execute: item)
        pending = item
    }

    private func setHovered(_ o: T?) {
        hovered = o
        if let o { HoverBubble.shared.show(preview(o), anchor: anchor.view) }
        else { HoverBubble.shared.hide() }
    }
}

// MARK: - Bouton à bascule

struct Chip: View {
    let title: String
    let selected: Bool
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .frame(minHeight: 26)
                .background(selected ? tint : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bouton ESA | ESV

/// Un seul bouton en deux moitiés : chaque clic passe à aucune → ESA → ESV → aucune
struct ExtrasystoleChip: View {
    @Binding var value: Extrasystole

    var body: some View {
        Button { value = value.next } label: {
            HStack(spacing: 0) {
                HoverPreview { half("ESA", on: value == .esa) } preview: {
                    PreviewCard(title: "Extrasystole atriale (ESA)",
                                text: """
                                • Battement prématuré précédé d'une onde P' de forme différente
                                • QRS fin, habituellement identique aux autres
                                • Repos non compensateur
                                """,
                                traces: Strips.esa())
                }
                Rectangle().fill(Color.primary.opacity(0.2)).frame(width: 1)
                HoverPreview { half("ESV", on: value == .esv) } preview: {
                    PreviewCard(title: "Extrasystole ventriculaire (ESV)",
                                text: """
                                • QRS prématuré, large (≥ 120 ms) et déformé, sans onde P
                                • Onde T opposée au QRS
                                • Repos compensateur
                                À préciser : fréquence, mono- ou polymorphes, doublets, bigéminisme.
                                """,
                                traces: Strips.esv())
                }
            }
            .frame(minHeight: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Clic : ESA → ESV → aucune")
    }

    private func half(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(.callout.weight(on ? .semibold : .regular))
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(on ? Color.orange : Color.secondary.opacity(0.12))
            .foregroundStyle(on ? Color.white : Color.primary)
            .opacity(on ? 1 : 0.5)
    }
}

// MARK: - Aperçu au survol d'un contrôle quelconque

struct HoverPreview<Content: View, Preview: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let preview: () -> Preview

    @State private var pending: DispatchWorkItem?
    @State private var anchor = ViewRef()

    var body: some View {
        content()
            .background(AnchorView(ref: anchor))
            .onHover { inside in
                guard Preview.self != EmptyView.self else { return }
                pending?.cancel()
                let item = DispatchWorkItem {
                    if inside { HoverBubble.shared.show(preview(), anchor: anchor.view) }
                    else { HoverBubble.shared.hide() }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.4 : 0.15), execute: item)
                pending = item
            }
    }
}

// MARK: - Sélection de dérivations

struct LeadPicker: View {
    @Binding var selection: Set<Lead>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
            ForEach(Lead.allCases) { lead in
                let on = selection.contains(lead)
                Button {
                    if on { selection.remove(lead) } else { selection.insert(lead) }
                } label: {
                    Text(lead.rawValue).font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(on ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
