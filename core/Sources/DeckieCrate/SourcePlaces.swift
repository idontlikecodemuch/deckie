import Foundation

// Reading a source as it is (D25, D26). A source is the thing a DJ holds that the songs were read from: a burned
// data CD, a USB stick, an SD card. Its name, its folders and the order of its songs come from the thing itself;
// nothing here builds or organises one (the corrections a DJ may make afterwards are in Discs.swift).
//
// A place has three levels, written in the crate's existing fields for an entry's own place, and in the same three
// parts for each of its other places (`ident.other_places`, D27: the same file found somewhere else):
//   ident.disc    the source's own name, as the Mac shows it ("Stick 3", "FRIDAY")
//   ident.folder  the group inside it: the folder's path below the source's top, names joined by "/"
//                 ("House", "House/Peak"); "" for songs at the top
//   ident.track   the song's number in that group, counted from 1 in the order a player shows
// Music that is not on a source (an ordinary folder on the Mac) has no disc; its place is its folder.
//
// The order a player shows is one rule, `SourceReading.comesBefore`, so it can be changed in one place.

public enum SourceReading {
    /// Where one file of a source sits.
    public struct Place: Equatable, Hashable, Sendable {
        public var source: String
        public var group: String
        public var number: Int
        public init(source: String, group: String, number: Int) {
            self.source = source; self.group = group; self.number = number
        }
    }

    /// The source's name: the volume's own name when the folder is the top of a mounted volume, else the folder's
    /// name. An empty or missing volume name falls back to the folder's. The name is made safe (`safeName`).
    public static func name(volumeName: String?, folderName: String) -> String {
        if let v = volumeName?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return safeName(v) }
        return safeName(folderName)
    }

    /// The name of a Windows drive with no label of its own: "Drive E" (Nov 27, 2026). Its letter and a colon ("E:")
    /// made every song's path look like a path from the top of a disk, and the crate refused every song.
    public static func driveName(letter: String) -> String { "Drive " + letter.uppercased() }

    /// Whether the paths a source named `name` gives its songs (`name/...`) are relative, by the crate's own check
    /// (`isAbsolute`, CrateValidation): a crate refuses every song of a source whose name fails it.
    public static func keepsPathsRelative(_ name: String) -> Bool { !isAbsolute(name + "/x") }

    /// A source's name with nothing that would break the paths of its songs (Nov 27, 2026). A name that is safe is
    /// returned as it is, so a DJ's ordinary names never change. Otherwise: a drive's letter and a colon alone ("E:",
    /// "E:\") is that drive's name (`driveName`); "/" and "\" become "-" (a Mac folder Finder shows as "A/B" is
    /// really named "A:B"; a volume can be named anything); a colon as the second character becomes "-"; an empty name,
    /// or one of dots only, is "Music".
    public static func safeName(_ name: String) -> String {
        if isSafeName(name) { return name }
        let chars = Array(name)
        if chars.count >= 2, chars.count <= 3, chars[0].isASCII, chars[0].isLetter, chars[1] == ":",
           chars.count == 2 || chars[2] == "\\" || chars[2] == "/" {
            return driveName(letter: String(chars[0]))
        }
        var n = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        if n.dropFirst().hasPrefix(":") { n = String(n.prefix(1)) + "-" + String(n.dropFirst(2)) }
        return isSafeName(n) ? n : "Music"
    }

    /// Whether `name` may be a source's name as it is: not empty, not dots only, no "/" or "\", and its songs' paths
    /// are relative (`keepsPathsRelative`).
    public static func isSafeName(_ name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !t.allSatisfy { $0 == "." } && !name.contains("/") && !name.contains("\\")
            && keepsPathsRelative(name)
    }

    /// The group of a file: its folder's path below the source's top, "" at the top. `path` is the file's path below
    /// the top with "/" between names (as the builder's `rel` has it).
    public static func group(of path: String) -> String { CratePath.folder(of: path) }

    /// The places of a source's audio files, keyed by `paths` (each below the source's top, "/" between names). Each
    /// group's files are numbered 1..n in the order a player shows them (`comesBefore`). Number every audio file the
    /// player would list, including ones the analysis later fails on, so the numbers match the player's.
    public static func places(source: String, paths: [String]) -> [String: Place] {
        var byGroup: [String: [String]] = [:]
        for p in Set(paths) { byGroup[group(of: p), default: []].append(p) }
        var out: [String: Place] = [:]
        for (g, members) in byGroup {
            let ordered = members.sorted { comesBefore(fileName($0), fileName($1), isFile: true) }
            for (i, p) in ordered.enumerated() { out[p] = Place(source: source, group: g, number: i + 1) }
        }
        return out
    }

    /// Groups (folder paths below a source's top) in the order a player's browser walks them: the top first, then
    /// each folder before what is inside it, folders of one level in `comesBefore` order.
    public static func groupComesBefore(_ a: String, _ b: String) -> Bool {
        let x = CratePath.names(a), y = CratePath.names(b)
        for (p, q) in zip(x, y) where p != q { return comesBefore(p, q, isFile: false) }
        return x.count < y.count
    }

    /// The order a player shows the names of one folder in: true when `a` comes before `b`.
    ///
    /// The rule is the disc's own. Letter K (section 1) records that an older club deck plays a data CD's files "in the
    /// order in which they were recorded", and a data CD is ISO 9660 (with Joliet names); ISO 9660 (ECMA-119, section
    /// 9.3) records a folder's entries sorted by name, the name part compared first with the shorter padded by
    /// spaces, then the extension the same way, character by character on the character codes (Joliet's are UCS-2,
    /// which is UTF-16 for these names). So for a burned data CD this is the order the player shows. A USB stick or an
    /// SD card has no order of its own on the disk that can be read the same way on every desk, so it gets the same
    /// rule; whether a given player sorts a stick differently is still to be checked with DJs.
    ///
    /// Consequences a DJ may see: capitals before small letters ("Zed" before "abc"), and numbers compared as
    /// characters ("10 x" before "2 x"), exactly as the disc records them; DJs number files "01", "02" for this
    /// reason. Names are compared in their composed form, so an accented name sorts the same whichever way the system
    /// spells it. Folder names (`isFile` false) are compared whole, without splitting off an extension.
    public static func comesBefore(_ a: String, _ b: String, isFile: Bool) -> Bool {
        let (an, ae) = isFile ? split(a) : (a, "")
        let (bn, be) = isFile ? split(b) : (b, "")
        if let r = padded(an, bn) { return r }
        if let r = padded(ae, be) { return r }
        // Equal under the rule (only possible for names that differ in composition alone): a stable tie-break.
        return Array(a.utf16).lexicographicallyPrecedes(Array(b.utf16))
    }

    // MARK: helpers

    static func fileName(_ path: String) -> String { CratePath.lastName(path) }

    /// Name and extension, split at the last dot (a name with no dot, or only a leading one, has no extension).
    static func split(_ name: String) -> (String, String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    /// Compares two parts code by code, the shorter padded with spaces (0x20); nil when they are equal.
    static func padded(_ a: String, _ b: String) -> Bool? {
        let x = Array(a.precomposedStringWithCanonicalMapping.utf16)
        let y = Array(b.precomposedStringWithCanonicalMapping.utf16)
        let space: UInt16 = 0x20
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : space, q = i < y.count ? y[i] : space
            if p != q { return p < q }
        }
        return nil
    }
}

extension Crate {
    /// Labels the tracks of one source with their places: each track whose `file.rel` is a key of `places` gets the
    /// place's source, group and number as its own place. Other tracks, and other places, are left as they are.
    public mutating func label(with places: [String: SourceReading.Place]) {
        for i in tracks.indices {
            guard let rel = tracks[i].file.rel, let p = places[rel] else { continue }
            tracks[i].ident.disc = p.source; tracks[i].ident.folder = p.group; tracks[i].ident.track = p.number
        }
    }
}
