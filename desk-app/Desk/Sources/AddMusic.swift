import SwiftUI
import UniformTypeIdentifiers
import DeckieDesk
import DeckieDisc

// Adding music, the same everywhere a DJ adds it (research AE): the three ways in (DeskAddMusic.ways, shared with the
// Windows and Linux window), the drive and CD pickers, a big drive's choice, the count and the question before a large
// read; and the crate's name with its icon, shown and renamed in the header and on the run screen.

/// The step of adding music the window is showing, as a sheet.
enum AddStep: Identifiable, Equatable {
    /// Add drive's list, and Add CD's.
    case drives, cds
    /// A big drive: choose a folder inside it, or read it whole.
    case bigDrive(DeskDrives.Drive)
    /// Counting the songs before reading (shown once it takes longer than a moment).
    case counting(name: String, songs: Int)
    /// The question before a large read.
    case ask(DeskAddMusic.Check, url: URL, name: String)

    var id: String {
        switch self {
        case .drives: return "drives"
        case .cds: return "cds"
        case let .bigDrive(d): return "big:" + d.path
        case .counting: return "counting"
        case .ask: return "ask"
        }
    }
}

extension DeskAddMusic.Way {
    var title: String { Words.t(word) }
    var helpText: String { Words.t(help) }
}

/// The three ways as buttons in a row: the first screen's, and the crate screen's under its songs.
struct AddWayButtons: View {
    @EnvironmentObject var model: DeskModel
    var prominent = false
    var body: some View {
        HStack(spacing: Look.Add.waysGap) {
            ForEach(DeskAddMusic.ways, id: \.id) { w in
                if prominent {
                    Button { model.addWay(w.id) } label: { Label(w.title, systemImage: w.macSymbol) }
                        .buttonStyle(.borderedProminent).help(w.helpText)
                } else {
                    Button { model.addWay(w.id) } label: { Label(w.title, systemImage: w.macSymbol) }.help(w.helpText)
                }
            }
        }
        .disabled(model.running)
    }
}

/// The three ways as menu items: the toolbar's Add music, the finished screen's Add more music, and the File menu.
struct AddWayItems: View {
    @ObservedObject var model: DeskModel
    var body: some View {
        ForEach(DeskAddMusic.ways, id: \.id) { w in
            Button { model.addWay(w.id) } label: { Label(w.title, systemImage: w.macSymbol) }.help(w.helpText)
        }
    }
}

/// A menu of the three ways, with words and an icon (research AE, problem 3: the toolbar's was an icon alone).
struct AddMusicMenu: View {
    @EnvironmentObject var model: DeskModel
    var label: String? = nil
    var body: some View {
        Menu {
            AddWayItems(model: model)
        } label: {
            Label(label ?? Words.addMusic, systemImage: "plus")
                .labelStyle(.titleAndIcon)
        }
        .help(Words.addMusicHelp)
        .disabled(model.running)
    }
}

/// The sheet for each step of adding music.
struct AddStepSheet: View {
    @EnvironmentObject var model: DeskModel
    let step: AddStep
    var body: some View {
        VStack(alignment: .leading, spacing: Look.Add.sheetGap) {
            switch step {
            case .drives: drivesList
            case .cds: cdsList
            case let .bigDrive(d): bigDrive(d)
            case let .counting(name, songs): counting(name, songs)
            case let .ask(check, url, name): ask(check, url, name)
            }
        }
        .padding(Look.Space.sheetPadding)
        .frame(width: Look.Add.sheetWidth)
    }

    private var plugged: [DeskDrives.Drive] { model.drives.filter { $0.kind == DeskDrives.Kind.drive } }
    private var dataCDs: [DeskDrives.Drive] { model.drives.filter { $0.kind == DeskDrives.Kind.cd } }

    @ViewBuilder private var drivesList: some View {
        Text(Words.chooseDriveTitle).font(Look.Fonts.sheetTitle)
        Text(Words.chooseDriveBody).foregroundStyle(.secondary)
        if plugged.isEmpty { Text(Words.noDriveIn).foregroundStyle(.secondary) }
        VStack(alignment: .leading, spacing: Look.Add.rowsGap) {
            ForEach(plugged, id: \.path) { d in
                row(symbol: d.big ? "externaldrive.fill" : "externaldrive", name: d.name,
                    detail: [d.size, d.big ? Words.driveBigNote : nil].compactMap { $0 }) { model.chooseDrive(d) }
            }
        }
        HStack { Spacer(); Button(Words.cancel, role: .cancel) { model.addStep = nil }.keyboardShortcut(.cancelAction) }
    }

    @ViewBuilder private var cdsList: some View {
        Text(Words.chooseCDTitle).font(Look.Fonts.sheetTitle)
        Text(Words.chooseCDBody).foregroundStyle(.secondary)
        if model.musicCDs.isEmpty && dataCDs.isEmpty { Text(Words.noCDIn).foregroundStyle(.secondary) }
        VStack(alignment: .leading, spacing: Look.Add.rowsGap) {
            ForEach(model.musicCDs, id: \.location) { cd in
                row(symbol: "opticaldisc", name: MusicCDItem.label(cd), detail: []) { model.addStep = nil; model.addMusicCD(cd) }
            }
            ForEach(dataCDs, id: \.path) { d in
                row(symbol: "opticaldisc", name: Words.dataCDItem(d.name), detail: [d.size].compactMap { $0 }) { model.chooseDrive(d) }
            }
        }
        HStack { Spacer(); Button(Words.cancel, role: .cancel) { model.addStep = nil }.keyboardShortcut(.cancelAction) }
    }

    private func row(symbol: String, name: String, detail: [String], _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Look.Add.rowGap) {
                Image(systemName: symbol).frame(width: Look.Add.rowIcon)
                VStack(alignment: .leading) {
                    Text(name).font(Look.Add.rowName)
                    if !detail.isEmpty { Text(Words.places(detail)).font(Look.Add.rowDetail).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(.vertical, Look.Add.rowPaddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func bigDrive(_ d: DeskDrives.Drive) -> some View {
        Text(Words.bigDriveTitle(d.name)).font(Look.Fonts.sheetTitle)
        Text(Words.bigDriveBody(d.size ?? "")).fixedSize(horizontal: false, vertical: true)
        HStack {
            Button(Words.readWholeDrive) { model.readWholeDrive(d) }
            Spacer()
            Button(Words.cancel, role: .cancel) { model.addStep = nil }.keyboardShortcut(.cancelAction)
            Button(Words.chooseFolderIn) { model.chooseFolder(in: d) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private func counting(_ name: String, _ songs: Int) -> some View {
        Text(Words.counting).font(Look.Fonts.sheetTitle)
        HStack(spacing: Look.Add.rowGap) {
            ProgressView().controlSize(.small)
            Text(Words.countingSoFar(songs)).font(Look.Add.count)
        }
        Text(name).foregroundStyle(.secondary)
        HStack { Spacer(); Button(Words.cancel, role: .cancel) { model.cancelAdd() }.keyboardShortcut(.cancelAction) }
    }

    @ViewBuilder private func ask(_ check: DeskAddMusic.Check, _ url: URL, _ name: String) -> some View {
        Text(Words.askReadTitle(check.songs, name)).font(Look.Fonts.sheetTitle)
        Text(Words.askReadBody(DeskAddMusic.aboutWords(check.seconds))).fixedSize(horizontal: false, vertical: true)
        if model.current == nil { NewCrateNameField() }
        else { Text(Words.intoCrate(model.shownName)).foregroundStyle(.secondary) }
        HStack {
            Spacer()
            Button(Words.cancel, role: .cancel) { model.cancelAdd() }.keyboardShortcut(.cancelAction)
            Button(Words.askReadStart(check.songs)) { model.confirmAdd(url, name: name) }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }
}

/// A new crate's name, on the first screen and in the question before a large read: filled in ("My crate"), the DJ
/// types over it.
struct NewCrateNameField: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        HStack {
            Text(Words.intoNewCrate).foregroundStyle(.secondary)
            TextField(Words.crateNameLabel, text: $model.newCrateName)
                .textFieldStyle(.roundedBorder).frame(width: Look.Add.nameFieldWidth)
                .accessibilityLabel(Words.crateNameLabel)
        }
    }
}

/// The crate's icon: Apple's box symbol, kept by the owner's choice (Nov 14, 2026). Named here once, for a design
/// pass to swap; the Windows and Linux pages draw a matching box (`icon-crate` in desk-web/index.html).
struct CrateIcon: View {
    static let symbol = "shippingbox"
    var size: CGFloat = Look.Add.crateIconHeader
    var body: some View {
        Image(systemName: Self.symbol).resizable().scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(Words.crateIcon)
    }
}

/// The crate's name with its icon; a click renames it (the crate showing, the one being read, or the new crate's).
struct CrateName: View {
    @EnvironmentObject var model: DeskModel
    @State private var renaming = false
    @State private var text = ""
    var body: some View {
        HStack(spacing: Look.Add.headerGap) {
            CrateIcon()
            Button { text = model.shownName; renaming = true } label: {
                Text(model.shownName).font(Look.Add.headerName).lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(Words.renameCrateHelp)
            .popover(isPresented: $renaming) {
                VStack(alignment: .leading, spacing: Look.Add.sheetGap) {
                    Text(Words.renameTitle(model.shownName)).font(Look.Fonts.panelTitle)
                    TextField(Words.nameField, text: $text).textFieldStyle(.roundedBorder).frame(width: Look.Add.renameWidth)
                        .onSubmit { commit() }
                    HStack {
                        Spacer()
                        Button(Words.cancel, role: .cancel) { renaming = false }.keyboardShortcut(.cancelAction)
                        Button(Words.renameButton) { commit() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    }
                }
                .padding(Look.Add.renamePadding)
            }
        }
    }

    private func commit() { renaming = false; model.renameShown(text) }
}

/// The run screen's header (research AE): the crate's name, to rename while it is read, and Stop.
struct RunHeader: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        HStack {
            CrateName()
            Spacer()
            if model.stopping { Text(Words.stoppingRun).foregroundStyle(.secondary) }
            Button(Words.stopRun) { model.stopRun() }.help(Words.stopRunHelp).disabled(model.stopping)
        }
    }
}

/// The crate screen's row of ways, under the songs (research AE, finding 1: a way back to add more, where the DJ is).
struct CrateAddRow: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        HStack(spacing: Look.Add.waysGap) {
            Text(Words.addMoreMusicTo(model.shownName)).foregroundStyle(.secondary)
            AddWayButtons().controlSize(.small)
            Spacer()
            Text(Words.dropHere).foregroundStyle(.tertiary)
        }
        .font(Look.Add.crateRow)
        .padding(.horizontal, Look.Add.crateRowH).padding(.vertical, Look.Add.crateRowV)
    }
}

/// A music CD as Add CD lists it: "Music CD, 14 songs, 71:12  ·  music CD in Audio CD".
enum MusicCDItem {
    static func label(_ cd: MusicCDs.Found) -> String {
        let secs = Int(cd.seconds.rounded())
        let name = Words.c("musicCDPlaceholder", cd.songs, ["length": Words.musicCDLength(secs)])
        return Words.t("musicCDItem", ["name": name, "drive": cd.drive])
    }
}
