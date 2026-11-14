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
                Section(Words.testWithFileSection) {
                    Stepper(Words.startAt(Int(start)), value: $start, in: 0...600, step: 15)
                    Picker(Words.playItAs, selection: $render) {
                        ForEach(Words.renders, id: \.code) { Text($0.words).tag($0.code) }
                    }
                    Toggle(Words.keepGoing, isOn: $loop)
                    Button(Words.chooseAudioFile) { importing = true }
                    ForEach(files, id: \.self) { u in
                        Button(u.lastPathComponent) { rec.testFile(u, start: start, render: render, loop: loop); dismiss() }
                    }
                }
                Section(Words.setRecording) {
                    @Bindable var rec = rec
                    Toggle(Words.recordWhileListening, isOn: $rec.recordingOn)
                    if rec.recActive { Button(rec.recPaused ? Words.resumeRecording : Words.pauseRecording) { rec.toggleRecPause() } }
                    Text(Words.setFilesWhere).font(Look.Debug.noteFont).foregroundStyle(.secondary)
                    ForEach(setFiles, id: \.self) { Text($0).font(Look.Debug.fileFont) }
                }
                Section(Words.status) {
                    LabeledContent(Words.matches, value: "\(rec.matchCount)")
                    LabeledContent(Words.lastLatency, value: Words.milliseconds(rec.lastLatencyMs))
                    if let f = rec.firstMatchSeconds { LabeledContent(Words.timeToRecognise, value: Words.seconds(f)) }
                    LabeledContent(Words.pitch, value: Words.pitchValue(signed1(rec.pitchPct), rec.pitchKind.rawValue, rec.pitchFrom))
                    Button(Words.backToMic) { rec.startMic(); dismiss() }
                }
                Section(Words.log) {
                    ForEach(Array(rec.log.reversed().enumerated()), id: \.offset) { Text($0.element).font(Look.Debug.logFont) }
                }
            }
            .navigationTitle(Words.debugTitle)
            .toolbar { Button(Words.done) { dismiss() } }
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
            Capsule().fill(Look.Debug.meterTrack)
            Capsule().fill(LinearGradient(colors: [Theme.mix, Theme.ok, Theme.amber], startPoint: .leading, endPoint: .trailing)).frame(width: Look.Debug.meterWidth * x)
        }
        .frame(width: Look.Debug.meterWidth, height: Look.Debug.meterHeight)
        .accessibilityLabel(Words.inputLevel)
    }
}
