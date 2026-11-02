import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Image d'ECG en cours de mise en forme : rotation et rognage
final class ECGImageDocument: ObservableObject {
    @Published private(set) var image: CGImage?
    /// Cadre de rognage, en coordonnées normalisées (0…1, origine en haut à gauche)
    @Published var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Image avant le cadrage automatique, pour pouvoir l'annuler
    @Published private(set) var beforeAutoFrame: CGImage?

    static let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    var pixelSize: CGSize { image.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
    var isCropped: Bool { crop != Self.fullFrame }

    // MARK: Chargement

    /// Charge une image (PNG, JPEG, TIFF…) ou la première page d'un PDF
    @discardableResult
    func load(_ url: URL) -> Bool {
        let loaded = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
            ? Self.renderPDF(url) : Self.loadImage(url)
        guard let loaded else { return false }
        image = loaded
        crop = Self.fullFrame
        beforeAutoFrame = nil
        return true
    }

    /// Retire l'image en cours (mauvais fichier, nouvel ECG)
    func clear() {
        image = nil
        crop = Self.fullFrame
        beforeAutoFrame = nil
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Applique l'orientation EXIF éventuelle (photos)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 8000,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Rend la première page d'un PDF à 300 dpi, dans son orientation d'affichage (pages paysage comprises)
    private static func renderPDF(_ url: URL) -> CGImage? {
        // Garder le document en mémoire : une page ne se dessine pas sans lui
        guard let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        // Page tournée de 90° (ECG paysage) : la page se dessine tournée, l'image doit donc l'être aussi
        let rotation = ((page.rotation % 360) + 360) % 360
        let size = rotation == 90 || rotation == 270 ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let scale: CGFloat = 300 / 72
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: ctx)
        return withExtendedLifetime(pdf) { ctx.makeImage() }
    }

    // MARK: Mise en forme

    /// Rotation de 90° (sens horaire ou anti-horaire) ; le cadre de rognage est réinitialisé
    func rotate(clockwise: Bool) {
        guard let image else { return }
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        if clockwise {
            ctx.translateBy(x: 0, y: CGFloat(w))
            ctx.rotate(by: -.pi / 2)
        } else {
            ctx.translateBy(x: CGFloat(h), y: 0)
            ctx.rotate(by: .pi / 2)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.image = ctx.makeImage()
        crop = Self.fullFrame
    }

    /// Met l'ECG en paysage s'il est en portrait
    func makeLandscape() {
        if pixelSize.height > pixelSize.width { rotate(clockwise: false) }
    }

    /// Image rognée selon le cadre courant
    var croppedImage: CGImage? {
        guard let image else { return nil }
        let rect = CGRect(x: crop.minX * CGFloat(image.width), y: crop.minY * CGFloat(image.height),
                          width: crop.width * CGFloat(image.width), height: crop.height * CGFloat(image.height)).integral
        return image.cropping(to: rect)
    }

    /// Applique définitivement le rognage
    func applyCrop() {
        guard isCropped, let cropped = croppedImage else { return }
        image = cropped
        crop = Self.fullFrame
    }

    /// Cadrage proposé par Claude. `sentCrop` : cadre de rognage au moment de l'envoi, car Claude a reçu
    /// l'image déjà rognée et donne ses coordonnées dans celle-ci. Renvoie false si rien n'a changé.
    @discardableResult
    func applyAutoFrame(_ frame: CGRect, rotation: Int, sentCrop: CGRect) -> Bool {
        guard let original = image else { return false }
        crop = sentCrop
        applyCrop()

        // Petite marge, bornée à l'image ; un cadre trop petit (mal placé) ou quasi complet est ignoré
        let margin = 0.01
        let minX = max(0, frame.minX - margin), minY = max(0, frame.minY - margin)
        let box = CGRect(x: minX, y: minY, width: min(1, frame.maxX + margin) - minX, height: min(1, frame.maxY + margin) - minY)
        var changed = sentCrop != Self.fullFrame
        if box.width >= 0.3, box.height >= 0.3, box.width * box.height < 0.97 {
            crop = box
            applyCrop()
            changed = true
        }
        switch rotation {
        case 90: rotate(clockwise: true); changed = true
        case 180: rotate(clockwise: true); rotate(clockwise: true); changed = true
        case 270: rotate(clockwise: false); changed = true
        default: break
        }
        beforeAutoFrame = changed ? original : nil
        return changed
    }

    func undoAutoFrame() {
        guard let previous = beforeAutoFrame else { return }
        image = previous
        crop = Self.fullFrame
        beforeAutoFrame = nil
    }

    // MARK: Export

    /// PNG de l'image mise en forme (rognage compris)
    var pngData: Data? {
        guard let cg = croppedImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
