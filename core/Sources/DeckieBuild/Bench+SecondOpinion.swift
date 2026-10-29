import Foundation
import DeckieEngine
import DeckieInference

extension Bench {
    /// The bench's analyser: the builder's (`Builder.makeAnalyser`, the same models, threads and sessions), with PANNs
    /// as the second vocal opinion when its model file is there (`PANNs.locateModel()`) and the vocal tagger is, so the
    /// yardstick's records carry `deckie.vocal.second_opinion` beside the tagger's series. The builder's own crates
    /// leave it out: it changes nothing in a crate record, and costs time.
    static func makeAnalyser(jobs: Int) throws -> Analyser {
        let base = try Builder.makeAnalyser(jobs: jobs)
        guard base.vocalTagger != nil, let path = PANNs.locateModel() else { return base }
        let session = base.beatTracker.session
        let panns = try PANNs(modelPath: path, runtime: session.runtime, options: session.options)
        return try Analyser(beatTracker: base.beatTracker, vocalTagger: base.vocalTagger, secondOpinion: panns)
    }
}
