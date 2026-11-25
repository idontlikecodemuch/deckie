import Foundation
#if os(Windows)
import WinSDK
#endif

/// Whether a path is a folder, and what is in one, right for the top of a drive on every system: the one check the
/// engine's requests (`add.count`, `run.add`), the count before a read and the builder's walk all use.
///
/// Why (Nov 25, 2026): on Windows, Desk could not read a whole drive. "Read this drive" on a USB stick at E: failed at
/// once with "E:/ is not a folder", and so did Add folder on the stick's top, while a folder inside it was read. The
/// drive list gives the drive as `E:\`, the engine's request check took that path as given and passed, and the
/// builder's walk asked Foundation again with the path its URL gives back (`URL(fileURLWithPath: "E:\\")
/// .standardizedFileURL.path`, written `E:/`), which Foundation on Windows answered "not there". A path below the top
/// (`E:/House`) was always answered right. So for the top of a drive (`E:`, `E:\`, `E:/`, `/E:/`, as each part of
/// the way writes it) the question goes to Windows itself, with the one form every Windows call takes for it, `E:\`
/// (`GetFileAttributesW`, `FindFirstFileW`); every other path, and every path on the other systems, goes to
/// Foundation as before (which also handles Windows' long paths).
public enum Folders {
    /// Whether there is a folder at `path` (a drive's top included).
    public static func isFolder(_ path: String) -> Bool {
        #if os(Windows)
        if let root = driveRoot(path) {
            let attributes = root.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
            // INVALID_FILE_ATTRIBUTES is all ones.
            return attributes != DWORD.max && attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0
        }
        #endif
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
    }

    /// `isFolder` for a file URL: a drive's top is found from any form the URL gives (`driveRoot(of:)`), else its
    /// path goes to Foundation.
    public static func isFolder(_ url: URL) -> Bool { isFolder(driveRoot(of: url) ?? url.path) }

    /// The top of a Windows drive (`E:\`) that `url` names, from any of the forms a URL gives for it: its path, its
    /// path as the file system takes it, and its standardised path. The CI runner of Nov 25, 2026 showed that a
    /// drive's top made into a URL and standardised (`URL(fileURLWithPath: "C:\\").standardizedFileURL`) was no
    /// longer taken for one, so the walk said "C:/ is not a folder." while the same path as text was a folder: each
    /// form is asked, the URL as given first. Nil for anything else, and always nil where there are no drive letters.
    public static func driveRoot(of url: URL) -> String? {
        #if os(Windows)
        let native = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } }
        for form in [url.path, native, url.standardizedFileURL.path].compactMap({ $0 }) {
            if let root = driveRoot(form) { return root }
        }
        #endif
        return nil
    }

    /// The folder at `path` as a URL, with a Windows drive's top in the one form every part of Desk reads as the top
    /// (`E:\`): a bare `E:` made into a URL is a folder named "E:" in the working folder, not the drive (the CI runner
    /// of Nov 25, 2026: `URL(fileURLWithPath: "C:")` came out as `D:/a/.../core/C:`). Every request's path is made
    /// into a URL through here.
    public static func folderURL(_ path: String) -> URL {
        #if os(Windows)
        if let root = driveRoot(path) { return URL(fileURLWithPath: root, isDirectory: true) }
        #endif
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// `url.standardizedFileURL`, except that a Windows drive's top is returned as `E:\`, untouched by Foundation.
    /// Established on the core-windows runner (run 45712545553, Nov 25, 2026): `standardizedFileURL` of a drive's top
    /// (`URL(fileURLWithPath: "C:\\")`, whose path is `C:/`) gives a path in the working folder, `<cwd>/C:`, which
    /// is not there; once standardised the drive cannot be found again. Every URL that can be a drive's top (the
    /// folder a run reads, a source's root, an export folder, a folder named on the command line) is standardised
    /// through here, never with `standardizedFileURL` directly. `resolvingLinks` also resolves links, for anything
    /// that is not a drive's top.
    public static func standardized(_ url: URL, resolvingLinks: Bool = false) -> URL {
        if let root = driveRoot(of: url) { return URL(fileURLWithPath: root, isDirectory: true) }
        let s = url.standardizedFileURL
        return resolvingLinks ? s.resolvingSymlinksInPath() : s
    }

    /// Whether two folder URLs name the same folder, by their `standardized` paths (a drive's top as `E:\`, any case
    /// of its letter).
    public static func same(_ a: URL, _ b: URL) -> Bool { standardized(a).path == standardized(b).path }

    /// The path to hand `names(in:)`, `isFolder` and Foundation for a folder URL: a drive's top as `E:\`, else its
    /// path.
    public static func path(of url: URL) -> String { driveRoot(of: url) ?? url.path }

    /// The names in the folder at `path` (a drive's top included), as `FileManager.contentsOfDirectory` gives them
    /// (not `.` or `..`, in no set order); throws when it cannot be listed.
    public static func names(in path: String) throws -> [String] {
        #if os(Windows)
        if let root = driveRoot(path) {
            var data = WIN32_FIND_DATAW()
            let find = (root + "*").withCString(encodedAs: UTF16.self) { FindFirstFileW($0, &data) }
            guard let find, find != HANDLE(bitPattern: -1) else {  // INVALID_HANDLE_VALUE
                throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: path,
                                                               "Win32Error": Int(GetLastError())])
            }
            defer { FindClose(find) }
            var out: [String] = []
            repeat {
                let name = withUnsafeBytes(of: data.cFileName) { raw -> String in
                    let units = raw.bindMemory(to: UInt16.self)
                    return String(decoding: units.prefix { $0 != 0 }, as: UTF16.self)
                }
                if name != "." && name != ".." { out.append(name) }
            } while FindNextFileW(find, &data)
            return out
        }
        #endif
        return try FileManager.default.contentsOfDirectory(atPath: path)
    }

    /// `names(in:)` for a file URL's path.
    public static func names(in url: URL) throws -> [String] { try names(in: path(of: url)) }

    /// The top of a Windows drive as Windows' own calls take it (`E:\`), when `path` is one, in any of the ways it
    /// is written on the way: `E:`, `E:\`, `E:/`, or with a slash in front as a file URL's path has it (`/E:/`).
    /// Nil for anything else (`E:\House`, `/`, `\\server\share`). Plain text, so it is the same answer, and is
    /// tested, on every system.
    public static func driveRoot(_ path: String) -> String? {
        var s = Substring(path.replacingOccurrences(of: "/", with: "\\"))
        if s.hasPrefix("\\"), s.count >= 3, s.dropFirst().first?.isASCII == true, s.dropFirst().first?.isLetter == true,
           s.dropFirst(2).first == ":" {
            s = s.dropFirst()
        }
        while s.count > 3 && s.hasSuffix("\\") { s = s.dropLast() }
        guard s.count == 2 || (s.count == 3 && s.hasSuffix("\\")) else { return nil }
        guard let letter = s.first, letter.isASCII, letter.isLetter, s.dropFirst().first == ":" else { return nil }
        return String(letter).uppercased() + ":\\"
    }
}
