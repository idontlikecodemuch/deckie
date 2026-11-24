import SwiftUI
import AVKit
import DeckieDesk

/// The quick start on the Mac (D46): the bundled film (`Contents/Resources/quick-start/`, copied from
/// `desk-web/quick-start/`; nothing is fetched), offered on the first screen as a card the DJ starts, and played
/// again from Help > Watch the quick start. Whether the card was hidden is kept where the Windows and Linux window
/// keeps it, in Desk's storage (`DeskQuickStart`, `quick-start.json`).
///
/// A film that cannot play never shows as a dead player: a missing file, an asset the system says is not playable, or
/// a player item that fails, each turns the card and the player to the poster and the film's steps in words.
enum QuickStartFiles {
    static var film: URL? { file(DeskQuickStart.filmFile) }
    static var poster: URL? { file(DeskQuickStart.posterFile) }
    /// The card's own picture (Nov 24, 2026), with nothing to read behind the play button; the poster is the film's
    /// title frame, unreadable at card size.
    static var cardPicture: URL? { file(DeskQuickStart.cardFile) }
    private static func file(_ name: String) -> URL? {
        guard let u = Bundle.main.resourceURL?.appendingPathComponent(DeskQuickStart.folder).appendingPathComponent(name),
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }
}

/// The first screen's card: the poster with a play button and one line; or, where the film cannot play, the poster
/// with the steps in words. Hide remembers it is hidden.
struct QuickStartCard: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        HStack(alignment: model.filmPlays ? .center : .top, spacing: Look.QuickStart.cardGap) {
            ZStack {
                // Behind the play button, the card's own picture; where the film cannot play, the title frame,
                // as nothing covers it there.
                QuickStartPoster(forCard: model.filmPlays)
                if model.filmPlays {
                    Button { model.showFilm = true } label: {
                        Image(systemName: "play.fill").font(Look.QuickStart.playFont).foregroundStyle(Look.QuickStart.playMark)
                            .frame(width: Look.QuickStart.playSize, height: Look.QuickStart.playSize)
                            .background(Look.QuickStart.playGround, in: Circle())
                    }
                    .buttonStyle(.plain).help(Words.t("quickStartPlay")).accessibilityLabel(Words.t("quickStartPlay"))
                }
            }
            .frame(width: Look.QuickStart.posterWidth, height: Look.QuickStart.posterWidth / Look.QuickStart.ratio)
            .clipShape(RoundedRectangle(cornerRadius: Look.QuickStart.posterCorner))
            VStack(alignment: .leading) {
                if model.filmPlays {
                    Text(Words.t("quickStartOffer")).font(Look.QuickStart.newFont)
                    Button(Words.t("quickStartWatch")) { model.showFilm = true }
                        .buttonStyle(.link).font(Look.QuickStart.offerFont).multilineTextAlignment(.leading)
                } else {
                    QuickStartWords()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(Words.t("quickStartHide")) { model.hideQuickStart() }
                .controlSize(.small).help(Words.t("quickStartHideHelp", ["quickStartAt": Words.t("quickStartAt.menu")]))
        }
        .padding(Look.QuickStart.cardPadding)
        .frame(maxWidth: Look.QuickStart.cardWidth)
        .background(Look.QuickStart.cardFill, in: RoundedRectangle(cornerRadius: Look.QuickStart.cardCorner))
        .overlay(RoundedRectangle(cornerRadius: Look.QuickStart.cardCorner).strokeBorder(Look.QuickStart.cardEdge, lineWidth: Look.QuickStart.cardLine))
        .task { await model.checkFilm() }
    }
}

/// The poster, the film's title frame; with `forCard`, the card's own picture, or the poster when that is missing or
/// does not read.
struct QuickStartPoster: View {
    var forCard = false
    var body: some View {
        if let image = Self.image(forCard: forCard) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(Look.QuickStart.filmGround)
        }
    }

    static func image(forCard: Bool) -> NSImage? {
        if forCard, let u = QuickStartFiles.cardPicture, let image = NSImage(contentsOf: u), image.isValid { return image }
        return QuickStartFiles.poster.flatMap { NSImage(contentsOf: $0) }
    }
}

/// The film's steps in words: the same four lines the pages show.
struct QuickStartWords: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Look.QuickStart.wordsGap) {
            Text(Words.t("quickStartInWords")).font(Look.QuickStart.wordsHeading)
            Text(Words.t("quickStartNoPlayer")).font(Look.QuickStart.wordsNote).foregroundStyle(.secondary)
            ForEach(Array(DeskWords.list("quickStartStep").enumerated()), id: \.offset) { i, step in
                Text(Words.t("quickStartStepLine", ["n": "\(i + 1)", "step": step]))
                    .font(Look.QuickStart.stepFont).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The player, in a sheet: the film from its start; its steps in words when it cannot play.
struct QuickStartPlayer: View {
    @EnvironmentObject var model: DeskModel
    @State private var player: AVPlayer?
    @State private var watch: NSKeyValueObservation?
    var body: some View {
        VStack(alignment: .trailing, spacing: Look.QuickStart.playerGap) {
            if model.filmPlays, let player {
                VideoPlayer(player: player)
                    .aspectRatio(Look.QuickStart.ratio, contentMode: .fit)
                    .frame(minWidth: Look.QuickStart.playerMinWidth)
            } else {
                HStack(alignment: .top, spacing: Look.QuickStart.cardGap) {
                    QuickStartPoster()
                        .frame(width: Look.QuickStart.posterWidth, height: Look.QuickStart.posterWidth / Look.QuickStart.ratio)
                        .clipShape(RoundedRectangle(cornerRadius: Look.QuickStart.posterCorner))
                    // A set width: given only a most, the sheet squeezed the steps to half of it (Nov 23, 2026).
                    QuickStartWords().frame(width: Look.QuickStart.wordsWidth, alignment: .leading)
                }
            }
            Button(Words.t("quickStartClose")) { model.showFilm = false }.keyboardShortcut(.cancelAction).buttonStyle(.borderedProminent)
        }
        .padding(Look.QuickStart.playerPadding)
        .onAppear(perform: start)
        .onDisappear { player?.pause(); watch = nil }
    }

    private func start() {
        guard model.filmPlays, let u = QuickStartFiles.film else { model.filmPlays = false; return }
        let item = AVPlayerItem(url: u)
        // The item fails (a film this Mac cannot decode): the steps instead, never a dead player.
        watch = item.observe(\.status) { item, _ in
            if item.status == .failed { Task { @MainActor in model.filmPlays = false } }
        }
        let p = AVPlayer(playerItem: item)
        player = p
        p.play()
        model.filmStarted()
    }
}
