import Foundation
import SwiftUI

final class ECGReport: ObservableObject {
    @AppStorage("paperSpeed") var paperSpeedRaw: Int = PaperSpeed.s25.rawValue

    @Published var manualHR = ""          // bpm saisis à la main
    /// nil = axe non normal, pas encore précisé
    @Published var axis: Axis? = .normal
    @Published var rhythm: Rhythm = .rsr {
        didSet { if rhythm == .fa { bavOn = false } }   // pas de BAV coché en FA
    }
    @Published var bavOn = false
    @Published var bav: BAVType = .bav1

    @Published var qWave = false
    @Published var qLeads: Set<Lead> = []
    @Published var s1q3 = false
    @Published var delta = false
    @Published var deltaLeads: Set<Lead> = []
    /// nil = QRS non normaux, aspect pas encore précisé
    @Published var qrs: QRSType? = .fins

    @Published var noST = true
    @Published var stUp = false
    @Published var stUpLeads: Set<Lead> = []
    @Published var stDown = false
    @Published var stDownLeads: Set<Lead> = []

    @Published var tNormal = true
    @Published var tNeg = false
    @Published var tNegLeads: Set<Lead> = []
    @Published var tBiph = false
    @Published var tBiphLeads: Set<Lead> = []
    @Published var tPeaked = false
    @Published var uWave = false
    @Published var extrasystole: Extrasystole = .none

    // Indice de Sokolow-Lyon (amplitudes en mm, 10 mm = 1 mV)
    @Published var sv1Mm = ""
    @Published var rv5Mm = ""

    // Mesures en mm sur le papier
    @Published var rrMm = ""              // accepté uniquement en RSR
    @Published var qtMm = ""

    /// Constatations ajoutées par l'analyse de Claude, hors formulaire
    @Published var extraFindings = ""

    var paperSpeed: PaperSpeed {
        get { PaperSpeed(rawValue: paperSpeedRaw) ?? .s25 }
        set { objectWillChange.send(); paperSpeedRaw = newValue.rawValue }
    }

    func reset() {
        manualHR = ""; axis = .normal; rhythm = .rsr; bavOn = false; bav = .bav1
        qWave = false; qLeads = []; s1q3 = false; delta = false; deltaLeads = []
        qrs = .fins
        noST = true; stUp = false; stUpLeads = []; stDown = false; stDownLeads = []
        tNormal = true; tNeg = false; tNegLeads = []; tBiph = false; tBiphLeads = []; tPeaked = false
        uWave = false
        extrasystole = .none
        sv1Mm = ""; rv5Mm = ""
        rrMm = ""; qtMm = ""
        extraFindings = ""
    }

    // MARK: Mesures

    private func ms(_ mm: String) -> Double? {
        guard let v = parseNumber(mm), v > 0 else { return nil }
        return v * paperSpeed.msPerMm
    }

    /// RR mesurable seulement en rythme sinusal régulier (BAV 1 compris)
    var rrAllowed: Bool { rhythm == .rsr && (!bavOn || bav == .bav1) }
    var measuredRR: Double? { rrAllowed ? ms(rrMm) : nil }
    var qtMs: Double? { ms(qtMm) }
    var manualHRValue: Double? { parseNumber(manualHR).flatMap { $0 > 0 ? $0 : nil } }

    /// FC saisie à la main, sinon déduite du RR (RSR uniquement)
    var heartRate: Double? {
        if let hr = manualHRValue { return hr }
        return measuredRR.map { 60000 / $0 }
    }

    /// RR pour le QTc : mesuré si possible, sinon déduit de la FC
    var rrForQTc: Double? { measuredRR ?? heartRate.map { 60000 / $0 } }

    /// QTc de Framingham : QT + 154 × (1 − RR), RR en secondes
    /// SV1 + RV5/V6 (mm) ; HVG électrique si > 35 mm
    var sokolow: Double? {
        guard let s = parseNumber(sv1Mm), let r = parseNumber(rv5Mm) else { return nil }
        return s + r
    }

    var framingham: Double? {
        guard let qt = qtMs, let rr = rrForQTc else { return nil }
        return qt + 154 * (1 - rr / 1000)
    }

    func qtcInterpretation(_ value: Double) -> String {
        if value >= 500 { return "allongement majeur (≥ 500 ms)" }
        if value > 450 { return "allongé (> 450 ms)" }
        if value > 440 { return "limite (allongé chez l'homme)" }
        if value < 340 { return "court (< 340 ms)" }
        return "normal"
    }

    // MARK: Compte rendu

    private func leadList(_ leads: Set<Lead>, territory withTerritory: Bool = true) -> String {
        guard !leads.isEmpty else { return "" }
        var s = " en " + Lead.allCases.filter(leads.contains).map(\.rawValue).joined(separator: ", ")
        let territory = Territory.describe(leads)
        if withTerritory && !territory.isEmpty { s += " (territoire \(territory))" }
        return s
    }

    var reportText: String {
        var parts: [String] = []

        // Ordre : axe, rythme + FC, onde Q, S1Q3, onde delta, QRS, ST, onde T, onde U, QTc
        if let axis, axis != .indetermine { parts.append(axis.phrase.capitalizedFirst + ".") }

        // Rythme et FC
        var r: String
        switch rhythm {
        case .rsr where bavOn: r = "Rythme sinusal"
        case .rsr:
            if let hr = heartRate, hr < 60 { r = "Bradycardie sinusale" }
            else if let hr = heartRate, hr > 100 { r = "Tachycardie sinusale" }
            else { r = "Rythme sinusal régulier" }
        case .fa: r = "Fibrillation atriale"
        }
        if bavOn { r += " avec " + bav.phrase }
        if let hr = heartRate { r += " à \(fmt(hr)) bpm" }
        if rhythm == .rsr && !bavOn { r += ", pas de BAV" }   // en FA, le BAV n'est pas décrit
        parts.append(r + ".")

        parts.append(qWave ? "Ondes Q anormales" + leadList(qLeads) + "." : "Pas d'onde Q significative.")
        parts.append(s1q3 ? "Aspect S1Q3." : "Pas de S1Q3.")
        parts.append(delta ? "Onde delta" + leadList(deltaLeads, territory: false) + " (pré-excitation)." : "Pas d'onde delta.")
        if let qrs { parts.append(qrs.phrase.capitalizedFirst + ".") }

        var st: [String] = []
        if !noST && stUp {
            // Une seule dérivation : le préciser (« isolé »)
            st.append("sus-décalage du segment ST" + (stUpLeads.count == 1 ? " isolé" : "") + leadList(stUpLeads))
        }
        if !noST && stDown { st.append("sous-décalage du segment ST" + leadList(stDownLeads)) }
        if noST { parts.append("Pas de décalage du segment ST.") }
        else { parts.append(st.isEmpty ? "Décalage du segment ST." : st.joined(separator: " ; ").capitalizedFirst + ".") }

        var t: [String] = []
        if !tNormal {
            if tNeg {
                // T négatives limitées à V1 et/ou aVR : variante normale
                if !tNegLeads.isEmpty && tNegLeads.isSubset(of: [.V1, .aVR]) {
                    let leads = [Lead.V1, .aVR].filter(tNegLeads.contains).map(\.rawValue).joined(separator: " et ")
                    t.append("ondes T négatives en \(leads) (normal)")
                } else {
                    t.append("ondes T négatives" + leadList(tNegLeads))
                }
            }
            if tBiph { t.append("ondes T biphasiques" + leadList(tBiphLeads)) }
            if tPeaked { t.append("ondes T amples et pointues") }
        }
        if tNormal { parts.append("Ondes T normales.") }
        else { parts.append(t.isEmpty ? "Ondes T anormales." : t.joined(separator: " ; ").capitalizedFirst + ".") }
        if uWave { parts.append("Présence d'ondes U.") }
        switch extrasystole {
        case .esa: parts.append("Extrasystoles atriales.")
        case .esv: parts.append("Extrasystoles ventriculaires.")
        case .none: break
        }

        if let qt = qtMs, let qtc = framingham {
            parts.append("QT \(fmt(qt)) ms, QTc \(fmt(qtc)) ms (Framingham) : \(qtcInterpretation(qtc)).")
        }

        if let sok = sokolow {
            parts.append("Indice de Sokolow-Lyon à \(fmt(sok)) mm : " + (sok > 35 ? "HVG électrique." : "pas d'HVG électrique."))
        }

        if !extraFindings.isEmpty { parts.append(extraFindings) }

        return "ECG : " + parts.joined(separator: " ")
    }
}
