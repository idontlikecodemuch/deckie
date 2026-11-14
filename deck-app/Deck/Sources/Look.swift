import SwiftUI
import UIKit

// Every design value of the booth, named, in one place (D36: "tag all values as variables so we can change them
// later"): colours, type, spacing, sizes, corners, opacities, lines and times. The views and the drawing routines hold
// none of their own; the design pass changes this file. Each name says what the value is for, not what it is: two
// places that happen to share a value have two names. Left in the views: the system's own named roles (.secondary,
// .footnote in the test sheet), SF Symbol names, 0 (flush), and the drawings' own arithmetic (a bar is 4 beats, a
// phrase 8 bars, a wave value out of 63, the confidence and pitch thresholds the status line reads).

// MARK: - theme (the web player's tokens)

enum Theme {
    static let bg = Color(hex: 0x0f0a17)
    static let bg2 = Color(hex: 0x160f22)
    static let card = Color(hex: 0x1d1530)
    static let card2 = Color(hex: 0x251b3b)
    static let line = Color(hex: 0x30254a)
    static let tx = Color(hex: 0xf2edf9)
    static let mut = Color(hex: 0xab9fc2)
    static let dim = Color(hex: 0x76698f)
    static let acc = Color(hex: 0xb490ff)
    static let acc2 = Color(hex: 0x8a5cff)
    static let accDim = Color(hex: 0x4a3b6e)
    static let orange = Color(hex: 0xff8a1f)
    static let amber = Color(hex: 0xffc040)
    static let bad = Color(hex: 0xff5d6c)
    static let ok = Color(hex: 0x72dca0)
    static let sing = Color(hex: 0x8f7bc8)     // CD1: muted lavender
    static let mix = Color(hex: 0x5a6cc0)      // CD2: dark, spooky blue
    /// A disc's colour by its number: the two disc colours alternating (odd discs lavender, even discs blue).
    static func disc(_ cd: Int) -> Color { cd % 2 == 1 ? sing : mix }
    static let hal = Color(hex: 0xff8a1f)
    static let rsn = Color(hex: 0xa99bd0)
    static let chipTx = Color(hex: 0xe3d6ff)
    static let backdrop = LinearGradient(colors: [Color(hex: 0x1c1036), Color(hex: 0x0f0a17)], startPoint: .topTrailing, endPoint: .bottomLeading)
}

enum Look {
    /// The whole app: the Minimal switch in the upper-left corner, and the note that a crate file opened.
    enum App {
        static let minimalLeading: CGFloat = 20, minimalTop: CGFloat = 2
        static let minimalGap: CGFloat = 6
        static let minimalIconFont = Font.system(size: 13, weight: .medium)
        static func minimalFont(_ on: Bool) -> Font { .system(size: 13, weight: on ? .semibold : .regular) }
        static let minimalSides: CGFloat = 10, minimalHeight: CGFloat = 30, minimalMinHeight: CGFloat = 44
        static let minimalOnFill = Color.white.opacity(0.12)
        static let minimalOffLineOpacity = 0.35
        static let minimalLine: CGFloat = 1
        static let noteFont = Font.system(size: 16, weight: .semibold)
        static let noteSides: CGFloat = 18, noteMinHeight: CGFloat = 40, noteTop: CGFloat = 8
        static let noteLine: CGFloat = 1
        /// How long "Friday night is open: 12 songs." stays, in seconds.
        static let noteSeconds = 5
    }

    /// The Listen page and its playing panel.
    enum Listen {
        // the page
        static let landscapeGap: CGFloat = 52
        static let waveMinHeight: CGFloat = 140
        static let waveHeightShare: CGFloat = 0.22                // of the screen's height, in landscape
        static let panelWidthShare: CGFloat = 0.42                // of the screen's width, in landscape
        static let picksTop: CGFloat = 6, picksLeading: CGFloat = 18
        static let landscapeLeading: CGFloat = 20, landscapeTrailing: CGFloat = 36, landscapeBottom: CGFloat = 16, landscapeTop: CGFloat = 4
        static let portraitGap: CGFloat = 28
        static let portraitWaveHeight: CGFloat = 110
        static let portraitSides: CGFloat = 24, portraitTop: CGFloat = 4
        // the playing panel
        static let playingGap: CGFloat = 22
        /// new (D36): the song's cover beside its names, small and quiet; nothing when it has none. Placeholders
        /// until the design pass (a crate file's covers are at most 128 pixels a side).
        static let coverSize: CGFloat = 64
        static let coverRadius: CGFloat = 8
        static let coverGap: CGFloat = 14
        static let coverOpacity = 0.9
        static let playingTitleGap: CGFloat = 4
        /// new (D35): the playing song's names and cover while Deckie's has not heard it for a few seconds (it stays
        /// on screen with its picks). A placeholder until the design pass.
        static let notHeardOpacity = 0.5
        static let notHeardFade = 0.4                              // seconds the dimming takes
        static let placeFont = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let alsoFont = Font.system(size: 14, weight: .medium, design: .rounded)
        static let alsoShrink: CGFloat = 0.7
        /// The panel's big line: the song, "Set the song by hand", "Listening…".
        static let titleFont = Font.system(size: 44, weight: .heavy)
        static let titleShrink: CGFloat = 0.6
        static let artistFont = Font.system(size: 24, weight: .medium)
        static let artistShrink: CGFloat = 0.7
        static let factsFont = Font.system(size: 15)
        static let bpmFont = Font.system(size: 22, weight: .regular, design: .rounded)
        static let byHandGap: CGFloat = 14
        static let byHandBodyFont = Font.system(size: 20)
        static let byHandHowFont = Font.system(size: 18)
        static let byHandButtonTop: CGFloat = 6
        static let listeningGap: CGFloat = 10
        static let listeningHelpFont = Font.system(size: 18)
        static let panelSides: CGFloat = 30, panelTop: CGFloat = 44, panelBottom: CGFloat = 10
        static let panelRadius: CGFloat = 24
        /// The panel's tint of the playing disc's colour: at its top left, and its bottom right.
        static let panelTintTop = 0.24, panelTintBottom = 0.08
        static let cornerGap: CGFloat = 6, cornerPadding: CGFloat = 10, marksTrailing: CGFloat = 8
        static let alsoHearingFont = Font.system(size: 11)
        static let alsoHearingLeading: CGFloat = 30, alsoHearingBottom: CGFloat = 12
        // the status corner
        static let statusGap: CGFloat = 6
        /// Seconds between redraws of the status dot and the recording time.
        static let statusTick = 1.0
        static let statusDot: CGFloat = 7
        static let statusFont = Font.system(size: 11, weight: .medium)
        static let statusTrailing: CGFloat = 6
        /// Seconds the status dot stays green after a match.
        static let matchFresh = 20.0
        static let idleDotOpacity = 0.5
        static let recGap: CGFloat = 4, recDot: CGFloat = 6, recDotOpacity = 0.75
        static let recFont = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let recSides: CGFloat = 6, recMinHeight: CGFloat = 28
        static let cornerButtonsGap: CGFloat = 2
        static let cornerIconFont = Font.system(size: 14)
        static let cornerButton: CGFloat = 34
    }

    /// The whole-song wave under the playing song, and its time readout.
    enum Wave {
        /// Seconds between redraws.
        static let tick = 0.5
        static let gap: CGFloat = 10
        static let mixInFill = Color.white.opacity(0.06)
        static let syncFill = Color(hex: 0xc9b99a, alpha: 0.10)
        static let syncLineColor = Color(hex: 0xc9b99a, alpha: 0.45)
        static let syncLine: CGFloat = 2
        /// Room above the wave for the IN and SYNC marks.
        static let labelRoom: CGFloat = 18
        static let flatLine: CGFloat = 2
        static let flatColor = Color.white.opacity(0.3)
        static let barMin: CGFloat = 1, barInset: CGFloat = 2, barMinWidth: CGFloat = 1, barShare: CGFloat = 0.7
        static let aheadOpacity = 0.35, playedOpacity = 0.85
        static let playhead = Color.white, playheadGlow = Color.white
        static let playheadGlowRadius: CGFloat = 4
        static let playheadWidth: CGFloat = 3, playheadOverhang: CGFloat = 2
        static let markFont = Font.system(size: 11, weight: .semibold)
        static let markInset: CGFloat = 4
        static let inMarkY: CGFloat = 9, syncMarkY: CGFloat = 10
        static let readoutGap: CGFloat = 6
        static let timeFont = Font.system(size: 22, weight: .regular, design: .monospaced)
        static let syncNoteFont = Font.system(size: 15)
    }

    /// The picks (Up next): the panel, a pick's card (Simple and Full sizes), and its join wave's caption.
    enum Picks {
        static let panelGap: CGFloat = 8
        static let plainPinnedTop: CGFloat = 6, plainTop: CGFloat = 14
        static let emptyFont = Font.system(size: 20), emptyPadding: CGFloat = 40
        static let searchBelowExtra: CGFloat = 4
        static let markerPaddingSimple: CGFloat = 10, markerPadding: CGFloat = 6
        static let nothingFont = Font.system(size: 17), nothingPadding: CGFloat = 20
        static let endAnchor: CGFloat = 1
        static let listFoot: CGFloat = 30
        static let groupFont = Font.system(size: 13, weight: .bold)
        static let groupKerning: CGFloat = 1.2
        static let groupHeightSimple: CGFloat = 22, groupHeight: CGFloat = 17
        // a card, Simple then Full
        static let titleSimple: CGFloat = 25, title: CGFloat = 19
        static let lineSimple: CGFloat = 16, line: CGFloat = 12.5           // folder path, artist
        static let bpmSimple: CGFloat = 18, bpm: CGFloat = 15
        static let smallSimple: CGFloat = 16, small: CGFloat = 13
        static let textWidthSimple: CGFloat = 275, textWidth: CGFloat = 235
        /// new (D36): a pick's cover, inside the text column (which keeps its width, so the join wave never moves);
        /// nothing when the song has none. Placeholders until the design pass.
        static let coverSimple: CGFloat = 44, cover: CGFloat = 34
        static let coverRadius: CGFloat = 6
        static let coverGap: CGFloat = 10
        static let coverOpacity = 0.85
        static let waveHeightSimple: CGFloat = 96, waveHeight: CGFloat = 68
        static let cardHeightSimple: CGFloat = 152, cardHeight: CGFloat = 106
        static let sidesSimple: CGFloat = 20, sides: CGFloat = 16
        static let topSimple: CGFloat = 14, top: CGFloat = 7
        static let cardGapSimple: CGFloat = 10, cardGap: CGFloat = 6
        static let groupGapMinimal: CGFloat = 40, groupGapSimple: CGFloat = 30, groupGap: CGFloat = 12
        static let rowGap: CGFloat = 18
        static let textGapSimple: CGFloat = 3, textGap: CGFloat = 1
        static func placeFont(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
        static func alsoFont(_ size: CGFloat) -> Font { .system(size: size, design: .rounded) }
        static let alsoShrink: CGFloat = 0.8
        static func titleFont(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
        static let titleShrink: CGFloat = 0.75
        static func artistFont(_ size: CGFloat) -> Font { .system(size: size) }
        static func bpmFont(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .rounded) }
        static let bpmOpacity = 0.85
        static let bpmTopSimple: CGFloat = 3, bpmTop: CGFloat = 1
        /// The move line: a step above the small size.
        static func moveFont(_ small: CGFloat) -> Font { .system(size: small + 1) }
        static let moveShrink: CGFloat = 0.8
        static let joinGap: CGFloat = 2
        static let startTimeSimple: CGFloat = 13, startTime: CGFloat = 11
        /// A monospaced digit's width, as a share of the font's size (to centre "0:34" on the join).
        static let monoWidthShare: CGFloat = 0.62
        static let startGap: CGFloat = 6
        static func startTimeFont(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
        static func syncsFont(_ simple: Bool) -> Font { .system(size: simple ? 10 : 9) }
        /// Where the start time sits under the join wave, as a share of its width (the join line).
        static let startTimeAt: CGFloat = 0.25
        static let startRowSimple: CGFloat = 16, startRow: CGFloat = 14
        static let bottomMin: CGFloat = 2, bottomShare: CGFloat = 0.35
        static let cardRadius: CGFloat = 16
        static let cardFill = Color.white.opacity(0.045)
        static let chipsTop: CGFloat = 7, chipsTrailing: CGFloat = 10
        static let pinnedBar: CGFloat = 4, pinnedBarInset: CGFloat = 16
    }

    /// Minimal mode's pick: a compact pill (Simple's size when `big`).
    enum Plain {
        static let gap: CGFloat = 18, textGap: CGFloat = 5, lineGap: CGFloat = 14, middleMin: CGFloat = 10
        static func titleFont(_ big: Bool) -> Font { .system(size: big ? 22 : 19, weight: .semibold) }
        static let titleShrink: CGFloat = 0.75
        static func lineFont(_ big: Bool) -> Font { .system(size: big ? 14 : 13) }
        static func placeFont(_ big: Bool) -> Font { .system(size: big ? 14 : 13, weight: .semibold, design: .rounded) }
        static func alsoFont(_ big: Bool) -> Font { .system(size: big ? 13 : 12, design: .rounded) }
        static let alsoShrink: CGFloat = 0.8
        static func bpmFont(_ big: Bool) -> Font { .system(size: big ? 17 : 15, weight: .regular, design: .rounded) }
        static let bpmOpacity = 0.85
        static func moveFont(_ big: Bool) -> Font { .system(size: big ? 14 : 13) }
        static let sides: CGFloat = 28, topBottomBig: CGFloat = 20, topBottom: CGFloat = 16
        static let fill = Color.white.opacity(0.04)
        static let pinnedOpacity = 0.8, pinnedLine: CGFloat = 1.5
    }

    /// More's search field.
    enum Search {
        static let gap: CGFloat = 8
        static let iconFont = Font.system(size: 16, weight: .medium)
        static let font = Font.system(size: 17)
        static let clearFont = Font.system(size: 18)
        static let clearSize: CGFloat = 44
        static let sides: CGFloat = 14, minHeight: CGFloat = 44
        static let radius: CGFloat = 12
        static let fill = Color.white.opacity(0.06)
        static let focusOpacity = 0.6, line: CGFloat = 1
        static let maxWidth: CGFloat = 520
    }

    /// Where the shortlist ends in More.
    enum Marker {
        static let gap: CGFloat = 10, leadWidth: CGFloat = 24, line: CGFloat = 1
        static let font = Font.system(size: 12, weight: .medium)
    }

    /// The controls: Simple / Full, the Shuffle dial, the round and pill buttons, a wrapping row.
    enum Controls {
        static let pickControlsGap: CGFloat = 12
        static let modeGap: CGFloat = 2
        static func modeFont(_ selected: Bool) -> Font { .system(size: 15, weight: selected ? .semibold : .regular) }
        static let modeSides: CGFloat = 7, modeMinHeight: CGFloat = 36
        static let modeJoinFont = Font.system(size: 15), modeJoinOpacity = 0.5
        static let dialGap: CGFloat = 10, dialLabelGap: CGFloat = 5
        static let dialFont = Font.system(size: 15)
        static let dialValueFont = Font.system(size: 15, weight: .semibold).monospacedDigit()
        static let dialValueWidth: CGFloat = 44
        static let dialMinWidth: CGFloat = 90, dialMaxWidth: CGFloat = 190, dialMinHeight: CGFloat = 44
        static let iconFont = Font.system(size: 18, weight: .semibold)
        static let iconSize: CGFloat = 44
        static let pillFont = Font.system(size: 16, weight: .semibold)
        static let pillSides: CGFloat = 14, pillMinHeight: CGFloat = 40
        /// The text on the orange (prominent) buttons.
        static let accentInk = Color(hex: 0x1a0d02)
        static let fill = Color.white.opacity(0.07)
        static let pressedOpacity = 0.6
        static let flowGap: CGFloat = 8
    }

    /// Chips: the disc filter's, the quiet ones, the tiny corner marks.
    enum Chips {
        static func libraryFont(_ on: Bool) -> Font { .system(size: 14, weight: on ? .semibold : .regular) }
        static let librarySides: CGFloat = 11, libraryHeight: CGFloat = 30, libraryMinHeight: CGFloat = 40
        static let libraryOnOpacity = 0.28, libraryOffOpacity = 0.4, libraryLine: CGFloat = 1
        static let quietFont = Font.system(size: 14, weight: .semibold, design: .monospaced)
        static let quietSides: CGFloat = 7, quietHeight: CGFloat = 30, quietRadius: CGFloat = 7
        static let quietFill = Color.white.opacity(0.06)
        static let tinyFont = Font.system(size: 10, weight: .semibold, design: .rounded)
        static let tinySides: CGFloat = 5, tinyHeight: CGFloat = 17
        static let tinyFill = Color.white.opacity(0.06)
        static let cornerGap: CGFloat = 4
        static let marksSize: CGFloat = 11
    }

    /// The confidence dots.
    enum Confidence {
        static let gap: CGFloat = 3, dot: CGFloat = 7
        static let off = Color.white.opacity(0.14)
    }

    /// A pick's long-press detail.
    enum Detail {
        static let gap: CGFloat = 10
        static let titleFont = Font.system(size: 18, weight: .bold)
        static let font = Font.system(size: 15)
        static let scoreFont = Font.system(size: 14)
        static let padding: CGFloat = 20, width: CGFloat = 420
    }

    /// The join wave (the web player's drawJoin): two lanes, their bars and phrases, the overlap and the join line.
    enum Join {
        /// Room above lane A and below lane B for the bar numbers.
        static let numberRoom: CGFloat = 10
        static let laneGap: CGFloat = 2, laneInset: CGFloat = 1
        static let overlapFill = Color.white.opacity(0.07)
        static let overlapLine: CGFloat = 1, overlapLineOpacity = 0.7
        static let barMin: CGFloat = 0.5, barOverlap: CGFloat = 0.3
        static let offOpacity = 0.3, onOpacity = 0.78
        static let beatLine: CGFloat = 1, beatInset: CGFloat = 1, beatOpacity = 0.75
        static let lines = Color.white
        static let barLineOffset: CGFloat = 0.5, phraseLine: CGFloat = 1.3, barLine: CGFloat = 0.8
        static let phraseOpacity = 0.6, barOpacity = 0.3
        static let numberFont = Font.system(size: 9, weight: .semibold, design: .monospaced)
        static let numberInset: CGFloat = 2
        static let windowEnd: CGFloat = 2
        static let markLeftMin: CGFloat = 4, markRightMin: CGFloat = 8
        static let syncTriTop: CGFloat = 1, syncTriBottom: CGFloat = 6, syncTriHalf: CGFloat = 3.5
        static let syncOpacity = 0.9
        static let markFont = Font.system(size: 8, weight: .bold, design: .rounded)
        static let syncLabelInset: CGFloat = 5, syncLabelDrop: CGFloat = 1
        static let tickWidth: CGFloat = 1, tickHeight: CGFloat = 5
        static let join = Color.white, joinGlow = Color.white.opacity(0.8)
        static let joinGlowRadius: CGFloat = 3
        static let joinLine: CGFloat = 2, joinOverhang: CGFloat = 2
    }

    /// The Crate tab.
    enum Crate {
        static let gap: CGFloat = 8, headGap: CGFloat = 14
        static let titleFont = Font.system(size: 26, weight: .heavy)
        static let crateNameFont = Font.system(size: 17, weight: .semibold)
        static let helpFont = Font.system(size: 13)
        static let pickerWidth: CGFloat = 320
        static let buttonFont = Font.system(size: 15), buttonMinHeight: CGFloat = 36
        static let emptyFont = Font.system(size: 15), emptyTop: CGFloat = 20
        static let detailsGap: CGFloat = 28, denseGap: CGFloat = 22
        static let sides: CGFloat = 24, top: CGFloat = 6
        // dense: two columns, one line a song
        static let denseHeadGap: CGFloat = 4
        static let denseNameFont = Font.system(size: 15, weight: .bold)
        static let denseColumnsGap: CGFloat = 14, denseFoot: CGFloat = 20
        static let denseFolderFont = Font.system(size: 11, weight: .bold, design: .rounded)
        static let denseFolderOpacity = 0.9
        static let denseFolderTop: CGFloat = 6, denseFolderHeight: CGFloat = 22
        static let denseRowGap: CGFloat = 6
        static func denseSongFont(_ named: Bool) -> Font { .system(size: 13.5, weight: named ? .medium : .regular) }
        static let denseArtistFont = Font.system(size: 10)
        static let denseSpacer: CGFloat = 2
        static let densePumpkinFont = Font.system(size: 9)
        static let denseBpmFont = Font.system(size: 12, weight: .semibold, design: .monospaced)
        static let denseRowHeight: CGFloat = 21
        // details: a list a section
        static let listGap: CGFloat = 6
        static let listNameFont = Font.system(size: 17, weight: .bold)
        static let listRowsGap: CGFloat = 2
        static let listFolderFont = Font.system(size: 13, weight: .bold, design: .rounded)
        static let listFolderOpacity = 0.85
        static let listFolderTop: CGFloat = 12, listFolderBottom: CGFloat = 4
        static let listFoot: CGFloat = 30
        static let rowGap: CGFloat = 12
        static let rowNumberFont = Font.system(size: 16, weight: .semibold, design: .monospaced)
        static let rowNumberWidth: CGFloat = 26
        static let rowTextGap: CGFloat = 1, rowTitleGap: CGFloat = 6
        static func rowSongFont(_ named: Bool) -> Font { .system(size: 18, weight: named ? .semibold : .regular) }
        static let rowMarks: CGFloat = 12
        static let rowArtistFont = Font.system(size: 14)
        static let rowSpacer: CGFloat = 8
        static let rowKeyFont = Font.system(size: 15, weight: .semibold, design: .monospaced)
        static let rowKeyWidth: CGFloat = 40
        /// new (D36): a row's key when it is words ("Home note A", "not sure"). A placeholder until the design pass.
        static let rowKeyWordsFont = Font.system(size: 13, weight: .medium)
        static let rowBpmFont = Font.system(size: 18, weight: .bold, design: .monospaced)
        static let rowBpmWidth: CGFloat = 42
        static let rowTopBottom: CGFloat = 7, rowSides: CGFloat = 10
        static let rowRadius: CGFloat = 10
        static let rowPlayingOpacity = 0.12
        static let rowFill = Color.white.opacity(0.03)
    }

    /// The Mix map tab's page, behind its own drawing.
    enum MixMap {
        static let background = UIColor(red: 0.06, green: 0.04, blue: 0.09, alpha: 1)
    }

    /// The test and details sheet.
    enum Debug {
        static let noteFont = Font.footnote
        static let fileFont = Font.system(size: 13, design: .monospaced)
        static let logFont = Font.system(size: 12, design: .monospaced)
        static let meterTrack = Color.white.opacity(0.1)
        static let meterWidth: CGFloat = 70, meterHeight: CGFloat = 8
    }

    /// The Halloween moment on the playing panel: a lightning flash, a ghost drifting across, a pumpkin popping in.
    enum FX {
        static let flashColor = Color.white
        static let ghostFont = Font.system(size: 64)
        static let pumpkinFont = Font.system(size: 80)
        /// The ghost: where it rests, starts and ends across the panel (shares of its width), its height (a share),
        /// how many waves it makes and how far it sways (points), its opacity.
        static let ghostRest: CGFloat = -0.2, ghostStart: CGFloat = -0.15, ghostEnd: CGFloat = 1.15
        static let ghostY: CGFloat = 0.30, ghostWaves: CGFloat = 9, ghostSway: CGFloat = 14
        static let ghostOpacity = 0.85
        /// The pumpkin: its place (shares of the panel), its scale from small to full.
        static let pumpkinX: CGFloat = 0.78, pumpkinY: CGFloat = 0.62
        static let pumpkinScaleMin: CGFloat = 0.4, pumpkinScaleRange: CGFloat = 0.6
        /// Under Reduce Motion: the pumpkin fades in to this, holds, fades out (seconds).
        static let stillPumpkin = 0.8, stillFade = 0.6, stillHold = 1.4
        /// The lightning: two flashes, their brightness, how fast they come and go (seconds), the holds and the gap
        /// between them (milliseconds).
        static let flash1 = 0.35, flash1In = 0.06, flash1Out = 0.12, flash1HoldMs = 90
        static let flashGapMs = 140
        static let flash2 = 0.22, flash2In = 0.05, flash2Out = 0.3, flash2HoldMs = 70
        /// The ghost's drift and fade in (seconds), the pumpkin's spring, how long it all shows (ms), the fade out.
        static let ghostDrift = 1.6, ghostFadeIn = 0.3
        static let pumpkinSpring = 0.35, pumpkinDamping = 0.5
        static let showMs = 1200
        static let fadeOut = 0.4
    }
}
