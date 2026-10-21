import Foundation
import Combine

@MainActor
final class GameImportViewModel: ObservableObject {
    private static let activeImportKey = "activeImportDirectoryID"

    @Published private(set) var isImporting = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "Choose game files or a ZIP archive to begin."
    @Published private(set) var errorMessage: String?
    @Published private(set) var report: GameContentReport?
    @Published private(set) var activeImportPath: String?
    @Published private(set) var storageBytes: Int64 = 0

    private var cancellation: ImportCancellationToken?

    func importItems(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        errorMessage = nil
        progress = 0
        status = "Preparing import…"

        let token = ImportCancellationToken()
        cancellation = token
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try GameFileImporter().importItems(urls, cancellation: token) { fraction, message in
                    DispatchQueue.main.async {
                        self?.progress = fraction
                        self?.status = message
                    }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.report = result.report
                    self.activeImportPath = result.directory.path
                    UserDefaults.standard.set(result.directory.lastPathComponent, forKey: Self.activeImportKey)
                    self.status = "Import complete. Review the compatibility checks below."
                    self.finishImport()
                    self.refreshStorage()
                }
            } catch is CancellationError {
                DispatchQueue.main.async {
                    self?.status = "Import cancelled. Incomplete files were removed from app storage."
                    self?.finishImport()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                    self?.status = "Import failed."
                    self?.finishImport()
                }
            }
        }
    }

    func cancelImport() {
        cancellation?.cancel()
        status = "Cancelling import…"
    }

    func reportPickerError(_ error: Error) {
        if (error as? CocoaError)?.code != .userCancelled {
            errorMessage = error.localizedDescription
        }
    }

    func refreshStorage() {
        let storedID = UserDefaults.standard.string(forKey: Self.activeImportKey)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let directory = try? GameFileImporter.importsDirectory()
            let size = directory.map(Self.sizeOfFiles(in:)) ?? 0
            let activeImport: URL?
            if let storedID, let directory {
                let candidate = directory.appendingPathComponent(storedID, isDirectory: true)
                activeImport = FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
            } else {
                activeImport = nil
            }
            let report = (activeImport ?? directory).map(GameContentValidator.validate(in:))
            DispatchQueue.main.async {
                guard let self else { return }
                self.storageBytes = size
                self.activeImportPath = activeImport?.path
                if let report {
                    self.report = report
                }
            }
        }
    }

    var storageDescription: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    private func finishImport() {
        isImporting = false
        cancellation = nil
    }

    private static func sizeOfFiles(in directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}