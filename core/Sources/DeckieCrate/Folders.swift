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

    /// `isFolder` for a file URL's path.
    public static func isFolder(_ url: URL) -> Bool { isFolder(url.path) }

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
    public static func names(in url: URL) throws -> [String] { try names(in: url.path) }

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
