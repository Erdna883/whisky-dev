//
//  WhiskyWineDownloadView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @State private var failure: String?
    @State private var attempt = 0
    @State private var useNetwork = true
    @Binding var tarLocation: URL
    @Binding var graphicsLocation: URL
    @Binding var path: [SetupStage]

    var body: some View {
        VStack(spacing: 18) {
            Text("setup.whiskywine.download").font(.title).bold()
            Text("runtime.download.subtitle").foregroundStyle(.secondary)
            if let failure {
                Text(failure).foregroundStyle(.red).textSelection(.enabled)
                Button("setup.retry") { useNetwork = true; attempt += 1 }
            } else {
                ProgressView()
                Text("runtime.download.size").font(.caption).foregroundStyle(.secondary)
            }
            Button("runtime.use.downloads") { importDownloads() }
        }
        .frame(width: 440, height: 240)
        .task(id: attempt) { if useNetwork { await download() } }
    }

    private func importDownloads() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "runtime.select.archives")
        guard panel.runModal() == .OK else { return }
        guard panel.urls.count == 2,
              let wine = panel.urls.first(where: { $0.lastPathComponent.hasPrefix("wine-") }),
              let graphics = panel.urls.first(where: { $0.lastPathComponent.hasPrefix("dxvk-") }) else {
            failure = String(localized: "runtime.select.archives")
            return
        }
        useNetwork = false
        attempt += 1
        let directory = FileManager.default.temporaryDirectory
        let wineCopy = directory.appending(path: "whisky-wine-\(UUID().uuidString).tar")
        let graphicsCopy = directory.appending(path: "whisky-dxvk-\(UUID().uuidString).tar")
        do {
            try FileManager.default.copyItem(at: wine, to: wineCopy)
            try FileManager.default.copyItem(at: graphics, to: graphicsCopy)
            tarLocation = wineCopy
            graphicsLocation = graphicsCopy
            path.append(.whiskyWineInstall)
        } catch {
            try? FileManager.default.removeItem(at: wineCopy)
            try? FileManager.default.removeItem(at: graphicsCopy)
            failure = error.localizedDescription
        }
    }

    private func download() async {
        failure = nil
        do {
            let wineArchive = try await downloadArchive(from: WhiskyWineInstaller.downloadURL)
            do {
                let graphicsArchive = try await downloadArchive(from: WhiskyWineInstaller.graphicsDownloadURL)
                try Task.checkCancellation()
                tarLocation = wineArchive
                graphicsLocation = graphicsArchive
            } catch {
                try? FileManager.default.removeItem(at: wineArchive)
                throw error
            }
            path.append(.whiskyWineInstall)
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
        }
    }
    private func downloadArchive(from address: String) async throws -> URL {
        guard let source = URL(string: address) else { throw URLError(.badURL) }
        let (temporary, response) = try await URLSession.shared.download(from: source)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        try Task.checkCancellation()
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "whisky-runtime-\(UUID().uuidString).tar")
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

}
