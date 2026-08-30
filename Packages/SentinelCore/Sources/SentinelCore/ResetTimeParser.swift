import Foundation

/// Which limit a reset time belongs to. Drives the fallback when no time can be
/// parsed (CLAUDE.md section 6.3).
public enum LimitKind: String, Sendable, Equatable {
    case session
    case weekly
}

/// The outcome of parsing a reset-time phrase out of a limit message.
public struct ResetTimeParseResult: Equatable, Sendable {
    public enum Source: String, Sendable {
        /// An absolute clock time resolved against "today" (e.g. `2:15 PM`).
        case absoluteClock
        /// An absolute clock time that had to roll to the next day.
        case absoluteClockNextDay
        /// An explicit "tomorrow at <time>" phrase.
        case tomorrowClock
        /// A relative offset (e.g. `in 3 hours`).
        case relative
    }

    /// The resolved reset instant.
    public var date: Date
    public var source: Source
    /// The exact substring that was recognised, for display in logs and the UI.
    public var matchedText: String

    public init(date: Date, source: Source, matchedText: String) {
        self.date = date
        self.source = source
        self.matchedText = matchedText
    }
}

/// Extracts a reset time from the free text of a limit message.
///
/// Recognised shapes:
///  - `Resets at 2:15 PM`, `resets 2:15pm`, `at 2 PM`
///  - `resets 14:15`, `at 14:15`
///  - `resets tomorrow at 9 AM`
///  - `in 3 hours`, `in 45 minutes`, `resets in 2 hours 30 minutes`, `in an hour`
///
/// The parser only produces a `Date`. The retry-time policy (add 60s, or fall
/// back to a fixed offset) lives in `retryTime(detectedAt:limit:parsed:)`.
public enum ResetTimeParser {
    public static func parse(
        _ text: String,
        now: Date,
        calendar: Calendar
    ) -> ResetTimeParseResult? {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")

        if let relative = parseRelative(normalized, now: now) {
            return relative
        }
        if let tomorrow = parseTomorrowClock(normalized, now: now, calendar: calendar) {
            return tomorrow
        }
        if let absolute = parseAbsoluteClock(normalized, now: now, calendar: calendar) {
            return absolute
        }
        return nil
    }

    /// The instant at which the scheduler should next check this target.
    ///
    /// CLAUDE.md section 6.3:
    ///  - parsed → 60 seconds after the parsed time
    ///  - not parsed, session limit → detected + 5h + 5min
    ///  - not parsed, weekly limit → detected + 6h
    public static func retryTime(
        detectedAt: Date,
        limit: LimitKind,
        parsed: ResetTimeParseResult?
    ) -> Date {
        if let parsed {
            return parsed.date.addingTimeInterval(60)
        }
        switch limit {
        case .session:
            return detectedAt.addingTimeInterval(5 * 3600 + 5 * 60)
        case .weekly:
            return detectedAt.addingTimeInterval(6 * 3600)
        }
    }

    // MARK: - Relative ("in 3 hours 30 minutes", "in an hour")

    private static func parseRelative(_ text: String, now: Date) -> ResetTimeParseResult? {
        // A relative phrase must be introduced by "in " (e.g. "resets in ...",
        // "available again in ..."). This keeps absolute times like "at 5:00"
        // out of this branch.
        guard let anchor = firstMatch(
            #"\bin\s+(?:about\s+|around\s+|approximately\s+|~\s*)?((?:an?|[0-9][0-9.]*)[a-z0-9\s.]*?(?:hours?|hrs?|minutes?|mins?)(?:\s+(?:and\s+)?[0-9][0-9.]*\s*(?:minutes?|mins?))?)"#,
            in: text
        ) else { return nil }

        let phrase = anchor.groups.first ?? anchor.text
        var seconds: TimeInterval = 0
        var found = false

        let hasDigit = phrase.range(of: #"[0-9]"#, options: .regularExpression) != nil

        if !hasDigit {
            if phrase.range(of: #"\ban?\s+hour"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return ResetTimeParseResult(
                    date: now.addingTimeInterval(3600), source: .relative, matchedText: anchor.text
                )
            }
            if phrase.range(of: #"\ban?\s+minute"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return ResetTimeParseResult(
                    date: now.addingTimeInterval(60), source: .relative, matchedText: anchor.text
                )
            }
            return nil
        }

        if let hours = firstMatch(#"([0-9]+(?:\.[0-9]+)?)\s*(?:hours?|hrs?)"#, in: phrase),
           let value = Double(hours.groups.first ?? "") {
            seconds += value * 3600
            found = true
        }
        if let mins = firstMatch(#"([0-9]+)\s*(?:minutes?|mins?)"#, in: phrase),
           let value = Double(mins.groups.first ?? "") {
            seconds += value * 60
            found = true
        }
        guard found, seconds > 0 else { return nil }
        return ResetTimeParseResult(
            date: now.addingTimeInterval(seconds),
            source: .relative,
            matchedText: anchor.text
        )
    }

    // MARK: - "tomorrow at 9 AM"

    private static func parseTomorrowClock(
        _ text: String,
        now: Date,
        calendar: Calendar
    ) -> ResetTimeParseResult? {
        guard text.range(of: #"tomorrow"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let clock = matchClock(in: text)
        else { return nil }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let resolved = calendar.date(
                bySettingHour: clock.hour, minute: clock.minute, second: 0, of: tomorrow
              )
        else { return nil }

        return ResetTimeParseResult(date: resolved, source: .tomorrowClock, matchedText: clock.matchedText)
    }

    // MARK: - Absolute clock time, resolved against today / next day

    private static func parseAbsoluteClock(
        _ text: String,
        now: Date,
        calendar: Calendar
    ) -> ResetTimeParseResult? {
        guard let clock = matchClock(in: text) else { return nil }
        guard let todayAt = calendar.date(
            bySettingHour: clock.hour, minute: clock.minute, second: 0, of: now
        ) else { return nil }

        if todayAt > now {
            return ResetTimeParseResult(date: todayAt, source: .absoluteClock, matchedText: clock.matchedText)
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayAt) else { return nil }
        return ResetTimeParseResult(
            date: tomorrow, source: .absoluteClockNextDay, matchedText: clock.matchedText
        )
    }

    private struct Clock {
        var hour: Int
        var minute: Int
        var matchedText: String
    }

    /// Finds the first `H`, `H:MM`, optionally followed by `am`/`pm`.
    private static func matchClock(in text: String) -> Clock? {
        guard let match = firstMatch(
            #"\b([0-9]{1,2})(?::([0-9]{2}))?\s*([ap]\.?m\.?)?"#,
            in: text,
            requireMeaningful: true
        ) else { return nil }

        guard let rawHour = Int(match.groups[0]) else { return nil }
        let minute = match.groups.count > 1 ? Int(match.groups[1]) ?? 0 : 0
        guard minute < 60 else { return nil }

        let meridiem = match.groups.count > 2
            ? match.groups[2].lowercased().replacingOccurrences(of: ".", with: "")
            : ""

        var hour = rawHour
        switch meridiem {
        case "pm":
            guard (1...12).contains(rawHour) else { return nil }
            hour = rawHour == 12 ? 12 : rawHour + 12
        case "am":
            guard (1...12).contains(rawHour) else { return nil }
            hour = rawHour == 12 ? 0 : rawHour
        default:
            guard (0...23).contains(rawHour) else { return nil }
        }
        return Clock(hour: hour, minute: minute, matchedText: trimClockText(match.text))
    }

    /// The meridiem sub-pattern allows a trailing `.` so it can match `p.m.`.
    /// At the end of a sentence ("resets at 2:15 PM.") that also swallows the
    /// full stop, so drop a trailing `.`/`,`/`)` unless it is the closing dot of
    /// a genuine `a.m.` / `p.m.`.
    private static func trimClockText(_ text: String) -> String {
        var result = text
        while let last = result.last, ".,)".contains(last) {
            if last == ".", result.lowercased().hasSuffix(".m.") { break }
            result.removeLast()
        }
        return result
    }

    // MARK: - Regex helper

    private struct RegexMatch {
        var text: String
        var groups: [String]
    }

    /// First match of `pattern` (case-insensitive). `groups` holds the captured
    /// groups that participated in the match, in order.
    ///
    /// When `requireMeaningful` is set, a bare single digit with no `:MM` and no
    /// meridiem is rejected, so numbers like "5 hours" are not read as "5:00".
    private static func firstMatch(
        _ pattern: String,
        in text: String,
        requireMeaningful: Bool = false
    ) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }

        guard let matchRange = Range(match.range, in: text) else { return nil }
        let matchedText = String(text[matchRange])

        // Keep group positions stable: a capture group that did not participate
        // (e.g. the optional `:MM`) contributes an empty string rather than
        // being dropped, so callers can index groups positionally.
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            if let groupRange = Range(match.range(at: index), in: text) {
                groups.append(String(text[groupRange]))
            } else {
                groups.append("")
            }
        }

        if requireMeaningful {
            let hasColon = groups.count > 1 && !groups[1].isEmpty
            let hasMeridiem = groups.count > 2 && !groups[2].isEmpty
            if !hasColon && !hasMeridiem { return nil }
        }
        return RegexMatch(text: matchedText, groups: groups)
    }
}
