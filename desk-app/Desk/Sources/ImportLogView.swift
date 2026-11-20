import SwiftUI
import DeckieCrate
import DeckieDesk

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
                    .foregroundStyle(.secondary).help(Words.readOnDetail(log.builtBy, log.builtAt))
                let groups = Dictionary(grouping: log.entries, by: \.reason).sorted { $0.key < $1.key }
                if groups.isEmpty { Text(Words.everySongWentIn).padding(.top, Look.Space.importLogEmptyAbove) }
                List {
                    ForEach(groups, id: \.key) { reason, entries in
                        Section(Words.reasonCount(reason, entries.count)) {
                            ForEach(entries.indices, id: \.self) { i in
                                // A plain line, or none where the heading says it; the decoder's words on hover.
                                VStack(alignment: .leading) {
                                    Text(entries[i].rel).font(Look.Fonts.importLogFile).lineLimit(1)
                                    if let plain = DeskWords.reasonDetail(reason, raw: entries[i].message) {
                                        Text(plain).font(Look.Fonts.importLogMessage).foregroundStyle(.secondary)
                                    }
                                }
                                .help(entries[i].message)
                            }
                        }
                    }
                }
            } else { Text(Words.noRecord).foregroundStyle(.secondary) }
            HStack { Spacer(); Button(Words.done) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(Look.Space.sheetPadding).frame(minWidth: Look.Size.importLogMinWidth, minHeight: Look.Size.importLogMinHeight)
    }
}
