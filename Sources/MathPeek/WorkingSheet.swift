import SwiftUI

/// The working laid out on one page, for copying as a picture: the problem, each step with
/// its maths, and the answer, on the window's own dark background.
struct WorkingSheet: View {
    let solution: Solution
    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(solution.problem.kind.lines.enumerated()), id: \.offset) { _, line in
                    MathLineView(line: line, size: 24, design: Z.maths, weight: .semibold)
                }
                if let subtitle = LearnModel.subtitle(solution) {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Z.secondary)
                }
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Z.tertiary)
                        .frame(width: 16, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Z.text)
                        if !step.explanation.isEmpty {
                            Text(step.explanation)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Z.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(Array(step.lines.enumerated()), id: \.offset) { _, line in
                            MathLineView(line: line, size: 17, design: Z.maths)
                        }
                    }
                }
            }
            if !solution.answers.isEmpty {
                HStack(spacing: 16) {
                    ForEach(Array((solution.answerSets ?? solution.answers.map { [$0] }).enumerated()), id: \.offset) { _, lines in
                        HStack(spacing: 14) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                MathLineView(line: line, size: 20, design: Z.maths, weight: .semibold)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Z.blue.opacity(0.22)))
                    }
                }
            }
        }
        .foregroundStyle(Z.text)
        .padding(28)
        .frame(width: 640, alignment: .leading)
        .background(Color(red: 0.09, green: 0.095, blue: 0.12))
        .environment(\.colorScheme, .dark)
    }
}
