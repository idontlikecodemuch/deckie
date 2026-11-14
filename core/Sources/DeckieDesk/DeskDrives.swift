import Foundation
import DeckieCrate
#if os(Windows)
import WinSDK
#endif

/// The CDs and drives plugged in that Add music offers (desk.md step 1), by their own names (D26), and the name a
/// source takes when the DJ chooses a folder (D31): the drive's own name when the folder is the top of a drive, else
/// the folder's. Never the computer's own disk.
///
/// - Mac: removable, ejectable or external volumes, as the Mac's Desk lists them.
/// - Linux: what is mounted below /media, /run/media or /mnt (where desktops mount sticks and cards).
/// - Windows: drives Windows calls removable (sticks, cards) or CD drives with a disc in. A USB hard disk that
///   Windows calls fixed is not listed; the DJ chooses it as a folder.
public enum DeskDrives {
    public struct Drive: Codable, Equatable, Hashable, Sendable {
        public var name: String
        public var path: String
        public init(name: String, path: String) { self.name = name; self.path = path }
    }

    public static func list() -> [Drive] {
        #if os(macOS)
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey,
                                      .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let drives = urls.compactMap { u -> Drive? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.volumeIsRootFileSystem != true,
                  v.volumeIsBrowsable != false,
                  v.volumeIsRemovable == true || v.volumeIsEjectable == true || v.volumeIsInternal == false else { return nil }
            return Drive(name: SourceReading.name(volumeName: v.volumeName, folderName: u.lastPathComponent), path: u.path)
        }
        #elseif os(Windows)
        var drives: [Drive] = []
        let mask = GetLogicalDrives()
        for i in 0..<26 where mask & (1 << UInt32(i)) != 0 {
            let letter = String(UnicodeScalar(UInt8(65 + i)))
            let root = letter + ":\\"
            let type = root.withCString(encodedAs: UTF16.self) { GetDriveTypeW($0) }
            guard type == UINT(DRIVE_REMOVABLE) || type == UINT(DRIVE_CDROM) else { continue }
            guard let label = volumeLabel(root) else { continue }   // no medium in the drive
            drives.append(Drive(name: SourceReading.name(volumeName: label, folderName: letter + ":"), path: root))
        }
        #else
        let drives = linuxMounts().filter { m in
            ["/media/", "/run/media/", "/mnt/"].contains { m.hasPrefix($0) }
        }.map { Drive(name: SourceReading.name(volumeName: nil, folderName: URL(fileURLWithPath: $0).lastPathComponent), path: $0) }
        #endif
        return drives.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

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
    static func linuxMounts() -> [String] {
        guard let text = try? String(contentsOfFile: "/proc/self/mounts", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count > 1 else { return nil }
            return unescape(String(fields[1]))
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
