// deckie-make: the PC program a DJ drags a music folder onto (D29, first step). In the zip it is started by
// "Make Crate File.exe" (core/Tools/windows/launcher.c), which passes on whatever was dropped on it.
//
//   deckie-make [<music folder> ...] [--no-wait] [--jobs N] [--work <folder>]
//
// With a folder (what Windows passes when a folder is dropped on the program), it makes that folder's crate file.
// With none (a double click), it asks for the folder in the console window, in plain words. It shows each song as it
// is read with the time left, writes the crate file in its single-file form next to the music folder, named after
// it, with a log beside it, says what went in and what did not, and waits for Enter so the window does not vanish.
// --no-wait (for scripts and the workflows) does not wait; --jobs and --work are for tests. The logic is DeckiePC.

import Foundation
import DeckiePC
#if os(Windows)
import WinSDK
#endif

/// One line to the console. The console is set to UTF-8 below, so names that are not ASCII show as written.
func say(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

/// A line typed (or a folder dropped) at the prompt. On Windows the console is read as UTF-16, which is the only way
/// a name that is not ASCII arrives whole on every version of Windows.
func readAnswer() -> String? {
    #if os(Windows)
    let input = GetStdHandle(STD_INPUT_HANDLE)
    var mode: DWORD = 0
    if let input, GetConsoleMode(input, &mode) {
        var buffer = [WCHAR](repeating: 0, count: 8192)
        var count: DWORD = 0
        guard ReadConsoleW(input, &buffer, DWORD(buffer.count - 1), &count, nil), count > 0 else { return nil }
        return String(decoding: buffer[0..<Int(count)], as: UTF16.self)
    }
    #endif
    return readLine(strippingNewline: true)
}

/// What was typed or dropped, as a path: without the quotes Windows puts round a dropped path that has a space.
func cleaned(_ answer: String) -> String {
    var s = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") { s = String(s.dropFirst().dropLast()) }
    if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") { s = String(s.dropFirst().dropLast()) }
    return s
}

#if os(Windows)
// The console shows and takes UTF-8, and the PC does not go to sleep in the middle of a long read.
_ = SetConsoleOutputCP(65001)
_ = SetConsoleCP(65001)
_ = SetThreadExecutionState(EXECUTION_STATE(0x8000_0000 | 0x0000_0001))  // ES_CONTINUOUS | ES_SYSTEM_REQUIRED
#endif

/// The whole program; returns the exit code and whether to wait for Enter before the window closes.
func program() -> (code: Int32, wait: Bool) {
    var folders: [String] = []
    var wait = true
    var jobs = PCBuild.defaultJobs
    var workRoot = PCBuild.defaultWorkRoot
    var args = Array(CommandLine.arguments.dropFirst())[...]
    while let arg = args.popFirst() {
        switch arg {
        case "--no-wait": wait = false
        case "--jobs": if let n = args.popFirst().flatMap({ Int($0) }), n >= 1 { jobs = n }
        case "--work": if let w = args.popFirst() { workRoot = URL(fileURLWithPath: w) }
        default: folders.append(cleaned(arg))
        }
    }

    say(PCWords.hello(version: PCBuild.version))
    say("")

    // The engine's files sit beside this program in the zip.
    let here = Bundle.main.executableURL?.deletingLastPathComponent()
        ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let engine: PCBuild.EngineFiles
    do {
        engine = try PCBuild.EngineFiles.locate(beside: here)
    } catch {
        say((error as? PCError)?.words ?? "\(error)")
        return (3, wait)
    }

    // A double click: ask for the folder until one is given that is there.
    if folders.isEmpty {
        while true {
            say(PCWords.askForFolder)
            FileHandle.standardOutput.write(Data(PCWords.prompt.utf8))
            // No answer at all: the window was closed, or there is no console to ask in.
            guard let answer = readAnswer() else { return (2, false) }
            let path = cleaned(answer)
            if path.isEmpty { say(PCWords.nothingTyped); say(""); continue }
            do {
                _ = try PCBuild.plan(folder: URL(fileURLWithPath: path), workRoot: workRoot)
                folders = [path]
                break
            } catch {
                say((error as? PCError)?.words ?? "\(error)")
                say("")
            }
        }
    }

    var failures = 0
    for path in folders {
        do {
            let plan = try PCBuild.plan(folder: URL(fileURLWithPath: path), workRoot: workRoot)
            do {
                let outcome = try PCBuild.run(plan, engine: engine, jobs: jobs, say: { say($0) })
                say(PCBuild.summary(outcome))
            } catch {
                failures += 1
                say("")
                say((error as? PCError)?.words ?? PCWords.wentWrong("\(error)"))
                if case PCError.failed = error { say(PCWords.sendLog(plan.logFile.path)) }
            }
        } catch {
            failures += 1
            say((error as? PCError)?.words ?? "\(error)")
        }
        if folders.count > 1 { say("") }
    }
    return (failures == 0 ? 0 : 1, wait)
}

let (code, wait) = program()
if wait {
    say("")
    say(PCWords.pressEnter)
    _ = readAnswer()
}
exit(code)
