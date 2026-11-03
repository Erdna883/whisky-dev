//
//  WhiskyWineInstaller.swift
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
import SemanticVersion

public class WhiskyWineInstaller {
    public static let runtimeVersion = "11.21"
    public static let downloadURL = "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/"
        + "wine-devel-11.21-osx64.tar.xz"
    public static let graphicsDownloadURL = "https://github.com/Gcenx/DXVK-macOS/releases/download/"
        + "v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz"
    public static let graphicsSHA256 = "acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477"
    public static let archiveSHA256 = "9909b486657e10ab66c7279371ae1f990345b596b3b1b3a0cf21f28af24fa0ce"

    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appending(path: Bundle.whiskyBundleIdentifier)
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")
    public static let runtimeFolder = applicationFolder.appending(path: "Runtime")
    public static let graphicsFolder = runtimeFolder.appending(path: "DXVK")
    private static let bundlePath = "Wine Devel.app/Contents/Resources/wine"
    public static let binFolder = runtimeFolder.appending(path: bundlePath).appending(path: "bin")

    public static func isWhiskyWineInstalled() -> Bool {
        let manager = FileManager.default
        return whiskyWineVersion() == SemanticVersion(11, 21, 0)
            && manager.isExecutableFile(atPath: binFolder.appending(path: "wine").path)
            && manager.isExecutableFile(atPath: binFolder.appending(path: "wineserver").path)
            && manager.fileExists(atPath: graphicsFolder.appending(path: "x64/d3d11.dll").path)
    }

    /// Verify and stage the new runtime before replacing the previous installation.
    /// Bottle directories are separate and are never removed here.
    public static func install(
        from archive: URL, graphicsArchive: URL,
        applicationFolder: URL = WhiskyWineInstaller.applicationFolder
    ) throws {
        let runtimeFolder = applicationFolder.appending(path: "Runtime")
        let manager = FileManager.default
        try verify(archive: archive, expected: archiveSHA256)
        try verify(archive: graphicsArchive, expected: graphicsSHA256)

        try manager.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
        let staging = applicationFolder.appending(path: "Runtime-staging-\(UUID().uuidString)")
        let backup = applicationFolder.appending(path: "Runtime-backup-\(UUID().uuidString)")
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        try Tar.untar(tarBall: archive, toURL: staging)
        let stagedBin = staging.appending(path: bundlePath).appending(path: "bin")
        guard manager.isExecutableFile(atPath: stagedBin.appending(path: "wine").path),
              manager.isExecutableFile(atPath: stagedBin.appending(path: "wineserver").path) else {
            throw RuntimeInstallError.invalidLayout
        }
        let graphicsStaging = staging.appending(path: "Graphics-staging")
        try manager.createDirectory(at: graphicsStaging, withIntermediateDirectories: true)
        try Tar.untar(tarBall: graphicsArchive, toURL: graphicsStaging)
        let graphicsSource = graphicsStaging.appending(path: "dxvk-macOS-async-v1.10.3-20230507-repack")
        for architecture in ["x64", "x32"] {
            for name in ["d3d11.dll", "d3d10core.dll"] {
                guard manager.fileExists(atPath: graphicsSource.appending(path: "\(architecture)/\(name)").path) else {
                    throw RuntimeInstallError.invalidLayout
                }
            }
        }
        try manager.moveItem(at: graphicsSource, to: staging.appending(path: "DXVK"))
        try manager.removeItem(at: graphicsStaging)
        let encoder = PropertyListEncoder()
        let metadata = WhiskyWineVersion(version: SemanticVersion(11, 21, 0))
        try encoder.encode(metadata).write(to: staging.appending(path: "WhiskyWineVersion.plist"))

        let hadRuntime = manager.fileExists(atPath: runtimeFolder.path)
        if hadRuntime { try manager.moveItem(at: runtimeFolder, to: backup) }
        do {
            try manager.moveItem(at: staging, to: runtimeFolder)
        } catch {
            if hadRuntime { try manager.moveItem(at: backup, to: runtimeFolder) }
            throw error
        }
        if hadRuntime { try? manager.removeItem(at: backup) }
    }

    private static func verify(archive: URL, expected: String) throws {
        let file = try FileHandle(forReadingFrom: archive)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { throw RuntimeInstallError.checksumMismatch }
    }

    public static func uninstall() {
        try? FileManager.default.removeItem(at: runtimeFolder)
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        guard let data = try? Data(contentsOf: runtimeFolder.appending(path: "WhiskyWineVersion.plist")),
              let info = try? PropertyListDecoder().decode(WhiskyWineVersion.self, from: data) else {
            return nil
        }
        return info.version
    }
}

public enum RuntimeInstallError: LocalizedError {
    case checksumMismatch
    case invalidLayout

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "The Wine download did not match its expected checksum. Download it again."
        case .invalidLayout:
            return "The runtime archive is missing the Wine executables."
        }
    }
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion
}
