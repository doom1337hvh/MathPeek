import AppKit
import SwiftUI

/// The roadmap: the problem at the top, each step a stop on the line below it, and the answers
/// where the line ends, branching when there are several. It can be dragged about and zoomed.
/// A step opens where it is; the parts of the maths can be picked, and the problem's numbers
/// changed.
struct RouteCanvas: View {
    @Bindable var model: LearnModel

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                if model.inkTap(at: point) { return }
                model.tap { model.dismiss() }
            }
            .modifier(InkPointer(tool: model.tryFirst ? model.inkTool : nil))
            .overlay(alignment: .top) {
                Route(model: model, z: model.zoom)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { model.routeSize = $0 }
                    .padding(.top, LearnModel.routeTop)
                    .offset(model.pan)
            }
            .overlay {
                if model.tryFirst { RoadmapInk(model: model) }
            }
            .clipped()
            .contentShape(Rectangle())
            .coordinateSpace(.named("canvas"))
            // Trying it yourself, a drag writes on the roadmap; otherwise it moves it.
            .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .onChanged { drag in
                    if model.tryFirst { model.inkDrag(at: drag.location, from: drag.startLocation) } else { model.drag(by: drag.translation) }
                }
                .onEnded { _ in
                    if model.tryFirst { model.endInkDrag() } else { model.endDrag() }
                })
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.canvasFrame = $0 }
            .overlay(alignment: .bottomTrailing) { ZoomControl(model: model).padding(14) }
            .overlay(alignment: .bottomLeading) {
                if model.tryFirst { InkToolbar(model: model).padding(14) }
            }
    }
}

/// Everything on the roadmap, at a zoom of `z`. Sizes are multiplied rather than the picture
/// scaled, so the text stays sharp.
private struct Route: View {
    @Bindable var model: LearnModel
    let z: CGFloat

    static let width: CGFloat = 640
    /// From the left edge to where a stop's card starts: the dot, then a gap.
    static let gutter: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProblemStop(model: model, z: z)
            if model.writesOwn {
                // Trying it yourself: your own lines at the stops, checked as they're written.
                let (results, verdict) = Checker.check(model.myLines, against: model.solution, angles: model.angles)
                let right = results.filter { $0.status == .holds || $0.status == .answer }.count
                let reach = results.lastIndex { $0.status == .holds || $0.status == .answer }
                ForEach(Array(model.myLines.enumerated()), id: \.offset) { index, _ in
                    WrittenStop(model: model, z: z, index: index,
                                result: results.indices.contains(index) ? results[index] : Checker.Result(status: .empty),
                                reached: index == reach, isLast: index == model.myLines.count - 1, right: right)
                }
                if let verdict {
                    let wrong = results.contains { $0.status == .wrong }
                    Text(verdict)
                        .font(.system(size: 13 * z, weight: .semibold))
                        .foregroundStyle(wrong ? Z.red : Z.green)
                        .padding(.leading, Route.gutter * z)
                        .padding(.bottom, 10 * z)
                }
            } else if model.fillsIn {
                // Trying it yourself, a step at a time: the one being done asks for what it finds.
                let current = model.currentFill
                ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, step in
                    if index == current {
                        FillStop(model: model, z: z, index: index, step: step)
                    } else {
                        StepStop(model: model, z: z, index: index, step: step)
                    }
                }
            } else {
                ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, step in
                    StepStop(model: model, z: z, index: index, step: step)
                }
            }
            AnswerStop(model: model, z: z)
        }
        .backgroundPreferenceValue(RailKey.self) { rail in
            GeometryReader { proxy in line(rail, in: proxy) }
        }
        .frame(width: Self.width * z, alignment: .leading)
    }

    /// The route's line, behind the dots: from the problem's dot down to where the answers
    /// branch off. Opening a step draws it in blue from the problem down to that step's dot,
    /// how far along the working is; opening another carries the blue on to it, or back, and
    /// closing it draws the blue back up. It moves with the cards, on the same curve.
    @ViewBuilder private func line(_ rail: Rail, in proxy: GeometryProxy) -> some View {
        if let start = rail.start, let end = rail.end {
            let top = proxy[start], bottom = proxy[end].y
            let width = max(1, 1.5 * z)
            let reach = min(max(rail.open.map { proxy[$0].y } ?? top.y, top.y), bottom)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(RailDot.line)
                    .frame(width: width, height: max(bottom - top.y, 0))
                    .offset(x: top.x - width / 2, y: top.y)
                Capsule().fill(model.softBlue)
                    .frame(width: width, height: max(reach - top.y, 0))
                    .offset(x: top.x - width / 2, y: top.y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Where the route's line runs, as the stops report it: the problem's dot, where the answers
/// branch off, and the dot of the step that's open.
private struct Rail {
    var start: Anchor<CGPoint>?
    var end: Anchor<CGPoint>?
    var open: Anchor<CGPoint>?
}

private struct RailKey: PreferenceKey {
    static var defaultValue: Rail { Rail() }

    static func reduce(value: inout Rail, nextValue: () -> Rail) {
        let next = nextValue()
        value.start = value.start ?? next.start
        value.end = next.end ?? value.end
        value.open = value.open ?? next.open
    }
}

/// The dot a stop sits on. The route's line is drawn once, behind them all.
private struct RailDot: View {
    enum Kind { case start, step, open, next, covered, wrong }

    let z: CGFloat
    let kind: Kind
    /// The blue of an open step's dot: the window's see-through blue.
    var blue = Z.blue

    static let line = Color.white.opacity(0.2)
    private static let hollow = Color(red: 0.12, green: 0.125, blue: 0.155)

    var body: some View {
        dot.frame(width: 24 * z, height: 24 * z)
            // An opening step's dot fills as the blue line reaches it; a closing one empties
            // straight away, before the line has left it.
            .animation(kind == .open ? .easeOut(duration: 0.2).delay(0.22) : .easeOut(duration: 0.14), value: kind)
    }

    /// One dot whatever the kind, so it changes smoothly from one to another: a ring fills
    /// with blue as its step opens, and empties as it closes.
    private var dot: some View {
        let look: (fill: Color, edge: Color, size: CGFloat) = switch kind {
        case .start: (Color.white.opacity(0.92), .clear, 10)
        case .open: (blue, .clear, 10)
        case .step: (.clear, Color.white.opacity(0.5), 9)
        case .next: (.clear, blue, 9)
        case .covered: (.clear, Color.white.opacity(0.24), 7)
        case .wrong: (.clear, Z.red, 9)
        }
        // Solid underneath, so the line doesn't show through the dot.
        return Circle().fill(Self.hollow)
            .overlay(Circle().fill(look.fill))
            .overlay(Circle().strokeBorder(look.edge, lineWidth: max(1, 1.5 * z)))
            .frame(width: look.size * z, height: look.size * z)
    }
}

// MARK: The problem

private struct ProblemStop: View {
    @Bindable var model: LearnModel
    let z: CGFloat

    var body: some View {
        let solution = model.solution
        let lines = solution.problem.kind.lines
        let longest = lines.map(\.text.count).max() ?? 0
        let size: CGFloat = (lines.count > 1 ? 22 : (longest > 48 ? 18 : (longest > 34 ? 22 : 26))) * z
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .center, spacing: 0) {
                    if index == 0 {
                        RailDot(z: z, kind: .start)
                            .transformAnchorPreference(key: RailKey.self, value: .center) { $0.start = $1 }
                    } else {
                        Color.clear.frame(width: 24 * z, height: 1)
                    }
                    MathLineView(line: line, size: size, design: Z.maths, weight: .semibold,
                                 touch: model.touch(line: "problem.\(index)", changesNumbers: true))
                        .padding(.leading, 10 * z)
                }
                .padding(.top, index == 0 ? 0 : 8 * z)
            }
            under(solution)
                .padding(.leading, Route.gutter * z)
                .padding(.top, 9 * z)
            // Other ways to the same answer, when there are any: the one showing in blue.
            let methods = model.methods
            if !methods.isEmpty {
                let showing = model.methodIndex
                HStack(spacing: 16 * z) {
                    ForEach(Array(methods.enumerated()), id: \.offset) { index, method in
                        let id = "method.\(index)"
                        Text(method.name)
                            .font(.system(size: 12.5 * z, weight: .semibold))
                            .foregroundStyle(index == showing ? model.softBlue : (model.hovered == id ? Z.text : Z.secondary))
                            .contentShape(Rectangle())
                            .onTapGesture { model.tap { model.choose(method: index) } }
                            .hoverID(id, in: model)
                    }
                }
                .padding(.leading, Route.gutter * z)
                .padding(.top, 10 * z)
            }
            // A problem read from a diagram shows it: what's written on it, and what's asked
            // for picked out.
            if case .diagram(_, let find) = solution.problem.kind, let figure = Figure(solution.problem.kind) {
                // Another angle, or a line, can be clicked to find that instead.
                FigureView(figure: figure, lights: figure.lights(asked: find), showsMarks: true, side: 250 * z,
                           hovered: model.hoveredFigure,
                           hover: { model.hoveredFigure = $0 },
                           pick: { target in
                               model.tap {
                                   if let target { model.find(target) } else { model.dismiss() }
                               }
                           })
                    .padding(.leading, Route.gutter * z)
                    .padding(.top, 12 * z)
            }
        }
        .padding(.bottom, 18 * z)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    /// Under the problem: what the picked part is, why a change didn't work, or what kind of
    /// problem it is.
    @ViewBuilder private func under(_ solution: Solution) -> some View {
        if let part = model.picked, part.line.hasPrefix("problem.") {
            PartNote(model: model, part: part, z: z)
        } else if let message = model.message, !model.isEditing {
            Text(message)
                .font(.system(size: 13 * z))
                .foregroundStyle(Z.red)
        } else if let subtitle = LearnModel.subtitle(solution) {
            Text(subtitle)
                .font(.system(size: 13 * z))
                .foregroundStyle(Z.secondary)
        }
    }
}

/// What a picked part of the maths is, right under the line it's in.
private struct PartNote: View {
    @Bindable var model: LearnModel
    let part: MathPart
    let z: CGFloat

    var body: some View {
        let note = model.note(for: part)
        VStack(alignment: .leading, spacing: 2 * z) {
            Text(note.name)
                .font(.system(size: 12.5 * z, weight: .semibold))
                .foregroundStyle(Z.body)
            Text(note.detail)
                .font(.system(size: 13 * z))
                .foregroundStyle(Z.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: (Route.width - Route.gutter - 30) * z, alignment: .leading)
        .transition(.opacity)
    }
}

// MARK: Your own line

/// A line of your own working at a stop on the roadmap, when trying it yourself: written in
/// place, checked as it's written, its dot blue when it's right and red when it isn't. The
/// line being written can ask for a hint.
private struct WrittenStop: View {
    @Bindable var model: LearnModel
    let z: CGFloat
    let index: Int
    let result: Checker.Result
    /// The last line that's right: the blue line comes down to here.
    let reached: Bool
    let isLast: Bool
    /// How many lines are right so far.
    let right: Int

    var body: some View {
        let kind: RailDot.Kind = switch result.status {
        case .holds, .answer: .open
        case .wrong: .wrong
        default: isLast ? .next : .step
        }
        HStack(alignment: .top, spacing: 0) {
            RailDot(z: z, kind: kind, blue: model.softBlue)
                .transformAnchorPreference(key: RailKey.self, value: .center) { rail, dot in
                    if reached { rail.open = dot }
                }
                .padding(.top, 6 * z)
            VStack(alignment: .leading, spacing: 6 * z) {
                HStack(spacing: 10 * z) {
                    LineInput(model: model, index: index, text: model.myLines[index], request: model.focusRequests)
                        .frame(height: 24 * z)
                    switch result.status {
                    case .holds, .answer:
                        Image(systemName: "checkmark").font(.system(size: 11 * z, weight: .bold)).foregroundStyle(Z.green)
                    case .wrong:
                        Image(systemName: "xmark").font(.system(size: 11 * z, weight: .bold)).foregroundStyle(Z.red)
                    case .unread:
                        Text("?").font(.system(size: 12 * z, weight: .bold)).foregroundStyle(Z.tertiary)
                    case .empty:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 13 * z)
                .frame(height: 36 * z)
                .background(RoundedRectangle(cornerRadius: 7 * z, style: .continuous).fill(Color.white.opacity(0.06)))
                if let note = result.note, result.status != .empty {
                    Text(note)
                        .font(.system(size: 12.5 * z))
                        .foregroundStyle(result.status == .wrong ? Z.red : Z.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 13 * z)
                }
                if isLast, !model.answerRevealed {
                    SymbolKeys(model: model, size: z)
                        .padding(.leading, 13 * z)
                    hint
                }
            }
            .frame(width: (Route.width - Route.gutter) * z, alignment: .leading)
            .padding(.leading, 10 * z)
        }
        .padding(.bottom, 8 * z)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Stuck: the next step's name first, then its line written in.
    @ViewBuilder private var hint: some View {
        if let step = model.nextStep(after: right) {
            VStack(alignment: .leading, spacing: 3 * z) {
                if model.hintLevel >= 1 {
                    Text(step.title)
                        .font(.system(size: 12.5 * z, weight: .semibold))
                        .foregroundStyle(Z.body)
                    if !step.explanation.isEmpty {
                        Text(step.explanation)
                            .font(.system(size: 12.5 * z))
                            .foregroundStyle(Z.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(model.hintLevel == 0 ? "Hint" : "Write It In")
                    .font(.system(size: 12.5 * z, weight: .semibold))
                    .foregroundStyle(model.hovered == "hint" ? model.softBlueHover : model.softBlue)
                    .contentShape(Rectangle())
                    .onTapGesture { model.tap { model.hint(at: index, right: right) } }
                    .hoverID("hint", in: model)
            }
            .padding(.leading, 13 * z)
            .padding(.top, 2 * z)
        }
    }
}

// MARK: A step to fill in

/// The step being done when trying it yourself where the working can't be checked as
/// equations: what it finds, with a box for its value ("∠BAD = ___°", "x³ → ___"), checked
/// on Return. Hint gives its rule, then writes it in.
private struct FillStop: View {
    @Bindable var model: LearnModel
    let z: CGFloat
    let index: Int
    let step: Step

    var body: some View {
        let blanks = model.blanks
        let current = model.currentBlank
        let wrong = current.map { model.wrongSteps.contains($0) } ?? false
        HStack(alignment: .top, spacing: 0) {
            RailDot(z: z, kind: wrong ? .wrong : .next, blue: model.softBlue)
                .transformAnchorPreference(key: RailKey.self, value: .center) { rail, dot in rail.open = dot }
                .padding(.top, 6 * z)
            VStack(alignment: .leading, spacing: 8 * z) {
                // A line that isn't asked for (the rule, in the diagram's names) would give the
                // working away, so it shows only with a hint.
                let shown = step.lines.indices.filter { number in
                    model.hintLevel >= 1 || blanks.contains { $0.step == index && $0.line == number }
                }
                ForEach(shown, id: \.self) { number in
                    let line = step.lines[number]
                    let blank = blanks.firstIndex { $0.step == index && $0.line == number }
                    HStack(spacing: 8 * z) {
                        Text(number == shown.first ? "\(index + 1)" : "")
                            .font(.system(size: 12 * z, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Z.tertiary)
                            .frame(width: 16 * z, alignment: .leading)
                        if let blank, model.solvedSteps.contains(blank) || blank != current {
                            if model.solvedSteps.contains(blank) {
                                MathLineView(line: line, size: 16 * z, design: Z.maths)
                                Image(systemName: "checkmark").font(.system(size: 10 * z, weight: .bold)).foregroundStyle(Z.green)
                            } else {
                                // Still to come.
                                MathLineView(line: MathLine(parts: Array(line.parts.dropLast())), size: 16 * z, design: Z.maths)
                                    .foregroundStyle(Z.tertiary)
                                Text(line.relation == "≈" ? "=" : line.relation).font(.system(size: 16 * z, design: Z.maths)).foregroundStyle(Z.tertiary)
                                Text("…").font(.system(size: 16 * z)).foregroundStyle(Z.tertiary)
                            }
                        } else if let blank {
                            MathLineView(line: MathLine(parts: Array(line.parts.dropLast())), size: 16 * z, design: Z.maths)
                            Text(line.relation == "≈" ? "=" : line.relation).font(.system(size: 16 * z, design: Z.maths))
                            LineInput(model: model, index: blank, text: model.myLines.indices.contains(blank) ? model.myLines[blank] : "", request: model.focusRequests)
                                .frame(width: 140 * z, height: 24 * z)
                                .padding(.horizontal, 8 * z)
                                .background(RoundedRectangle(cornerRadius: 5 * z, style: .continuous).fill(Color.white.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 5 * z, style: .continuous).strokeBorder(wrong ? Z.red : model.softBlue, lineWidth: 1.2))
                            if let suffix = line.suffix {
                                Text(suffix).font(.system(size: 16 * z, design: Z.maths)).foregroundStyle(Z.secondary)
                            }
                        } else {
                            MathLineView(line: line, size: 16 * z, design: Z.maths)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 13 * z)
            .padding(.vertical, 10 * z)
            .frame(width: (Route.width - Route.gutter) * z, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7 * z, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(alignment: .bottomLeading) { EmptyView() }
            .padding(.leading, 10 * z)
        }
        .padding(.bottom, 4 * z)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Under the card: keys for powers and roots, what went wrong, and the hint.
        VStack(alignment: .leading, spacing: 3 * z) {
            if model.currentBlank != nil {
                SymbolKeys(model: model, size: z).padding(.bottom, 4 * z)
            }
            if wrong {
                Text("Not quite. Try again.").font(.system(size: 12.5 * z)).foregroundStyle(Z.red)
            }
            if model.hintLevel >= 1 {
                Text(step.title).font(.system(size: 12.5 * z, weight: .semibold)).foregroundStyle(Z.body)
                if !step.explanation.isEmpty {
                    Text(step.explanation)
                        .font(.system(size: 12.5 * z))
                        .foregroundStyle(Z.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let current {
                Text(model.hintLevel == 0 ? "Hint" : "Write It In")
                    .font(.system(size: 12.5 * z, weight: .semibold))
                    .foregroundStyle(model.hovered == "hint" ? model.softBlueHover : model.softBlue)
                    .contentShape(Rectangle())
                    .onTapGesture { model.tap { model.fillHint(current) } }
                    .hoverID("hint", in: model)
            }
        }
        .padding(.leading, (Route.gutter + 13) * z)
        .padding(.bottom, 10 * z)
        .frame(width: (Route.width - 13) * z, alignment: .leading)
    }
}

// MARK: A step

private struct StepStop: View {
    @Bindable var model: LearnModel
    let z: CGFloat
    let index: Int
    let step: Step

    var body: some View {
        let isOpen = model.openStop == index
        let isCovered = model.tryFirst && index >= model.revealed
        let isNext = isCovered && index == model.revealed
        HStack(alignment: .top, spacing: 0) {
            RailDot(z: z, kind: isOpen ? .open : (isNext ? .next : (isCovered ? .covered : .step)), blue: model.softBlue)
                // The line is blue down to an open step's dot.
                .transformAnchorPreference(key: RailKey.self, value: .center) { rail, dot in
                    if model.lineStop == index, !isCovered { rail.open = dot }
                }
                .padding(.top, 6 * z)
            card(isOpen: isOpen && !isCovered, isCovered: isCovered, isNext: isNext)
                .padding(.leading, 10 * z)
        }
        .padding(.bottom, 8 * z)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("canvas")) } action: { frame in
            if model.openStop == index { model.bringIntoView(frame) }
        }
    }

    private func card(isOpen: Bool, isCovered: Bool, isNext: Bool) -> some View {
        let id = "stop.\(index)"
        let hovered = model.hovered == id
        let fill: Color = isOpen ? Color.black.opacity(0.3)
            : Color.white.opacity(isCovered && !isNext ? 0.03 : (hovered ? 0.11 : 0.06))
        return VStack(alignment: .leading, spacing: 0) {
            header(isOpen: isOpen, isCovered: isCovered, isNext: isNext, hovered: hovered)
                .frame(height: 36 * z)
                .padding(.horizontal, 13 * z)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.tap { if isNext { model.revealNext() } else { model.toggle(stop: index) } }
                }
                .hoverID(id, in: model)
            // Always there, folded away to nothing when the step is closed: so what's in it
            // moves with its card, uncovered as the card grows and covered as it shrinks.
            if !isCovered {
                StepBody(model: model, z: z, index: index, step: step)
                    .padding(.horizontal, 13 * z)
                    .padding(.top, 2 * z)
                    .padding(.bottom, 15 * z)
                    .frame(height: isOpen ? nil : 0, alignment: .top)
                    .clipped()
                    .opacity(isOpen ? 1 : 0)
                    .allowsHitTesting(isOpen)
                    .accessibilityHidden(!isOpen)
            }
        }
        .frame(width: (Route.width - Route.gutter) * z, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7 * z, style: .continuous).fill(fill))
        .clipShape(RoundedRectangle(cornerRadius: 7 * z, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7 * z, style: .continuous)
            .strokeBorder(Color.white.opacity(isOpen ? 0.1 : 0), lineWidth: 1))
        // An open card closes with a click anywhere on it, except on what's clickable in it
        // (the maths, Visualise, Graph), which takes the click first.
        .contentShape(RoundedRectangle(cornerRadius: 7 * z, style: .continuous))
        .onTapGesture {
            guard isOpen else { return }
            model.tap { model.toggle(stop: index) }
        }
    }

    @ViewBuilder private func header(isOpen: Bool, isCovered: Bool, isNext: Bool, hovered: Bool) -> some View {
        let number = Text("\(index + 1)")
            .font(.system(size: 12 * z, weight: .semibold).monospacedDigit())
            .foregroundStyle(isCovered && !isNext ? Color.white.opacity(0.25) : Z.tertiary)
            .frame(width: 16 * z, alignment: .leading)
        if isNext {
            HStack(spacing: 10 * z) {
                number
                Text("Show step")
                    .font(.system(size: 13 * z, weight: .semibold))
                    .foregroundStyle(hovered ? model.softBlueHover : model.softBlue)
                Spacer(minLength: 0)
            }
        } else if isCovered {
            HStack(spacing: 10 * z) {
                number
                Spacer(minLength: 0)
            }
        } else {
            // One row whether the step is open or closed, so its name slides with the card
            // rather than fading out in one place and in at another.
            HStack(spacing: 10 * z) {
                number
                // The same weight open or closed: text that changes weight while it moves
                // is redrawn on its own path and drifts from its number.
                Text(step.title)
                    .font(.system(size: 13 * z, weight: .semibold))
                    .foregroundStyle(isOpen ? Z.text : Z.body)
                    .contentTransition(.identity)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 18 * z)
                // Closed, a step shows where it got to, if there's room beside its name.
                if let result = step.lines.last {
                    ViewThatFits {
                        MathLineView(line: result, size: 14 * z, design: Z.maths)
                        MathLineView(line: result, size: 11 * z, design: Z.maths)
                        Color.clear.frame(width: 0, height: 0)
                    }
                    .foregroundStyle(Z.secondary)
                    .opacity(isOpen ? 0 : 1)
                }
            }
        }
    }
}

/// An open step: what was done, the maths (whose parts can be picked), why it works and what
/// to watch out for.
private struct StepBody: View {
    @Bindable var model: LearnModel
    let z: CGFloat
    let index: Int
    let step: Step

    var body: some View {
        let why = Insight.why(step)
        let watch = Insight.watchOut(step)
        let figure = Figure(model.solution.problem.kind)
        // Maths too long to share the line with a picture has it underneath.
        let beside = !step.lines.contains { $0.text.count > 40 }
        // Anything else can show what the step did, written out, and a graph of it, when asked.
        let isOpen = figure == nil && model.openStop == index
        let visual = isOpen ? StepVisual.make(for: model.stops, at: index, in: model.solution) : nil
        let drawing = isOpen ? StepPicture.make(for: model.stops, at: index, in: model.solution) : nil
        VStack(alignment: .leading, spacing: 12 * z) {
            if let figure, beside {
                HStack(alignment: .top, spacing: 14 * z) {
                    VStack(alignment: .leading, spacing: 12 * z) { working }
                    Spacer(minLength: 0)
                    picture(figure)
                }
            } else if let drawing, model.graphs, beside {
                HStack(alignment: .top, spacing: 14 * z) {
                    VStack(alignment: .leading, spacing: 12 * z) {
                        working
                        written(visual)
                        options(visual: visual != nil, graph: true)
                    }
                    Spacer(minLength: 0)
                    StepPictureView(picture: drawing, width: 230 * z, blue: model.softBlue)
                        .transition(.opacity)
                }
            } else {
                working
                if let figure { picture(figure) }
                written(visual)
                if let drawing, model.graphs {
                    StepPictureView(picture: drawing, width: 300 * z, blue: model.softBlue)
                        .transition(.opacity)
                }
                if visual != nil || drawing != nil { options(visual: visual != nil, graph: drawing != nil) }
            }
            if why != nil || watch != nil {
                Rectangle().fill(Z.hairline).frame(height: 1)
                if let why { note("Why it works", why) }
                if let watch { note("Watch out", watch) }
            }
        }
        .padding(.leading, 26 * z)
    }

    /// The step written out with what was done to it marked, when that's asked for.
    @ViewBuilder private func written(_ visual: StepVisual?) -> some View {
        if let visual, model.visualises {
            StepVisualView(visual: visual, size: 17 * z, blue: model.softBlue)
                .padding(.vertical, 4 * z)
                .transition(.opacity)
        }
    }

    /// Shows or hides the step written out, and its graph. Once shown, each stays shown for
    /// every step opened, until it's hidden.
    private func options(visual: Bool, graph: Bool) -> some View {
        HStack(spacing: 18 * z) {
            if visual { option(model.visualises ? "Hide visual" : "Visualise", id: "visualise") { model.visualises.toggle() } }
            if graph { option(model.graphs ? "Hide graph" : "Graph", id: "graph") { model.graphs.toggle() } }
        }
    }

    private func option(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.system(size: 12.5 * z, weight: .semibold))
            .foregroundStyle(model.hovered == id ? model.softBlueHover : model.softBlue)
            .contentShape(Rectangle())
            .onTapGesture { model.tap { withAnimation(.easeOut(duration: 0.22)) { action() } } }
            .hoverID(id, in: model)
    }

    /// What was done, and the maths.
    @ViewBuilder private var working: some View {
        if !step.explanation.isEmpty {
            Text(step.explanation)
                .font(.system(size: 13.5 * z))
                .foregroundStyle(Z.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !step.lines.isEmpty {
            VStack(alignment: .leading, spacing: 11 * z) {
                ForEach(Array(step.lines.enumerated()), id: \.offset) { number, line in
                    let id = "step.\(index).\(number)"
                    let size: CGFloat = line.text.count > 44 ? 15 : (step.lines.count > 3 ? 17 : 19)
                    MathLineView(line: line, size: size * z, design: Z.maths, touch: model.touch(line: id))
                    if let part = model.picked, part.line == id {
                        PartNote(model: model, part: part, z: z)
                    }
                }
            }
            .padding(.vertical, 3 * z)
        }
    }

    /// The diagram with what this step is about picked out: the angles it works from, and
    /// in blue the one it finds.
    private func picture(_ figure: Figure) -> some View {
        FigureView(figure: figure, lights: figure.lights(for: step, after: Array(model.stops.prefix(index))), side: 176 * z)
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3 * z) {
            Text(title)
                .font(.system(size: 12.5 * z, weight: .semibold))
                .foregroundStyle(Z.secondary)
            Text(text)
                .font(.system(size: 13.5 * z))
                .foregroundStyle(Z.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: The answers

/// Where the route ends: each answer, with the line branching to reach them all. An answer
/// that can be checked opens its check; one that can't is copied.
private struct AnswerStop: View {
    @Bindable var model: LearnModel
    let z: CGFloat

    var body: some View {
        let solution = model.solution
        let items = model.answerItems
        let checks = Insight.checks(solution)
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                HStack(alignment: .center, spacing: 0) {
                    // With no answer to branch off to, the line ends at this dot.
                    RailDot(z: z, kind: .step)
                        .transformAnchorPreference(key: RailKey.self, value: .center) { $0.end = $1 }
                    Text(solution.note ?? "No answer")
                        .font(.system(size: 14 * z))
                        .foregroundStyle(Z.body)
                        .padding(.leading, 10 * z)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            } else if model.tryFirst, !model.answerRevealed {
                end(first: true, last: true) {
                    Text("Show answer")
                        .font(.system(size: 13 * z, weight: .semibold))
                        .foregroundStyle(model.hovered == "answer.show" ? model.softBlueHover : model.softBlue)
                        .padding(.horizontal, 14 * z)
                        .frame(height: 36 * z)
                        .background(RoundedRectangle(cornerRadius: 7 * z, style: .continuous)
                            .fill(Color.white.opacity(model.hovered == "answer.show" ? 0.11 : 0.06)))
                        .contentShape(Rectangle())
                        .onTapGesture { model.tap { model.answerRevealed = true } }
                        .hoverID("answer.show", in: model)
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, lines in
                        end(first: index == 0, last: index == items.count - 1) {
                            answer(index, lines, alone: items.count == 1, checkable: checks.indices.contains(index), solution)
                        }
                    }
                }
                details(solution, checks, named: items.count > 1)
                    .padding(.top, 14 * z)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The line comes down to the top of the answers, where it branches.
        .transformAnchorPreference(key: RailKey.self, value: .top) { rail, top in
            if rail.end == nil { rail.end = top }
        }
    }

    /// One end of the route: the line coming down into it, joined to its neighbours' lines.
    private func end<Content: View>(first: Bool, last: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.top, 22 * z)
            .padding(.trailing, last ? 0 : 10 * z)
            .background(alignment: .top) {
                Branch(first: first, last: last, inset: 12 * z, bar: 9 * z)
                    .stroke(RailDot.line, lineWidth: max(1, 1.5 * z))
                    .frame(height: 22 * z)
            }
    }

    private func answer(_ index: Int, _ lines: [MathLine], alone: Bool, checkable: Bool, _ solution: Solution) -> some View {
        let id = "answer.\(index)"
        let selected = checkable && model.showsCheck && model.selectedAnswer == index
        let lit = selected || model.hovered == id
        let longest = lines.map(\.text.count).max() ?? 0
        let size: CGFloat = alone ? (longest > 34 ? 17 : (longest > 22 ? 20 : 24)) : 19
        return HStack(spacing: 18 * z) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MathLineView(line: line, size: size * z, design: Z.maths, weight: alone ? .semibold : .medium)
            }
        }
        .padding(.horizontal, 15 * z)
        .padding(.vertical, (alone ? 12 : 10) * z)
        .background(BlueGlass(radius: 7 * z, wash: Z.blue.opacity(lit ? 0.36 : 0.25), shade: model.glassShade))
        .clipShape(RoundedRectangle(cornerRadius: 7 * z, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7 * z, style: .continuous)
            .strokeBorder(selected ? model.softBlue : Color.clear, lineWidth: 1.5 * z))
        .contentShape(Rectangle())
        .onTapGesture {
            model.tap {
                if checkable {
                    model.select(answer: index)
                } else {
                    model.copy(lines.map(\.text).joined(separator: ", "), as: "Answer")
                }
            }
        }
        .hoverID(id, in: model)
    }

    /// Under the answers: the picked answer put back into the question, its decimal value,
    /// and anything worth knowing about it.
    @ViewBuilder private func details(_ solution: Solution, _ checks: [AnswerCheck], named: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10 * z) {
            if model.showsCheck, checks.indices.contains(model.selectedAnswer) {
                check(checks[model.selectedAnswer], named: named)
                    .transition(.opacity)
            }
            // Rounded as a question asks: the choice, and what it was rounded from.
            if model.canRound {
                HStack(spacing: 14 * z) {
                    ForEach(Rounding.allCases) { choice in
                        let id = "round.\(choice.rawValue)"
                        Text(choice.rawValue)
                            .font(.system(size: 12.5 * z, weight: .semibold))
                            .foregroundStyle(choice == model.rounding ? model.softBlue : (model.hovered == id ? Z.text : Z.secondary))
                            .contentShape(Rectangle())
                            .onTapGesture { model.tap { model.rounding = choice } }
                            .hoverID(id, in: model)
                    }
                }
            }
            if model.rounding == .exact, let approximation = solution.approximation { quiet(approximation) }
            if model.rounding != .exact {
                quiet("Rounded \(model.rounding.words) from " + (solution.answerSets?.flatMap { $0 } ?? solution.answers)
                    .compactMap { line in line.parts.last?.evaluate().map { Format.decimal(($0 * 1e8).rounded() / 1e8) } }
                    .joined(separator: " and ") + "…")
            }
            if let note = solution.note { quiet(note) }
            // A new problem of the same kind, to try: offered once one's been found.
            if model.practiceReady[solution.problem.text] != nil {
                Text("Another Like This")
                    .font(.system(size: 12.5 * z, weight: .semibold))
                    .foregroundStyle(model.hovered == "another" ? model.softBlueHover : model.softBlue)
                    .contentShape(Rectangle())
                    .onTapGesture { model.tap { model.anotherLikeThis() } }
                    .hoverID("another", in: model)
            }
            // The graph, with the answers marked where they are on it: the one picked in yellow.
            if let plot = solution.plot, !plot.marks.isEmpty {
                GraphView(plot: plot, selected: model.selectedAnswer, blue: model.softBlue)
                    .frame(width: (Route.width - 30) * z, height: 220 * z)
                    .padding(14 * z)
                    .background(RoundedRectangle(cornerRadius: 8 * z, style: .continuous).fill(Color.black.opacity(0.3)))
                    .overlay(RoundedRectangle(cornerRadius: 8 * z, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
                    .padding(.top, 4 * z)
            }
        }
        .task(id: solution.problem.text) { await model.preparePractice() }
    }

    private func check(_ check: AnswerCheck, named: Bool) -> some View {
        // "0 = 0" says nothing: only the lines that show something.
        let shown = check.lines.filter { $0.parts.count != 2 || Format.text($0.parts[0]) != Format.text($0.parts[1]) }
        let lines = shown.isEmpty ? check.lines : shown
        return VStack(alignment: .leading, spacing: 10 * z) {
            Text(named ? "Check \(check.answer)" : "Check")
                .font(.system(size: 12.5 * z, weight: .semibold))
                .foregroundStyle(Z.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 10 * z) {
                    MathLineView(line: line, size: 15 * z, design: Z.maths)
                    if index == lines.count - 1 {
                        Image(systemName: check.holds ? "checkmark" : "xmark")
                            .font(.system(size: 11 * z, weight: .bold))
                            .foregroundStyle(check.holds ? Z.green : Z.red)
                    }
                }
            }
        }
        .padding(15 * z)
        .background(RoundedRectangle(cornerRadius: 8 * z, style: .continuous).fill(Color.black.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 8 * z, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13 * z).monospacedDigit())
            .foregroundStyle(Z.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Route.width * z, alignment: .leading)
    }
}

/// The line into one answer: straight down into the first, and across the top to the rest.
private struct Branch: Shape {
    let first: Bool
    let last: Bool
    /// How far in from the answer's left edge the line comes down.
    let inset: CGFloat
    /// How far down the line across is.
    let bar: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: inset, y: first ? 0 : bar))
        path.addLine(to: CGPoint(x: inset, y: rect.maxY))
        if !(first && last) {
            path.move(to: CGPoint(x: first ? inset : 0, y: bar))
            path.addLine(to: CGPoint(x: last ? inset : rect.maxX, y: bar))
        }
        return path
    }
}

// MARK: Zoom

/// Zoom out, the zoom (click to go back to 100% and the middle), zoom in.
private struct ZoomControl: View {
    @Bindable var model: LearnModel

    var body: some View {
        HStack(spacing: 0) {
            key("−", id: "zoom.out") { model.zoom(by: 1 / 1.2) }
            Text("\(Int((model.zoom * 100).rounded()))%")
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(model.hovered == "zoom.reset" ? Z.text : Z.secondary)
                .frame(width: 46, height: 26)
                .contentShape(Rectangle())
                .onTapGesture { model.resetView() }
                .hoverID("zoom.reset", in: model)
            key("+", id: "zoom.in") { model.zoom(by: 1.2) }
        }
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.32)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
    }

    private func key(_ label: String, id: String, _ action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(model.hovered == id ? Z.text : Z.secondary)
            .frame(width: 28, height: 26)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .hoverID(id, in: model)
    }
}

// MARK: Changing a number

/// The field that takes a number's place while it's being changed. Return puts the new number
/// in, Escape leaves it, and the up and down arrows go up and down by one.
struct NumberField: View {
    @Bindable var model: LearnModel
    let size: CGFloat

    var body: some View {
        let characters = CGFloat(max(model.numberText.count, 1))
        NumberInput(model: model, size: size)
            .frame(width: characters * size * 0.62 + size * 0.7, height: size * 1.3)
            .background(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(Color.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).strokeBorder(model.softBlue, lineWidth: 1.5))
    }
}

private struct NumberInput: NSViewRepresentable {
    let model: LearnModel
    let size: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: model.numberText)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.textColor = .white
        field.font = .systemFont(ofSize: size, weight: .semibold)
        field.delegate = context.coordinator
        field.cell?.usesSingleLineMode = true
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.numberText { field.stringValue = model.numberText }
        field.font = .systemFont(ofSize: size, weight: .semibold)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: LearnModel

        init(model: LearnModel) {
            self.model = model
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.numberText = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            model.commitNumber()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                model.commitNumber()
            case #selector(NSResponder.cancelOperation(_:)):
                model.changing = nil
            case #selector(NSResponder.moveUp(_:)):
                model.nudgeNumber(by: 1)
            case #selector(NSResponder.moveDown(_:)):
                model.nudgeNumber(by: -1)
            default:
                return false
            }
            return true
        }
    }
}
