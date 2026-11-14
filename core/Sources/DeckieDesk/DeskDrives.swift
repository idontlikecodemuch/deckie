import Foundation
import DeckieCrate
import DeckieDisc
#if os(Windows)
import WinSDK
#endif

/// The CDs and drives plugged in that Add music offers (desk.md step 1), by their own names (D26), with their kind and
/// size, and the name a source takes when the DJ chooses a folder (D31): the drive's own name when the folder is the
/// top of a drive, else the folder's. Never the computer's own disk.
///
/// - Mac: removable, ejectable or external volumes, as the Mac's Desk lists them.
/// - Linux: what is mounted below /media, /run/media or /mnt (where desktops mount sticks and cards).
/// - Windows: drives Windows calls removable (sticks, cards), CD drives with a disc in, and fixed drives other than
///   the one Windows is on (a USB hard disk is often called fixed; research AE, finding 3).
///
/// What is a stick and what is a big drive is decided by size alone, the same on every system (`DeskAddMusic.isBig`):
/// the removable flag is wrong too often to trust (research AE, "Telling a stick from a big drive").
public enum DeskDrives {
    public struct Drive: Codable, Equatable, Hashable, Sendable {
        public var name: String
        public var path: String
        /// `drive` (a stick, a card or a hard drive) or `cd` (a data CD or DVD; a music CD is listed by MusicCDs).
        public var kind: String
        /// The drive's size in bytes, when the system says.
        public var bytes: Int64?
        /// Bigger than `DeskAddMusic.bigDriveBytes`: Add drive opens a folder chooser inside it first.
        public var big: Bool
        /// The size in words ("16 GB"), for the list (DeskAddMusic.sizeWords).
        public var size: String?
        public init(name: String, path: String, kind: String = Kind.drive, bytes: Int64? = nil, big: Bool = false) {
            self.name = name; self.path = path; self.kind = kind; self.bytes = bytes; self.big = big
            self.size = bytes.map(DeskAddMusic.sizeWords)
        }
    }

    /// A drive's kinds, as `Drive.kind` holds them.
    public enum Kind {
        public static let drive = "drive"
        public static let cd = "cd"
    }

    /// The file systems a data CD or DVD is mounted with, by the name each system gives them.
    static let discFileSystems: Set<String> = ["cd9660", "iso9660", "udf", "cdfs"]

    /// Lists the folders inside this folder as the drives plugged in, in place of the real ones (tests, and trials
    /// with generated songs, so nothing reads a DJ's own drives).
    public static let standInVariable = "DECKIE_DESK_DRIVES"
    /// A stand-in folder whose name ends in this is listed as a data CD.
    public static let standInCDSuffix = " (CD)"

    public static func list(environment: [String: String] = ProcessInfo.processInfo.environment) -> [Drive] {
        if let stand = environment[standInVariable], !stand.isEmpty {
            let root = URL(fileURLWithPath: stand, isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            // A stand-in is a folder or a link to a mounted disk image; its size is the volume it is on, and a name
            // ending in " (CD)" stands in for a data CD.
            return names.filter { !$0.hasPrefix(".") }.sorted().map { name in
                let path = root.appendingPathComponent(name).resolvingSymlinksInPath().path
                let cd = name.hasSuffix(standInCDSuffix)
                return described(name: cd ? String(name.dropLast(standInCDSuffix.count)) : name, path: path,
                                 kind: cd ? Kind.cd : Kind.drive, environment: environment)
            }
        }
        #if os(macOS)
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey,
                                      .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let drives = urls.compactMap { u -> Drive? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.volumeIsRootFileSystem != true,
                  v.volumeIsBrowsable != false,
                  v.volumeIsRemovable == true || v.volumeIsEjectable == true || v.volumeIsInternal == false,
                  !MusicCDs.isMacMusicCD(u) else { return nil }   // a music CD is offered as one (MusicCDs)
            return described(name: SourceReading.name(volumeName: v.volumeName, folderName: u.lastPathComponent), path: u.path,
                             kind: discFileSystems.contains(fileSystem(u.path)) ? Kind.cd : Kind.drive, environment: environment)
        }
        #elseif os(Windows)
        var drives: [Drive] = []
        let mask = GetLogicalDrives()
        for i in 0..<26 where mask & (1 << UInt32(i)) != 0 {
            let letter = String(UnicodeScalar(UInt8(65 + i)))
            let root = letter + ":\\"
            let type = root.withCString(encodedAs: UTF16.self) { GetDriveTypeW($0) }
            // The drive Windows is on is never offered; another fixed drive is (a USB hard disk is often fixed).
            let system = (environment["SystemDrive"] ?? "C:").uppercased()
            guard type == UINT(DRIVE_REMOVABLE) || type == UINT(DRIVE_CDROM)
                || (type == UINT(DRIVE_FIXED) && letter + ":" != system) else { continue }
            guard let label = volumeLabel(root) else { continue }   // no medium in the drive
            // A music CD shows its songs as Track01.cda stubs; it is offered as a music CD instead (MusicCDs).
            if type == UINT(DRIVE_CDROM) && MusicCDs.isCDAudioRoot(URL(fileURLWithPath: root, isDirectory: true)) { continue }
            drives.append(described(name: SourceReading.name(volumeName: label, folderName: letter + ":"), path: root,
                                    kind: type == UINT(DRIVE_CDROM) ? Kind.cd : Kind.drive, environment: environment))
        }
        #else
        let drives = linuxMountsWithTypes().filter { m in
            ["/media/", "/run/media/", "/mnt/"].contains { m.path.hasPrefix($0) }
        }.map { m in
            described(name: SourceReading.name(volumeName: nil, folderName: URL(fileURLWithPath: m.path).lastPathComponent),
                      path: m.path, kind: discFileSystems.contains(m.type) ? Kind.cd : Kind.drive, environment: environment)
        }
        #endif
        return drives.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A drive with its size, as the system gives it, and whether it is big.
    static func described(name: String, path: String, kind: String, environment: [String: String]) -> Drive {
        let bytes = size(of: path)
        return Drive(name: name, path: path, kind: kind, bytes: bytes,
                     big: kind == Kind.drive && DeskAddMusic.isBig(bytes: bytes, environment: environment))
    }

    /// The size in bytes of the drive `path` is on, or nil.
    public static func size(of path: String) -> Int64? {
        guard let n = (try? FileManager.default.attributesOfFileSystem(forPath: path))?[.systemSize] as? NSNumber else { return nil }
        return n.int64Value
    }

    /// Whether `url` is the top of a drive (the root of a mounted volume, or a Windows drive's letter).
    public static func isTopOfDrive(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        #if os(macOS)
        let v = try? url.resourceValues(forKeys: [.volumeURLKey])
        return v?.volume?.standardizedFileURL.path == path
        #elseif os(Windows)
        let trimmed = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? path
        return trimmed.count <= 3 && trimmed.dropFirst().hasPrefix(":")
        #else
        return linuxMounts().contains(path)
        #endif
    }

    #if os(macOS)
    /// The file system's name (`cd9660`, `udf`, `apfs`, `msdos`, ...) of the volume at `path`.
    static func fileSystem(_ path: String) -> String {
        var s = statfs()
        guard statfs(path, &s) == 0 else { return "" }
        return withUnsafeBytes(of: &s.f_fstypename) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
    #endif

    /// The source's name for a folder the DJ chose (D31): the drive's own name when it is the top of a drive, else
    /// the folder's own name.
    public static func sourceName(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        #if os(macOS)
        let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeURLKey])
        let isTop = v?.volume?.standardizedFileURL.path == path
        return SourceReading.name(volumeName: isTop ? v?.volumeName : nil, folderName: url.lastPathComponent)
        #elseif os(Windows)
        let trimmed = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? path
        if let d = list().first(where: { $0.path.lowercased() == (trimmed.hasSuffix("\\") ? trimmed : trimmed + "\\").lowercased() }) {
            return d.name
        }
        if trimmed.count <= 3, trimmed.dropFirst().hasPrefix(":") {   // a drive's top, not removable
            return SourceReading.name(volumeName: volumeLabel(String(trimmed.prefix(2)) + "\\"), folderName: String(trimmed.prefix(2)))
        }
        return url.lastPathComponent
        #else
        if let d = list().first(where: { $0.path == path }) { return d.name }
        return url.lastPathComponent
        #endif
    }

    #if os(Windows)
    static func volumeLabel(_ root: String) -> String? {
        var name = [WCHAR](repeating: 0, count: Int(MAX_PATH) + 1)
        let ok = root.withCString(encodedAs: UTF16.self) {
            GetVolumeInformationW($0, &name, DWORD(name.count), nil, nil, nil, nil, 0)
        }
        guard ok else { return nil }
        return String(decodingCString: name, as: UTF16.self)
    }
    #endif

    #if !os(macOS) && !os(Windows)
    /// The mount points listed in /proc/self/mounts, with the kernel's octal escapes (\040 for a space) undone.
    static func linuxMounts() -> [String] { linuxMountsWithTypes().map { $0.path } }

    /// The mount points with their file system's type (the third field).
    static func linuxMountsWithTypes() -> [(path: String, type: String)] {
        guard let text = try? String(contentsOfFile: "/proc/self/mounts", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count > 2 else { return nil }
            return (unescape(String(fields[1])), String(fields[2]))
        }
    }

    static func unescape(_ s: String) -> String {
        var bytes: [UInt8] = []
        let u = Array(s.utf8)
        var i = 0
        while i < u.count {
            if u[i] == 0x5C, i + 3 < u.count, let v = UInt8(String(decoding: u[(i + 1)...(i + 3)], as: UTF8.self), radix: 8) {
                bytes.append(v); i += 4
            } else { bytes.append(u[i]); i += 1 }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    #endif
}
