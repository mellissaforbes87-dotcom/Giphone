import Foundation
import ZIPFoundation

final class ImportCancellationToken {
    private let lock = NSLock()
    private var cancelled = false
    private var activeProgress: Progress?

    func cancel() {
        lock.lock()
        cancelled = true
        let progress = activeProgress
        lock.unlock()
        progress?.cancel()
    }

    func check() throws {
        lock.lock()
        let shouldCancel = cancelled || activeProgress?.isCancelled == true
        lock.unlock()
        if shouldCancel {
            throw CancellationError()
        }
    }

    func setActiveProgress(_ progress: Progress?) {
        lock.lock()
        activeProgress = progress
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel {
            progress?.cancel()
        }
    }
}

struct GameImportResult {
    let directory: URL
    let report: GameContentReport
}

struct GameFileImporter {
    private let fileManager = FileManager.default

    static func importsDirectory() throws -> URL {
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = supportDirectory
            .appendingPathComponent("Giphone", isDirectory: true)
            .appendingPathComponent("Imported", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func importItems(
        _ sources: [URL],
        cancellation: ImportCancellationToken,
        onProgress: @escaping (Double, String) -> Void
    ) throws -> GameImportResult {
        let importsDirectory = try Self.importsDirectory()
        let importDirectory = importsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)

        do {
            for (index, source) in sources.enumerated() {
                try cancellation.check()
                let hasScopedAccess = source.startAccessingSecurityScopedResource()
                defer {
                    if hasScopedAccess {
                        source.stopAccessingSecurityScopedResource()
                    }
                }

                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
                    throw ImportError.unavailableSource(source.lastPathComponent)
                }

                if !isDirectory.boolValue && source.pathExtension.lowercased() == "zip" {
                    try extractArchive(
                        source,
                        index: index,
                        total: sources.count,
                        into: importDirectory,
                        cancellation: cancellation,
                        onProgress: onProgress
                    )
                } else {
                    let destination = uniqueDestination(
                        named: source.lastPathComponent,
                        in: importDirectory,
                        isDirectory: isDirectory.boolValue
                    )
                    try copyRecursively(source, to: destination, cancellation: cancellation)
                    onProgress(Double(index + 1) / Double(sources.count), "Imported \(source.lastPathComponent)")
                }
                try cancellation.check()
            }

            return GameImportResult(
                directory: importDirectory,
                report: GameContentValidator.validate(in: importDirectory)
            )
        } catch {
            try? fileManager.removeItem(at: importDirectory)
            throw error
        }
    }

    private func extractArchive(
        _ archiveURL: URL,
        index: Int,
        total: Int,
        into importDirectory: URL,
        cancellation: ImportCancellationToken,
        onProgress: @escaping (Double, String) -> Void
    ) throws {
        let archiveName = archiveURL.deletingPathExtension().lastPathComponent
        let destination = uniqueDestination(named: archiveName, in: importDirectory, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let archiveProgress = Progress(totalUnitCount: 0)
        archiveProgress.isCancellable = true
        cancellation.setActiveProgress(archiveProgress)
        let observation = archiveProgress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
            let fraction = (Double(index) + progress.fractionCompleted) / Double(total)
            onProgress(fraction, "Extracting \(archiveURL.lastPathComponent)")
        }
        defer {
            observation.invalidate()
            cancellation.setActiveProgress(nil)
        }

        try fileManager.unzipItem(
            at: archiveURL,
            to: destination,
            allowUncontainedSymlinks: false,
            progress: archiveProgress
        )
        try cancellation.check()
    }

    private func uniqueDestination(named name: String, in directory: URL, isDirectory: Bool) -> URL {
        let safeName = name.isEmpty ? "Imported Item" : name
        var candidate = directory.appendingPathComponent(safeName, isDirectory: isDirectory)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let sourceURL = URL(fileURLWithPath: safeName)
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            let numberedName = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            candidate = directory.appendingPathComponent(numberedName, isDirectory: isDirectory)
            suffix += 1
        }
        return candidate
    }
}

enum ImportError: LocalizedError {
    case unavailableSource(String)
    case symbolicLink(String)

    var errorDescription: String? {
        switch self {
        case .unavailableSource(let name):
            return "The selected item is no longer available: \(name)."
        case .symbolicLink(let name):
            return "Symbolic links are not imported for safety: \(name). Select the actual file or folder instead."
        }
    }
}

private extension GameFileImporter {
    func copyRecursively(_ source: URL, to destination: URL, cancellation: ImportCancellationToken) throws {
        try cancellation.check()
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw ImportError.symbolicLink(source.lastPathComponent)
        }

        if values.isDirectory == true {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])
            for child in children {
                let childValues = try child.resourceValues(forKeys: [.isDirectoryKey])
                let childDestination = destination.appendingPathComponent(
                    child.lastPathComponent,
                    isDirectory: childValues.isDirectory == true
                )
                try copyRecursively(child, to: childDestination, cancellation: cancellation)
            }
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
    }
}