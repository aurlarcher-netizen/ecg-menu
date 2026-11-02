import SwiftUI

/// Affiche l'ECG et un cadre de rognage déplaçable, redimensionnable par ses 4 coins
struct CropEditor: View {
    @ObservedObject var doc: ECGImageDocument

    /// Cadre au début du geste en cours
    @State private var dragStart: CGRect?
    private let minSize: CGFloat = 0.05

    var body: some View {
        GeometryReader { geo in
            if let image = doc.image {
                let fit = fitRect(doc.pixelSize, in: geo.size)
                let frame = CGRect(x: fit.minX + doc.crop.minX * fit.width, y: fit.minY + doc.crop.minY * fit.height,
                                   width: doc.crop.width * fit.width, height: doc.crop.height * fit.height)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .offset(x: fit.minX, y: fit.minY)

                    // Zone hors cadre assombrie
                    Path { p in
                        p.addRect(fit)
                        p.addRect(frame)
                    }
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .gesture(moveGesture(fit))

                    ForEach(0..<4, id: \.self) { corner in
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                            .frame(width: 14, height: 14)
                            .position(cornerPoint(corner, of: frame))
                            .gesture(cornerGesture(corner, fit))
                    }
                }
            }
        }
    }

    // MARK: Géométrie

    private func fitRect(_ size: CGSize, in container: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(container.width / size.width, container.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    /// 0 = haut gauche, 1 = haut droit, 2 = bas droit, 3 = bas gauche
    private func cornerPoint(_ corner: Int, of r: CGRect) -> CGPoint {
        switch corner {
        case 0: return CGPoint(x: r.minX, y: r.minY)
        case 1: return CGPoint(x: r.maxX, y: r.minY)
        case 2: return CGPoint(x: r.maxX, y: r.maxY)
        default: return CGPoint(x: r.minX, y: r.maxY)
        }
    }

    // MARK: Gestes

    private func moveGesture(_ fit: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? doc.crop
                dragStart = start
                var r = start.offsetBy(dx: value.translation.width / fit.width, dy: value.translation.height / fit.height)
                r.origin.x = min(max(r.minX, 0), 1 - r.width)
                r.origin.y = min(max(r.minY, 0), 1 - r.height)
                doc.crop = r
            }
            .onEnded { _ in dragStart = nil }
    }

    private func cornerGesture(_ corner: Int, _ fit: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? doc.crop
                dragStart = start
                let dx = value.translation.width / fit.width, dy = value.translation.height / fit.height
                var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
                if corner == 0 || corner == 3 { minX = min(max(start.minX + dx, 0), maxX - minSize) }
                else { maxX = max(min(start.maxX + dx, 1), minX + minSize) }
                if corner == 0 || corner == 1 { minY = min(max(start.minY + dy, 0), maxY - minSize) }
                else { maxY = max(min(start.maxY + dy, 1), minY + minSize) }
                doc.crop = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in dragStart = nil }
    }
}
