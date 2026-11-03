//
//  WhiskyWineInstallView.swift
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

struct WhiskyWineInstallView: View {
    @State private var failure: String?
    @State private var attempt = 0
    @Binding var tarLocation: URL
    @Binding var graphicsLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("setup.whiskywine.install").font(.title).bold()
            if let failure {
                Text(failure).foregroundStyle(.red).textSelection(.enabled)
                HStack {
                    Button("setup.retry") { attempt += 1 }
                    Button("runtime.download.again") {
                        try? FileManager.default.removeItem(at: tarLocation)
                        try? FileManager.default.removeItem(at: graphicsLocation)
                        path.removeLast()
                    }
                }
            } else {
                ProgressView()
                Text("runtime.install.verifying").foregroundStyle(.secondary)
            }
        }
        .frame(width: 440, height: 240)
        .task(id: attempt) {
            failure = nil
            let archive = tarLocation
            let graphicsArchive = graphicsLocation
            do {
                try await Task.detached(priority: .userInitiated) {
                    try WhiskyWineInstaller.install(from: archive, graphicsArchive: graphicsArchive)
                }.value
                try? FileManager.default.removeItem(at: archive)
                try? FileManager.default.removeItem(at: graphicsArchive)
                showSetup = false
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
