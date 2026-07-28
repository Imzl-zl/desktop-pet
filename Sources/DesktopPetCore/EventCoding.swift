import Foundation

/// Shared JSON coders so the CLI helper and the daemon agree on the wire
/// format (notably the date strategy).
public enum EventCoding {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// Default on-disk locations used by both the daemon and the CLI helper.
public enum DesktopPetPaths {
    public static var baseDir: String { NSHomeDirectory() + "/.desktoppet" }
    public static var socketPath: String { baseDir + "/desktoppet.sock" }
    public static var queueDir: String { baseDir + "/queue" }
}
