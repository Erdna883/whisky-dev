//
//  SettingsView.swift
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

struct SettingsView: View {
    @AppStorage("steamBrowserMode") var steamBrowserMode = SteamBrowserMode.compatibility.rawValue
    @AppStorage("steamBrowserCompatibility") var steamBrowserCompatibility = true
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir

    var body: some View {
        Form {
            Section("settings.general") {
                Toggle("settings.toggle.kill.on.terminate", isOn: $killOnTerminate)
                ActionView(
                    text: "settings.path",
                    subtitle: defaultBottleLocation.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.containerDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            defaultBottleLocation = url
                        }
                    }
                }
            }
            Section("steam.settings") {
                Toggle("steam.compatibility", isOn: $steamBrowserCompatibility)
                Picker("steam.browser.mode", selection: $steamBrowserMode) {
                    Text("steam.mode.compatibility").tag(SteamBrowserMode.compatibility.rawValue)
                    Text("steam.mode.responsive").tag(SteamBrowserMode.responsive.rawValue)
                }
                .disabled(!steamBrowserCompatibility)
                Text("steam.browser.mode.description").foregroundStyle(.secondary)
                Text("steam.compatibility.description").foregroundStyle(.secondary)
            }
            Section("runtime.title") {
                LabeledContent("runtime.version", value: WhiskyWineInstaller.runtimeVersion)
                Text("runtime.updates.manual")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.medium)
    }
}

#Preview {
    SettingsView()
}
