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
                // One list holds every group, and tells its rows apart by their ids alone: each says its group and
                // its file (`LogRowID`), so no two rows share one. (Ids that were a row's index in its group repeated
                // in every group, and a file showed under another group's heading; Nov 25, 2026.)
                List {
                    ForEach(groups, id: \.key) { reason, entries in
                        Section(Words.reasonCount(reason, entries.count)) {
                            ForEach(LogRowID.rows(entries, reason: reason), id: \.id) { row in
                                // A plain line, or none where the heading says it; the decoder's words on hover.
                                VStack(alignment: .leading) {
                                    Text(row.entry.rel).font(Look.Fonts.importLogFile).lineLimit(1)
                                    if let plain = DeskWords.reasonDetail(reason, raw: row.entry.message) {
                                        Text(plain).font(Look.Fonts.importLogMessage).foregroundStyle(.secondary)
                                    }
                                }
                                .help(row.entry.message)
                            }
                        }
                    }
                }
            } else { Text(Words.noRecord).foregroundStyle(.secondary) }
            HStack { Spacer(); Button(Words.done) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(Look.Space.sheetPadding).frame(minWidth: Look.Size.importLogMinWidth, minHeight: Look.Size.importLogMinHeight)
    }
}

/// A row's identity in "What didn't go in": its group (the reason), its file, and the how-manyth time that file is in
/// the group (0 for the first), so it is unique across every group of the one list.
struct LogRowID: Hashable {
    var reason: String
    var rel: String
    var nth: Int

    struct Row { var id: LogRowID; var entry: CrateManifest.ImportLog.Entry }

    static func rows(_ entries: [CrateManifest.ImportLog.Entry], reason: String) -> [Row] {
        var seen: [String: Int] = [:]
        return entries.map { e in
            let n = seen[e.rel, default: 0]
            seen[e.rel] = n + 1
            return Row(id: LogRowID(reason: reason, rel: e.rel, nth: n), entry: e)
        }
    }
}
