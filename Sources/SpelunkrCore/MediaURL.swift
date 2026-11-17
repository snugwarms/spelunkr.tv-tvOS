import Foundation

public enum MediaURL {
    /// Encode path components separately: Archive filenames may contain spaces, #, %, +, or subdirectories.
    public static func archive(id: String, file: String) -> URL? {
        guard !id.isEmpty, !file.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let identifier = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        let path = file.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }.joined(separator: "/")
        return URL(string: "https://archive.org/download/\(identifier)/\(path)")
    }

    public static func asset(path: String, base: URL) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_./-"))
        guard !path.contains(".."), !path.hasPrefix("/"), path.hasSuffix(".json"),
              path.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              ["manifests/", "platform/", "details/"].contains(where: path.hasPrefix) else { return nil }
        return base.appendingPathComponent(path)
    }
}
