import Foundation

public enum ProjectPetResolver {
    /// Most-specific (longest projectPath) mapping whose folder contains `cwd`.
    public static func mapping(forProject cwd: String?,
                               mappings: [ProjectPetMapping]) -> ProjectPetMapping? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let target = normalize(cwd)
        return mappings
            .filter { contains(root: normalize($0.projectPath), path: target) }
            .max { normalize($0.projectPath).count < normalize($1.projectPath).count }
    }

    /// True when `path` equals `root` or is a descendant directory of `root`.
    /// Boundary-aware: "/work/foo" does not contain "/work/foobar".
    static func contains(root: String, path: String) -> Bool {
        if path == root { return true }
        return path.hasPrefix(root + "/")
    }

    /// Mappings de-duplicated by normalized project path (first wins), sorted by
    /// path for a stable window order. Guards the planner against a settings file
    /// that somehow holds two entries for the same folder.
    public static func dedupedByKey(_ mappings: [ProjectPetMapping]) -> [ProjectPetMapping] {
        var seen = Set<String>()
        var out: [ProjectPetMapping] = []
        for m in mappings.sorted(by: { normalize($0.projectPath) < normalize($1.projectPath) }) {
            let k = normalize(m.projectPath)
            if seen.insert(k).inserted { out.append(m) }
        }
        return out
    }

    /// Strips a trailing slash and standardises the path.
    public static func normalize(_ path: String) -> String {
        let std = (path as NSString).standardizingPath
        if std.count > 1 && std.hasSuffix("/") { return String(std.dropLast()) }
        return std
    }
}
