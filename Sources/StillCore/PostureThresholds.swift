import Foundation

public enum PostureThreshold: String, CaseIterable, CodingKey {
    case sustainSeconds, displaySeconds, cooldownSeconds
    case headTiltDegrees, shoulderTiltDegrees, loweredPitchDegrees, headOnlyPitchDegrees, loweredHeadDrop
    case forwardScalePercent, forwardPitchDegrees, forwardHeadDrop
    case maxYawDegrees, maxPitchDegrees, observationGraceSeconds

    public var title: String {
        switch self {
        case .sustainSeconds: return "偏离累计秒数"
        case .displaySeconds: return "提醒展示秒数"
        case .cooldownSeconds: return "提醒冷却秒数"
        case .headTiltDegrees: return "歪头角度阈值"
        case .shoulderTiltDegrees: return "肩线角度阈值"
        case .loweredPitchDegrees: return "有肩部时的低头角度阈值"
        case .headOnlyPitchDegrees: return "仅头部时的低头角度阈值"
        case .loweredHeadDrop: return "低头头肩距离比下降阈值"
        case .forwardScalePercent: return "探头头肩比例增加百分比"
        case .forwardPitchDegrees: return "探头辅助低头角度阈值"
        case .forwardHeadDrop: return "探头辅助头肩距离比下降阈值"
        case .maxYawDegrees: return "可识别的转头角度上限"
        case .maxPitchDegrees: return "可识别的俯仰角度上限"
        case .observationGraceSeconds: return "识别丢失保留秒数"
        }
    }
    public var range: ClosedRange<Double> {
        switch self {
        case .sustainSeconds: return 1...120
        case .displaySeconds: return 1...15
        case .cooldownSeconds: return 5...600
        case .headTiltDegrees, .shoulderTiltDegrees, .loweredPitchDegrees, .headOnlyPitchDegrees, .forwardPitchDegrees: return 1...30
        case .loweredHeadDrop, .forwardHeadDrop: return 0.01...0.50
        case .forwardScalePercent: return 5...60
        case .maxYawDegrees: return 10...45
        case .maxPitchDegrees: return 20...60
        case .observationGraceSeconds: return 0...3
        }
    }
    public var decimalPlaces: Int {
        switch self {
        case .loweredHeadDrop, .forwardHeadDrop: return 2
        case .observationGraceSeconds: return 1
        default: return 0
        }
    }
    public var keyPath: WritableKeyPath<PostureThresholds, Double> {
        switch self {
        case .sustainSeconds: return \.sustainSeconds
        case .displaySeconds: return \.displaySeconds
        case .cooldownSeconds: return \.cooldownSeconds
        case .headTiltDegrees: return \.headTiltDegrees
        case .shoulderTiltDegrees: return \.shoulderTiltDegrees
        case .loweredPitchDegrees: return \.loweredPitchDegrees
        case .headOnlyPitchDegrees: return \.headOnlyPitchDegrees
        case .loweredHeadDrop: return \.loweredHeadDrop
        case .forwardScalePercent: return \.forwardScalePercent
        case .forwardPitchDegrees: return \.forwardPitchDegrees
        case .forwardHeadDrop: return \.forwardHeadDrop
        case .maxYawDegrees: return \.maxYawDegrees
        case .maxPitchDegrees: return \.maxPitchDegrees
        case .observationGraceSeconds: return \.observationGraceSeconds
        }
    }
    public func formatted(_ value: Double) -> String { String(format: "%.*f", decimalPlaces, value) }
    public var rangeDescription: String {
        let precision = decimalPlaces == 0 ? "整数" : "最多 \(decimalPlaces) 位小数"
        return "\(formatted(range.lowerBound))–\(formatted(range.upperBound))（\(precision)）"
    }
    public func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return PostureThresholds()[self] }
        let precision = pow(10, Double(decimalPlaces))
        return (min(range.upperBound, max(range.lowerBound, value)) * precision).rounded() / precision
    }
    public func parsed(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, range.contains(value) else { return nil }
        let result = normalized(value)
        guard abs(result - value) < 0.000000001 else { return nil }
        return result
    }
}

/// User-editable product thresholds. Recognition confidence and model parameters remain separate.
public struct PostureThresholds: Codable, Equatable {
    public var sustainSeconds: Double = 12
    public var displaySeconds: Double = 5
    public var cooldownSeconds: Double = 60
    public var headTiltDegrees: Double = 12
    public var shoulderTiltDegrees: Double = 10
    public var loweredPitchDegrees: Double = 12
    public var headOnlyPitchDegrees: Double = 15
    public var loweredHeadDrop: Double = 0.12
    public var forwardScalePercent: Double = 20
    public var forwardPitchDegrees: Double = 10
    public var forwardHeadDrop: Double = 0.10
    public var maxYawDegrees: Double = 20
    public var maxPitchDegrees: Double = 40
    public var observationGraceSeconds: Double = 1.5
    public init() {}
    public subscript(_ field: PostureThreshold) -> Double {
        get { self[keyPath: field.keyPath] }
        set { self[keyPath: field.keyPath] = field.normalized(newValue) }
    }
    public var normalized: Self {
        var result = self
        for field in PostureThreshold.allCases { result[field] = self[field] }
        return result
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: PostureThreshold.self)
        for field in PostureThreshold.allCases {
            if let value = try container.decodeIfPresent(Double.self, forKey: field) { self[field] = value }
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PostureThreshold.self)
        for field in PostureThreshold.allCases { try container.encode(field.normalized(self[field]), forKey: field) }
    }
}
