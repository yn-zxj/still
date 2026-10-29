import Foundation

public struct Course: Codable, Identifiable, Equatable {
    public struct Source: Codable, Equatable {
        public let application: String
        public let provider: String?
        public let capturedAt: String?
    }
    public struct Action: Codable, Equatable, Identifiable {
        public let order: Int
        public let phase: String
        public let name: String
        public let quantityText: String?
        public var id: Int { order }
    }
    public struct Media: Codable, Equatable {
        public let filename: String
        public let sha256: String?
        public let fullAudioVideoDecode: String?
    }
    public let schemaVersion: Int
    public let id: String
    public let title: String
    public let source: Source
    public let displayDurationMinutes: Int
    public let estimatedKcal: Int?
    public let difficulty: String
    public let description: String
    public let courseTypes: [String]?
    public let suitableFor: [String]?
    public let contraindications: [String]?
    public let preparation: [String]?
    public let bodyResponses: [String]?
    public let recommendations: [String]?
    public let sourceText: String?
    public let actions: [Action]
    public let actionsComplete: Bool
    public let media: Media?

    public static func decodeCatalog(_ data: Data) throws -> [Course] {
        let courses = try JSONDecoder().decode([Course].self, from: data)
        guard courses.allSatisfy({ $0.schemaVersion == 1 && !$0.id.isEmpty && !$0.title.isEmpty && $0.displayDurationMinutes > 0 }),
              Set(courses.map(\.id)).count == courses.count else { throw CourseError.invalidCatalog }
        for course in courses {
            guard Set(course.actions.map(\.order)).count == course.actions.count else { throw CourseError.invalidCatalog }
            if let filename = course.media?.filename {
                guard !filename.isEmpty, filename != ".", filename != "..", !filename.contains("/"), !filename.contains("\\") else { throw CourseError.unsafeFilename }
            }
        }
        return courses
    }
}

public enum CourseError: LocalizedError {
    case invalidCatalog, unsafeFilename, missingMedia, invalidMedia
    public var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "课程目录格式不正确，或包含重复课程。"
        case .unsafeFilename: return "视频文件必须与 courses.json 放在同一文件夹。"
        case .missingMedia: return "找不到视频文件，请重新导入课程文件夹。"
        case .invalidMedia: return "视频无法播放或校验不一致，请重新取得完整视频。"
        }
    }
}

/// Only contiguous playback advances guided rest. Pauses, seeks and process gaps do not.
public struct CourseProgress {
    public let duration: Double
    public private(set) var elapsed: Double = 0
    private var previous: Double = 0
    public init(duration: Double) { self.duration = max(1, duration.isFinite ? duration : 1) }
    public mutating func observe(position: Double, playing: Bool) {
        guard position.isFinite, position >= 0 else { return }
        let delta = position - previous
        if playing, delta > 0, delta <= 3 { elapsed = min(duration, elapsed + delta) }
        previous = position
    }
    public var completed: Bool { elapsed >= duration - min(1, duration * 0.01) }
}

public struct HeartRateMeasurement: Equatable {
    public let bpm: Int
    public let contactDetected: Bool?
    /// Bluetooth SIG Heart Rate Measurement: flags, UINT8/16, optional energy and RR values.
    public static func decode(_ data: Data) -> Self? {
        let b = Array(data)
        guard let flags = b.first, flags & 0xE0 == 0 else { return nil }
        let wide = flags & 1 != 0
        let count = wide ? 3 : 2
        guard b.count >= count else { return nil }
        var offset = count
        if flags & 8 != 0 { offset += 2 }
        guard b.count >= offset else { return nil }
        if flags & 16 != 0 { guard b.count - offset >= 2, (b.count - offset) % 2 == 0 else { return nil } }
        else if b.count != offset { return nil }
        let bpm = Int(b[1]) + (wide ? Int(b[2]) * 256 : 0)
        let contact: Bool? = flags & 4 != 0 ? flags & 2 != 0 : nil
        guard (1...300).contains(bpm), contact != false else { return nil }
        return Self(bpm: bpm, contactDetected: contact)
    }
}

public enum WatchCommand: String { case pause, resume, end }
public enum WatchProtocol {
    public static let service = "782B1000-6F52-4C85-A701-596BE18A7810"
    public static let state = "782B1001-6F52-4C85-A701-596BE18A7810"
    public static let control = "782B1002-6F52-4C85-A701-596BE18A7810"
    public static func command(_ data: Data, sessionID: UUID?) -> WatchCommand? {
        guard let sessionID, let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: "|")
        guard parts.count == 2, String(parts[0]) == String(sessionID.uuidString.prefix(8)) else { return nil }
        return WatchCommand(rawValue: String(parts[1]))
    }
}
