import SwiftUI

/// What the booth shows: its first-run screen while no crate file is open, else its tabs. No song data ships inside
/// the app, so with no crate file there is nothing to listen for and nothing to pick from.
enum BoothScreen: Equatable {
    /// No crate file open; `demo` when a demo crate file comes with the app (the "Try the demo" button shows then).
    case firstRun(demo: Bool)
    /// A crate file is open: Listen and Crate, as before.
    case crate

    static func now(crateOpen: Bool, demoBundled: Bool) -> BoothScreen {
        crateOpen ? .crate : .firstRun(demo: demoBundled)
    }
    /// The booth as it is now.
    static var current: BoothScreen { now(crateOpen: Library.shared.crate != nil, demoBundled: DemoCrate.url() != nil) }
}

/// A demo crate file that may come with the app, so a DJ can see the booth before making their own. None does yet:
/// a later task adds one, made from generated sound and named in project.yml beside the privacy manifest. Until then
/// `url()` is nil and the first-run screen leaves the button out.
enum DemoCrate {
    static let resourceName = "Demo"
    static let resourceExtension = "deckie"
    static func url(in bundle: Bundle = .main) -> URL? { bundle.url(forResource: resourceName, withExtension: resourceExtension) }
}

/// The first-run screen, shown whenever no crate file is open: what the booth does, the three steps to a crate file,
/// "Open a crate file" (the system's chooser) and the site. Landscape: the words and buttons on the left, the steps on
/// the right. Portrait: one column. Every line is set by phrase (Words.phrases), so none ends on one word alone.
struct FirstRunView: View {
    let demo: Bool
    /// The chooser for a crate file (the app's), and the demo crate file opened as any other.
    let openCrateFile: () -> Void
    let openDemo: () -> Void
    @State private var showCredits = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ScrollView {
                Group {
                    if landscape {
                        HStack(alignment: .center, spacing: Look.FirstRun.columnsGap) {
                            VStack(alignment: .leading, spacing: Look.FirstRun.partsGap) { intro; buttons; foot }
                                .frame(maxWidth: Look.FirstRun.columnMaxWidth, alignment: .leading)
                            steps.frame(maxWidth: Look.FirstRun.columnMaxWidth)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Look.FirstRun.partsGap) { intro; steps; buttons; foot }
                            .frame(maxWidth: Look.FirstRun.portraitMaxWidth, alignment: .leading)
                    }
                }
                .padding(.horizontal, Look.FirstRun.sides).padding(.vertical, Look.FirstRun.ends)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Look.FirstRun.background.ignoresSafeArea())
        .sheet(isPresented: $showCredits) { CreditsView() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Look.FirstRun.headGap) {
            Text(Words.firstRunWaiting).font(Look.FirstRun.waitingFont).foregroundStyle(Look.FirstRun.waitingColor)
            Text(Words.firstRunName).font(Look.FirstRun.nameFont).foregroundStyle(Look.FirstRun.nameColor)
                .accessibilityAddTraits(.isHeader)
            Text(Words.firstRunWhat).font(Look.FirstRun.whatFont).foregroundStyle(Look.FirstRun.whatColor)
                .lineSpacing(Look.FirstRun.whatLineSpacing).fixedSize(horizontal: false, vertical: true)
                .padding(.top, Look.FirstRun.headGap)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Look.FirstRun.stepsGap) {
            ForEach(Array(Words.firstRunSteps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: Look.FirstRun.stepGap) {
                    Text(Words.stepNumber(i + 1)).font(Look.FirstRun.numberFont).foregroundStyle(Look.FirstRun.numberColor)
                        .frame(width: Look.FirstRun.numberSize, height: Look.FirstRun.numberSize)
                        .background(Circle().fill(Look.FirstRun.numberFill))
                    VStack(alignment: .leading, spacing: Look.FirstRun.stepTextGap) {
                        Text(s.title).font(Look.FirstRun.stepTitleFont).foregroundStyle(Look.FirstRun.stepTitleColor)
                        Text(s.note).font(Look.FirstRun.stepNoteFont).foregroundStyle(Look.FirstRun.stepNoteColor)
                            .lineSpacing(Look.FirstRun.stepNoteLineSpacing)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Words.stepSpoken(i + 1, s.title, s.note))
            }
        }
        .padding(Look.FirstRun.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.FirstRun.cardRadius).fill(Look.FirstRun.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Look.FirstRun.cardRadius).stroke(Look.FirstRun.cardLine, lineWidth: Look.FirstRun.cardLineWidth))
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Look.FirstRun.buttonsGap) {
            HStack(spacing: Look.FirstRun.buttonsGap) {
                Button(action: openCrateFile) {
                    HStack(spacing: Look.FirstRun.buttonIconGap) {
                        Image(systemName: "folder")
                        Text(Words.openACrateFile)
                    }
                    .font(Look.FirstRun.buttonFont).foregroundStyle(Look.FirstRun.buttonText)
                    .padding(.horizontal, Look.FirstRun.buttonSides).frame(height: Look.FirstRun.buttonHeight)
                    .background(Capsule().fill(Look.FirstRun.buttonFill))
                }
                .buttonStyle(.plain)
                // Only when a demo crate file comes with the app (DemoCrate); none does yet.
                if demo {
                    Button(action: openDemo) {
                        Text(Words.tryTheDemo).font(Look.FirstRun.buttonFont).foregroundStyle(Look.FirstRun.demoText)
                            .padding(.horizontal, Look.FirstRun.buttonSides).frame(height: Look.FirstRun.buttonHeight)
                            .overlay(Capsule().stroke(Look.FirstRun.demoLine, lineWidth: Look.FirstRun.demoLineWidth))
                    }
                    .buttonStyle(.plain)
                }
            }
            Link(destination: Words.siteURL) {
                HStack(spacing: Look.FirstRun.buttonIconGap) {
                    Text(Words.siteLink)
                    Image(systemName: "arrow.up.right")
                }
                .font(Look.FirstRun.linkFont).foregroundStyle(Look.FirstRun.linkColor)
                .frame(minHeight: Look.FirstRun.linkMinHeight)
            }
            .accessibilityLabel(Words.siteSpoken)
        }
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: Look.FirstRun.footGap) {
            Text(Words.firstRunPrivacy).font(Look.FirstRun.footFont).foregroundStyle(Look.FirstRun.footColor)
                .fixedSize(horizontal: false, vertical: true)
            Button { showCredits = true } label: {
                Text(Words.credits).font(Look.FirstRun.creditsFont).foregroundStyle(Look.FirstRun.creditsColor)
                    .frame(minHeight: Look.FirstRun.creditsMinHeight)
            }
            .buttonStyle(.plain)
        }
    }
}
