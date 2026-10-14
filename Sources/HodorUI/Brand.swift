import AppKit
import SwiftUI

/// Colors from the app icon: winter night, frost, the dev server's light and the coral doorstop.
extension Color {
    /// Night blue in light mode, frost in dark mode. Used as the tint for buttons and links.
    static let hodorNight = adaptive(light: 0x2C4F86, dark: 0xA9CBF0)
    /// The light through the open door. Marks running tunnels.
    static let hodorLight = adaptive(light: 0xF29A1F, dark: 0xFFB547)
    /// The doorstop. Used for errors.
    static let hodorWedge = adaptive(light: 0xD9442B, dark: 0xFF8A5C)

    fileprivate init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
            })
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Template images for the menu bar: a shut door, or the door held ajar by a wedge while a tunnel runs.
/// The paths match the 18×18 glyphs drawn for the icon.
public enum MenuBarIcon {
    public static func image(open: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)

            // Frame with rounded top corners, standing on a floor line.
            let frame = CGMutablePath()
            frame.move(to: CGPoint(x: 2.5, y: 15.5))
            frame.addArc(tangent1End: CGPoint(x: 2.5, y: 1.5), tangent2End: CGPoint(x: 4, y: 1.5), radius: 1.5)
            frame.addArc(tangent1End: CGPoint(x: 15.5, y: 1.5), tangent2End: CGPoint(x: 15.5, y: 3), radius: 1.5)
            for point in [(15.5, 15.5), (17, 15.5), (17, 17), (1, 17), (1, 15.5)] {
                frame.addLine(to: CGPoint(x: point.0, y: point.1))
            }
            frame.closeSubpath()
            frame.addRect(CGRect(x: 4, y: 3, width: 10, height: 12.5))

            if open {
                context.addPath(frame)
                context.fillPath(using: .evenOdd)
                // Door leaf swung toward the viewer, and the wedge in the gap.
                let leaf = CGMutablePath()
                leaf.addLines(between: [
                    CGPoint(x: 4, y: 4.6), CGPoint(x: 9.4, y: 3.8), CGPoint(x: 9.4, y: 15.5), CGPoint(x: 4, y: 15.5),
                ])
                leaf.closeSubpath()
                leaf.addLines(between: [CGPoint(x: 10.3, y: 15.5), CGPoint(x: 13, y: 15.5), CGPoint(x: 13, y: 12.1)])
                leaf.closeSubpath()
                context.addPath(leaf)
                context.fillPath()
            } else {
                // Shut door with the knob punched out.
                frame.addRect(CGRect(x: 5.5, y: 4.5, width: 7, height: 11))
                frame.addEllipse(in: CGRect(x: 9.7, y: 9.2, width: 1.8, height: 1.8))
                context.addPath(frame)
                context.fillPath(using: .evenOdd)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = open ? "Hodor, tunnels running" : "Hodor"
        return image
    }
}

/// The app icon drawn small for the menu header. Leaves out the snowflake, which is lost at this size.
struct HodorMark: View {
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvasSize in
            // Draw in the icon's 1024 grid, cropped to its 824 px body.
            let scale = canvasSize.width / 824
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -100, y: -100)

            let body = Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerRadius: 185, style: .continuous)
            context.clip(to: body)
            context.fill(body, with: gradient(0x2C4F86, 0x16244A, from: 100, to: 924))

            context.fill(
                polygon([(566, 770), (672, 770), (900, 924), (548, 924)]),
                with: .color(Color(hex: 0xFFC861).opacity(0.5)))
            context.fill(
                Path(roundedRect: CGRect(x: 320, y: 232, width: 384, height: 548), cornerRadius: 26),
                with: gradient(0xA9CBF0, 0x86ADDC, from: 232, to: 780))
            context.fill(
                Path(roundedRect: CGRect(x: 352, y: 264, width: 320, height: 506), cornerRadius: 6),
                with: gradient(0xFFEDB3, 0xFFB547, from: 264, to: 770))
            context.fill(polygon([(352, 264), (548, 234), (548, 796), (352, 770)]), with: .color(Color(hex: 0xE4F0FE)))
            context.fill(polygon([(548, 234), (568, 240), (568, 790), (548, 796)]), with: .color(Color(hex: 0x7FA6D6)))
            context.fill(polygon([(484, 812), (621, 812), (604, 752)]), with: gradient(0xFF8A5C, 0xE9533A, from: 752, to: 812))
            context.fill(
                Path(roundedRect: CGRect(x: 308, y: 210, width: 408, height: 44), cornerRadius: 22),
                with: .color(.white))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func gradient(_ top: UInt32, _ bottom: UInt32, from: CGFloat, to: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(colors: [Color(hex: top), Color(hex: bottom)]), startPoint: CGPoint(x: 0, y: from),
            endPoint: CGPoint(x: 0, y: to))
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        Path { path in
            path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
            path.closeSubpath()
        }
    }
}
