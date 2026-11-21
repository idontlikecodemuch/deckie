// deckie-desk-engine: Deckie Desk's engine on Windows and Linux (D32), a program with no window. The window
// (desk-shell) starts it and speaks to it in one JSON message a line over standard input and output
// (docs/architecture/desk-protocol.md); everything it does is DeckieDesk's (DeskProtocol, DeskSession, DeskRun).
// Its own log lines go to standard error. It exits when its input closes or on {"type":"quit"}.
//
// Desk's storage is DeskHome.standard (DECKIE_DESK_HOME moves it, for tests and trials); DJ libraries are looked for
// as DeskLocalFacts says (DECKIE_DJ_HOME). DECKIE_DESK_JOBS sets the run's jobs; else half the cores, at most 4,
// fewer when memory is short (DeskJobs). ONNX Runtime and the two models are
// found by the environment variables the core reads, else beside this program, else in the checkout.
import Foundation
import DeckieDesk
import DeckieEngine
import DeckieInference

// In the Windows zip the engine's files sit beside this program (onnxruntime.dll, models/), as they do beside
// deckie-make; they are looked for there before the checkout a developer runs from.
OnnxRuntime.programFolder = Bundle.main.executableURL?.deletingLastPathComponent()
    ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()

let stdout = FileHandle.standardOutput
let home = DeskHome.standard()
let device = Analysis.platform
let jobs = DeskJobs.current()

let engine = DeskProtocol(home: home, output: { data in
    var line = data
    line.append(0x0A)
    stdout.write(line)
}, makeRun: { home, crateId, request in
    // No recognition signatures here: ShazamKit is Apple's only. The print that finds copies is the shared decoder's,
    // made from the audio the analysis decoded (the same samples), so each song is read once.
    DeskRun(home: home, crateId: crateId, request: request, jobs: jobs.count, device: device,
            signer: nil, printer: DeskRun.portablePrint, audioPrinter: DeskRun.portableAudioPrint, jobsBy: jobs.reason)
})

FileHandle.standardError.write(Data("deckie-desk-engine: protocol \(DeskProtocol.version), storage \(home.root.path)\n".utf8))
FileHandle.standardError.write(Data("deckie-desk-engine: \(jobs.count) songs at once (by \(jobs.reason.rawValue))\n".utf8))
// Which key reader the runs use, for a tester's check log (the window passes these lines on): the learned one when its
// pinned file was found, else the untrained one and why.
FileHandle.standardError.write(Data("deckie-desk-engine: \(KeyModel.readerLine)\n".utf8))
engine.start()
while let line = readLine(strippingNewline: true) {
    if !engine.handle(line: line) { break }
}
// The window closed (or asked to quit): the microphone is let go of before the engine ends.
engine.stopBooth()
exit(0)
