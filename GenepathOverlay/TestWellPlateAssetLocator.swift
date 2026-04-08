import Foundation

enum TestWellPlateAssetLocator {
    private static let candidateExtensions = ["usdz", "usd", "reality"]
    private static let preferredNameFragments = [
        "wellplate",
        "well_plate",
        "well-plate",
        "well plate",
        "plate"
    ]

    static func locate(in bundle: Bundle = .main) -> URL? {
        let fileManager = FileManager.default
        let bundleRoot = bundle.bundleURL
        guard let enumerator = fileManager.enumerator(
            at: bundleRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let matches = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let pathExtension = url.pathExtension.lowercased()
            guard candidateExtensions.contains(pathExtension) else { return nil }
            return url
        }

        return matches.sorted(by: compareURLs(_:_:)).first
    }

    static func displayName(in bundle: Bundle = .main) -> String? {
        locate(in: bundle)?.lastPathComponent
    }

    private static func compareURLs(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsRank = rank(for: lhs)
        let rhsRank = rank(for: rhs)

        if lhsRank != rhsRank {
            return lhsRank > rhsRank
        }

        return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
    }

    private static func rank(for url: URL) -> Int {
        let filename = url.deletingPathExtension().lastPathComponent.lowercased()

        for (offset, fragment) in preferredNameFragments.enumerated() {
            if filename.contains(fragment) {
                return preferredNameFragments.count - offset
            }
        }

        return 0
    }
}
