//
//  BottleView.swift
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
import UniformTypeIdentifiers
import WhiskyKit

enum BottleStage {
    case config
    case programs
    case processes
}

struct BottleView: View {
    @ObservedObject var bottle: Bottle
    @State private var path = NavigationPath()
    @State private var steamLaunchStarted: Date?
    @State private var programLoading: Bool = false

    private let gridLayout = [GridItem(.adaptive(minimum: 100, maximum: .infinity))]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: gridLayout, alignment: .center) {
                    ForEach(bottle.pinnedPrograms, id: \.id) { pinnedProgram in
                        PinView(
                            bottle: bottle, program: pinnedProgram.program, pin: pinnedProgram.pin, path: $path
                        )
                    }
                    PinAddView(bottle: bottle)
                }
                .padding()
                Form {
                    NavigationLink(value: BottleStage.programs) {
                        Label("tab.programs", systemImage: "list.bullet")
                    }
                    NavigationLink(value: BottleStage.config) {
                        Label("tab.config", systemImage: "gearshape")
                    }
//                    NavigationLink(value: BottleStage.processes) {
//                        Label("tab.processes", systemImage: "hockey.puck.circle")
//                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
            .bottomBar {
                HStack {
                    Button(steamLaunchStarted == nil ? "steam.action" : "steam.starting") {
                        Task { await openSteam() }
                    }
                    .disabled(programLoading || steamLaunchStarted != nil)
                    .help("steam.help")
                    Spacer()
                    Button("button.cDrive") {
                        bottle.openCDrive()
                    }
                    Button("button.terminal") {
                        bottle.openTerminal()
                    }
                    Button("button.run") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [UTType.exe,
                                                     UTType(exportedAs: "com.microsoft.msi-installer"),
                                                     UTType(exportedAs: "com.microsoft.bat")]
                        panel.directoryURL = bottle.url.appending(path: "drive_c")
                        panel.begin { result in
                            programLoading = true
                            Task(priority: .userInitiated) {
                                if result == .OK {
                                    if let url = panel.urls.first {
                                        do {
                                            if url.pathExtension == "bat" {
                                                try await Wine.runBatchFile(url: url, bottle: bottle)
                                            } else {
                                                try await Wine.runProgram(at: url, bottle: bottle)
                                            }
                                        } catch {
                                            showLaunchError(error)
                                        }
                                        programLoading = false
                                    }
                                } else {
                                    programLoading = false
                                }
                                updateStartMenu()
                            }
                        }
                    }
                    .disabled(programLoading)
                    if programLoading {
                        Spacer()
                            .frame(width: 10)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding()
            }
            .onAppear {
                updateStartMenu()
            }
            .disabled(!bottle.isAvailable)
            .navigationTitle(bottle.settings.name)
            .task(id: steamLaunchStarted) {
                guard steamLaunchStarted != nil else { return }
                do {
                    try await Task.sleep(for: .seconds(12))
                    steamLaunchStarted = nil
                } catch { }
            }
            .onChange(of: bottle.settings) { oldValue, newValue in
                guard oldValue != newValue else { return }
                // Trigger a reload
                BottleVM.shared.bottles = BottleVM.shared.bottles
            }
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(bottle: bottle)
                case .programs:
                    ProgramsView(
                        bottle: bottle, path: $path
                    )
                case .processes:
                    RunningProcessesView(bottle: bottle)
                }
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

    @MainActor
    private func openSteam() async {
        guard steamLaunchStarted == nil else { return }
        steamLaunchStarted = Date()
        programLoading = true
        defer { programLoading = false }
        do {
            let steam = ["Program Files (x86)", "Program Files"].map {
                bottle.url.appending(path: "drive_c/\($0)/Steam/steam.exe")
            }.first { FileManager.default.fileExists(atPath: $0.path) }
            if let steam {
                try await Wine.runProgram(at: steam, bottle: bottle, onStarted: { programLoading = false })
            } else {
                guard let source = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe") else {
                    throw URLError(.badURL)
                }
                let (download, response) = try await URLSession.shared.download(from: source)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let installers = WhiskyWineInstaller.applicationFolder.appending(path: "Installers")
                try FileManager.default.createDirectory(at: installers, withIntermediateDirectories: true)
                let installer = installers.appending(path: "SteamSetup-\(UUID().uuidString).exe")
                // Keep the installer while Wine's child process is using it.
                try FileManager.default.moveItem(at: download, to: installer)
                try await Wine.runProgram(at: installer, bottle: bottle, onStarted: { programLoading = false })
            }
            updateStartMenu()
        } catch {
            steamLaunchStarted = nil
            showLaunchError(error)
        }
    }

    @MainActor
    private func showLaunchError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }

    private func updateStartMenu() {
        bottle.updateInstalledPrograms()

        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
            // For some godforsaken reason "foo/bar" != "foo/Bar" so...
            program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                guard !bottle.settings.pins.contains(where: { $0.url == program.url }) else { return }
                bottle.settings.pins.append(PinnedProgram(
                    name: program.url.deletingPathExtension().lastPathComponent,
                    url: program.url
                ))
            }
        }
    }
}
