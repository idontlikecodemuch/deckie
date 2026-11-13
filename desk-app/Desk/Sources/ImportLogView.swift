import SwiftUI
import DeckieCrate

/// What didn't go in: files that are not in the crate, and songs with a note (a damaged frame, a protected file),
/// never skipped silently.
struct ImportLogView: View {
    @EnvironmentObject var model: DeskModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Words.whatDidntGoIn).font(.title2)
            if let log = model.crate?.manifest.importLog {
                Text(Words.readOn(log.builtBy, log.builtAt, seen: log.filesSeen, songs: log.tracks))
                    .foregroundStyle(.secondary)
                let groups = Dictionary(grouping: log.entries, by: \.reason).sorted { $0.key < $1.key }
                if groups.isEmpty { Text(Words.everySongWentIn).padding(.top) }
                List {
                    ForEach(groups, id: \.key) { reason, entries in
                        Section(Words.reasonCount(reason, entries.count)) {
                            ForEach(entries.indices, id: \.self) { i in
                                VStack(alignment: .leading) {
                                    Text(entries[i].rel).font(.system(.body, design: .monospaced)).lineLimit(1)
                                    Text(entries[i].message).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else { Text(Words.noRecord).foregroundStyle(.secondary) }
            HStack { Spacer(); Button(Words.done) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(minWidth: 640, minHeight: 420)
    }
}
