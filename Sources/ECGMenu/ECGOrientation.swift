import CoreGraphics
import Vision

/// Sens de lecture de l'ECG, déduit de l'écriture (noms des dérivations, vitesse, étalonnage…)
enum ECGOrientation {
    /// Rotation horaire (0, 90, 180 ou 270) qui met le texte à l'endroit ; `confident` faux si trop peu de texte lisible.
    /// Vision lit le texte dans tous les sens : la direction de chaque ligne (de son début vers sa fin)
    /// indique comment l'image est tournée.
    static func uprightRotation(of image: CGImage) -> (rotation: Int, confident: Bool) {
        guard let small = downscaled(image, maxSide: 2000) else { return (0, false) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["fr-FR", "en-US"]
        try? VNImageRequestHandler(cgImage: small, orientation: .up).perform([request])

        // Votes pondérés par le nombre de caractères : sens de lecture → droite, bas, gauche, haut
        var votes = [0: 0.0, 90: 0.0, 180: 0.0, 270: 0.0]
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.5 else { continue }
            let weight = Double(candidate.string.filter { $0.isLetter || $0.isNumber }.count)
            guard weight >= 2 else { continue }
            // Coordonnées Vision : origine en bas à gauche, y vers le haut
            let dx = observation.topRight.x - observation.topLeft.x
            let dy = (observation.topRight.y - observation.topLeft.y) * CGFloat(small.height) / CGFloat(small.width)
            let rotation: Int
            if abs(dx) >= abs(dy) { rotation = dx > 0 ? 0 : 180 }       // à l'endroit / à l'envers
            else { rotation = dy < 0 ? 270 : 90 }                        // se lit vers le bas / vers le haut
            votes[rotation, default: 0] += weight
        }
        let sorted = votes.sorted { $0.value > $1.value }
        let total = votes.values.reduce(0, +)
        let confident = sorted[0].value >= 12 && sorted[0].value >= total * 0.7
        return (sorted[0].key, confident)
    }

    private static func downscaled(_ image: CGImage, maxSide: CGFloat) -> CGImage? {
        let scale = min(1, maxSide / CGFloat(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let w = Int(CGFloat(image.width) * scale), h = Int(CGFloat(image.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
