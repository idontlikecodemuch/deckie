import Foundation
#if os(Windows)
import WinSDK
#endif

/// Which drive a source was read from, by the drive's own identity rather than its name or the path it was mounted at
/// (Nov 25, 2026). Unbranded sticks nearly all share a name ("NO NAME", "Untitled", "USB DISK") and are mounted at the
/// same path one after another, so neither tells two sticks apart; the identity the file system carries does. Kept in
/// Desk's own storage beside where the source was read from (`CrateInfo.sourceIds`); it never goes into a crate file.
public struct SourceIdentity: Codable, Hashable, Sendable {
    /// The volume's own identity as the system gives it: on macOS the volume UUID (FAT32 and exFAT sticks have one,
    /// made from the serial number written when the stick was formatted); on Windows the volume serial number; on
    /// Linux the file system UUID (`/dev/disk/by-uuid`, readable without privileges).
    public var volume: String
    /// Where the source's top is on that volume: its path below the volume's top, "" for the top itself.
    public var inside: String

    public init(volume: String, inside: String) { self.volume = volume; self.inside = inside }

    /// What the system says of a place music is read from.
    public struct Found: Equatable, Sendable {
        /// Nil when the system gives none (a file system without one, a FAT stick whose serial number is 0, a
        /// platform that cannot say).
        public var identity: SourceIdentity?
        /// The place is on the computer's own disk, not on a drive Add music offers (a stick, a card, a USB disk, a
        /// CD): there a path is the same place every time, which a mount point is not.
        public var ownDisk: Bool
        public init(identity: SourceIdentity?, ownDisk: Bool) { self.identity = identity; self.ownDisk = ownDisk }
    }

    /// Reads what the system says of a place: the one seam a test replaces.
    public typealias Reader = (URL) -> Found

    /// What the system says of `url`, on this platform.
    public static func read(_ url: URL) -> Found {
        #if os(macOS)
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .volumeURLKey, .volumeIsRootFileSystemKey,
                                         .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return Found(identity: nil, ownDisk: false) }
        // The same rule as the drives Add music lists (DeskDrives.list): removable, ejectable or not internal is a drive.
        let own = v.volumeIsRootFileSystem == true
            || (v.volumeIsInternal == true && v.volumeIsEjectable != true && v.volumeIsRemovable != true)
        let identity = v.volumeUUIDString.flatMap { uuid -> SourceIdentity? in
            guard let top = v.volume, !uuid.isEmpty, uuid != zeroUUID else { return nil }
            return SourceIdentity(volume: uuid, inside: inside(url.resolvingSymlinksInPath().path,
                                                               below: top.resolvingSymlinksInPath().path, separator: "/"))
        }
        return Found(identity: identity, ownDisk: own)
        #elseif os(Windows)
        return windows(url)
        #else
        return linux(url)
        #endif
    }

    static let zeroUUID = "00000000-0000-0000-0000-000000000000"

    /// `path` below `top`, with "/" between its parts and none at either end; `path` itself when it is not below `top`.
    /// With Windows' separator ("\"), "/" separates too and letters' case does not matter (`E:\Sets`, `e:/Sets`).
    /// Plain string work: nothing here standardises a drive's top.
    static func inside(_ path: String, below top: String, separator: Character) -> String {
        let windows = separator == "\\"
        let cut = { (s: String) in
            s.split(omittingEmptySubsequences: true) { $0 == separator || (windows && $0 == "/") }.map(String.init)
        }
        let p = cut(path), t = cut(top)
        let below = p.count >= t.count
            && zip(p, t).allSatisfy { windows ? $0.lowercased() == $1.lowercased() : $0 == $1 }
            ? Array(p.dropFirst(t.count)) : p
        return below.joined(separator: "/")
    }

    #if os(Windows)
    /// The volume serial number of the volume `url` is on (`GetVolumePathNameW`, `GetVolumeInformationW`), written as
    /// Windows writes it ("1A2B-3C4D"); none when it is 0. The drive Windows is on is the computer's own disk.
    static func windows(_ url: URL) -> Found {
        let path = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
        var buffer = [WCHAR](repeating: 0, count: Int(MAX_PATH) + 1)
        let gotTop = path.withCString(encodedAs: UTF16.self) { GetVolumePathNameW($0, &buffer, DWORD(buffer.count)) }
        guard gotTop else { return Found(identity: nil, ownDisk: false) }
        let top = String(decodingCString: buffer, as: UTF16.self)
        var serial: DWORD = 0
        let gotSerial = top.withCString(encodedAs: UTF16.self) {
            GetVolumeInformationW($0, nil, 0, &serial, nil, nil, nil, 0)
        }
        let type = top.withCString(encodedAs: UTF16.self) { GetDriveTypeW($0) }
        let system = (ProcessInfo.processInfo.environment["SystemDrive"] ?? "C:").uppercased()
        let own = type == UINT(DRIVE_FIXED) && top.uppercased().hasPrefix(system)
        guard gotSerial, serial != 0 else { return Found(identity: nil, ownDisk: own) }
        let volume = String(format: "%04X-%04X", Int(serial >> 16), Int(serial & 0xFFFF))
        return Found(identity: SourceIdentity(volume: volume, inside: inside(path, below: top, separator: "\\")), ownDisk: own)
    }
    #endif

    #if !os(macOS) && !os(Windows)
    /// The file system UUID of the mount `url` is on: the name of the link in /dev/disk/by-uuid that leads to the
    /// mount's device (readable by anyone; absent in some containers, and then there is none). Mounts below /media,
    /// /run/media and /mnt are drives (DeskDrives.list); any other is the computer's own disk.
    static func linux(_ url: URL) -> Found {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        var best: (device: String, path: String)?
        for m in DeskDrives.linuxMountTable() where m.path == "/" || path == m.path || path.hasPrefix(m.path + "/") {
            if best == nil || m.path.count >= best!.path.count { best = (m.device, m.path) }
        }
        guard let mount = best else { return Found(identity: nil, ownDisk: false) }
        let own = !["/media/", "/run/media/", "/mnt/"].contains { mount.path.hasPrefix($0) }
        guard mount.device.hasPrefix("/dev/") else { return Found(identity: nil, ownDisk: own) }
        let device = URL(fileURLWithPath: mount.device).resolvingSymlinksInPath().path
        let folder = "/dev/disk/by-uuid"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted()
        guard let uuid = names.first(where: {
            URL(fileURLWithPath: folder + "/" + $0).resolvingSymlinksInPath().path == device
        }) else { return Found(identity: nil, ownDisk: own) }
        return Found(identity: SourceIdentity(volume: uuid, inside: inside(path, below: mount.path, separator: "/")), ownDisk: own)
    }
    #endif
}
