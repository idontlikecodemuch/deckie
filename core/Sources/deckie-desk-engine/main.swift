// deckie-desk-engine: Deckie Desk's engine on Windows and Linux (D32), a program with no window. The window
// (desk-shell) starts it and speaks to it in one JSON message a line over standard input and output
// (docs/architecture/desk-protocol.md); everything it does is DeckieDesk's (DeskProtocol, DeskSession, DeskRun).
// Its own log lines go to standard error. It exits when its input closes or on {"type":"quit"}.
//
// Desk's storage is DeskHome.standard (DECKIE_DESK_HOME moves it, for tests and trials); DJ libraries are looked for
// as DeskLocalFacts says (DECKIE_DJ_HOME). DECKIE_DESK_JOBS sets the run's jobs.
import Foundation
import DeckieDesk
import DeckieEngine

let stdout = FileHandle.standardOutput
let home = DeskHome.standard()
let device = Analysis.platform
let jobs = DeskProtocol.jobs()

let engine = DeskProtocol(home: home, output: { data in
    var line = data
    line.append(0x0A)
    stdout.write(line)
}, makeRun: { home, crateId, request in
    // No recognition signatures here: ShazamKit is Apple's only. The print that finds copies is the shared decoder's.
    DeskRun(home: home, crateId: crateId, request: request, jobs: jobs, device: device,
            signer: nil, printer: DeskRun.portablePrint)
})

FileHandle.standardError.write(Data("deckie-desk-engine: protocol \(DeskProtocol.version), storage \(home.root.path)\n".utf8))
engine.start()
while let line = readLine(strippingNewline: true) {
    if !engine.handle(line: line) { break }
}
exit(0)
