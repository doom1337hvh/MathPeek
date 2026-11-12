// Draws the pages MathPeek's README clips are acted out on, works out where each clip's pointer
// goes, and writes scripts/clips.jsonc for AppShell's recorder:
//
//   scripts/build.sh && swift scripts/clip-pages.swift && scripts/record-clips.sh
//   swift scripts/clip-pages.swift draw      just this scene; the others keep their entries
//
// Each scene gets a worksheet with its maths on it, as MathPeek would be pointed at, saved as
// docs/clips/pages/<scene>.png: the recorder's backdrop, and for the diagram scene the picture
// MathPeek reads the diagram from. Then each scene is rehearsed: the built app acts it out off
// screen (`-demoRehearse <file>`, see Sources/MathPeek/DemoScene.swift) and says where its
// pointer went and when it clicked, which goes into clips.jsonc for the recorder to draw.
// Nothing shows on the screen meanwhile, and a copy of MathPeek that's running is left alone.
// Run it again after changing a page here or a scene's script there.
import AppKit
import UniformTypeIdentifiers

_ = NSApplication.shared

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let app = root.appendingPathComponent("build/MathPeek.app/Contents/MacOS/MathPeek")

/// The area recorded, in points: MathPeek's stage (DemoStage) and the 40 points the recorder
/// takes around it. The pages are drawn at twice that.
let stage = CGSize(width: 964, height: 684)
let scale: CGFloat = 2
/// Settings for the scenes, as launch arguments, which are never saved: the defaults, whatever
/// they've been changed to on this Mac.
let settings: [(String, String)] = [
    ("isEnabled", "true"), ("areaMode", "\"aroundPointer\""), ("answerSeconds", "5.0"), ("angles", "\"degrees\""),
    ("useAppleIntelligence", "false"), ("windowTranslucency", "0.55"), ("showsWhatItSees", "false"), ("keepsHistory", "true"),
    // (For the Settings clip, which AppShell plays: the menu bar icon as it starts out, on.)
    ("showMenuBarIcon", "true"),
    // The shortcut as it starts out, ⌃⌥=: the Hotkey as it's saved.
    ("hotkey", "\"<data>eyJrZXlDb2RlIjoyNCwibW9kaWZpZXJzIjo2MTQ0LCJrZXlOYW1lIjoiPSJ9</data>\""),
]
/// The same, as the app takes them on its command line.
let launchSettings = ["-isEnabled", "<true/>", "-areaMode", "aroundPointer", "-answerSeconds", "<real>5</real>", "-angles", "degrees",
                      "-useAppleIntelligence", "<false/>", "-windowTranslucency", "<real>0.55</real>", "-showsWhatItSees", "<false/>",
                      "-keepsHistory", "<true/>", "-hotkey", "<data>eyJrZXlDb2RlIjoyNCwibW9kaWZpZXJzIjo2MTQ0LCJrZXlOYW1lIjoiPSJ9</data>"]

// MARK: Drawing

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A context the size of a page, in points with the origin at the top left, like a screen.
func makeContext() -> CGContext {
    let width = Int(stage.width * scale), height = Int(stage.height * scale)
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    context.interpolationQuality = .high
    return context
}

/// Runs AppKit drawing (text, the cursor) in a context whose origin is at the top left.
func withAppKit(_ context: CGContext, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: The page

/// The page MathPeek is pointed at: a worksheet, drawn plainly. `spots` are the places on it
/// the scene's pointer goes to, in the order the scene uses them, from the page's top left.
final class Sheet {
    let context: CGContext
    var spots: [CGPoint] = []
    static let ink = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)
    static let quiet = NSColor(srgbRed: 0.40, green: 0.42, blue: 0.46, alpha: 1)
    static let left: CGFloat = 112

    init(_ context: CGContext) {
        self.context = context
        // A desk, and a sheet of paper on it that runs on below.
        context.setFillColor(color(0xE7E8EC))
        context.fill(CGRect(origin: .zero, size: stage))
        let paper = CGRect(x: 56, y: 26, width: stage.width - 112, height: stage.height)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2 * scale), blur: 14 * scale, color: color(0x000000, 0.13))
        context.setFillColor(color(0xFFFFFF))
        context.fill(paper)
        context.restoreGState()
    }

    /// Words, from their top left. Returns how wide they came out.
    @discardableResult
    func words(_ text: String, x: CGFloat = Sheet.left, y: CGFloat, size: CGFloat = 15, weight: NSFont.Weight = .regular,
               color: NSColor = Sheet.ink) -> CGFloat {
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        withAppKit(context) { string.draw(at: CGPoint(x: x, y: y)) }
        return string.size().width
    }

    /// A line of maths as a textbook sets it: letters in italics, `^` raising what follows
    /// it (one character, or a group in braces).
    static func maths(_ source: String, size: CGFloat, color: NSColor = Sheet.ink) -> NSAttributedString {
        let upright = NSFont(name: "Times New Roman", size: size) ?? .systemFont(ofSize: size)
        let italic = NSFont(name: "Times New Roman Italic", size: size) ?? upright
        let result = NSMutableAttributedString()
        var raised = false, grouped = false
        let characters = Array(source)
        for (index, character) in characters.enumerated() {
            if character == "^" { raised = true; continue }
            if raised, character == "{" { grouped = true; continue }
            if grouped, character == "}" { raised = false; grouped = false; continue }
            // A letter on its own is a quantity; letters together are a word.
            func lettered(_ at: Int) -> Bool { characters.indices.contains(at) && characters[at].isLetter && characters[at].isASCII }
            let isLetter = lettered(index) && !lettered(index - 1) && !lettered(index + 1)
            var font = isLetter ? italic : upright
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if raised {
                font = NSFont(descriptor: font.fontDescriptor, size: size * 0.62) ?? font
                attributes[.baselineOffset] = size * 0.36
            }
            attributes[.font] = font
            result.append(NSAttributedString(string: String(character), attributes: attributes))
            if raised, !grouped { raised = false }
        }
        return result
    }

    /// Maths on one line, from its top left. Returns its box.
    @discardableResult
    func maths(_ source: String, x: CGFloat, y: CGFloat, size: CGFloat = 26, color: NSColor = Sheet.ink) -> CGRect {
        let string = Sheet.maths(source, size: size, color: color)
        withAppKit(context) { string.draw(at: CGPoint(x: x, y: y)) }
        return CGRect(origin: CGPoint(x: x, y: y), size: string.size())
    }

    /// One number over another, centred on the line that `maths` at the same `y` sits on.
    /// Returns its box.
    @discardableResult
    func fraction(_ top: String, _ bottom: String, x: CGFloat, y: CGFloat, size: CGFloat = 26) -> CGRect {
        let over = Sheet.maths(top, size: size * 0.86), under = Sheet.maths(bottom, size: size * 0.86)
        let width = max(over.size().width, under.size().width) + 8
        let middle = y + size * 0.62
        withAppKit(context) {
            over.draw(at: CGPoint(x: x + (width - over.size().width) / 2, y: middle - over.size().height + 1))
            under.draw(at: CGPoint(x: x + (width - under.size().width) / 2, y: middle + 1))
        }
        context.setFillColor(Sheet.ink.cgColor)
        context.fill(CGRect(x: x, y: middle - 0.6, width: width, height: 1.3))
        return CGRect(x: x, y: middle - over.size().height, width: width, height: over.size().height + under.size().height)
    }

    /// A question's number, in the margin.
    func number(_ number: Int, y: CGFloat, size: CGFloat = 26) {
        words("\(number)", x: Sheet.left - 34, y: y + size * 0.36, size: 14, weight: .semibold, color: Sheet.quiet)
    }

    /// A faint rule, as between the questions of a worksheet.
    func rule(y: CGFloat, from x: CGFloat = Sheet.left - 34, to end: CGFloat = stage.width - 78) {
        context.setFillColor(color(0x000000, 0.08))
        context.fill(CGRect(x: x, y: y, width: end - x, height: 1))
    }

    /// The pointer goes to the middle of a box, with its tip just under what's written there
    /// so the arrow doesn't cover it.
    func spot(_ box: CGRect, dx: CGFloat = 0) {
        spots.append(CGPoint(x: (box.midX + dx).rounded(), y: (box.maxY - 1).rounded()))
    }

    /// A circle with its centre O and three points on it, the angle at the centre marked and
    /// the angle at the circumference called x: the angle at the centre is twice the angle at
    /// the circumference. Drawn plainly, as an exam paper draws one. Returns its box.
    @discardableResult
    func circleDiagram(centre: CGPoint, radius: CGFloat) -> CGRect {
        /// Degrees anticlockwise from three o'clock, as on paper.
        func onCircle(_ degrees: CGFloat, _ distance: CGFloat = 1) -> CGPoint {
            CGPoint(x: centre.x + cos(degrees * .pi / 180) * radius * distance, y: centre.y - sin(degrees * .pi / 180) * radius * distance)
        }
        let a = onCircle(80), b = onCircle(200), c = onCircle(326)
        context.saveGState()
        context.setStrokeColor(Sheet.ink.cgColor)
        context.setLineWidth(1.4)
        context.setLineCap(.round)
        context.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
        for (from, to) in [(a, b), (a, c), (b, centre), (centre, c)] {
            context.move(to: from)
            context.addLine(to: to)
        }
        context.strokePath()
        context.setFillColor(Sheet.ink.cgColor)
        context.fillEllipse(in: CGRect(x: centre.x - 2.6, y: centre.y - 2.6, width: 5.2, height: 5.2))
        // The arcs in the two angles. On the page y runs down, so anticlockwise there is
        // clockwise here.
        context.setLineWidth(1)
        func direction(from: CGPoint, to: CGPoint) -> CGFloat { atan2(to.y - from.y, to.x - from.x) }
        context.addArc(center: centre, radius: radius * 0.15, startAngle: direction(from: centre, to: c), endAngle: direction(from: centre, to: b), clockwise: false)
        context.strokePath()
        context.addArc(center: a, radius: radius * 0.15, startAngle: direction(from: a, to: c), endAngle: direction(from: a, to: b), clockwise: false)
        context.strokePath()
        context.restoreGState()
        func label(_ text: String, at point: CGPoint, italic: Bool = false) {
            let font = NSFont(name: italic ? "Helvetica-Oblique" : "Helvetica", size: 17) ?? .systemFont(ofSize: 17)
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: Sheet.ink])
            withAppKit(context) { string.draw(at: CGPoint(x: point.x - string.size().width / 2, y: point.y - string.size().height / 2)) }
        }
        label("A", at: onCircle(80, 1.13))
        label("B", at: onCircle(200, 1.13))
        label("C", at: onCircle(326, 1.13))
        label("O", at: CGPoint(x: centre.x + 2, y: centre.y - 16))
        label("126°", at: CGPoint(x: centre.x + 1, y: centre.y + 37))
        let bisector = (direction(from: a, to: b) + direction(from: a, to: c)) / 2
        label("x", at: CGPoint(x: a.x + cos(bisector) * 36, y: a.y + sin(bisector) * 36), italic: true)
        return CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)
    }

    /// A written answer, in pen.
    func written(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 26) {
        let font = NSFont(name: "Bradley Hand Bold", size: size * 1.05) ?? NSFont(name: "Noteworthy", size: size) ?? .systemFont(ofSize: size)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.10, green: 0.25, blue: 0.62, alpha: 1)])
        withAppKit(context) { string.draw(at: CGPoint(x: x, y: y)) }
    }
}

// MARK: The scenes

/// A clip: the page it's acted out on. What happens is the scene's script in DemoScene.swift.
struct Scene {
    let name: String
    /// Frames a second in the GIF. The recorder draws each frame as the app plays, and never
    /// skips one: a scene it can't keep up with at 20 runs ahead of its pointer, and gets fewer.
    var gifFPS = 20
    let page: (Sheet) -> Void
}

/// The page behind the scenes that start with the working already open.
func quadratics(_ sheet: Sheet, first: String = "x^2 − 5x + 6 = 0", second: String = "x^2 + 2x − 15 = 0") {
    sheet.words("Quadratic equations", y: 62, size: 25, weight: .bold)
    sheet.words("Solving by factorising", y: 98, size: 15, color: Sheet.quiet)
    sheet.rule(y: 134)
    sheet.words("Write each equation as two brackets multiplied together, then find the value of", y: 156)
    sheet.words("x that makes each bracket zero.", y: 178)
    sheet.number(1, y: 250, size: 30)
    sheet.words("Solve", y: 258, size: 17)
    sheet.spot(sheet.maths(first, x: Sheet.left + 62, y: 250, size: 30))
    sheet.rule(y: 400)
    sheet.number(2, y: 440, size: 30)
    sheet.words("Solve", y: 448, size: 17)
    sheet.maths(second, x: Sheet.left + 62, y: 440, size: 30)
    sheet.rule(y: 590)
}

func linear(_ sheet: Sheet) {
    sheet.words("Linear equations", y: 62, size: 25, weight: .bold)
    sheet.words("Show each line of your working.", y: 98, size: 15, color: Sheet.quiet)
    sheet.rule(y: 134)
    sheet.number(1, y: 176, size: 30)
    sheet.words("Solve", y: 184, size: 17)
    sheet.maths("3x + 5 = 20", x: Sheet.left + 62, y: 176, size: 30)
}

// A press of the shortcut reads 700 × 200 points around the pointer. So that a scene's answer
// is the one a real press there would give, problems it points at one at a time are set
// more than 100 points clear of each other down the page, and problems it reads together
// are set close.
let scenes: [Scene] = [
    Scene(name: "tour") { quadratics($0) },
    Scene(name: "bubble") { sheet in
        sheet.words("Number: mixed practice", y: 30, size: 22, weight: .bold)
        let size: CGFloat = 28
        var y: CGFloat = 70
        // The pointer goes just past each sum, where its answer would be written.
        func after(_ box: CGRect) { sheet.spots.append(CGPoint(x: (box.maxX + 16).rounded(), y: (y + size * 0.86).rounded())) }
        for (number, sum) in ["12 × (3 + 4.5) =", "12 × 7.5 =", "15% of 80 ="].enumerated() {
            sheet.number(number + 1, y: y, size: size)
            var box = sheet.maths(sum, x: Sheet.left, y: y, size: size)
            if number == 1 {
                // Someone's answer, and it's wrong.
                sheet.written("91", x: box.maxX + 10, y: y - 3, size: size)
                box.size.width += 44
            }
            after(box)
            y += number == 2 ? 118 : 110
            sheet.rule(y: y - 40)
        }
        sheet.number(4, y: y, size: size)
        var box = sheet.fraction("3", "4", x: Sheet.left, y: y, size: size)
        box = box.union(sheet.maths(" + ", x: box.maxX, y: y, size: size))
        box = box.union(sheet.fraction("5", "6", x: box.maxX, y: y, size: size))
        box = box.union(sheet.maths(" =", x: box.maxX, y: y, size: size))
        after(box)
    },
    Scene(name: "several") { sheet in
        sheet.words("Warm-up", y: 62, size: 25, weight: .bold)
        sheet.words("Five minutes. No calculator.", y: 98, size: 15, color: Sheet.quiet)
        sheet.rule(y: 134)
        let size: CGFloat = 26
        sheet.number(1, y: 168, size: size)
        sheet.maths("2x + 3 = 11", x: Sheet.left, y: 168, size: size)
        sheet.number(2, y: 216, size: size)
        sheet.spot(sheet.maths("x^2 − 7x + 10 = 0", x: Sheet.left, y: 216, size: size))
        sheet.number(3, y: 270, size: size)
        var box = sheet.fraction("5", "6", x: Sheet.left, y: 270, size: size)
        box = sheet.maths(" − ", x: box.maxX, y: 270, size: size)
        sheet.fraction("1", "4", x: box.maxX, y: 270, size: size)
        sheet.number(4, y: 324, size: size)
        sheet.maths("3(2y − 1) = 15", x: Sheet.left, y: 324, size: size)
    },
    Scene(name: "roadmap") { sheet in
        sheet.words("Polynomial equations", y: 62, size: 25, weight: .bold)
        sheet.words("Find every solution.", y: 98, size: 15, color: Sheet.quiet)
        sheet.rule(y: 134)
        sheet.number(1, y: 176, size: 28)
        sheet.spot(sheet.maths("x^3 − 6x^2 + 11x − 6 = 0", x: Sheet.left, y: 176, size: 28))
        sheet.number(2, y: 228, size: 28)
        sheet.maths("2x^2 + 5x − 3 = 0", x: Sheet.left, y: 228, size: 28)
    },
    Scene(name: "draw", gifFPS: 15) { linear($0) },
    Scene(name: "try") { linear($0) },
    Scene(name: "diagram") { sheet in
        sheet.words("Circle theorems", y: 62, size: 25, weight: .bold)
        sheet.rule(y: 110)
        sheet.number(1, y: 128, size: 16)
        sheet.words("A, B and C are points on a circle.", y: 132, size: 16)
        sheet.words("O is the centre of the circle.", y: 156, size: 16)
        let box = sheet.circleDiagram(centre: CGPoint(x: 330, y: 372), radius: 132)
        sheet.words("Work out the size of angle x.", y: 566, size: 16)
        sheet.spots.append(CGPoint(x: box.midX + 44, y: box.midY - 30))
    },
    Scene(name: "change") { quadratics($0, first: "x^2 − 6x + 8 = 0") },
    Scene(name: "history") { quadratics($0) },
]

// MARK: Pages, rehearsals and clips.jsonc

guard FileManager.default.isExecutableFile(atPath: app.path) else {
    FileHandle.standardError.write(Data("Build the app first: scripts/build.sh\n".utf8))
    exit(1)
}
let pages = root.appendingPathComponent("docs/clips/pages")
try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
let requested = Set(CommandLine.arguments.dropFirst())
// Given scenes' names, only those are rehearsed, and the rest keep the entries they have.
let written = (try? String(contentsOf: root.appendingPathComponent("scripts/clips.jsonc"), encoding: .utf8)) ?? ""
var entries: [String] = []
for scene in scenes {
    if !requested.isEmpty, !requested.contains(scene.name),
       let start = written.range(of: "    {\n      \"name\": \"\(scene.name)\""), let end = written.range(of: "\n    },", range: start.upperBound..<written.endIndex) {
        entries.append(String(written[start.lowerBound..<end.upperBound]))
        continue
    }
    let context = makeContext()
    let sheet = Sheet(context)
    scene.page(sheet)
    let picture = "docs/clips/pages/\(scene.name).png"
    if let image = context.makeImage(),
       let file = CGImageDestinationCreateWithURL(root.appendingPathComponent(picture) as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(file, image, nil)
        CGImageDestinationFinalize(file)
    }
    let spots = sheet.spots.map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: ";")

    // The rehearsal: the app acts the scene out off screen and writes down its pointer's path.
    let notes = FileManager.default.temporaryDirectory.appendingPathComponent("mathpeek-rehearsal-\(getpid())-\(scene.name).json")
    try? FileManager.default.removeItem(at: notes)
    let process = Process()
    process.executableURL = app
    process.arguments = ["-demo", scene.name, "-demoOffscreen", "<true/>", "-demoRehearse", notes.path, "-demoSpots", spots,
                         "-demoPage", picture] + launchSettings
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    var rehearsal: [String: Any]?
    for _ in 0..<600 where rehearsal == nil && process.isRunning {
        usleep(100_000)
        rehearsal = (try? Data(contentsOf: notes)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
    process.terminate()
    process.waitUntilExit()
    try? FileManager.default.removeItem(at: notes)
    guard let rehearsal, let length = rehearsal["length"] as? Double, let path = rehearsal["pointer"] as? [[Double]],
          let clicks = rehearsal["clicks"] as? [Double], let drags = rehearsal["drags"] as? [[Double]] else {
        print("  \(scene.name): the rehearsal didn't finish")
        continue
    }
    if let missing = rehearsal["missing"] as? [String], !missing.isEmpty {
        print("  \(scene.name): nothing to click called \(missing.joined(separator: ", "))")
    }
    func number(_ value: Double) -> String { String(format: "%.2f", value) }
    let pointer = path.map { "[\(number($0[0])), \(Int($0[1].rounded())), \(Int($0[2].rounded()))]" }.joined(separator: ", ")
    entries.append("""
        {
          "name": "\(scene.name)", "area": "window", "gifWidth": 1640,\(scene.gifFPS == 20 ? "" : " \"gifFPS\": \(scene.gifFPS),") "backdrop": "\(picture)",
          "settings": { "demoSpots": "\(spots)", "demoPage": "\(picture)" },
          "length": \(number(length)),
          "pointer": [\(pointer)],
          "clicks": [\(clicks.map(number).joined(separator: ", "))],\(drags.isEmpty ? "" : "\n      \"drags\": [\(drags.map { "[\(number($0[0])), \(number($0[1]))]" }.joined(separator: ", "))],")
        },
    """)
    print("  \(scene.name): \(picture), \(number(length)) s")
}

let clips = """
// The README's clips, recorded from the built app by scripts/record-clips.sh (AppShell's
// recorder; its scripts/record-clips.swift describes every option).
//
// Written by scripts/clip-pages.swift: change a page or a scene there (or the scene's script in
// Sources/MathPeek/DemoScene.swift) and run it again, rather than editing this. Each scene's
// backdrop is the page it's acted out on, and its pointer is where the app's own pointer went
// when the scene was rehearsed.
//
// The tour isn't marked "tour": that also makes a 60-frames-a-second video, and with a
// window this size the recorder falls seconds behind the app, so what's on screen runs ahead
// of the pointer. It's recorded like the rest, to docs/clips/tour.gif, and docs/demo.gif (the
// clip at the top of the README) is a copy of that.
{
  // Settings for every scene, as launch arguments, which are never saved.
  "settings": { \(settings.map { "\"\($0.0)\": \($0.1)" }.joined(separator: ", ")) },
  "scenes": [
\(entries.joined(separator: "\n"))
    // Settings, clicking through its tabs by itself.
    { "name": "settings", "demo": "settings-tabs", "area": "window" },
  ],
}

"""
guard entries.count == scenes.count else {
    print("scripts/clips.jsonc is left as it was.")
    exit(1)
}
try clips.write(to: root.appendingPathComponent("scripts/clips.jsonc"), atomically: true, encoding: .utf8)
print("Wrote scripts/clips.jsonc. Record with scripts/record-clips.sh.")
