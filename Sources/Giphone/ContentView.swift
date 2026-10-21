import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = GameImportViewModel()
    @State private var isPickerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    importSection
                    compatibilitySection
                    engineStatusSection
                    storageSection
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Giphone")
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.item, .folder, .zip],
                allowsMultipleSelection: true,
                onCompletion: handlePickerResult
            )
            .task {
                model.refreshStorage()
            }
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Game Files")
                .font(.title2.weight(.semibold))
            Text("Select a Garry's Mod installation folder, individual files, or ZIP archives from Files. Imports are copied into this app; originals are left untouched.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                isPickerPresented = true
            } label: {
                Label("Import or Change Game Data", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isImporting)

            if model.isImporting {
                ProgressView(value: model.progress)
                HStack {
                    Text(model.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .destructive) {
                        model.cancelImport()
                    }
                    .font(.subheadline.weight(.medium))
                }
            } else {
                Text(model.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private var compatibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected Content")
                .font(.title3.weight(.semibold))

            if let report = model.report {
                ForEach(report.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: check.found ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check.found ? .green : .orange)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(check.title)
                                .font(.subheadline.weight(.medium))
                            Text(check.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                }

                if let installRoot = report.installRoot {
                    Text("Detected folder: \(installRoot.lastPathComponent)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !report.unsupportedFiles.isEmpty {
                    Label("PC or Android native binaries are not iOS-compatible.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                    Text(report.unsupportedFiles.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No game data imported yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var engineStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Engine Status")
                .font(.title3.weight(.semibold))
            Text("This prototype imports and checks content only. It does not contain an iOS Source engine or Garry's Mod executable, and it cannot launch the game. GDroid's Android engine binaries are not iOS-compatible.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Custom maps and addons are copied as files, but this prototype does not parse their formats or verify dependencies. PC-native addon modules are not iOS-compatible.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Storage")
                .font(.title3.weight(.semibold))
            LabeledContent("Imported data", value: model.storageDescription)
                .font(.subheadline)
            Text("Stored in the app's private Application Support directory. Each import uses a new folder; importing again does not overwrite earlier data.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let activeImportPath = model.activeImportPath {
                Text("Latest import: \(URL(fileURLWithPath: activeImportPath).lastPathComponent)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            model.importItems(urls)
        case .failure(let error):
            model.reportPickerError(error)
        }
    }
}

private extension GameImportViewModel {
    func reportPickerError(_ error: Error) {
        // Keep picker cancellation quiet; surface actual picker failures.
        if (error as? CocoaError)?.code != .userCancelled {
            errorMessage = error.localizedDescription
        }
    }
}