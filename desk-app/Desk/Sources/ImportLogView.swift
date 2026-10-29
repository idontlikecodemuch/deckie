import SwiftUI
import DeckieCrate

/// Files that are not in the crate, and tracks with a note (a damaged frame, a protected file): never skipped silently.
struct ImportLogView: View {
    @EnvironmentObject var model: DeskModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import log").font(.title2)
            if let log = model.crate?.manifest.importLog {
                Text("Built on \(log.builtBy) at \(log.builtAt): \(log.filesSeen) files seen, \(log.tracks) tracks in the crate.")
                    .foregroundStyle(.secondary)
                let groups = Dictionary(grouping: log.entries, by: \.reason).sorted { $0.key < $1.key }
                if groups.isEmpty { Text("Every file went in cleanly.").padding(.top) }
                List {
                    ForEach(groups, id: \.key) { reason, entries in
                        Section("\(Self.plain(reason)) (\(entries.count))") {
                            ForEach(entries.indices, id: \.self) { i in
                                VStack(alignment: .leading) {
                                    Text(entries[i].rel).font(.system(.body, design: .monospaced)).lineLimit(1)
                                    Text(entries[i].message).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else { Text("This crate carries no import log.").foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(minWidth: 640, minHeight: 420)
    }

    static func plain(_ reason: String) -> String {
        switch reason {
        case "unsupported": return "File type not supported"
        case "protected": return "Protected, cannot be read"
        case "damaged_frames": return "Damaged frames, played as silence"
        case "decode_failed", "decode": return "Could not be decoded"
        case "analysis_failed", "analysis": return "Analysis failed"
        default: return reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
