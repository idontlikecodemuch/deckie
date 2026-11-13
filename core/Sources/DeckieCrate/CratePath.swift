import Foundation

/// Paths as a crate file writes them: names joined by "/", whatever the platform that made the crate.
///
/// A crate made on a PC must read on an iPad, so a path in a crate (`file.rel`, an import log's `rel`, `ident.folder`)
/// never uses the platform's own separator. Two rules keep it so, and every place in the core that makes or takes
/// apart such a path goes through this type:
///
/// 1. A path is made from names, never from a platform path string: the folder walk lists one folder at a time and
///    joins the names it gets with `join`. (Foundation's `FileManager.enumerator(atPath:)` hands back paths with the
///    platform's separator, a backslash on Windows, and Foundation's `NSString` path methods split on the platform's
///    separator; neither is used for crate paths.)
/// 2. A path is taken apart on "/" only. A backslash is an ordinary character in a name on a Mac (a file may be
///    called `AC\DC - Track.mp3`), so it is never read as a separator; on Windows a name cannot hold one.
public enum CratePath {
    /// The separator between names in a crate path.
    public static let separator: Character = "/"

    /// The names joined by "/". Empty names are left out, so joining onto the top ("") gives just the name.
    public static func join(_ names: [String]) -> String {
        names.filter { !$0.isEmpty }.joined(separator: String(separator))
    }

    /// `path` and then `name`: `join([path, name])`.
    public static func join(_ path: String, _ name: String) -> String { join([path, name]) }

    /// The names of a crate path, empty names (a doubled or a leading "/") left out.
    public static func names(_ path: String) -> [String] {
        path.split(separator: separator, omittingEmptySubsequences: true).map(String.init)
    }

    /// The last name of a crate path (the file's name); the path itself when it has no "/".
    public static func lastName(_ path: String) -> String { names(path).last ?? path }

    /// The folder part of a crate path: everything before the last name, "" for a name at the top.
    public static func folder(of path: String) -> String { join(Array(names(path).dropLast())) }

    /// A name's extension, as written (not lower-cased), without the dot: what follows the last dot. A name with no
    /// dot, or whose only dot is its first character (`.DS_Store`), or that ends in a dot, has none ("").
    public static func fileExtension(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...])
    }
}
