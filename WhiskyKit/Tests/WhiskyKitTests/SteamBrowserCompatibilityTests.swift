//
//  SteamBrowserCompatibilityTests.swift
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

final class SteamBrowserCompatibilityTests: XCTestCase {
    private var root: URL!
    private var cef: URL!
    private var adapters: URL!
    private var steam: URL!
    private var helper: URL { cef.appending(path: "steamwebhelper.exe") }
    private var backup: URL { cef.appending(path: "steamwebhelper_valve.exe") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        cef = root.appending(path: "Steam/bin/cef/cef.win64")
        adapters = root.appending(path: "Adapters")
        steam = root.appending(path: "Steam/steam.exe")
        try FileManager.default.createDirectory(at: cef, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: adapters, withIntermediateDirectories: true)
        try executable(size: 600_000, marker: 1).write(to: helper)
        try executable(size: 1_024, marker: 2).write(to: adapters.appending(path: "x86_64.exe"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func executable(size: Int, marker: UInt8, machine: UInt16 = 0x8664) -> Data {
        var data = Data(repeating: 0, count: size)
        data[0] = 0x4d; data[1] = 0x5a; data[0x3c] = 0x80
        data[0x80] = 0x50; data[0x81] = 0x45
        data[0x84] = UInt8(machine & 0xff); data[0x85] = UInt8(machine >> 8)
        data[512] = marker
        return data
    }

    @discardableResult
    private func prepare(_ enabled: Bool = true) throws -> [String] {
        try SteamBrowserCompatibility.prepare(steamExecutable: steam, adaptersFolder: adapters, enabled: enabled)
    }

    func testInstallIsRepeatableAndCanRestoreOriginal() throws {
        let original = try Data(contentsOf: helper)
        XCTAssertEqual(try prepare(), ["-noverifyfiles"])
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try Data(contentsOf: helper), try Data(contentsOf: adapters.appending(path: "x86_64.exe")))
        try prepare()
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try prepare(false), [])
        XCTAssertEqual(try Data(contentsOf: helper), original)
    }

    func testSteamUpdateRefreshesBackupBeforeReinstallingAdapter() throws {
        try prepare()
        let update = executable(size: 610_000, marker: 3)
        try update.write(to: helper)
        try prepare()
        XCTAssertEqual(try Data(contentsOf: backup), update)
        try prepare(false)
        XCTAssertEqual(try Data(contentsOf: helper), update)
    }

    func testCorruptBackupDoesNotOverwriteInstalledAdapter() throws {
        try prepare()
        let installed = try Data(contentsOf: helper)
        try Data("damaged".utf8).write(to: backup)
        XCTAssertThrowsError(try prepare())
        XCTAssertThrowsError(try prepare(false))
        XCTAssertEqual(try Data(contentsOf: helper), installed)
    }

    func testUnrecognizedWrapperIsNeverPromotedToValveBackup() throws {
        let unknown = executable(size: 2_048, marker: 5)
        try unknown.write(to: helper)
        XCTAssertThrowsError(try prepare())
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try Data(contentsOf: helper), unknown)
    }

    func testAdapterUpgradePreservesValveOriginal() throws {
        let original = try Data(contentsOf: helper)
        try prepare()
        let update = executable(size: 1_536, marker: 6)
        try update.write(to: adapters.appending(path: "x86_64.exe"))
        try prepare()
        XCTAssertEqual(try Data(contentsOf: helper), update)
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    func testTerminalLaunchPreparesBrowserAndKeepsRepairFlag() throws {
        let bottleFolder = root.appending(path: "Bottle")
        try FileManager.default.createDirectory(at: bottleFolder, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleFolder)
        bottle.settings.dxvk = false
        let command = try Wine.generateRunCommand(
            at: steam, bottle: bottle, args: "-console", environment: [:], adaptersFolder: adapters
        )
        let enabled = UserDefaults(suiteName: Bundle.whiskyBundleIdentifier)?
            .object(forKey: "steamBrowserCompatibility") as? Bool ?? true
        XCTAssertEqual(command.contains("-noverifyfiles"), enabled)
        XCTAssertTrue(command.contains("-console"))
        if enabled {
            XCTAssertEqual(try Data(contentsOf: helper), try Data(contentsOf: adapters.appending(path: "x86_64.exe")))
        }
    }

    func testAutorunPreservesUserFlagsAndCanRemoveCompatibilityFlag() {
        let command = #""C:\Program Files (x86)\Steam\steam.exe" -silent"#
        let updated = SteamBrowserCompatibility.updatedAutorunCommand(command, enabled: true)
        XCTAssertEqual(updated, command + " -noverifyfiles")
        XCTAssertNil(SteamBrowserCompatibility.updatedAutorunCommand(updated ?? "", enabled: true))
        XCTAssertEqual(SteamBrowserCompatibility.updatedAutorunCommand(updated ?? "", enabled: false), command)
        XCTAssertNil(SteamBrowserCompatibility.updatedAutorunCommand("OtherApp.exe -silent", enabled: true))
    }

    func testAutorunReadsOnlySteamInWindowsRunSection() throws {
        let folder = root.appending(path: "RegistryBottle")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let command = #""C:\Program Files (x86)\Steam\steam.exe" -silent"#
        let encoded = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        let registry = #"[Software\\Other]"# + "\n\"Steam\"=\"OtherApp.exe\"\n"
            + #"[Software\\Microsoft\\Windows\\CurrentVersion\\Run] 12345"#
            + "\n\"Steam\"=" + encoded + "\n"
        try registry.write(to: folder.appending(path: "user.reg"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try SteamBrowserCompatibility.autorunCommand(in: folder, enabled: true), command + " -noverifyfiles")
    }

    func testBrowserModeDefaultsToCompatibilityForMissingOrUnknownValue() {
        XCTAssertEqual(SteamBrowserMode.resolve(nil), .compatibility)
        XCTAssertEqual(SteamBrowserMode.resolve("unknown"), .compatibility)
        XCTAssertEqual(SteamBrowserMode.resolve("responsive"), .responsive)
    }

    func testGeneratedCommandIncludesSelectedBrowserMode() throws {
        let bottleFolder = root.appending(path: "ModeBottle")
        try FileManager.default.createDirectory(at: bottleFolder, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleFolder)
        bottle.settings.dxvk = false
        let command = try Wine.generateRunCommand(
            at: steam, bottle: bottle, args: "", environment: [:], adaptersFolder: adapters
        )
        XCTAssertTrue(command.contains("WHISKY_STEAM_BROWSER_MODE=\"\(SteamBrowserMode.selected().rawValue)\""))
    }

    func testArchitectureMismatchLeavesOriginalUntouched() throws {
        let original = try Data(contentsOf: helper)
        try executable(size: 1_024, marker: 7, machine: 0x14c)
            .write(to: adapters.appending(path: "x86_64.exe"))
        XCTAssertThrowsError(try prepare())
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try Data(contentsOf: helper), original)
    }
}
