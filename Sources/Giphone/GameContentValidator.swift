import Foundation

struct GameContentCheck: Identifiable {
    let id: String
    let title: String
    let detail: String
    let found: Bool
}

struct GameContentReport {
    let checks: [GameContentCheck]
    let installRoot: URL?
    let unsupportedFiles: [String]

    var readyForEngine: Bool {
        checks.allSatisfy(\.found)
    }
}

enum GameContentValidator {
    private static let requiredDirectories = ["garrysmod", "sourceengine", "platform"]
    private static let incompatibleBinaryExtensions: Set<String> = ["apk", "dll", "dylib", "exe", "so"]

    static func validate(in importedDirectory: URL) -> GameContentReport {
        let installRoot = findInstallRoot(in: importedDirectory)
        let contentRoot = installRoot ?? importedDirectory
        let layoutFound = requiredDirectories.allSatisfy { name in
            var isDirectory: ObjCBool = false
            let path = contentRoot.appendingPathComponent(name, isDirectory: true).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }

        let checks = [
            GameContentCheck(
                id: "layout",
                title: "Source game-data layout",
                detail: layoutFound ? "Found garrysmod/, sourceengine/, and platform/." : "Missing one or more required folders: garrysmod/, sourceengine/, platform/.",
                found: layoutFound
            ),
            check("gameinfo", "garrysmod/gameinfo.txt", "Required game configuration file.", at: contentRoot.appendingPathComponent("garrysmod/gameinfo.txt")),
            check("gmod-vpk", "garrysmod/garrysmod_dir.vpk", "Main Garry's Mod VPK index; keep numbered VPK parts beside it.", at: contentRoot.appendingPathComponent("garrysmod/garrysmod_dir.vpk")),
            check("hl2-misc", "sourceengine/hl2_misc_dir.vpk", "Source shared game content.", at: contentRoot.appendingPathComponent("sourceengine/hl2_misc_dir.vpk")),
            check("hl2-textures", "sourceengine/hl2_textures_dir.vpk", "Source shared texture content.", at: contentRoot.appendingPathComponent("sourceengine/hl2_textures_dir.vpk")),
            check("platform", "platform/ directory", "Platform content directory.", at: contentRoot.appendingPathComponent("platform")),
            GameContentCheck(
                id: "engine",
                title: "iOS engine runtime",
                detail: "Not included. GDroid's Android runtime is not an iOS engine.",
                found: false
            )
        ]
        return GameContentReport(
            checks: checks,
            installRoot: installRoot,
            unsupportedFiles: incompatibleBinaries(in: importedDirectory)
        )
    }

    private static func check(_ id: String, _ title: String, _ detail: String, at url: URL) -> GameContentCheck {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let shouldBeDirectory = title == "platform/ directory"
        return GameContentCheck(
            id: id,
            title: title,
            detail: detail,
            found: exists && (!shouldBeDirectory || isDirectory.boolValue)
        )
    }

    private static func findInstallRoot(in directory: URL) -> URL? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let childNames = Set(children.map { $0.lastPathComponent.lowercased() })
        if requiredDirectories.contains(where: childNames.contains) {
            return directory
        }

        for child in children {
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let result = findInstallRoot(in: child) else {
                continue
            }
            return result
        }
        return nil
    }

    private static func incompatibleBinaries(in directory: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [String] = []
        for case let fileURL as URL in enumerator where incompatibleBinaryExtensions.contains(fileURL.pathExtension.lowercased()) {
            results.append(fileURL.lastPathComponent)
            if results.count == 10 {
                break
            }
        }
        return results
    }
}