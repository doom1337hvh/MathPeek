import Foundation

/// The question kinds kept by topic, each in a file of its own, tried in turn after
/// `Worded.problem` has nothing to say.
enum WordedTopics {
    static func problem(_ text: String) -> Problem? {
        WordedNumber.problem(text) ?? WordedAlgebra.problem(text) ?? WordedGraphs.problem(text)
            ?? WordedMensuration.problem(text) ?? WordedStatistics.problem(text) ?? WordedProbability.problem(text)
    }
}
