import SwiftUI

// MARK: - Tracé synthétique (somme de gaussiennes)

/// Une déflexion : centre (ms), amplitude (mV), largeur sigma (ms)
struct Bump {
    let c: Double, a: Double, w: Double
}

struct Trace {
    var label: String
    var duration: Double            // ms
    var yMin: Double = -0.6         // mV
    var yMax: Double = 1.4
    var bumps: [Bump]
    var baseline: ((Double) -> Double)? = nil

    func value(at t: Double) -> Double {
        var v = baseline?(t) ?? 0
        for b in bumps where abs(t - b.c) < 4 * b.w {
            let x = (t - b.c) / b.w
            v += b.a * exp(-x * x / 2)
        }
        return v
    }
}

// MARK: - Bibliothèque de tracés

enum Strips {
    static func p(_ t: Double) -> [Bump] { [Bump(c: t, a: 0.15, w: 20)] }

    /// QRS fin + onde T, t = pic de R
    static func beat(_ t: Double) -> [Bump] {
        [Bump(c: t - 22, a: -0.1, w: 6), Bump(c: t, a: 1.1, w: 9),
         Bump(c: t + 24, a: -0.25, w: 8), Bump(c: t + 280, a: 0.3, w: 40)]
    }

    /// QRS large d'échappement ventriculaire
    static func wideBeat(_ t: Double) -> [Bump] {
        [Bump(c: t, a: 0.8, w: 24), Bump(c: t + 65, a: -0.4, w: 24), Bump(c: t + 360, a: -0.35, w: 55)]
    }

    /// Rythme : P à intervalle fixe, PR par battement (nil = P bloquée)
    static func conducted(start: Double, pp: Double, prs: [Double?], count: Int) -> [Bump] {
        (0..<count).flatMap { i -> [Bump] in
            let tp = start + Double(i) * pp
            guard let pr = prs[i % prs.count] else { return p(tp) }
            return p(tp) + beat(tp + pr + 30)
        }
    }

    static func rhythm(_ r: Rhythm) -> Trace {
        switch r {
        case .rsr:
            return Trace(label: "DII", duration: 3000,
                         bumps: conducted(start: 150, pp: 800, prs: [160], count: 4))
        case .fa:
            let rs: [Double] = [250, 780, 1130, 1830, 2280, 2700]
            return Trace(label: "DII", duration: 3000, bumps: rs.flatMap(beat)) { t in
                0.05 * sin(t / 22) + 0.035 * sin(t / 15 + 1) + 0.025 * sin(t / 9 + 2)
            }
        }
    }

    static func bav(_ b: BAVType) -> Trace {
        let bumps: [Bump]
        var duration = 3000.0
        switch b {
        case .bav1: bumps = conducted(start: 100, pp: 900, prs: [320], count: 4)
        case .mobitz1:
            bumps = conducted(start: 60, pp: 740, prs: [160, 240, 300, nil], count: 5); duration = 3400
        case .mobitz2:
            bumps = conducted(start: 60, pp: 740, prs: [180, 180, 180, nil], count: 5); duration = 3400
        case .bav21:
            bumps = conducted(start: 100, pp: 700, prs: [180, nil], count: 5); duration = 3200
        case .bav3:
            let ps = stride(from: 120.0, to: 3000, by: 620).flatMap(p)
            let qrs = stride(from: 480.0, to: 3000, by: 1500).flatMap(wideBeat)
            bumps = ps + qrs
        }
        return Trace(label: "DII", duration: duration, bumps: bumps)
    }

    /// Complexes en DI, DII, aVF : la polarité suit la projection de l'axe sur chaque dérivation
    static func axis(_ a: Axis) -> [Trace] {
        [("DI", 0.0), ("DII", 60.0), ("aVF", 90.0)].map { name, leadAngle in
            let net = cos((a.angle - leadAngle) * .pi / 180)
            return Trace(label: name, duration: 600, yMin: -1.3, yMax: 1.3, bumps: [
                Bump(c: 70, a: 0.12, w: 18),
                Bump(c: 220, a: 0.12 + 0.5 * (1 + net), w: 9),
                Bump(c: 250, a: -(0.12 + 0.5 * (1 - net)), w: 9),
                Bump(c: 470, a: 0.05 + 0.2 * net, w: 40),
            ])
        }
    }

    /// Complexe QRS fin suivi d'une onde T (et éventuellement U) paramétrable
    static func tComplex(_ name: String, qrsSign: Double = 1, t: [Bump], u: Bool = false) -> Trace {
        Trace(label: name, duration: 700, yMin: -1.3, yMax: 1.3, bumps: [
            Bump(c: 70, a: 0.12 * qrsSign, w: 18),
            Bump(c: 205, a: -0.1 * qrsSign, w: 5),
            Bump(c: 225, a: 1.0 * qrsSign, w: 9),
            Bump(c: 250, a: -0.2 * qrsSign, w: 7),
        ] + t + (u ? [Bump(c: 610, a: 0.12, w: 25)] : []))
    }

    static func tWave(_ w: TWave) -> [Trace] {
        switch w {
        case .normales:
            // T asymétrique : montée lente, descente rapide
            let normal = [Bump(c: 450, a: 0.22, w: 45), Bump(c: 490, a: 0.15, w: 25)]
            return [tComplex("V5", t: normal),
                    Trace(label: "V1", duration: 700, yMin: -1.3, yMax: 1.3, bumps: [
                        Bump(c: 70, a: 0.1, w: 18), Bump(c: 210, a: 0.25, w: 7),
                        Bump(c: 240, a: -0.9, w: 10), Bump(c: 470, a: -0.15, w: 40)]),
                    tComplex("aVR", qrsSign: -1, t: [Bump(c: 470, a: -0.3, w: 40)])]
        case .negatives:
            return [tComplex("V5", t: [Bump(c: 480, a: -0.45, w: 38)])]
        case .biphasiques:
            return [tComplex("V2", t: [Bump(c: 430, a: 0.25, w: 28), Bump(c: 530, a: -0.35, w: 32)])]
        case .amples:
            return [tComplex("V3", t: [Bump(c: 450, a: 1.0, w: 26)])]
        }
    }

    /// q normale (fine, peu profonde) face à une Q de nécrose (large, profonde)
    static func qWave() -> [Trace] {
        [Trace(label: "q normale", duration: 700, yMin: -1.3, yMax: 1.3, bumps: [
            Bump(c: 70, a: 0.12, w: 18), Bump(c: 205, a: -0.12, w: 5), Bump(c: 228, a: 1.1, w: 9),
            Bump(c: 252, a: -0.15, w: 7), Bump(c: 470, a: 0.3, w: 40)]),
         Trace(label: "Q pathologique", duration: 700, yMin: -1.3, yMax: 1.3, bumps: [
            Bump(c: 70, a: 0.12, w: 18), Bump(c: 225, a: -0.75, w: 14), Bump(c: 272, a: 0.45, w: 9),
            Bump(c: 480, a: -0.3, w: 40)])]
    }

    /// ST isoélectrique, sus-décalage convexe, sous-décalage horizontal
    static func st() -> [Trace] {
        func complex(_ label: String, _ extra: [Bump]) -> Trace {
            Trace(label: label, duration: 700, yMin: -1.0, yMax: 1.6, bumps: [
                Bump(c: 70, a: 0.12, w: 18), Bump(c: 205, a: -0.1, w: 5),
                Bump(c: 225, a: 1.1, w: 9), Bump(c: 250, a: -0.2, w: 7)] + extra)
        }
        return [complex("Normal", [Bump(c: 470, a: 0.3, w: 40)]),
                complex("Sus-décalage", [Bump(c: 330, a: 0.3, w: 55), Bump(c: 440, a: 0.4, w: 50)]),
                complex("Sous-décalage", [Bump(c: 320, a: -0.18, w: 45), Bump(c: 490, a: 0.15, w: 35)])]
    }

    /// Complexe normal face à une pré-excitation : PR court et empâtement initial du QRS
    static func delta() -> [Trace] {
        [Trace(label: "Normal", duration: 700, yMin: -1.0, yMax: 1.6, bumps: [
            Bump(c: 70, a: 0.12, w: 18), Bump(c: 205, a: -0.1, w: 5), Bump(c: 225, a: 1.1, w: 9),
            Bump(c: 250, a: -0.2, w: 7), Bump(c: 470, a: 0.3, w: 40)]),
         Trace(label: "Onde delta", duration: 700, yMin: -1.0, yMax: 1.6, bumps: [
            Bump(c: 60, a: 0.12, w: 16),
            // rampe lente (delta) fondue dans le R
            Bump(c: 145, a: 0.15, w: 20), Bump(c: 170, a: 0.3, w: 18), Bump(c: 200, a: 0.9, w: 12),
            Bump(c: 235, a: -0.15, w: 8), Bump(c: 460, a: -0.15, w: 40)])]
    }

    /// S profonde en DI, Q et T négative en DIII
    static func s1q3() -> [Trace] {
        [Trace(label: "DI", duration: 700, yMin: -1.3, yMax: 1.3, bumps: [
            Bump(c: 70, a: 0.12, w: 18), Bump(c: 220, a: 0.4, w: 8), Bump(c: 250, a: -0.75, w: 12),
            Bump(c: 470, a: 0.2, w: 40)]),
         Trace(label: "DIII", duration: 700, yMin: -1.3, yMax: 1.3, bumps: [
            Bump(c: 70, a: 0.1, w: 18), Bump(c: 215, a: -0.5, w: 10), Bump(c: 250, a: 0.55, w: 9),
            Bump(c: 470, a: -0.3, w: 40)])]
    }

    /// ESA : P' prématurée, QRS fin, repos non compensateur
    static func esa() -> [Trace] {
        let early: [Bump] = [Bump(c: 1620, a: -0.12, w: 14)] + beat(1620 + 160 + 30)
        let bumps = conducted(start: 100, pp: 900, prs: [160], count: 2) + early
            + conducted(start: 2520, pp: 900, prs: [160], count: 1)
        return [Trace(label: "DII", duration: 3200, bumps: bumps)]
    }

    /// ESV : QRS prématuré large sans P, T opposée, repos compensateur
    static func esv() -> [Trace] {
        let bumps = conducted(start: 100, pp: 750, prs: [160], count: 2)
            + [Bump(c: 1500, a: 1.0, w: 26), Bump(c: 1570, a: -0.35, w: 26), Bump(c: 1850, a: -0.4, w: 55)]
            + conducted(start: 2350, pp: 750, prs: [160], count: 1)
        return [Trace(label: "DII", duration: 3200, bumps: bumps)]
    }

    static func uWave() -> [Trace] {
        [tComplex("V2", t: [Bump(c: 450, a: 0.3, w: 38)], u: true)]
    }

    /// Complexes V1 et V6 pour chaque aspect de QRS
    static func qrs(_ q: QRSType) -> [Trace] {
        let pw = Bump(c: 70, a: 0.12, w: 18)
        func lead(_ name: String, _ b: [Bump]) -> Trace {
            Trace(label: name, duration: 700, yMin: -1.3, yMax: 1.3, bumps: [pw] + b)
        }
        switch q {
        case .fins:
            return [lead("V1", [Bump(c: 210, a: 0.25, w: 7), Bump(c: 240, a: -0.9, w: 10), Bump(c: 480, a: 0.2, w: 40)]),
                    lead("V6", [Bump(c: 205, a: -0.1, w: 5), Bump(c: 225, a: 1.1, w: 9), Bump(c: 250, a: -0.2, w: 7), Bump(c: 480, a: 0.35, w: 40)])]
        case .bbdi:
            return [lead("V1", [Bump(c: 210, a: 0.3, w: 7), Bump(c: 238, a: -0.55, w: 9), Bump(c: 272, a: 0.45, w: 10), Bump(c: 490, a: 0.1, w: 40)]),
                    lead("V6", [Bump(c: 205, a: -0.1, w: 5), Bump(c: 225, a: 1.0, w: 9), Bump(c: 262, a: -0.3, w: 12), Bump(c: 490, a: 0.3, w: 40)])]
        case .bbd:
            return [lead("V1", [Bump(c: 212, a: 0.35, w: 9), Bump(c: 245, a: -0.4, w: 10), Bump(c: 295, a: 0.95, w: 18), Bump(c: 510, a: -0.3, w: 45)]),
                    lead("V6", [Bump(c: 205, a: -0.1, w: 5), Bump(c: 228, a: 1.0, w: 10), Bump(c: 285, a: -0.4, w: 25), Bump(c: 510, a: 0.3, w: 45)])]
        case .bbgi:
            return [lead("V1", [Bump(c: 212, a: 0.15, w: 8), Bump(c: 252, a: -1.0, w: 14), Bump(c: 490, a: 0.3, w: 40)]),
                    lead("V6", [Bump(c: 240, a: 1.0, w: 16), Bump(c: 490, a: 0.2, w: 40)])]
        case .bbg:
            return [lead("V1", [Bump(c: 205, a: 0.05, w: 6), Bump(c: 265, a: -1.1, w: 28), Bump(c: 530, a: 0.4, w: 50)]),
                    lead("V6", [Bump(c: 235, a: 0.8, w: 16), Bump(c: 290, a: 0.85, w: 16), Bump(c: 540, a: -0.35, w: 50)])]
        }
    }
}

// MARK: - Rendu sur papier millimétré

struct StripView: View {
    let trace: Trace
    var pxPerMm: CGFloat = 4

    var body: some View {
        let widthMm = trace.duration / 40           // 25 mm/s
        let heightMm = (trace.yMax - trace.yMin) * 10  // 10 mm/mV
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 1, green: 0.97, blue: 0.96)))
            var small = Path(), big = Path()
            for i in 0...Int(widthMm) {
                let x = CGFloat(i) * pxPerMm
                if i % 5 == 0 { big.move(to: .init(x: x, y: 0)); big.addLine(to: .init(x: x, y: size.height)) }
                else { small.move(to: .init(x: x, y: 0)); small.addLine(to: .init(x: x, y: size.height)) }
            }
            for j in 0...Int(heightMm) {
                let y = CGFloat(j) * pxPerMm
                if j % 5 == 0 { big.move(to: .init(x: 0, y: y)); big.addLine(to: .init(x: size.width, y: y)) }
                else { small.move(to: .init(x: 0, y: y)); small.addLine(to: .init(x: size.width, y: y)) }
            }
            ctx.stroke(small, with: .color(.red.opacity(0.12)), lineWidth: 0.5)
            ctx.stroke(big, with: .color(.red.opacity(0.3)), lineWidth: 0.8)

            var path = Path()
            for t in stride(from: 0.0, through: trace.duration, by: 2) {
                let pt = CGPoint(x: CGFloat(t / 40) * pxPerMm,
                                 y: CGFloat((trace.yMax - trace.value(at: t)) * 10) * pxPerMm)
                if t == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
        .frame(width: CGFloat(widthMm) * pxPerMm, height: CGFloat(heightMm) * pxPerMm)
        .overlay(alignment: .topLeading) {
            Text(trace.label).font(.caption2.bold()).foregroundStyle(.black.opacity(0.7)).padding(3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Carte d'aperçu : tracé(s) + texte court
struct PreviewCard: View {
    let title: String
    let text: String
    let traces: [Trace]
    var pxPerMm: CGFloat = 4
    var axisAngle: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            HStack(spacing: 8) {
                if let axisAngle { AxisDial(angle: axisAngle) }
                ForEach(traces.indices, id: \.self) { StripView(trace: traces[$0], pxPerMm: pxPerMm) }
            }
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Cadran de l'axe (système hexaxial simplifié : DI à 0°, aVF à +90° vers le bas)
struct AxisDial: View {
    let angle: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 18
            func point(_ deg: Double, _ radius: CGFloat) -> CGPoint {
                CGPoint(x: c.x + radius * CGFloat(cos(deg * .pi / 180)),
                        y: c.y + radius * CGFloat(sin(deg * .pi / 180)))
            }
            // Secteur normal 0° → +90°
            var sector = Path()
            sector.move(to: c)
            sector.addArc(center: c, radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            sector.closeSubpath()
            ctx.fill(sector, with: .color(.green.opacity(0.18)))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.secondary), lineWidth: 1)
            var axes = Path()
            for deg in [0.0, 90, 180, 270] { axes.move(to: c); axes.addLine(to: point(deg, r)) }
            ctx.stroke(axes, with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))

            for (text, deg) in [("0°", 0.0), ("+90°", 90), ("±180°", 180), ("-90°", 270)] {
                ctx.draw(Text(text).font(.system(size: 8)).foregroundColor(.secondary), at: point(deg, r + 10))
            }

            // Flèche de l'axe
            let tip = point(angle, r - 2)
            var arrow = Path()
            arrow.move(to: c); arrow.addLine(to: tip)
            arrow.move(to: tip); arrow.addLine(to: point(angle - 160, 9).offset(tip, from: c))
            arrow.move(to: tip); arrow.addLine(to: point(angle + 160, 9).offset(tip, from: c))
            ctx.stroke(arrow, with: .color(.red), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 150, height: 130)
    }
}

private extension CGPoint {
    /// Déplace un point calculé autour de `from` pour qu'il soit relatif à `tip`
    func offset(_ tip: CGPoint, from c: CGPoint) -> CGPoint {
        CGPoint(x: tip.x + (x - c.x), y: tip.y + (y - c.y))
    }
}
