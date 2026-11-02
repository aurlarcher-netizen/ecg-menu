import AppKit
import Foundation
import Security

// MARK: - Clé API (Trousseau macOS)

enum APIKeyStore {
    private static let service = "local.ecgmenu"
    private static let account = "anthropic-api-key"

    private static var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    static func read() -> String? {
        var q = query
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var q = query
        q[kSecValueData] = Data(key.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Résultat de l'analyse

/// Lecture de l'ECG renvoyée par Claude, calquée sur les choix du formulaire
struct ECGAnalysis: Decodable {
    let paperSpeed: Int?
    let heartRate: Double?
    let axis: String
    let rhythm: String
    let bav: String
    let qrs: String
    let qWaveLeads: [String]
    let s1q3: Bool
    let deltaLeads: [String]
    let stUpLeads: [String]
    let stDownLeads: [String]
    let tNegativeLeads: [String]
    let tBiphasicLeads: [String]
    let tPeaked: Bool
    let uWave: Bool
    let extrasystole: String
    let qtMs: Double?
    let sv1Mm: Double?
    let rv5Mm: Double?
    let additionalFindings: String
    let detailedAnalysis: String
    let comment: String

    enum CodingKeys: String, CodingKey {
        case paperSpeed = "paper_speed", heartRate = "heart_rate", axis, rhythm, bav, qrs
        case qWaveLeads = "q_wave_leads", s1q3, deltaLeads = "delta_leads"
        case stUpLeads = "st_elevation_leads", stDownLeads = "st_depression_leads"
        case tNegativeLeads = "t_negative_leads", tBiphasicLeads = "t_biphasic_leads"
        case tPeaked = "t_peaked", uWave = "u_wave", extrasystole
        case qtMs = "qt_ms", sv1Mm = "sv1_mm", rv5Mm = "rv5_mm"
        case additionalFindings = "additional_findings", detailedAnalysis = "detailed_analysis", comment
    }
}

extension ECGReport {
    /// Remplace le formulaire par la lecture de Claude
    func apply(_ a: ECGAnalysis) {
        reset()
        func leads(_ names: [String]) -> Set<Lead> { Set(names.compactMap(Lead.init(rawValue:))) }

        if let speed = a.paperSpeed.flatMap(PaperSpeed.init(rawValue:)) { paperSpeed = speed }
        if let hr = a.heartRate, hr > 0 { manualHR = fmt(hr) }

        axis = Axis(rawValue: a.axis) ?? .indetermine
        rhythm = Rhythm(rawValue: a.rhythm) ?? .rsr
        if rhythm == .rsr, let type = BAVType(rawValue: a.bav) { bavOn = true; bav = type }

        qLeads = leads(a.qWaveLeads); qWave = !qLeads.isEmpty
        s1q3 = a.s1q3
        deltaLeads = leads(a.deltaLeads); delta = !deltaLeads.isEmpty
        qrs = QRSType(rawValue: a.qrs) ?? .fins

        stUpLeads = leads(a.stUpLeads); stUp = !stUpLeads.isEmpty
        stDownLeads = leads(a.stDownLeads); stDown = !stDownLeads.isEmpty
        noST = !stUp && !stDown

        tNegLeads = leads(a.tNegativeLeads); tNeg = !tNegLeads.isEmpty
        tBiphLeads = leads(a.tBiphasicLeads); tBiph = !tBiphLeads.isEmpty
        tPeaked = a.tPeaked
        tNormal = !tNeg && !tBiph && !tPeaked
        uWave = a.uWave
        extrasystole = a.extrasystole == "ESA" ? .esa : a.extrasystole == "ESV" ? .esv : .none

        // Le formulaire attend des mm de papier : QT converti selon la vitesse
        let mm: (Double) -> String = { String(format: "%.1f", $0).replacingOccurrences(of: ".0", with: "") }
        if let qt = a.qtMs, qt > 0 { qtMm = mm(qt / paperSpeed.msPerMm) }
        if let s = a.sv1Mm, let r = a.rv5Mm { sv1Mm = mm(s); rv5Mm = mm(r) }

        extraFindings = a.additionalFindings.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Appel à l'API Anthropic

enum ClaudeAnalyzerError: LocalizedError {
    case noKey, http(Int, String), refusal, truncated, badResponse

    var errorDescription: String? {
        switch self {
        case .noKey: return "Aucune clé API enregistrée."
        case .http(401, _): return "Clé API refusée (401) : vérifiez-la."
        case .http(let code, let message): return "Erreur de l'API (\(code)) : \(message)"
        case .refusal: return "Claude a refusé d'analyser cette image."
        case .truncated: return "Réponse incomplète, réessayez."
        case .badResponse: return "Réponse illisible."
        }
    }
}

enum ClaudeAnalyzer {
    static let model = "claude-sonnet-5-5"

    private static let prompt = """
    Voici un ECG 12 dérivations scanné. Lis-le comme un cardiologue et remplis le formulaire de compte rendu.

    Attention : l'ECG peut avoir été imprimé sur 2 feuilles de 6 dérivations (souvent DI à aVF d'un côté,
    V1 à V6 de l'autre), scannées ensemble ou l'une sous l'autre. Ces deux moitiés ne sont alors pas
    synchronisées : enregistrées à des moments différents, elles ne montrent pas les mêmes battements.
    Repère d'abord la disposition. Si les feuilles sont séparées, n'aligne pas les complexes d'une moitié sur
    l'autre, ne compare pas les battements entre elles, et mesure rythme, FC et intervalles dans chaque moitié
    séparément ; si elles diffèrent (FC, extrasystole présente d'un seul côté), dis-le dans detailed_analysis.
    Une feuille peut aussi manquer ou être coupée : ne déduis rien sur les dérivations absentes.

    Règles :
    - Vitesse du papier : lis-la sur le tracé si elle est imprimée (25 ou 50 mm/s), sinon null.
    - Fréquence cardiaque en bpm, mesurée sur le tracé ; null si impossible.
    - bav : "Aucun" si pas de BAV ; en FA, toujours "Aucun".
    - Pour chaque anomalie par dérivation, liste les dérivations concernées ; liste vide si absente.
      Les ondes T négatives isolées en aVR (et V1) sont normales : liste-les quand même si présentes.
    - qt_ms : intervalle QT en ms mesuré dans la dérivation où il est le plus long ; null si non mesurable.
    - sv1_mm et rv5_mm : amplitude de l'onde S en V1 et de l'onde R la plus grande en V5 ou V6, en mm
      (10 mm = 1 mV, vérifie l'étalonnage) ; null si non mesurable.
    - Ne devine pas : si un élément n'est pas lisible, garde la valeur normale et signale-le dans comment.
    - additional_findings : éléments cliniquement utiles que le formulaire ne permet pas de noter, rédigés
      comme la suite du compte rendu (phrases courtes terminées par un point, style médical, en français).
      Exemples : flutter atrial, rythme jonctionnel, électro-entraînement, hypertrophie atriale, microvoltage,
      PR court, alternance électrique, aspect de Brugada, repolarisation précoce, ESV polymorphes ou en salves.
      N'y répète rien de ce qui est déjà dans le formulaire. Chaîne vide s'il n'y a rien d'utile à ajouter :
      c'est le cas le plus fréquent, n'ajoute rien par principe.
    - detailed_analysis : lecture complète et argumentée de l'ECG pour le médecin, en français, une ligne par
      élément, au format « Élément : description », dans cet ordre : Rythme, Fréquence, Onde P, PR, QRS (durée,
      morphologie, amplitude), Axe, Ondes Q, ST, Onde T, QT/QTc, Autres, puis Conclusion (synthèse et
      principaux diagnostics à évoquer). Donne les valeurs mesurées (ms, mm, bpm) et les dérivations
      concernées. Décris aussi ce qui est normal. Sépare les lignes par un retour à la ligne, sans markdown.
    - comment : en français, 1 à 3 phrases courtes pour le médecin : qualité du tracé, étalonnage,
      éléments incertains ou non lisibles. Chaîne vide si rien à signaler.
    """

    private static var schema: [String: Any] {
        let leads: [String: Any] = ["type": "array", "items": ["type": "string", "enum": Lead.allCases.map(\.rawValue)]]
        let nullableNumber: [String: Any] = ["anyOf": [["type": "number"], ["type": "null"]]]
        let properties: [String: Any] = [
            "paper_speed": ["anyOf": [["type": "integer", "enum": [25, 50]], ["type": "null"]]],
            "heart_rate": nullableNumber,
            "axis": ["type": "string", "enum": Axis.allCases.map(\.rawValue)],
            "rhythm": ["type": "string", "enum": Rhythm.allCases.map(\.rawValue)],
            "bav": ["type": "string", "enum": ["Aucun"] + BAVType.allCases.map(\.rawValue)],
            "qrs": ["type": "string", "enum": QRSType.allCases.map(\.rawValue)],
            "q_wave_leads": leads,
            "s1q3": ["type": "boolean"],
            "delta_leads": leads,
            "st_elevation_leads": leads,
            "st_depression_leads": leads,
            "t_negative_leads": leads,
            "t_biphasic_leads": leads,
            "t_peaked": ["type": "boolean"],
            "u_wave": ["type": "boolean"],
            "extrasystole": ["type": "string", "enum": ["Aucune", "ESA", "ESV"]],
            "qt_ms": nullableNumber,
            "sv1_mm": nullableNumber,
            "rv5_mm": nullableNumber,
            "additional_findings": ["type": "string"],
            "detailed_analysis": ["type": "string"],
            "comment": ["type": "string"],
        ]
        return ["type": "object", "properties": properties,
                "required": Array(properties.keys), "additionalProperties": false]
    }

    /// Envoie l'image à Claude et renvoie sa lecture structurée
    static func analyze(_ image: CGImage) async throws -> ECGAnalysis {
        guard let key = APIKeyStore.read(), !key.isEmpty else { throw ClaudeAnalyzerError.noKey }
        guard let jpeg = jpegData(image) else { throw ClaudeAnalyzerError.badResponse }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            // En cas de refus par les filtres de sécurité, l'API réessaie sur le modèle de repli recommandé
            "fallbacks": "default",
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                                 "data": jpeg.base64EncodedString()]],
                    ["type": "text", "text": prompt],
                ],
            ]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let json else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "réponse inattendue"
            throw ClaudeAnalyzerError.http(status, message)
        }

        switch json["stop_reason"] as? String {
        case "refusal": throw ClaudeAnalyzerError.refusal
        case "max_tokens": throw ClaudeAnalyzerError.truncated
        default: break
        }
        // Le JSON demandé est dans le dernier bloc texte (les blocs de réflexion et de repli sont ignorés)
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let analysis = try? JSONDecoder().decode(ECGAnalysis.self, from: Data(text.utf8))
        else { throw ClaudeAnalyzerError.badResponse }
        return analysis
    }

    /// JPEG réduit à 2000 px de côté au plus, pour rester sous la limite de taille d'image de l'API
    private static func jpegData(_ image: CGImage) -> Data? {
        let maxSide: CGFloat = 2000
        let scale = min(1, maxSide / CGFloat(max(image.width, image.height)))
        let w = Int(CGFloat(image.width) * scale), h = Int(CGFloat(image.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}
