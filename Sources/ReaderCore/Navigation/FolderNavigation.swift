import Foundation

/// SumatraPDF's "open next/previous file in folder".
public enum FolderNavigation {
    public static let supportedExtensions: Set<String> = ["pdf", "djvu", "djv"]

    /// The neighbouring supported file in Finder order, skipping missing ones.
    /// Like SumatraPDF, it does not wrap around at either end of the folder.
    public static func sibling(of file: URL, in candidates: [URL], forward: Bool) -> URL? {
        let supported = candidates.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        let files = supported.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        guard let index = files.firstIndex(where: { $0.standardizedFileURL == file.standardizedFileURL }) else {
            return nil
        }
        let step = forward ? 1 : -1
        var next = index + step
        while files.indices.contains(next) {
            if FileManager.default.fileExists(atPath: files[next].path) { return files[next] }
            next += step
        }
        return nil
    }

    /// Lists the folder of `file` and finds its sibling.
    public static func sibling(of file: URL, forward: Bool) -> URL? {
        let folder = file.deletingLastPathComponent()
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return sibling(of: file, in: contents, forward: forward)
    }
}
