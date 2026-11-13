import Foundation

let arguments = CommandLine.arguments.dropFirst()
if arguments.contains("--self-test") {
    SelfTest.run(seconds: Double(ProcessInfo.processInfo.environment["DECKIE_SELF_TEST_SECONDS"] ?? "") ?? 60)
}
