import SwiftUI
import AppKit

// Every design value of Deckie Desk's Mac window, named, in one place (D36: "tag all values as variables so we can
// change them later"): colours, type, spacing, sizes, corners and times. The views and the drawing routines hold none
// of their own; the design pass changes this file. Each name says what the value is for, not what it is: two places
// that happen to share a value have two names. Left in the views, as the system's own named roles: the system's
// foreground and fill styles (.primary, .secondary, .tertiary, .quaternary, .bar, .tint), control styles
// (.borderedProminent, .small) and SF Symbol names; and the drawings' own arithmetic (64 points a wave, a mark every
// 8 bars, twelve keys round the wheel). The run screen's values are RunLook and the lookup's LookupStyle, below.
enum Look {
    enum Colour {
        /// A run that stopped, and what didn't go in.
        static let warning = Color.orange
        /// A name that is Desk's guess, under its field.
        static let guess = Color.orange
        /// A song's notes when it needs a name.
        static let needsName = Color.orange
        /// new (D36): the empty square of a song with no cover (or whose cover is still being read) in the names
        /// panel, as the pages' --cover-empty. A placeholder until the design pass.
        static let coverEmpty = Color.primary.opacity(0.07)
    }

    /// Type: each the font of one kind of text.
    enum Fonts {
        static let firstIcon = Font.system(size: 56)
        static let finishedIcon = Font.system(size: 48)
        /// The first screen's, the run's and the finished screen's titles.
        static let screenTitle = Font.title2
        static let sheetTitle = Font.title2
        static let banner = Font.callout
        static let leaveRunning = Font.caption
        static let runListLine = Font.system(.caption, design: .monospaced)
        static let runList = Font.callout
        static let runProgress = Font.callout
        static let statusBar = Font.callout
        static let discAskTitleWeight = Font.Weight.bold
        static let finishedMomentWeight = Font.Weight.semibold
        static let sayingMomentWeight = Font.Weight.semibold
        static let sayingWeight = Font.Weight.regular
        static let statusSongsWeight = Font.Weight.bold
        static let importLogFile = Font.system(.body, design: .monospaced)
        static let importLogMessage = Font.caption
        static let toolPaste = Font.system(.body, design: .monospaced)
        static let toolHelp = Font.caption
        static let toolPreviewTitle = Font.headline
        static let toolNote = Font.caption
        static let panelTitle = Font.headline
        static let sourcesCaption = Font.caption
        static let sourcesEmptyBody = Font.callout
        static let sourceName = Font.body.bold()
        static let sourcesSongNumber = Font.callout.monospacedDigit()
        static let sourcesSongMore = Font.caption.monospacedDigit()
        static let sourcesHint = Font.caption
        static let inspectorHeading = Font.headline
        /// The small label above each of the inspector's fields and lists.
        static let inspectorLabel = Font.caption
        /// The line under a field (where the name came from), and the file's left-out tags.
        static let inspectorSmallPrint = Font.caption2
        static let splitOffer = Font.callout
        static let fileTag = Font.callout
        static let lookupUnder = Font.caption
        /// "What Desk found": the rows.
        static let found = Font.callout
        static let musicAt = Font.caption
        static let lookupTitle = Font.title2.bold()
        static let lookupSentenceFirst = Font.title3
        static let lookupSentence = Font.body
        static let lookupCount = Font.headline
        static let lookupSummary = Font.headline
        static let lookupGenreNote = Font.caption
        static let lookupSongTitle = Font.headline
        static let lookupHeader = Font.caption
        static let lookupNotes = Font.caption
        static let lookupGrid = Font.callout
        static let sentAnswer = Font.caption
        static let sentAddress = Font.caption2
    }

    /// Spacing: gaps between things (stacks), padding inside them, and indents, in points.
    enum Space {
        static let firstScreen: CGFloat = 14
        static let firstScreenPadding: CGFloat = 40
        static let pendingBanner: CGFloat = 10
        static let bannerPadding: CGFloat = 8
        static let crateBanner: CGFloat = 8
        static let runScreenPadding: CGFloat = 20
        static let discAsk: CGFloat = 6
        static let discAskPadding: CGFloat = 10
        static let runList: CGFloat = 2
        static let finishedScreen: CGFloat = 14
        static let finishedScreenPadding: CGFloat = 40
        static let finishedWall: CGFloat = 8
        static let finishedSummary: CGFloat = 6
        static let finishedIndent: CGFloat = 12
        static let nextStepAbove: CGFloat = 6
        static let statusBar: CGFloat = 12
        static let statusBarH: CGFloat = 12, statusBarV: CGFloat = 6
        static let sheetPadding: CGFloat = 20
        static let importLog: CGFloat = 10
        /// "Every song went in" in the import log: the system's own space above it.
        static let importLogEmptyAbove: CGFloat? = nil
        static let player: CGFloat = 10
        static let playerH: CGFloat = 12, playerV: CGFloat = 6
        static let toolSheet: CGFloat = 10
        static let sourcesHead: CGFloat = 2
        static let sourcesHeadH: CGFloat = 12, sourcesHeadV: CGFloat = 8
        static let sourcesEmpty: CGFloat = 8
        static let sourcesEmptyPadding: CGFloat = 16
        static let sourcesFolderIndent: CGFloat = 14
        static let sourcesSong: CGFloat = 6
        static let sourcesSongIndent: CGFloat = 30
        static let sourcesActions: CGFloat = 10
        static let sourcesActionsStack: CGFloat = 8
        static let titleCell: CGFloat = 6
        static let keyCell: CGFloat = 4
        static let inspector: CGFloat = 12
        static let inspectorPadding: CGFloat = 14
        static let inspectorEmpty: CGFloat = 8
        static let inspectorGroup: CGFloat = 2
        static let field: CGFloat = 2
        static let splitOffer: CGFloat = 6
        static let splitOfferPadding: CGFloat = 8
        static let lookupUnder: CGFloat = 4
        static let foundRows: CGFloat = 4
        static let lookupSheet: CGFloat = 12
        static let lookupBand: CGFloat = 8
        static let lookupSentence: CGFloat = 8
        static let lookupSentenceAbove: CGFloat = 4
        static let lookupSongs: CGFloat = 10
        static let lookupSong: CGFloat = 6
        static let lookupSongPadding: CGFloat = 12
        static let lookupGridH: CGFloat = 10, lookupGridV: CGFloat = 4
        static let lookupCandidate: CGFloat = 1
        static let lookupTicks: CGFloat = 2
        static let lookupTicksAbove: CGFloat = 4
        static let sentSheet: CGFloat = 10
        static let sentItem: CGFloat = 2
    }

    /// Sizes: widths and heights, in points.
    enum Size {
        static let windowMinWidth: CGFloat = 900, windowMinHeight: CGFloat = 560
        static let firstBodyWidth: CGFloat = 520
        static let runScreenWidth: CGFloat = 1000
        static let sayingMinHeight: CGFloat = 20
        static let finishedWallWidth: CGFloat = 760
        static let finishedSummaryWidth: CGFloat = 420
        static let tableMinWidth: CGFloat = 560
        static let sourcesMinWidth: CGFloat = 260, sourcesIdealWidth: CGFloat = 300, sourcesMaxWidth: CGFloat = 420
        static let inspectorMinWidth: CGFloat = 260, inspectorIdealWidth: CGFloat = 300, inspectorMaxWidth: CGFloat = 380
        static let colTitleMin: CGFloat = 140, colTitleIdeal: CGFloat = 220
        static let colArtistMin: CGFloat = 100, colArtistIdeal: CGFloat = 160
        static let colTempo: CGFloat = 60
        static let colKey: CGFloat = 60
        /// new (D36): the Key column's ideal width, so "Home note A" fits where a code is short. A placeholder.
        static let colKeyIdeal: CGFloat = 96
        /// new (D36): a song's cover in the names panel, as the pages' --cover-size (a crate file's covers are at most
        /// 128 pixels, so this is sharp). A placeholder until the design pass.
        static let cover: CGFloat = 80
        static let colKeyFromMin: CGFloat = 60, colKeyFromIdeal: CGFloat = 90
        static let colBars: CGFloat = 50
        static let colLength: CGFloat = 60
        static let colVocals: CGFloat = 56
        static let colWhereMin: CGFloat = 80, colWhereIdeal: CGFloat = 180
        static let playButton: CGFloat = 14
        static let importLogMinWidth: CGFloat = 640, importLogMinHeight: CGFloat = 420
        static let playerTitleWidth: CGFloat = 220
        static let toolSheetWidth: CGFloat = 760, toolSheetHeight: CGFloat = 600
        static let toolSourcePickerWidth: CGFloat = 320
        static let toolPasteHeight: CGFloat = 120
        static let toolPatternMenuWidth: CGFloat = 30
        static let toolSongColumn: CGFloat = 180, toolFieldColumn: CGFloat = 70, toolBeforeColumn: CGFloat = 150
        static let toolPreviewMinHeight: CGFloat = 200
        static let sentSheetWidth: CGFloat = 760, sentSheetHeight: CGFloat = 560
    }

    /// Corners, in points.
    enum Shape {
        static let banner: CGFloat = 6
        static let discAsk: CGFloat = 8
        static let splitOffer: CGFloat = 6
        static let toolPaste: CGFloat = 4
        /// new (D36): a song's cover's corners, as the pages' --r-cover. A placeholder until the design pass.
        static let cover: CGFloat = 10
    }
}

/// The run screen's look (D37): every colour, size and time it uses, named, for the design pass to change in one place
/// (desk-web/desk.css's run-screen variables are the pages' own; where the two differ is listed for the design pass).
enum RunLook {
    // colour
    static let accent = Color(red: 0.706, green: 0.565, blue: 1.0)          // #b490ff: the site's and the booth's lavender
    static let amber = Color(red: 1.0, green: 0.753, blue: 0.251)           // #ffc040: a tempo reading, as the booth's pitch line
    static let wave = NSColor(red: 0.706, green: 0.565, blue: 1.0, alpha: 0.82)
    static let waveQuiet = NSColor(red: 0.706, green: 0.565, blue: 1.0, alpha: 0.28)
    static let waveNew = NSColor(red: 0.925, green: 0.894, blue: 1.0, alpha: 1)
    static let wavePick = NSColor(red: 1.0, green: 0.753, blue: 0.251, alpha: 1)
    static let waveNone = NSColor(white: 0.5, alpha: 0.25)
    static let tick = Color.primary.opacity(0.22), tickStrong = Color.primary.opacity(0.45)
    static let wheelEmpty = Color.primary.opacity(0.07)
    static let wheelHome = Color.secondary
    static let card = Color.primary.opacity(0.045)
    /// A moment: the glow round the progress bar, and the ring round a card.
    static let momentGlowOpacity = 0.9
    static let momentGlowRadius: CGFloat = 6
    static let momentRingOpacity = 0.6
    static let momentRingWidth: CGFloat = 2

    // type
    static let bigFont = Font.system(size: 26, weight: .bold).monospacedDigit()
    static let stageFont = Font.system(size: 17, weight: .semibold)
    static let labelFont = Font.caption2
    static let chipFont = Font.caption2.weight(.semibold)
    static let stageNoteFont = Font.caption
    static let stageValueWeight = Font.Weight.semibold
    static let figureTextFont = Font.caption
    static let figureLabelFont = Font.caption.weight(.semibold)
    static let figureValueWeight = Font.Weight.bold
    static let figureListFont = Font.callout
    static let wallTitleFont = Font.headline
    static let wallNameFont = Font.callout
    static let wallHelpFont = Font.caption

    // space and shape
    static let cardRadius: CGFloat = 16
    static let gap: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let stageGap: CGFloat = 20
    static let stageFactsGap: CGFloat = 8
    static let stageNameGap: CGFloat = 6
    static let stageFactsRowGap: CGFloat = 22
    static let stageFactGap: CGFloat = 1
    static let chipPaddingH: CGFloat = 8, chipPaddingV: CGFloat = 1
    static let figuresGap: CGFloat = 10
    static let figureGap: CGFloat = 6
    static let figureListGap: CGFloat = 4
    static let wallCardGap: CGFloat = 8
    static let wallHeadGap: CGFloat = 12

    // size
    static let stageHeight: CGFloat = 120
    static let figureHeight: CGFloat = 70
    static let wallHeight: CGFloat = 200
    static let musicFigureWidth: CGFloat = 180
    /// The song on stage: the share of its height under the wave for the bar marks; half the wave's height at full
    /// loudness, as a share; the thinnest half-wave; the middle line; a bar mark's width, the cut every 32 bars, the
    /// gap between the wave and its marks (points); the mark every 8 bars as a share of the one every 32.
    static let stageMarkShare: CGFloat = 0.12
    static let stageWaveRoom: CGFloat = 0.48
    static let stageWaveMin: CGFloat = 1
    static let stageLine: CGFloat = 1
    static let stageTickWidth: CGFloat = 1, stageTickStrongWidth: CGFloat = 2, stageTickGap: CGFloat = 2
    static let stageTickShort: CGFloat = 0.5
    /// The tempo picture: its baseline, the gap between bars, the narrowest and the shortest bar, the room kept above.
    static let histBaseline: CGFloat = 1, histBarGap: CGFloat = 1, histBarMinWidth: CGFloat = 1, histBarMin: CGFloat = 2, histTop: CGFloat = 2
    /// The wheel, drawn in a box of this many units: its rings (major outside, minor inside), where the home-note dots
    /// sit, the degrees trimmed from each side of a key's cell, a cell's opacity with one song plus this much at the
    /// most, a dot's radius plus the square root of its songs up to this, and its turn at a moment.
    static let wheelBox: CGFloat = 120
    static let wheelMajorIn: CGFloat = 43, wheelMajorOut: CGFloat = 58
    static let wheelMinorIn: CGFloat = 27, wheelMinorOut: CGFloat = 41
    static let wheelHomeR: CGFloat = 18
    static let wheelCellGap = 1.7
    static let wheelFillMin = 0.35, wheelFillRange = 0.65
    static let wheelDotBase = 1.8, wheelDotMax = 5.0
    static let wheelTurn = 360.0
    /// Points a wall line needs to be drawn as a wave, the narrowest column of waves, of brightness lines.
    static let wallWaveMin: CGFloat = 6, wallColMin: CGFloat = 150, wallDenseColMin: CGFloat = 18
    /// Points a brightness line aims for, before the columns run out (then lines thin to a pixel).
    static let wallDenseLine: CGFloat = 3
    /// Points between columns of waves, and of brightness lines.
    static let wallGap: CGFloat = 6, wallDenseGap: CGFloat = 2
    /// A wave on the wall: half its height at full loudness as a share of its line, and its thinnest half (pixels).
    static let wallWaveRoom = 0.46, wallWaveMinHalf = 0.5
    /// A brightness line: below this loudness it takes waveQuiet; its least brightness, and how much loudness adds.
    static let wallDenseQuiet = 0.5, wallDenseDim = 0.25, wallDenseBright = 0.75
    /// How loudness becomes height, the same for every song (the pages' --wave-curve).
    static let waveCurve = 2.2

    // motion
    /// Seconds: a wave drawing in; a song on stage with nothing waiting, and with many; a fade; each quiet line; a
    /// moment; the wall's quickest redraw.
    static let draw = 0.9, hold = 3.2, holdMin = 0.3, holdStill = 2.0, fade = 0.42, saying = 7.0, moment = 1.6, wallEvery = 0.25
    /// A moment's glow and ring come and go in this.
    static let momentFlash = moment / 2
    /// A song held on stage shorter than this (seconds) appears whole, not drawn in; at most this share of its time
    /// on stage is its wave drawing in.
    static let ticker = 0.9, drawShare = 0.45
    /// Songs waiting for the stage before the oldest go straight to the wall.
    static let queueMax = 24
    static let frame = 1.0 / 30
}

/// The lookup's look (D36): the step that uses the internet, marked everywhere by its own colour and the globe.
enum LookupStyle {
    static let net = Color(red: 0.435, green: 0.839, blue: 0.788)
    static let band = net.opacity(0.14)
    static let fits = Color(red: 0.56, green: 0.89, blue: 0.64)
    static let off = Color.orange
    static let icon = "globe"
    static let bandFont = Font.callout.weight(.medium)
    static let bandPaddingH: CGFloat = 12, bandPaddingV: CGFloat = 8
    static let bandRadius: CGFloat = 10
    static let scopePickerWidth: CGFloat = 520
    static let songCardOpacity = 0.5
    static let songCardRadius: CGFloat = 12
    static let sheetWidth: CGFloat = 860
    static let sheetHeight: CGFloat = 640
}
