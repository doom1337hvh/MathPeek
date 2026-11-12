import CoreGraphics
import Foundation
import FoundationModels

/// Apple Intelligence, on this Mac, for what text recognition alone can't read: maths laid out
/// in two dimensions (stacked fractions, handwriting) and word problems. It only ever turns
/// them into maths; MathPeek's own engine works the maths out, exactly. Nothing goes online.
enum Tutor {
    /// Whether Apple's on-device model is ready, and new enough to read images.
    static var isAvailable: Bool {
        guard #available(macOS 27.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Why it isn't, for Settings.
    static var unavailableReason: String? {
        guard #available(macOS 27.0, *) else { return "Needs macOS 27 or later." }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to use this."
        case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready. Try again later."
        default: return "Apple Intelligence isn't available."
        }
    }

    private static let transcribeInstructions = """
        You read maths from a screenshot for a maths app. Write the maths problem closest to the middle \
        of the picture as ONE line of plain text. Use + - * / ^ ( ) and =, sqrt(), sin cos tan ln log, pi. \
        Write fractions as (top)/(bottom) and powers with ^. Separate simultaneous equations with ; . \
        If the picture asks to solve, simplify, expand, factorise, differentiate or integrate, start with that word. \
        Write integrals as: integrate <expression> dx from <a> to <b>. Reply with the maths only, no working and no answer.
        """

    private static let wordProblemInstructions = """
        You turn word problems into maths for a maths app. Choose one letter for each unknown. \
        Reply with exactly two lines. Line 1: the equation or equations separated by ; using + - * / ^ ( ) =, \
        or an expression to work out. Line 2: what each letter stands for, like: p = the price of a popcorn in £. \
        When a formula is given and then some of its values, put each number into the formula: for "the nth term is \
        an^2 + bn and the 2nd term is 2" write a*2^2 + b*2 = 2. Use only numbers that are in the problem. \
        Do not solve it and do not explain.
        """

    /// The maths in a picture, written on one line.
    static func transcribe(_ image: CGImage) async -> String? {
        guard #available(macOS 27.0, *), isAvailable else { return nil }
        do {
            let session = LanguageModelSession(instructions: transcribeInstructions)
            let response = try await session.respond(to: Prompt { "Write the maths in this picture."; Attachment(image) },
                                                      options: GenerationOptions(samplingMode: .greedy))
            return cleaned(response.content).first
        } catch {
            return nil
        }
    }

    /// A word problem as maths, and what its letters mean.
    static func translate(_ wordProblem: String) async -> (maths: String, meaning: String?)? {
        guard #available(macOS 27.0, *), isAvailable else { return nil }
        do {
            let session = LanguageModelSession(instructions: wordProblemInstructions)
            let response = try await session.respond(to: wordProblem, options: GenerationOptions(samplingMode: .greedy))
            let lines = cleaned(response.content)
            guard let maths = lines.first else { return nil }
            return (maths, lines.count > 1 ? lines[1] : nil)
        } catch {
            return nil
        }
    }

    /// The reply's lines without code fences, labels or blank lines.
    private static func cleaned(_ reply: String) -> [String] {
        reply.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " `*")) }
            .map { $0.replacingOccurrences(of: #"^(Line \d:|Maths:|Equation[s]?:|Answer:)\s*"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") }
    }
}
