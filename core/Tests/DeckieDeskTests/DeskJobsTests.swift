import Foundation
import Testing
import DeckieBuild
@testable import DeckieDesk

/// How many songs a Desk run reads at once: half the cores, at most 4, fewer when memory is short by the builder's
/// rule (`JobMemory`: 1.5 GB a job, 2 GB kept back), `DECKIE_DESK_JOBS` over both, one for a music CD.
@Suite struct DeskJobsTests {
    static let gb: UInt64 = 1 << 30

    /// cores x memory (GB) -> (jobs, why).
    static let table: [(cores: Int, gb: UInt64, jobs: Int, by: DeskJobs.Reason)] = [
        (2, 4, 1, .cores), (2, 8, 1, .cores), (2, 16, 1, .cores), (2, 24, 1, .cores),
        (4, 4, 1, .memory), (4, 8, 2, .cores), (4, 16, 2, .cores), (4, 24, 2, .cores),
        (8, 4, 1, .memory), (8, 8, 4, .cores), (8, 16, 4, .cores), (8, 24, 4, .cores),
        (10, 4, 1, .memory), (10, 8, 4, .cores), (10, 16, 4, .cores), (10, 24, 4, .cores),
    ]

    @Test func coresByMemory() {
        for row in Self.table {
            let j = DeskJobs.choose(cores: row.cores, physicalMemory: row.gb * Self.gb)
            #expect(j == DeskJobs(count: row.jobs, reason: row.by), "\(row.cores) cores, \(row.gb) GB")
        }
    }

    @Test func memoryRuleIsTheBuilders() {
        #expect(JobMemory.jobsAllowed(physicalMemory: 4 * Self.gb) == 1)
        #expect(JobMemory.jobsAllowed(physicalMemory: 6 * Self.gb) == 2)
        #expect(JobMemory.jobsAllowed(physicalMemory: 8 * Self.gb) == 4)
        #expect(JobMemory.jobsAllowed(physicalMemory: 16 * Self.gb) == 9)
        // A "4 GB" PC often reports a little less than 4 GB: still one job.
        #expect(JobMemory.jobsAllowed(physicalMemory: 4 * Self.gb - (200 << 20)) == 1)
        // Never fewer than one, however little memory.
        #expect(JobMemory.jobsAllowed(physicalMemory: Self.gb) == 1)
        #expect(JobMemory.jobsAllowed(physicalMemory: 0) == 1)
        #expect(DeskJobs.choose(cores: 16, physicalMemory: 2 * Self.gb) == DeskJobs(count: 1, reason: .memory))
        #expect(DeskJobs.choose(cores: 1, physicalMemory: 16 * Self.gb) == DeskJobs(count: 1, reason: .cores))
    }

    @Test func overrideWins() {
        let set = ["DECKIE_DESK_JOBS": "3"]
        #expect(DeskJobs.choose(cores: 10, physicalMemory: 4 * Self.gb, environment: set) == DeskJobs(count: 3, reason: .set))
        #expect(DeskJobs.choose(cores: 2, physicalMemory: 4 * Self.gb, environment: set) == DeskJobs(count: 3, reason: .set))
        // Nothing usable set: the rule.
        for bad in ["0", "-2", "many", ""] {
            #expect(DeskJobs.choose(cores: 10, physicalMemory: 4 * Self.gb, environment: ["DECKIE_DESK_JOBS": bad])
                    == DeskJobs(count: 1, reason: .memory))
        }
        #expect(DeskProtocol.jobs(environment: ["DECKIE_DESK_JOBS": "5"]) == 5)
        #expect(DeskProtocol.jobs(environment: [:]) == DeskJobs.current(environment: [:]).count)
    }

    @Test func discIsOneJob() {
        for row in Self.table {
            #expect(DeskJobs.choose(cores: row.cores, physicalMemory: row.gb * Self.gb, disc: true)
                    == DeskJobs(count: 1, reason: .disc))
        }
        #expect(DeskJobs.choose(cores: 10, physicalMemory: 24 * Self.gb, environment: ["DECKIE_DESK_JOBS": "4"], disc: true)
                == DeskJobs(count: 1, reason: .disc))
    }
}
