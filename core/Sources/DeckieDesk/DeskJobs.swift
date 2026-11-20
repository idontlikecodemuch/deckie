import Foundation
import DeckieBuild

/// How many songs a Desk run analyses at once, and why, for the Windows and Linux engine (`deckie-desk-engine`) and
/// the Mac app alike: half the cores, at most 4, or fewer when memory is short by the builder's own rule
/// (`JobMemory`, the one deckie-build's `defaultJobs` uses), never fewer than one. `DECKIE_DESK_JOBS` wins over both.
/// A music CD is read one song at a time whatever this says (the builder takes one job for it).
public struct DeskJobs: Equatable, Sendable {
    /// Why the count is what it is, as the run log records it (`jobs_by`).
    public enum Reason: String, Sendable {
        /// Half the cores, at most 4.
        case cores
        /// Fewer than the cores allow, as memory is short.
        case memory
        /// Set by `DECKIE_DESK_JOBS`.
        case set
        /// A music CD: one song at a time.
        case disc
    }

    public let count: Int
    public let reason: Reason

    public init(count: Int, reason: Reason) { self.count = max(1, count); self.reason = reason }

    /// The most jobs the cores rule gives.
    public static let mostByCores = 4

    /// The rule as a pure function of the machine and the environment.
    public static func choose(cores: Int, physicalMemory: UInt64, environment: [String: String] = [:],
                              disc: Bool = false) -> DeskJobs {
        if disc { return DeskJobs(count: 1, reason: .disc) }
        if let j = environment["DECKIE_DESK_JOBS"].flatMap(Int.init), j > 0 { return DeskJobs(count: j, reason: .set) }
        let byCores = max(1, min(cores / 2, mostByCores))
        let byMemory = JobMemory.jobsAllowed(physicalMemory: physicalMemory)
        return byMemory < byCores ? DeskJobs(count: byMemory, reason: .memory) : DeskJobs(count: byCores, reason: .cores)
    }

    /// The rule on this machine.
    public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> DeskJobs {
        choose(cores: ProcessInfo.processInfo.activeProcessorCount, physicalMemory: ProcessInfo.processInfo.physicalMemory,
               environment: environment)
    }
}
