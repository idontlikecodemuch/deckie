import SwiftUI

/// The Credits sheet: who makes Deckie, the version, the open-source parts inside Booth with their licences (none
/// today, said plainly; Credits.booth), and the privacy line. Reached from the first-run screen's foot and the Crate
/// tab's info button.
struct CreditsView: View {
    var entries: [Credit] = Credits.booth
    @Environment(\.dismiss) private var dismiss

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Look.Credits.headGap) {
                        Text(Words.creditsMaker).font(Look.Credits.makerFont)
                        Text(Words.creditsVersion(version, build)).font(Look.Credits.versionFont).foregroundStyle(.secondary)
                    }
                }
                Section(Words.creditsOpenSourceSection) {
                    if entries.isEmpty {
                        Text(Words.creditsNoneYet).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(entries) { e in
                        VStack(alignment: .leading, spacing: Look.Credits.entryGap) {
                            Text(e.name).font(Look.Credits.entryNameFont)
                            Text(Words.creditsLine(e.version, e.licence)).font(Look.Credits.entryLineFont).foregroundStyle(.secondary)
                            ForEach(e.parts, id: \.self) { Text($0).font(Look.Credits.entryLineFont).foregroundStyle(.secondary) }
                            DisclosureGroup(Words.creditsLicenceText) {
                                Text(e.licenceText).font(Look.Credits.licenceFont).textSelection(.enabled)
                            }
                        }
                    }
                }
                Section(Words.creditsPrivacySection) {
                    Text(Words.creditsPrivacy).fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle(Words.credits)
            .toolbar { Button(Words.done) { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}
