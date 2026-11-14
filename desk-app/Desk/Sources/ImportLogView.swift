import SwiftUI
import DeckieCrate

/// What didn't go in: files that are not in the crate, and songs with a note (a damaged frame, a protected file),
/// never skipped silently.
struct ImportLogView: View {
    @EnvironmentObject var model: DeskModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Look.Space.importLog) {
            Text(Words.whatDidntGoIn).font(Look.Fonts.sheetTitle)
            if let log = model.crate?.manifest.importLog {
                Text(Words.readOn(log.builtBy, log.builtAt, seen: log.filesSeen, songs: log.tracks))
                    .foregroundStyle(.secondary)
                let groups = Dictionary(grouping: log.entries, by: \.reason).sorted { $0.key < $1.key }
                if groups.isEmpty { Text(Words.everySongWentIn).padding(.top, Look.Space.importLogEmptyAbove) }
                List {
                    ForEach(groups, id: \.key) { reason, entries in
                        Section(Words.reasonCount(reason, entries.count)) {
                            ForEach(entries.indices, id: \.self) { i in
                                VStack(alignment: .leading) {
                                    Text(entries[i].rel).font(Look.Fonts.importLogFile).lineLimit(1)
                                    Text(entries[i].message).font(Look.Fonts.importLogMessage).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else { Text(Words.noRecord).foregroundStyle(.secondary) }
            HStack { Spacer(); Button(Words.done) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(Look.Space.sheetPadding).frame(minWidth: Look.Size.importLogMinWidth, minHeight: Look.Size.importLogMinHeight)
    }
}
