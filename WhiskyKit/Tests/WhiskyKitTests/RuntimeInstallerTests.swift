//
//  RuntimeInstallerTests.swift
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
import XCTest
@testable import WhiskyKit

final class RuntimeInstallerTests: XCTestCase {
    func testInvalidDownloadPreservesExistingRuntimeAndBottles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = root.appending(path: "Runtime")
        let bottles = root.appending(path: "Bottles")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bottles, withIntermediateDirectories: true)
        let sentinel = runtime.appending(path: "keep.txt")
        let save = bottles.appending(path: "save.txt")
        try Data("runtime".utf8).write(to: sentinel)
        try Data("save".utf8).write(to: save)
        let archive = root.appending(path: "invalid.tar.xz")
        try Data("not a Wine archive".utf8).write(to: archive)

        XCTAssertThrowsError(try WhiskyWineInstaller.install(from: archive, graphicsArchive: archive, applicationFolder: root)) { error in
            guard case RuntimeInstallError.checksumMismatch = error else {
                return XCTFail("Expected a checksum failure, got \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "runtime")
        XCTAssertEqual(try String(contentsOf: save, encoding: .utf8), "save")
    }

    func testDamagedGraphicsDownloadPreservesExistingRuntime() throws {
        guard let archivePath = ProcessInfo.processInfo.environment["WHISKY_TEST_ARCHIVE"] else {
            throw XCTSkip("Set WHISKY_TEST_ARCHIVE to test graphics checksum validation.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = root.appending(path: "Runtime")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        let sentinel = runtime.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        let graphics = root.appending(path: "bad-graphics.tar")
        try Data("damaged".utf8).write(to: graphics)
        XCTAssertThrowsError(try WhiskyWineInstaller.install(
            from: URL(fileURLWithPath: archivePath), graphicsArchive: graphics, applicationFolder: root
        ))
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
    }

    func testGraphicsToggleSelectsOnlyThePackagedDLLs() {
        var settings = BottleSettings()
        var environment: [String: String] = [:]
        settings.dxvk = true
        settings.environmentVariables(wineEnv: &environment)
        XCTAssertEqual(environment["WINEDLLOVERRIDES"], "d3d11,d3d10core=n,b")
        XCTAssertNil(environment["WINEMSYNC"])
        XCTAssertNil(environment["WINEESYNC"])
        settings.dxvk = false
        settings.environmentVariables(wineEnv: &environment)
        XCTAssertEqual(environment["WINEDLLOVERRIDES"], "d3d11,d3d10core=b")
    }

    func testPinnedArchiveInstallsAndReplacesRuntime() throws {
        guard let archivePath = ProcessInfo.processInfo.environment["WHISKY_TEST_ARCHIVE"],
              let graphicsPath = ProcessInfo.processInfo.environment["WHISKY_TEST_DXVK"] else {
            throw XCTSkip("Set WHISKY_TEST_ARCHIVE to exercise the downloaded runtime.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldRuntime = root.appending(path: "Runtime")
        try FileManager.default.createDirectory(at: oldRuntime, withIntermediateDirectories: true)
        try Data().write(to: oldRuntime.appending(path: "old-engine"))
        let archive = URL(fileURLWithPath: archivePath)
        try WhiskyWineInstaller.install(from: archive, graphicsArchive: URL(fileURLWithPath: graphicsPath),
                                        applicationFolder: root)

        let wine = oldRuntime.appending(path: "Wine Devel.app/Contents/Resources/wine/bin/wine")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: wine.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldRuntime.appending(path: "DXVK/x64/d3d11.dll").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldRuntime.appending(path: "WhiskyWineVersion.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldRuntime.appending(path: "old-engine").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .contains(where: { $0.hasPrefix("Runtime-staging-") || $0.hasPrefix("Runtime-backup-") }))
    }
}
