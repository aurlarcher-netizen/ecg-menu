import Foundation

// MARK: - Choix

enum PaperSpeed: Int, CaseIterable, Identifiable {
    case s25 = 25, s50 = 50
    var id: Int { rawValue }
    var label: String { "\(rawValue) mm/s" }
    /// Durée représentée par 1 mm de papier
    var msPerMm: Double { 1000.0 / Double(rawValue) }
}

enum Rhythm: String, CaseIterable, Identifiable {
    case rsr = "RSR", fa = "FA"
    var id: String { rawValue }

    var info: String {
        switch self {
        case .rsr: return "Une onde P avant chaque QRS, PR constant (120–200 ms), RR réguliers."
        case .fa: return "Pas d'onde P, trémulations de la ligne de base, RR irrégulièrement irréguliers."
        }
    }
}

enum BAVType: String, CaseIterable, Identifiable {
    case bav1 = "BAV 1", mobitz1 = "Mobitz I", mobitz2 = "Mobitz II", bav21 = "BAV 2:1", bav3 = "BAV 3"
    var id: String { rawValue }

    var phrase: String {
        switch self {
        case .bav1: return "BAV du 1er degré"
        case .mobitz1: return "BAV du 2e degré Mobitz I (Luciani-Wenckebach)"
        case .mobitz2: return "BAV du 2e degré Mobitz II"
        case .bav21: return "BAV du 2e degré 2:1"
        case .bav3: return "BAV complet (3e degré)"
        }
    }

    var info: String {
        switch self {
        case .bav1: return "PR > 200 ms, constant. Chaque P est suivie d'un QRS."
        case .mobitz1: return "Allongement progressif du PR jusqu'à une P bloquée."
        case .mobitz2: return "PR constant puis P bloquée brutalement, sans allongement préalable."
        case .bav21: return "Une P sur deux est conduite : Mobitz I ou II non distinguable."
        case .bav3: return "Dissociation AV complète : P et QRS indépendants, échappement lent."
        }
    }
}

enum QRSType: String, CaseIterable, Identifiable {
    case fins = "Fins normaux", bbdi = "BBDi", bbgi = "BBGi", bbd = "BBD", bbg = "BBG"
    var id: String { rawValue }

    var phrase: String {
        switch self {
        case .fins: return "QRS fins"
        case .bbdi: return "bloc de branche droit incomplet"
        case .bbgi: return "bloc de branche gauche incomplet"
        case .bbd: return "bloc de branche droit complet"
        case .bbg: return "bloc de branche gauche complet"
        }
    }

    var info: String {
        switch self {
        case .fins: return "QRS < 120 ms."
        case .bbdi: return "QRS 110–119 ms. rSr' en V1."
        case .bbgi: return "QRS 110–119 ms. Disparition de l'onde q en V5-V6."
        case .bbd: return "QRS ≥ 120 ms. rsR' en V1 (aspect en M), S large en DI/V6."
        case .bbg: return "QRS ≥ 120 ms. QS en V1, R large crocheté en V6, T discordante."
        }
    }
}

enum Axis: String, CaseIterable, Identifiable {
    case normal = "Normal", gauche = "Gauche", hyperGauche = "Hypergauche"
    case droit = "Droit", hyperDroit = "Hyperdroit", indetermine = "Indéterminé"
    var id: String { rawValue }

    var phrase: String { "axe " + rawValue.lowercased() }

    /// Angle représentatif pour l'illustration (degrés, convention ECG : +90° en bas)
    var angle: Double {
        switch self {
        case .normal: return 60
        case .gauche: return -15
        case .hyperGauche: return -60
        case .droit: return 105
        case .hyperDroit: return 150
        case .indetermine: return -135
        }
    }

    var info: String {
        switch self {
        case .normal: return "0° à +90°. QRS positifs en DI et aVF."
        case .gauche: return "0° à -30°. DI positif, aVF négatif, DII encore positif."
        case .hyperGauche: return "Au-delà de -30°. DI positif, DII et aVF négatifs (HBAG ?)."
        case .droit: return "+90° à +120°. DI négatif, aVF positif."
        case .hyperDroit: return "Au-delà de +120°. DI très négatif (HBPG, cœur droit ?)."
        case .indetermine: return "-90° à ±180°. DI et aVF négatifs."
        }
    }
}

enum TWave: String, CaseIterable, Identifiable {
    case normales = "Normales", negatives = "Négatives", biphasiques = "Biphasiques", amples = "Amples et pointues"
    var id: String { rawValue }

    var info: String {
        switch self {
        case .normales: return "Positives, asymétriques. T négative normale en aVR et V1."
        case .negatives: return "Inversées, souvent symétriques : ischémie sous-épicardique, HVG, séquelle…"
        case .biphasiques: return "Composante positive puis négative (ou l'inverse)."
        case .amples: return "Grandes, pointues, symétriques, base étroite : hyperkaliémie, ischémie hyperaiguë."
        }
    }
}

/// Extrasystoles : un clic fait défiler aucune → ESA → ESV → aucune
enum Extrasystole {
    case none, esa, esv

    var next: Extrasystole {
        switch self {
        case .none: return .esa
        case .esa: return .esv
        case .esv: return .none
        }
    }
}

// MARK: - Dérivations

enum Lead: String, CaseIterable, Identifiable {
    case DI, DII, DIII, aVR, aVL, aVF
    case V1, V2, V3, V4, V5, V6
    var id: String { rawValue }
}

struct Territory {
    let name: String
    let leads: [Lead]

    static let all: [Territory] = [
        Territory(name: "antéro-septal", leads: [.V1, .V2, .V3]),
        Territory(name: "apical", leads: [.V4]),
        Territory(name: "latéral haut", leads: [.DI, .aVL]),
        Territory(name: "latéral bas", leads: [.V5, .V6]),
        Territory(name: "inférieur", leads: [.DII, .DIII, .aVF]),
    ]

    /// Nom des territoires concernés par un ensemble de dérivations (aVR exclu)
    static func describe(_ leads: Set<Lead>) -> String {
        var names = all.filter { !Set($0.leads).isDisjoint(with: leads) }.map(\.name)
        if names.contains("antéro-septal") && names.contains("apical") {
            let extended = names.contains("latéral bas")
            let merged = extended ? ["antéro-septal", "apical", "latéral bas"] : ["antéro-septal", "apical"]
            names.removeAll { merged.contains($0) }
            names.insert(extended ? "antérieur étendu" : "antérieur", at: 0)
        }
        return names.joined(separator: " et ")
    }
}

// MARK: - Utilitaires

func parseNumber(_ s: String) -> Double? {
    Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
}

func fmt(_ v: Double) -> String { String(Int(v.rounded())) }

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
