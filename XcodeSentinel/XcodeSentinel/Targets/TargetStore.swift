import Foundation

struct ScheduleStore: Sendable {
    private let url: URL

    init() throws {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("XcodeSentinel", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("schedules.json")
    }

    func load() throws -> [Schedule] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Schedule].self, from: Data(contentsOf: url))
    }

    func save(_ schedules: [Schedule]) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(schedules).write(to: url, options: .atomic)
    }
}
