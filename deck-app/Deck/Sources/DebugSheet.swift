import SwiftUI
import UniformTypeIdentifiers


struct DebugSheet: View {
    @Environment(Recognizer.self) private var rec
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var start = 60.0
    @State private var render = "o"
    @State private var loop = true
    @State private var files: [URL] = []
    @State private var setFiles: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Test with file") {
                    Stepper("Start at \(Int(start)) s", value: $start, in: 0...600, step: 15)
                    Picker("Play it as", selection: $render) {
                        Text("original").tag("o")
                        Text("vinyl −8").tag("r-8"); Text("vinyl −4").tag("r-4"); Text("vinyl +4").tag("r+4"); Text("vinyl +8").tag("r+8")
                        Text("tempo −4").tag("t-4"); Text("tempo +4").tag("t+4"); Text("tempo +8").tag("t+8")
                    }
                    Toggle("Keep going (simulate playing)", isOn: $loop)
                    Button("Choose an audio file…") { importing = true }
                    ForEach(files, id: \.self) { u in
                        Button(u.lastPathComponent) { rec.testFile(u, start: start, render: render, loop: loop); dismiss() }
                    }
                }
                Section("Set recording") {
                    @Bindable var rec = rec
                    Toggle("Record while listening", isOn: $rec.recordingOn)
                    if rec.recActive { Button(rec.recPaused ? "Resume recording" : "Pause recording") { rec.toggleRecPause() } }
                    Text("Files: Files app > On My iPad > Deck > Sets (or Finder > iPad > Files).").font(.footnote).foregroundStyle(.secondary)
                    ForEach(setFiles, id: \.self) { Text($0).font(.system(size: 13, design: .monospaced)) }
                }
                Section("Status") {
                    LabeledContent("Matches", value: "\(rec.matchCount)")
                    LabeledContent("Last match latency", value: String(format: "%.0f ms", rec.lastLatencyMs))
                    if let f = rec.firstMatchSeconds { LabeledContent("Time to recognise current song", value: String(format: "%.1f s", f)) }
                    LabeledContent("Pitch", value: "\(signed1(rec.pitchPct))% \(rec.pitchKind.rawValue) (\(rec.pitchFrom))")
                    Button("Back to the microphone") { rec.startMic(); dismiss() }
                }
                Section("Log") {
                    ForEach(Array(rec.log.reversed().enumerated()), id: \.offset) { Text($0.element).font(.system(size: 12, design: .monospaced)) }
                }
            }
            .navigationTitle("Debug")
            .toolbar { Button("Done") { dismiss() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav]) { r in
                if case .success(let u) = r { rec.testFile(u, start: start, render: render, loop: loop); dismiss() }
            }
            .onAppear {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                setFiles = ((try? FileManager.default.contentsOfDirectory(atPath: SetRecorder.folder.path)) ?? []).sorted()
                files = ((try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []).filter { ["mp3", "m4a", "wav", "aif", "aiff"].contains($0.pathExtension.lowercased()) }
            }
        }
    }
}

/// Microphone input level: shows that the iPad hears the music.
struct LevelMeter: View {
    let db: Float
    var body: some View {
        let x = CGFloat(min(1, max(0, (db + 60) / 60)))
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.1))
            Capsule().fill(LinearGradient(colors: [Theme.mix, Theme.ok, Theme.amber], startPoint: .leading, endPoint: .trailing)).frame(width: 70 * x)
        }
        .frame(width: 70, height: 8)
        .accessibilityLabel("Input level")
    }
}
