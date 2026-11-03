//
//  SteamLaunchGateTests.swift
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
import Testing
@testable import WhiskyKit

@Test func steamStartupRequestsAreCoalescedPerExecutable() async {
    let gate = SteamLaunchGate(interval: 12)
    let steam = URL(fileURLWithPath: "/test/Steam/steam.exe")
    let now = Date(timeIntervalSince1970: 100)
    let first = await gate.reserve(for: steam, now: now)
    let duplicate = await gate.reserve(for: steam, now: now.addingTimeInterval(1))
    let otherBottle = await gate.reserve(for: URL(fileURLWithPath: "/other/Steam/steam.exe"), now: now)
    #expect(first != nil)
    #expect(duplicate == nil)
    #expect(otherBottle != nil)
}

@Test func failedStartupCanRetryAndOldFailureCannotCancelNewReservation() async throws {
    let gate = SteamLaunchGate(interval: 12)
    let steam = URL(fileURLWithPath: "/test/Steam/steam.exe")
    let now = Date(timeIntervalSince1970: 100)
    let first = try #require(await gate.reserve(for: steam, now: now))
    await gate.cancel(for: steam, token: first)
    let retry = try #require(await gate.reserve(for: steam, now: now.addingTimeInterval(1)))
    let later = await gate.reserve(for: steam, now: now.addingTimeInterval(14))
    await gate.cancel(for: steam, token: retry)
    let duplicate = await gate.reserve(for: steam, now: now.addingTimeInterval(15))
    #expect(later != nil)
    #expect(duplicate == nil)
}

@Test func simultaneousStartupRequestsCreateOneReservation() async {
    let gate = SteamLaunchGate(interval: 12)
    let steam = URL(fileURLWithPath: "/test/Steam/steam.exe")
    let now = Date(timeIntervalSince1970: 100)
    let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
        for _ in 0..<20 { group.addTask { await gate.reserve(for: steam, now: now) != nil } }
        var count = 0
        for await started in group where started { count += 1 }
        return count
    }
    #expect(accepted == 1)
}
