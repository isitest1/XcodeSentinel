import Foundation
import XCTest
@testable import SentinelCore

enum Fixture {
    /// Loads a JSON fixture copied into the test bundle under `Fixtures/`.
    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            Bundle.module.url(forResource: name, withExtension: "json")
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            XCTFail("Fixture \(name).json not found in test bundle", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func snapshot(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> AXSnapshot {
        try AXSnapshot.decode(from: data(name, file: file, line: line))
    }
}

/// A gregorian calendar pinned to a fixed time zone, for deterministic tests.
func fixedCalendar(_ identifier: String = "America/New_York") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
}

/// Builds a `Date` from components in the given time zone.
func makeDate(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
    timeZone: String = "America/New_York"
) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = minute; comps.second = second
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    return calendar.date(from: comps)!
}
