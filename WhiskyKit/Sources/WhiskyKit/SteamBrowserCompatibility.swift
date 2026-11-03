//
//  SteamBrowserCompatibility.swift
//  WhiskyKit
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

import Foundation
import CryptoKit

public enum SteamBrowserMode: String, CaseIterable, Sendable {
    case compatibility
    case responsive

    public static func resolve(_ storedValue: String?) -> SteamBrowserMode {
        SteamBrowserMode(rawValue: storedValue ?? "") ?? .compatibility
    }

    static func selected() -> SteamBrowserMode {
        let preferences = UserDefaults(suiteName: Bundle.whiskyBundleIdentifier) ?? .standard
        return resolve(preferences.string(forKey: "steamBrowserMode"))
    }
}

/// Steam's CEF browser needs its flags applied to the helper process itself.
/// Keep Valve's executable intact in a separate file, verified against metadata.
public enum SteamBrowserCompatibility {
    private static let installationLock = NSLock()
    private struct Installation: Codable {
        var adapterHash: String
        var originalHash: String
    }

    public static func prepare(steamExecutable: URL, adaptersFolder: URL, enabled: Bool) throws -> [String] {
        installationLock.lock()
        defer { installationLock.unlock() }
        let manager = FileManager.default
        let cef = steamExecutable.deletingLastPathComponent().appending(path: "bin/cef")
        let directories = try manager.contentsOfDirectory(at: cef, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.lastPathComponent.hasPrefix("cef.win") }
        var count = 0
        for directory in directories {
            let executable = directory.appending(path: "steamwebhelper.exe")
            guard manager.fileExists(atPath: executable.path) else { continue }
            let backup = directory.appending(path: "steamwebhelper_valve.exe")
            let metadata = directory.appending(path: "whisky-browser-adapter.json")
            let current = try Data(contentsOf: executable)
            let currentHash = hash(current)
            let installation: Installation?
            if manager.fileExists(atPath: metadata.path) {
                installation = try JSONDecoder().decode(Installation.self, from: Data(contentsOf: metadata))
            } else {
                installation = nil
            }
            let isOurAdapter = installation?.adapterHash == currentHash

            if !enabled {
                if isOurAdapter, let installation {
                    let original = try Data(contentsOf: backup)
                    guard hash(original) == installation.originalHash else { throw CompatibilityError.invalidBackup }
                    try original.write(to: executable, options: .atomic)
                }
                continue
            }

            let original: Data
            if isOurAdapter, let installation {
                original = try Data(contentsOf: backup)
                guard hash(original) == installation.originalHash else { throw CompatibilityError.invalidBackup }
            } else {
                // Refuse to back up an unknown small wrapper as Valve's real browser.
                guard current.count > 500_000 else { throw CompatibilityError.unknownHelper }
                original = current
            }
            let architecture = try architecture(of: original)
            let adapter = try Data(contentsOf: adaptersFolder.appending(path: "\(architecture).exe"))
            guard try self.architecture(of: adapter) == architecture else { throw CompatibilityError.invalidAdapter }
            if !isOurAdapter {
                try original.write(to: backup, options: .atomic)
            }
            let record = Installation(adapterHash: hash(adapter), originalHash: hash(original))
            try JSONEncoder().encode(record).write(to: metadata, options: .atomic)
            if current != adapter { try adapter.write(to: executable, options: .atomic) }
            count += 1
        }
        guard !enabled || count > 0 else { throw CompatibilityError.missingHelper }
        // Without this, Steam's startup file repair replaces our adapter immediately.
        // Steam's normal update checks remain enabled.
        return enabled ? ["-noverifyfiles"] : []
    }

    static func autorunCommand(in bottle: URL, enabled: Bool) throws -> String? {
        let registry = bottle.appending(path: "user.reg")
        guard FileManager.default.fileExists(atPath: registry.path) else { return nil }
        let text = try String(contentsOf: registry, encoding: .utf8)
        let runSection = #"[Software\\Microsoft\\Windows\\CurrentVersion\\Run]"#
        var inRunSection = false
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("[") {
                inRunSection = line.lowercased().hasPrefix(runSection.lowercased())
            }
            let prefix = "\"Steam\"="
            if inRunSection && line.hasPrefix(prefix) {
                let data = Data(line.dropFirst(prefix.count).utf8)
                guard let command = try? JSONDecoder().decode(String.self, from: data) else { return nil }
                return updatedAutorunCommand(command, enabled: enabled)
            }
        }
        return nil
    }

    static func updatedAutorunCommand(_ command: String, enabled: Bool) -> String? {
        guard command.lowercased().contains("steam.exe") else { return nil }
        let pattern = #"(?i)(?:^|\s)-noverifyfiles(?=\s|$)"#
        let hasFlag = command.range(of: pattern, options: .regularExpression) != nil
        if enabled {
            return hasFlag ? nil : command + " -noverifyfiles"
        }
        return hasFlag ? command.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces) : nil
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func architecture(of data: Data) throws -> String {
        guard data.count > 64, data[0] == 0x4d, data[1] == 0x5a else { throw CompatibilityError.invalidAdapter }
        let offset = (0..<4).reduce(0) { $0 | Int(data[0x3c + $1]) << ($1 * 8) }
        guard offset >= 64, offset <= data.count - 6,
              Array(data[offset..<(offset + 4)]) == [0x50, 0x45, 0, 0] else {
            throw CompatibilityError.invalidAdapter
        }
        let machine = Int(data[offset + 4]) | Int(data[offset + 5]) << 8
        switch machine {
        case 0x8664: return "x86_64"
        case 0x14c: return "i686"
        default: throw CompatibilityError.invalidAdapter
        }
    }
}

private enum CompatibilityError: LocalizedError {
    case invalidBackup, unknownHelper, invalidAdapter, missingHelper

    var errorDescription: String? {
        switch self {
        case .invalidBackup:
            return "The saved Steam browser file is missing or damaged. Restore Steam's files before continuing."
        case .unknownHelper:
            return "Steam's browser executable is unrecognized. Its original file has been left unchanged."
        case .invalidAdapter:
            return "The Steam browser executable has an unsupported format or architecture."
        case .missingHelper:
            return "Steam's browser files are not installed yet. Finish Steam's update, then reopen it."
        }
    }
}

/// Suppress overlapping startup requests from buttons and pinned programs.
public actor SteamLaunchGate {
    public static let shared = SteamLaunchGate()
    private var reservations: [URL: (token: UUID, expires: Date)] = [:]
    private let interval: TimeInterval

    public init(interval: TimeInterval = 12) { self.interval = interval }

    public func reserve(for executable: URL, now: Date = Date()) -> UUID? {
        let key = executable.standardizedFileURL
        if let current = reservations[key], now < current.expires { return nil }
        let token = UUID()
        reservations[key] = (token, now.addingTimeInterval(interval))
        return token
    }

    public func cancel(for executable: URL, token: UUID) {
        let key = executable.standardizedFileURL
        if reservations[key]?.token == token { reservations.removeValue(forKey: key) }
    }
}
